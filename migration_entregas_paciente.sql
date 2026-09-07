-- ═══════════════════════════════════════════════════════════════════
-- MIGRACIÓN — vínculo entregas ↔ pacientes
-- Ejecutar en Supabase → SQL Editor
--
-- Problema: la tabla `entregas` nunca guardó a QUÉ paciente se entregó.
-- Solo tenía `nro_reprocann` como texto libre. Por eso el modal
-- "Ver entregas" de un paciente (que filtra por paciente_id) nunca
-- mostraba nada, y el historial del lote no podía nombrar al paciente.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Columnas nuevas ─────────────────────────────────────────────
-- paciente_id: NULL cuando la entrega fue a alguien no cargado en el listado.
-- ON DELETE SET NULL: borrar un paciente no debe borrar el historial de entregas.
ALTER TABLE public.entregas
  ADD COLUMN IF NOT EXISTS paciente_id UUID REFERENCES public.pacientes(id) ON DELETE SET NULL;

-- paciente_nombre: nombre del receptor. Se completa siempre —
-- copiado de la ficha si vino del listado, o escrito a mano si no.
ALTER TABLE public.entregas
  ADD COLUMN IF NOT EXISTS paciente_nombre TEXT;

-- registrado_por: ya lo escribe el frontend pero faltaba en el schema versionado.
ALTER TABLE public.entregas
  ADD COLUMN IF NOT EXISTS registrado_por TEXT;

-- ── 2. nro_reprocann pasa a ser opcional ───────────────────────────
-- La regla de negocio es "nombre Y/O REPROCANN", así que el NOT NULL
-- original bloqueaba las entregas identificadas solo por nombre.
ALTER TABLE public.entregas ALTER COLUMN nro_reprocann DROP NOT NULL;

-- ── 3. Regla: toda entrega debe identificar al receptor ────────────
-- Al menos uno de los tres: el vínculo real, el nombre, o el REPROCANN.
ALTER TABLE public.entregas DROP CONSTRAINT IF EXISTS entregas_receptor_identificado;
ALTER TABLE public.entregas
  ADD CONSTRAINT entregas_receptor_identificado CHECK (
    paciente_id IS NOT NULL
    OR NULLIF(TRIM(paciente_nombre), '') IS NOT NULL
    OR NULLIF(TRIM(nro_reprocann), '') IS NOT NULL
  ) NOT VALID;   -- NOT VALID: no rechaza las filas históricas ya cargadas

-- ── 4. Índice para el modal "Ver entregas" del paciente ────────────
CREATE INDEX IF NOT EXISTS idx_entregas_paciente ON public.entregas(paciente_id);

-- ── 4b. Audit trail del cambio de paciente en las correcciones ─────
-- Una corrección puede re-vincular la entrega a otro paciente. El cambio
-- de receptor tiene que quedar asentado igual que el de cantidad.
ALTER TABLE public.entregas_correcciones
  ADD COLUMN IF NOT EXISTS paciente_nombre_ant TEXT;
ALTER TABLE public.entregas_correcciones
  ADD COLUMN IF NOT EXISTS paciente_nombre_nvo TEXT;

-- ── 5. Backfill: reconstruir el vínculo de las entregas ya cargadas ─
-- Cruza por nro_reprocann exacto. Solo toca filas donde el número
-- identifica a UN paciente sin ambigüedad.
UPDATE public.entregas e
SET paciente_id = p.id,
    paciente_nombre = COALESCE(NULLIF(TRIM(e.paciente_nombre), ''), p.nombre || ' ' || p.apellido)
FROM public.pacientes p
WHERE e.paciente_id IS NULL
  AND NULLIF(TRIM(e.nro_reprocann), '') IS NOT NULL
  AND TRIM(p.nro_reprocann) = TRIM(e.nro_reprocann)
  AND (
    SELECT COUNT(*) FROM public.pacientes p2
    WHERE TRIM(p2.nro_reprocann) = TRIM(e.nro_reprocann)
  ) = 1;

-- ── 6. Verificación — correr después y revisar el resultado ────────
-- Cuántas entregas quedaron vinculadas y cuántas siguen sueltas:
--
--   SELECT
--     COUNT(*) FILTER (WHERE paciente_id IS NOT NULL) AS vinculadas,
--     COUNT(*) FILTER (WHERE paciente_id IS NULL)     AS sin_vincular,
--     COUNT(*)                                        AS total
--   FROM public.entregas;
--
-- Las que quedan sin vincular son entregas cuyo REPROCANN no coincide
-- con ningún paciente cargado (o está vacío). Se pueden completar a mano.
