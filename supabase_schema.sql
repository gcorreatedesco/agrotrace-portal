-- ================================================
-- AgroTrace — Schema v5
-- Basado en agrotrace_prototipo_v3.html
-- Ejecutar completo en Supabase > SQL Editor
-- ================================================


-- ── ORGANIZACIONES (ONGs como entidades) ─────────
-- Cada ONG es una organización independiente.
-- Un RT puede tener múltiples ONG asignadas.
CREATE TABLE IF NOT EXISTS public.organizaciones (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      TEXT NOT NULL,
  reprocann   TEXT,
  creado_por  UUID REFERENCES auth.users(id),
  activa      BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.organizaciones ENABLE ROW LEVEL SECURITY;


-- ── RT ↔ ORGANIZACIONES ───────────────────────────
-- Tabla pivote: un RT puede supervisar múltiples ONG.
CREATE TABLE IF NOT EXISTS public.rt_organizaciones (
  rt_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ong_id    UUID NOT NULL REFERENCES public.organizaciones(id) ON DELETE CASCADE,
  creado_en TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (rt_id, ong_id)
);
ALTER TABLE public.rt_organizaciones ENABLE ROW LEVEL SECURITY;


-- ── PERFILES DE USUARIO ──────────────────────────
-- Extiende la tabla de autenticación de Supabase.
-- ong_id: solo para rol='ong'. NULL para superadmin y rt.
CREATE TABLE IF NOT EXISTS public.perfiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      TEXT NOT NULL,
  rol         TEXT NOT NULL CHECK (rol IN ('superadmin','rt','ong')),
  ong_id      UUID REFERENCES public.organizaciones(id),
  creado_en   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;


-- ── FUNCIÓN HELPER — evita recursión en RLS ──────
-- SECURITY DEFINER: lee el rol del usuario actual sin activar RLS sobre perfiles.
CREATE OR REPLACE FUNCTION public.get_my_rol()
RETURNS TEXT AS $$
  SELECT rol FROM public.perfiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;


-- ── POLÍTICAS RLS (se definen DESPUÉS de crear todas las tablas) ──

-- perfiles
CREATE POLICY "usuario ve su propio perfil" ON public.perfiles
  FOR ALL USING (auth.uid() = id);
CREATE POLICY "superadmin ve todos los perfiles" ON public.perfiles
  FOR ALL USING (public.get_my_rol() = 'superadmin');
CREATE POLICY "rt ve perfiles de sus ong" ON public.perfiles
  FOR SELECT USING (
    public.get_my_rol() = 'rt'
    AND EXISTS (SELECT 1 FROM public.rt_organizaciones WHERE rt_id = auth.uid() AND ong_id = public.perfiles.ong_id)
  );

-- organizaciones
CREATE POLICY "superadmin ve todas las organizaciones" ON public.organizaciones
  FOR ALL USING (public.get_my_rol() = 'superadmin');
CREATE POLICY "rt ve y modifica sus organizaciones" ON public.organizaciones
  FOR ALL USING (
    public.get_my_rol() = 'rt'
    AND EXISTS (SELECT 1 FROM public.rt_organizaciones WHERE rt_id = auth.uid() AND ong_id = public.organizaciones.id)
  );
CREATE POLICY "ong ve su organizacion" ON public.organizaciones
  FOR SELECT USING (
    public.get_my_rol() = 'ong'
    AND EXISTS (SELECT 1 FROM public.perfiles WHERE id = auth.uid() AND ong_id = public.organizaciones.id)
  );

-- rt_organizaciones
CREATE POLICY "superadmin ve todas las asignaciones" ON public.rt_organizaciones
  FOR ALL USING (public.get_my_rol() = 'superadmin');
CREATE POLICY "rt ve sus asignaciones" ON public.rt_organizaciones
  FOR SELECT USING (rt_id = auth.uid());


-- ── MIGRACIÓN: ong_id en perfiles (si la tabla ya existía) ──
ALTER TABLE public.perfiles
  ADD COLUMN IF NOT EXISTS ong_id UUID REFERENCES public.organizaciones(id);

-- ── MIGRACIÓN: campo activo en perfiles (para desactivar RTs desde superadmin) ──
ALTER TABLE public.perfiles
  ADD COLUMN IF NOT EXISTS activo BOOLEAN DEFAULT TRUE;

GRANT UPDATE(activo) ON public.perfiles TO authenticated;

-- ── MIGRACIÓN: campos extra en organizaciones ────
ALTER TABLE public.organizaciones
  ADD COLUMN IF NOT EXISTS cuit             TEXT,
  ADD COLUMN IF NOT EXISTS localidad        TEXT,
  ADD COLUMN IF NOT EXISTS direccion        TEXT,
  ADD COLUMN IF NOT EXISTS email            TEXT,
  ADD COLUMN IF NOT EXISTS telefono         TEXT,
  ADD COLUMN IF NOT EXISTS fecha_inscripcion DATE,
  ADD COLUMN IF NOT EXISTS notas            TEXT;

-- ── TRIGGER: auto-crear perfil al aceptar invitación ──
-- Cuando Supabase crea un usuario vía inviteUserByEmail(),
-- este trigger lee el metadata (rol, ong_id) y crea la fila en perfiles.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.raw_user_meta_data->>'rol' IS NOT NULL THEN
    INSERT INTO public.perfiles (id, nombre, rol, ong_id)
    VALUES (
      NEW.id,
      COALESCE(
        NEW.raw_user_meta_data->>'nombre_contacto',
        split_part(NEW.email, '@', 1)
      ),
      NEW.raw_user_meta_data->>'rol',
      NULLIF(NEW.raw_user_meta_data->>'ong_id', '')::UUID
    )
    ON CONFLICT (id) DO UPDATE SET
      rol    = EXCLUDED.rol,
      ong_id = EXCLUDED.ong_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ── LOTES DE SEMILLAS ────────────────────────────
CREATE TABLE IF NOT EXISTS public.lotes_semillas (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre_lote       TEXT NOT NULL,
  fecha_adquisicion DATE NOT NULL,
  origen_tipo       TEXT NOT NULL CHECK (origen_tipo IN ('externo','interno')),
  proveedor         TEXT,
  lote_origen_id    UUID REFERENCES public.lotes_semillas(id),
  variedad          TEXT NOT NULL,
  stock_inicial     NUMERIC NOT NULL CHECK (stock_inicial > 0),
  unidad            TEXT NOT NULL, -- 'gramos', 'semillas', 'sobres', etc.
  stock_actual      NUMERIC NOT NULL,
  notas             TEXT,
  creado_en         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.lotes_semillas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "productor ve sus semillas" ON public.lotes_semillas
  FOR ALL USING (auth.uid() = usuario_id);


-- ── LOTES DE PLANTAS MADRE ───────────────────────
-- origen_tipo:
--   'externo'                → compra externa sin registro previo en el sistema
--   'esqueje_produccion'     → esqueje extraído de un lote de producción propio (lote_origen_id → lotes_produccion.id)
--   'esqueje_material_basico'→ esqueje de un lote de esquejes registrado como Material Básico (lote_origen_id → lotes_esquejes.id)
CREATE TABLE IF NOT EXISTS public.lotes_plantas_madre (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre_lote         TEXT NOT NULL,
  fecha_adquisicion   DATE NOT NULL,
  origen_tipo         TEXT NOT NULL CHECK (origen_tipo IN ('externo','esqueje_produccion','esqueje_material_basico')),
  proveedor           TEXT,                -- solo para origen 'externo'
  lote_origen_id      UUID,               -- referencia flexible: lotes_produccion o lotes_esquejes según origen_tipo
  variedad            TEXT NOT NULL,
  cantidad_inicial    INTEGER NOT NULL CHECK (cantidad_inicial > 0),
  cantidad_actual     INTEGER NOT NULL,
  esquejes_extraidos  INTEGER NOT NULL DEFAULT 0,
  notas               TEXT,
  creado_en           TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.lotes_plantas_madre ENABLE ROW LEVEL SECURITY;
CREATE POLICY "productor ve sus plantas madre" ON public.lotes_plantas_madre
  FOR ALL USING (auth.uid() = usuario_id);


-- ── LOTES DE ESQUEJES ────────────────────────────
-- RESTRICCIÓN DE NEGOCIO: origen_tipo NO puede ser 'lote_semillas_propio'
CREATE TABLE IF NOT EXISTS public.lotes_esquejes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  planta_madre_id   UUID REFERENCES public.lotes_plantas_madre(id),
  nombre_lote       TEXT NOT NULL,
  fecha_adquisicion DATE NOT NULL,
  origen_tipo       TEXT NOT NULL CHECK (origen_tipo IN ('externo','plantas_madre_propio','lote_produccion_propio')),
  proveedor         TEXT,
  lote_origen_id    UUID, -- referencia flexible según origen_tipo
  variedad          TEXT NOT NULL,
  stock_inicial     INTEGER NOT NULL CHECK (stock_inicial > 0),
  stock_actual      INTEGER NOT NULL,
  notas             TEXT,
  creado_en         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.lotes_esquejes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "productor ve sus esquejes" ON public.lotes_esquejes
  FOR ALL USING (auth.uid() = usuario_id);


-- ── BAJAS DE MATERIAL ────────────────────────────
CREATE TABLE IF NOT EXISTS public.bajas_material (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lote_id      UUID NOT NULL,
  lote_tipo    TEXT NOT NULL CHECK (lote_tipo IN ('semillas','esquejes','plantas_madre')),
  fecha_baja   DATE NOT NULL,
  cantidad_baja NUMERIC NOT NULL CHECK (cantidad_baja > 0),
  motivo_baja  TEXT NOT NULL,
  creado_en    TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.bajas_material ENABLE ROW LEVEL SECURITY;
CREATE POLICY "productor ve sus bajas" ON public.bajas_material
  FOR ALL USING (auth.uid() = usuario_id);


-- ── LOTES DE PRODUCCIÓN ──────────────────────────
CREATE TABLE IF NOT EXISTS public.lotes_produccion (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id            UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- origen del material (solo uno de los tres debe estar completado)
  origen_semilla_id     UUID REFERENCES public.lotes_semillas(id),
  origen_esqueje_id     UUID REFERENCES public.lotes_esquejes(id),
  origen_pm_id          UUID REFERENCES public.lotes_plantas_madre(id),
  -- sublotes
  lote_padre_id         UUID REFERENCES public.lotes_produccion(id),
  etapa_origen_division TEXT CHECK (etapa_origen_division IN ('nursery','vegetativa','floracion','cosecha')),
  motivo_division       TEXT,
  -- nomenclatura
  nombre_base           TEXT NOT NULL,  -- generado automáticamente, no editable
  nombre_agregado       TEXT,           -- obligatorio si es sublote
  nombre_completo       TEXT NOT NULL,  -- AUTO: nombre_base + ' → ' + nombre_agregado
  -- estado
  etapa_actual          TEXT NOT NULL DEFAULT 'nursery'
                          CHECK (etapa_actual IN ('nursery','vegetativa','floracion','cosecha','curado_secado','flores','completado','cerrado')),
  cantidad_inicial      INTEGER,
  fecha_inicio          DATE NOT NULL,
  notas                 TEXT,
  creado_en             TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.lotes_produccion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "productor ve sus lotes de produccion" ON public.lotes_produccion
  FOR ALL USING (auth.uid() = usuario_id);


-- ── ETAPA NURSERY ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.etapa_nursery (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id            UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  origen_material    TEXT NOT NULL CHECK (origen_material IN ('semillas','esquejes','plantas_madre')),
  fecha_inicio       DATE NOT NULL,
  fecha_fin          DATE,
  metodo_ingreso     TEXT NOT NULL CHECK (metodo_ingreso IN ('bandejas','directo')),
  bandejas           INTEGER,  -- solo si metodo_ingreso = 'bandejas'
  alveolos           INTEGER,  -- solo si metodo_ingreso = 'bandejas'
  cantidad_ingreso   INTEGER NOT NULL,
  material_utilizado NUMERIC,  -- solo para semillas (cantidad descontada del stock)
  cantidad_egreso    INTEGER,
  bajas              INTEGER DEFAULT 0,
  notas              TEXT,
  creado_en          TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_nursery ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via lote nursery" ON public.etapa_nursery
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid())
  );


-- ── ETAPA VEGETATIVA ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.etapa_vegetativa (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id          UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  fecha_inicio     DATE NOT NULL,  -- Trasplante
  fecha_fin        DATE,           -- Inicio de inducción
  cantidad_ingreso INTEGER NOT NULL, -- tomada del egreso de Nursery, confirmada por usuario
  cantidad_egreso  INTEGER,
  bajas            INTEGER DEFAULT 0,
  notas            TEXT,
  creado_en        TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_vegetativa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via lote vegetativa" ON public.etapa_vegetativa
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid())
  );


-- ── ETAPA FLORACIÓN ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.etapa_floracion (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id          UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  fecha_inicio     DATE NOT NULL,  -- tomada de fecha_fin Vegetativa, confirmada por usuario
  fecha_fin        DATE,           -- Cosecha
  cantidad_ingreso INTEGER NOT NULL, -- tomada del egreso de Vegetativa, confirmada por usuario
  cantidad_egreso  INTEGER,
  bajas            INTEGER DEFAULT 0,
  notas            TEXT,
  creado_en        TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_floracion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via lote floracion" ON public.etapa_floracion
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid())
  );


-- ── ETAPA COSECHA ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.etapa_cosecha (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id           UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  fecha_inicio      DATE NOT NULL,   -- propagada desde fecha_fin floración
  fecha_fin         DATE,
  peso_humedo_total NUMERIC,         -- peso post-cosecha (informativo, opcional)
  notas             TEXT,
  creado_en         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_cosecha ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via lote cosecha" ON public.etapa_cosecha
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid())
  );


-- ── ETAPA CURADO/SECADO ───────────────────────────
CREATE TABLE IF NOT EXISTS public.etapa_curado_secado (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id             UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  fecha_inicio        DATE,
  fecha_fin           DATE,
  peso_inicial_humedo NUMERIC,        -- opcional
  tiene_empaque       BOOLEAN NOT NULL DEFAULT FALSE,
  tara_empaque        NUMERIC,        -- solo si tiene_empaque = true
  unidad              TEXT NOT NULL DEFAULT 'gramos' CHECK (unidad IN ('gramos','kg')),
  peso_seco_final     NUMERIC,        -- siempre almacenado en gramos; pasa a stock_inicial de flores_cosechadas
  notas               TEXT,
  creado_en           TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_curado_secado ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via lote curado" ON public.etapa_curado_secado
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid())
  );


