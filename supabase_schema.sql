-- ================================================
-- AgroTrace — Schema v5
-- Basado en agrotrace_prototipo_v3.html
-- Ejecutar completo en Supabase > SQL Editor
-- ================================================


-- ── PERFILES DE USUARIO ──────────────────────────
-- Extiende la tabla de autenticación de Supabase.
-- Se crea automáticamente al registrar un usuario.
CREATE TABLE IF NOT EXISTS public.perfiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      TEXT NOT NULL,
  rol         TEXT NOT NULL CHECK (rol IN ('productor','inspector','operador','administrador')),
  creado_en   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "usuario ve su propio perfil" ON public.perfiles
  FOR ALL USING (auth.uid() = id);


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
  etapa_origen_division TEXT CHECK (etapa_origen_division IN ('nursery','vegetativa','floracion')),
  motivo_division       TEXT,
  -- nomenclatura
  nombre_base           TEXT NOT NULL,  -- generado automáticamente, no editable
  nombre_agregado       TEXT,           -- obligatorio si es sublote
  nombre_completo       TEXT NOT NULL,  -- AUTO: nombre_base + ' → ' + nombre_agregado
  -- estado
  etapa_actual          TEXT NOT NULL DEFAULT 'nursery'
                          CHECK (etapa_actual IN ('nursery','vegetativa','floracion','cosecha_curado','flores','completado','cerrado')),
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


-- ── ETAPA COSECHA Y CURADO ───────────────────────
CREATE TABLE IF NOT EXISTS public.etapa_cosecha_curado (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id              UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  fecha_inicio_cosecha DATE NOT NULL,
  fecha_fin_cosecha    DATE,
  fecha_inicio_curado  DATE,
  fecha_fin_curado     DATE,
  peso_inicial_curado  NUMERIC NOT NULL,  -- en gramos
  tiene_empaque        BOOLEAN NOT NULL DEFAULT FALSE,
  tara_empaque         NUMERIC,           -- solo si tiene_empaque = true
  peso_seco_final      NUMERIC,           -- AUTO: peso_inicial si sin empaque; peso_inicial - tara si con empaque
  notas                TEXT,
  creado_en            TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_cosecha_curado ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via lote cosecha" ON public.etapa_cosecha_curado
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
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flores_id     UUID NOT NULL REFERENCES public.flores_cosechadas(id) ON DELETE CASCADE,
  fecha_analisis DATE NOT NULL,
  laboratorio   TEXT NOT NULL,
  informe_url   TEXT,  -- URL al archivo en Supabase Storage
  notas         TEXT,
  creado_en     TIMESTAMPTZ DEFAULT NOW()
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
