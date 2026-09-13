-- ═══════════════════════════════════════════════════════════════════
-- MIGRACIÓN — control de concurrencia optimista + stock atómico
-- Ejecutar en Supabase → SQL Editor
--
-- Problema: dos pestañas (o dos dispositivos con la misma cuenta de ONG)
-- abiertas sobre el mismo lote pisan los datos entre sí. El último en
-- guardar gana y el cambio del otro desaparece sin aviso — "lost update".
--
-- Solución en dos partes, porque son dos problemas distintos:
--
--  1. FORMULARIOS (etapas, fichas, datos) → concurrencia optimista.
--     Cada fila lleva `actualizado_en`. El UPDATE del frontend viaja con
--     el valor que leyó al abrir el formulario; si alguien lo cambió en
--     el medio, el WHERE no matchea, se actualizan 0 filas y la app avisa
--     en vez de sobreescribir.
--
--  2. CONTADORES (stock) → decremento atómico vía RPC.
--     Acá el patrón "leer, restar, escribir" es de por sí inseguro. Se
--     reemplaza por un UPDATE que hace la resta en el motor
--     (stock = stock - X), que Postgres serializa por bloqueo de fila.
--
-- Esta migración NO rompe el código actual: agrega columnas y funciones.
-- El frontend que no manda el token sigue funcionando como hasta ahora.
-- ═══════════════════════════════════════════════════════════════════


-- ── 1. Función de trigger: estampar la última modificación ─────────
-- clock_timestamp() y no now(): now() devuelve el instante de inicio de
-- la transacción, así que dos UPDATEs de la misma transacción quedarían
-- con idéntico valor y el token dejaría de discriminar entre ellos.
CREATE OR REPLACE FUNCTION public.set_actualizado_en()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.actualizado_en = clock_timestamp();
  RETURN NEW;
END;
$$;


-- ── 2. Columna + trigger en toda tabla que reciba UPDATE ───────────
-- Se omiten a propósito las tablas append-only (bajas_material,
-- actividades_log, *_correcciones, *_documentos): nunca se actualizan,
-- agregarles la columna sería ruido.
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'lotes_produccion',
    'etapa_nursery', 'etapa_vegetativa', 'etapa_floracion',
    'etapa_cosecha', 'etapa_curado_secado',
    'flores_cosechadas',
    'lotes_semillas', 'lotes_esquejes', 'lotes_plantas_madre',
    'analisis_calidad', 'entregas', 'pacientes',
    'establecimientos', 'organizaciones', 'perfiles'
  ] LOOP
    EXECUTE format(
      'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()', t);
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_actualizado_en ON public.%I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_actualizado_en BEFORE UPDATE ON public.%I
         FOR EACH ROW EXECUTE FUNCTION public.set_actualizado_en()', t);
  END LOOP;
END $$;