-- ── FLORES COSECHADAS ────────────────────────────
CREATE TABLE IF NOT EXISTS public.flores_cosechadas (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id          UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  stock_inicial    NUMERIC NOT NULL,  -- de peso_seco_final (confirmado) o ingresado manualmente
  stock_actual     NUMERIC NOT NULL,  -- se descuenta automáticamente con cada entrega
  fecha_disponible DATE,
  notas            TEXT,
  creado_en        TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.flores_cosechadas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via lote flores" ON public.flores_cosechadas
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid())
  );


-- ── ANÁLISIS DE CALIDAD ──────────────────────────
CREATE TABLE IF NOT EXISTS public.analisis_calidad (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flores_id        UUID NOT NULL REFERENCES public.flores_cosechadas(id) ON DELETE CASCADE,
  fecha_analisis   DATE NOT NULL,
  preparado_por    TEXT,              -- nombre de quien preparó la muestra
  thc_pct          NUMERIC(5,2),     -- porcentaje THC (0-100)
  cbd_pct          NUMERIC(5,2),     -- porcentaje CBD (0-100)
  humedad_pct      NUMERIC(5,2),     -- porcentaje humedad (0-100)
  otro_compuesto   TEXT,             -- nombre del compuesto adicional
  otro_valor       NUMERIC(10,4),    -- valor numérico del compuesto adicional
  otro_unidad      TEXT,             -- unidad definida por el usuario (%, mg, ppm, etc.)
  informe_url      TEXT,             -- URL al archivo en Supabase Storage
  informe_nombre   TEXT,             -- nombre original del archivo
  creado_en        TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.analisis_calidad ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via flores analisis" ON public.analisis_calidad
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.flores_cosechadas fc
      JOIN public.lotes_produccion lp ON lp.id = fc.lote_id
      WHERE fc.id = flores_id AND lp.usuario_id = auth.uid()
    )
  );


-- ── ENTREGAS A PACIENTES ─────────────────────────
CREATE TABLE IF NOT EXISTS public.entregas (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flores_id         UUID NOT NULL REFERENCES public.flores_cosechadas(id) ON DELETE CASCADE,
  nro_reprocann     TEXT NOT NULL,  -- OBLIGATORIO por regulación REPROCANN
  cantidad_otorgada NUMERIC NOT NULL CHECK (cantidad_otorgada > 0),
  fecha_entrega     DATE NOT NULL,
  notas             TEXT,
  creado_en         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via flores entregas" ON public.entregas
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.flores_cosechadas fc
      JOIN public.lotes_produccion lp ON lp.id = fc.lote_id
      WHERE fc.id = flores_id AND lp.usuario_id = auth.uid()
    )
  );


-- ================================================
-- MIGRACIONES — ejecutar en Supabase > SQL Editor
-- sobre una base ya existente (no recrear desde cero)
-- ================================================

-- ── MIGRACIÓN: lotes_plantas_madre ──────────────
-- Amplía origen_tipo y corrige lote_origen_id
ALTER TABLE public.lotes_plantas_madre
  DROP CONSTRAINT IF EXISTS lotes_plantas_madre_origen_tipo_check;

ALTER TABLE public.lotes_plantas_madre
  ADD CONSTRAINT lotes_plantas_madre_origen_tipo_check
    CHECK (origen_tipo IN ('externo','esqueje_produccion','esqueje_material_basico'));