-- ── 3. Stock de material básico: ajuste atómico ────────────────────
-- SECURITY INVOKER (el default): la función corre con los permisos de
-- quien la llama, así que la RLS de 3 niveles sigue aplicando igual que
-- en un UPDATE directo. No usar SECURITY DEFINER acá — saltearía la RLS.
--
-- p_delta negativo descuenta, positivo repone.
-- Devuelve JSON en vez de lanzar excepción para que el frontend pueda
-- mostrar un mensaje preciso sin parsear strings de error.
CREATE OR REPLACE FUNCTION public.ajustar_stock_material(
  p_tipo    TEXT,
  p_lote_id UUID,
  p_delta   NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_nuevo  NUMERIC;
  v_existe BOOLEAN;
BEGIN
  IF p_tipo = 'semillas' THEN
    UPDATE public.lotes_semillas
       SET stock_actual = stock_actual + p_delta
     WHERE id = p_lote_id AND stock_actual + p_delta >= 0
     RETURNING stock_actual INTO v_nuevo;
    SELECT EXISTS(SELECT 1 FROM public.lotes_semillas WHERE id = p_lote_id) INTO v_existe;

  ELSIF p_tipo = 'esquejes' THEN
    UPDATE public.lotes_esquejes
       SET stock_actual = stock_actual + p_delta
     WHERE id = p_lote_id AND stock_actual + p_delta >= 0
     RETURNING stock_actual INTO v_nuevo;
    SELECT EXISTS(SELECT 1 FROM public.lotes_esquejes WHERE id = p_lote_id) INTO v_existe;

  ELSIF p_tipo = 'pm' THEN
    UPDATE public.lotes_plantas_madre
       SET cantidad_actual = cantidad_actual + p_delta
     WHERE id = p_lote_id AND cantidad_actual + p_delta >= 0
     RETURNING cantidad_actual INTO v_nuevo;
    SELECT EXISTS(SELECT 1 FROM public.lotes_plantas_madre WHERE id = p_lote_id) INTO v_existe;

  ELSE
    RETURN jsonb_build_object('ok', false, 'motivo', 'tipo_desconocido');
  END IF;

  IF v_nuevo IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'stock', v_nuevo);
  END IF;

  -- 0 filas afectadas: o el stock no alcanza, o la fila no existe / la RLS la oculta
  RETURN jsonb_build_object(
    'ok', false,
    'motivo', CASE WHEN v_existe THEN 'stock_insuficiente' ELSE 'no_encontrado' END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.ajustar_stock_material(TEXT, UUID, NUMERIC) TO authenticated;


-- ── 3b. Baja total de un lote de material ──────────────────────────
-- "Eliminar la totalidad" es un caso aparte: no es un delta conocido de
-- antemano sino "llevá a 0 y decime cuánto había". Resolverlo leyendo el
-- stock y después escribiendo 0 deja una ventana en la que otro
-- movimiento se pierde y la baja queda registrada por una cantidad que
-- no es la que realmente se descontó. Acá las dos cosas pasan en el
-- mismo UPDATE, así que la cantidad devuelta es exactamente la retirada.
-- SELECT ... FOR UPDATE bloquea la fila hasta el fin de la transacción,
-- así que entre leer cuánto había y escribir 0 no entra nadie.
CREATE OR REPLACE FUNCTION public.vaciar_stock_material(
  p_tipo    TEXT,
  p_lote_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE v_previo NUMERIC;
BEGIN
  IF p_tipo = 'semillas' THEN
    SELECT stock_actual INTO v_previo
      FROM public.lotes_semillas WHERE id = p_lote_id FOR UPDATE;
    IF v_previo IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); END IF;
    UPDATE public.lotes_semillas SET stock_actual = 0 WHERE id = p_lote_id;

  ELSIF p_tipo = 'esquejes' THEN
    SELECT stock_actual INTO v_previo
      FROM public.lotes_esquejes WHERE id = p_lote_id FOR UPDATE;
    IF v_previo IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); END IF;
    UPDATE public.lotes_esquejes SET stock_actual = 0 WHERE id = p_lote_id;

  ELSIF p_tipo = 'pm' THEN
    SELECT cantidad_actual INTO v_previo
      FROM public.lotes_plantas_madre WHERE id = p_lote_id FOR UPDATE;
    IF v_previo IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); END IF;
    UPDATE public.lotes_plantas_madre SET cantidad_actual = 0 WHERE id = p_lote_id;

  ELSE
    RETURN jsonb_build_object('ok', false, 'motivo', 'tipo_desconocido');
  END IF;

  IF v_previo <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'ya_vacio');
  END IF;
  RETURN jsonb_build_object('ok', true, 'retirado', v_previo);
END;
$$;

GRANT EXECUTE ON FUNCTION public.vaciar_stock_material(TEXT, UUID) TO authenticated;

-- Misma lógica, tabla propia. Se redondea a 2 decimales porque el stock
-- se lleva en gramos con decimales y la app ya redondea así.
CREATE OR REPLACE FUNCTION public.ajustar_stock_flores(
  p_flores_id UUID,
  p_delta     NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_nuevo  NUMERIC;
  v_existe BOOLEAN;
BEGIN
  UPDATE public.flores_cosechadas
     SET stock_actual = ROUND((stock_actual + p_delta)::NUMERIC, 2)
   WHERE id = p_flores_id AND stock_actual + p_delta >= 0
   RETURNING stock_actual INTO v_nuevo;

  IF v_nuevo IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'stock', v_nuevo);
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.flores_cosechadas WHERE id = p_flores_id) INTO v_existe;
  RETURN jsonb_build_object(
    'ok', false,
    'motivo', CASE WHEN v_existe THEN 'stock_insuficiente' ELSE 'no_encontrado' END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.ajustar_stock_flores(UUID, NUMERIC) TO authenticated;


-- ── 5. Verificación ────────────────────────────────────────────────
-- Debe devolver 16 filas, una por tabla, todas con trigger = 't'.
SELECT c.table_name,
       EXISTS(
         SELECT 1 FROM pg_trigger tg
         JOIN pg_class cl ON cl.oid = tg.tgrelid
         WHERE cl.relname = c.table_name AND tg.tgname = 'trg_actualizado_en'
       ) AS trigger
  FROM information_schema.columns c
 WHERE c.table_schema = 'public'
   AND c.column_name = 'actualizado_en'
 ORDER BY c.table_name;