-- Elimina la FK auto-referencial incorrecta y deja lote_origen_id como UUID libre
ALTER TABLE public.lotes_plantas_madre
  DROP CONSTRAINT IF EXISTS lotes_plantas_madre_lote_origen_id_fkey;

-- ── MIGRACIÓN: lotes_produccion — campos de cierre ──
ALTER TABLE public.lotes_produccion
  ADD COLUMN IF NOT EXISTS fecha_cierre DATE,
  ADD COLUMN IF NOT EXISTS motivo_cierre TEXT;

-- ── MIGRACIÓN: analisis_calidad — nuevos campos ──
ALTER TABLE public.analisis_calidad
  ALTER COLUMN laboratorio DROP NOT NULL;
ALTER TABLE public.analisis_calidad
  ADD COLUMN IF NOT EXISTS preparado_por  TEXT,
  ADD COLUMN IF NOT EXISTS thc_pct        NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS cbd_pct        NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS humedad_pct    NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS otro_compuesto TEXT,
  ADD COLUMN IF NOT EXISTS otro_valor     NUMERIC(10,4),
  ADD COLUMN IF NOT EXISTS otro_unidad    TEXT,
  ADD COLUMN IF NOT EXISTS informe_nombre TEXT;
-- Nota: informe_url ya existía — solo se agregan los campos nuevos

-- ── MIGRACIÓN: Supabase Storage — bucket analisis-calidad ──
-- Ejecutar en Supabase Dashboard > Storage > New bucket:
--   Nombre: analisis-calidad
--   Public: NO (privado)
-- Luego ejecutar esta policy para que usuarios autenticados puedan subir/leer sus archivos:
INSERT INTO storage.buckets (id, name, public)
  VALUES ('analisis-calidad', 'analisis-calidad', false)
  ON CONFLICT (id) DO NOTHING;

CREATE POLICY "usuarios pueden subir sus analisis"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'analisis-calidad');

CREATE POLICY "usuarios pueden leer sus analisis"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'analisis-calidad');


-- ── TABLA: material_documentos ────────────────────
-- Documentos de origen adjuntos a lotes de material básico
-- (Rótulo/Estampilla INASE y Facturas de compra)
CREATE TABLE IF NOT EXISTS public.material_documentos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id        UUID NOT NULL,
  lote_tipo      TEXT NOT NULL CHECK (lote_tipo IN ('semillas','esquejes','pm')),
  tipo_doc       TEXT NOT NULL CHECK (tipo_doc IN ('rotulo_estampilla','factura')),
  archivo_url    TEXT NOT NULL,
  archivo_nombre TEXT,
  creado_en      TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.material_documentos ENABLE ROW LEVEL SECURITY;
-- RLS: el usuario solo ve documentos de sus propios lotes
-- (verificamos via la tabla correspondiente según lote_tipo)
CREATE POLICY "usuario ve sus material_documentos"
  ON public.material_documentos FOR ALL
  USING (
    (lote_tipo = 'semillas'  AND EXISTS (SELECT 1 FROM public.lotes_semillas      WHERE id = lote_id AND usuario_id = auth.uid()))
    OR
    (lote_tipo = 'esquejes'  AND EXISTS (SELECT 1 FROM public.lotes_esquejes      WHERE id = lote_id AND usuario_id = auth.uid()))
    OR
    (lote_tipo = 'pm'        AND EXISTS (SELECT 1 FROM public.lotes_plantas_madre WHERE id = lote_id AND usuario_id = auth.uid()))
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.material_documentos TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.material_documentos TO authenticated;


-- ── MIGRACIÓN: Supabase Storage — bucket material-basico-docs ──
-- Bucket privado para documentos de Material Básico
INSERT INTO storage.buckets (id, name, public)
  VALUES ('material-basico-docs', 'material-basico-docs', false)
  ON CONFLICT (id) DO NOTHING;

CREATE POLICY "usuarios pueden subir docs material basico"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'material-basico-docs');

CREATE POLICY "usuarios pueden leer docs material basico"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'material-basico-docs');


-- ── MIGRACIÓN: Supabase Storage — bucket documentos-ong ──
-- Bucket privado para documentos adjuntos a ONGs/Asociaciones Civiles
INSERT INTO storage.buckets (id, name, public)
  VALUES ('documentos-ong', 'documentos-ong', false)
  ON CONFLICT (id) DO NOTHING;

CREATE POLICY "rt puede subir docs ong"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'documentos-ong');

CREATE POLICY "rt puede leer docs ong"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'documentos-ong');

CREATE POLICY "rt puede eliminar docs ong"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'documentos-ong');

-- ── TABLA: documentos_ong ────────────────────────
CREATE TABLE IF NOT EXISTS public.documentos_ong (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ong_id         UUID NOT NULL REFERENCES public.organizaciones(id) ON DELETE CASCADE,
  nombre_archivo TEXT NOT NULL,
  descripcion    TEXT,
  storage_path   TEXT NOT NULL,
  subido_por     UUID REFERENCES auth.users(id),
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.documentos_ong ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public.documentos_ong TO authenticated;

CREATE POLICY "rt ve docs de sus ongs" ON public.documentos_ong FOR SELECT
  USING (EXISTS (SELECT 1 FROM rt_organizaciones WHERE ong_id = documentos_ong.ong_id AND rt_id = auth.uid()));
CREATE POLICY "rt inserta docs" ON public.documentos_ong FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM rt_organizaciones WHERE ong_id = documentos_ong.ong_id AND rt_id = auth.uid()));
CREATE POLICY "rt elimina sus docs" ON public.documentos_ong FOR DELETE
  USING (subido_por = auth.uid());

-- ── MIGRACIÓN: fecha_baja en organizaciones ──────
ALTER TABLE public.organizaciones
  ADD COLUMN IF NOT EXISTS fecha_baja TIMESTAMPTZ;

-- ── MIGRACIÓN: correcciones de entregas ──
-- Guarda valores anteriores y nuevos de cada corrección de una entrega
CREATE TABLE IF NOT EXISTS public.entregas_correcciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entrega_id          UUID NOT NULL REFERENCES public.entregas(id) ON DELETE CASCADE,
  nro_reprocann_ant   TEXT,
  cantidad_ant        NUMERIC,
  notas_ant           TEXT,
  registrado_por_ant  TEXT,
  nro_reprocann_nvo   TEXT,
  cantidad_nvo        NUMERIC,
  notas_nvo           TEXT,
  corregido_por       TEXT,
  fecha_correccion    TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.entregas_correcciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via entregas correcciones" ON public.entregas_correcciones
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.entregas e
      JOIN public.flores_cosechadas fc ON fc.id = e.flores_id
      JOIN public.lotes_produccion lp ON lp.id = fc.lote_id
      WHERE e.id = entrega_id AND lp.usuario_id = auth.uid()
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.entregas_correcciones TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.entregas_correcciones TO authenticated;
