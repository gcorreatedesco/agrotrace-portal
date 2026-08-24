-- ================================================
-- AgroTrace — Schema v6
-- Actualizado 2026-08-20
-- RLS unificado con funciones helper SECURITY DEFINER
-- en todas las tablas (superadmin / RT / ONG).
--
-- Para instalación nueva:
--   DROP SCHEMA public CASCADE;
--   CREATE SCHEMA public;
--   GRANT ALL ON SCHEMA public TO postgres, public;
--   (luego ejecutar este archivo completo)
-- ================================================


-- ── ORGANIZACIONES ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.organizaciones (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre            TEXT NOT NULL,
  reprocann         TEXT,
  cuit              TEXT,
  localidad         TEXT,
  direccion         TEXT,
  email             TEXT,
  telefono          TEXT,
  fecha_inscripcion DATE,
  notas             TEXT,
  fecha_baja        TIMESTAMPTZ,
  creado_por        UUID REFERENCES auth.users(id),
  activa            BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.organizaciones ENABLE ROW LEVEL SECURITY;


-- ── RT ↔ ORGANIZACIONES ──────────────────────────
CREATE TABLE IF NOT EXISTS public.rt_organizaciones (
  rt_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ong_id    UUID NOT NULL REFERENCES public.organizaciones(id) ON DELETE CASCADE,
  creado_en TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (rt_id, ong_id)
);
ALTER TABLE public.rt_organizaciones ENABLE ROW LEVEL SECURITY;


-- ── PERFILES ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.perfiles (
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre              TEXT NOT NULL,
  rol                 TEXT NOT NULL CHECK (rol IN ('superadmin','rt','ong')),
  ong_id              UUID REFERENCES public.organizaciones(id),
  email               TEXT,
  activo              BOOLEAN DEFAULT TRUE,
  apellido            TEXT,
  cuit                TEXT,
  titulo_profesional  TEXT,
  colegio_profesional TEXT,
  nro_matricula       TEXT,
  provincia           TEXT,
  ciudad              TEXT,
  direccion           TEXT,
  creado_en           TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;


-- ── FUNCIONES HELPER (SECURITY DEFINER) ──────────
-- Centralizan la lógica de acceso y evitan recursión en RLS.
-- Al ser SECURITY DEFINER corren como owner y no activan RLS interno.

CREATE OR REPLACE FUNCTION public.get_my_rol()
RETURNS TEXT AS $$
  SELECT rol FROM public.perfiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.get_my_ong_id()
RETURNS UUID AS $$
  SELECT ong_id FROM public.perfiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.es_superadmin()
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'superadmin');
END;
$$;

CREATE OR REPLACE FUNCTION public.es_rt_de_usuario(uid UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM perfiles p
    JOIN rt_organizaciones rto ON rto.ong_id = p.ong_id
    WHERE p.id = uid AND rto.rt_id = auth.uid()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.puede_acceder_usuario(uid UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN auth.uid() = uid OR es_superadmin() OR es_rt_de_usuario(uid);
END;
$$;

CREATE OR REPLACE FUNCTION public.puede_acceder_lote(lote_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID;
BEGIN
  SELECT usuario_id INTO v_uid FROM lotes_produccion WHERE id = lote_id;
  RETURN puede_acceder_usuario(v_uid);
END;
$$;

CREATE OR REPLACE FUNCTION public.puede_acceder_flores(flores_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lote UUID;
BEGIN
  SELECT lote_id INTO v_lote FROM flores_cosechadas WHERE id = flores_id;
  RETURN puede_acceder_lote(v_lote);
END;
$$;

CREATE OR REPLACE FUNCTION public.puede_acceder_entrega(entrega_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_flores UUID;
BEGIN
  SELECT flores_id INTO v_flores FROM entregas WHERE id = entrega_id;
  RETURN puede_acceder_flores(v_flores);
END;
$$;


-- ── POLÍTICAS RLS — perfiles, organizaciones, rt_org ──

CREATE POLICY "usuario ve su propio perfil" ON public.perfiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "usuario actualiza su propio perfil" ON public.perfiles
  FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "superadmin ve todos los perfiles" ON public.perfiles
  FOR ALL USING (public.get_my_rol() = 'superadmin');
CREATE POLICY "rt ve perfiles de sus ong" ON public.perfiles
  FOR SELECT USING (
    public.get_my_rol() = 'rt'
    AND EXISTS (SELECT 1 FROM public.rt_organizaciones
                WHERE rt_id = auth.uid() AND ong_id = public.perfiles.ong_id)
  );

CREATE POLICY "superadmin_organizaciones" ON public.organizaciones
  FOR ALL USING (public.get_my_rol() = 'superadmin');
CREATE POLICY "rt_organizaciones_asignadas" ON public.organizaciones
  FOR SELECT USING (
    public.get_my_rol() = 'rt'
    AND EXISTS (SELECT 1 FROM public.rt_organizaciones
                WHERE rt_id = auth.uid() AND ong_id = public.organizaciones.id)
  );
CREATE POLICY "ong_ve_su_org" ON public.organizaciones
  FOR SELECT USING (
    public.get_my_rol() = 'ong'
    AND EXISTS (SELECT 1 FROM public.perfiles
                WHERE id = auth.uid() AND ong_id = public.organizaciones.id)
  );

CREATE POLICY "superadmin_rt_org" ON public.rt_organizaciones
  FOR ALL USING (public.get_my_rol() = 'superadmin');
CREATE POLICY "rt_ve_sus_asignaciones" ON public.rt_organizaciones
  FOR SELECT USING (rt_id = auth.uid());
CREATE POLICY "ong_ve_su_rt" ON public.rt_organizaciones
  FOR SELECT USING (ong_id = public.get_my_ong_id());
CREATE POLICY "ong_ve_perfil_de_su_rt" ON public.perfiles
  FOR SELECT USING (
    public.get_my_rol() = 'ong'
    AND EXISTS (
      SELECT 1 FROM public.rt_organizaciones
      WHERE rt_id = public.perfiles.id
        AND ong_id = public.get_my_ong_id()
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.organizaciones TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.rt_organizaciones TO authenticated;
GRANT SELECT ON public.perfiles TO authenticated;
GRANT UPDATE(activo) ON public.perfiles TO authenticated;
GRANT UPDATE(nombre, apellido, cuit, titulo_profesional, colegio_profesional, nro_matricula, provincia, ciudad, direccion)
  ON public.perfiles TO authenticated;


-- ── TRIGGER: crear perfil al registrar usuario ────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.raw_user_meta_data->>'rol' IS NOT NULL THEN
    INSERT INTO public.perfiles (id, nombre, rol, ong_id, email)
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'nombre_contacto', split_part(NEW.email, '@', 1)),
      NEW.raw_user_meta_data->>'rol',
      NULLIF(NEW.raw_user_meta_data->>'ong_id', '')::UUID,
      NEW.email
    )
    ON CONFLICT (id) DO UPDATE SET
      rol    = EXCLUDED.rol,
      ong_id = EXCLUDED.ong_id,
      email  = EXCLUDED.email;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ── VARIEDADES RNC ────────────────────────────────
-- (definida antes de lotes_produccion por la FK rnc_id)
CREATE TABLE IF NOT EXISTS public.variedades_rnc (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nro_rnc     TEXT UNIQUE NOT NULL,
  cultivar    TEXT NOT NULL,
  especie     TEXT,
  activa      BOOLEAN DEFAULT TRUE,
  fecha_carga TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.variedades_rnc ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rnc_select" ON public.variedades_rnc
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "rnc_manage" ON public.variedades_rnc
  FOR ALL TO authenticated
  USING (es_superadmin()) WITH CHECK (es_superadmin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.variedades_rnc TO authenticated;


-- ── MATERIAL BÁSICO ───────────────────────────────

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
  unidad            TEXT NOT NULL,
  stock_actual      NUMERIC NOT NULL,
  notas             TEXT,
  creado_en         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.lotes_semillas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "semillas_all" ON public.lotes_semillas
  FOR ALL USING (puede_acceder_usuario(usuario_id)) WITH CHECK (puede_acceder_usuario(usuario_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lotes_semillas TO authenticated;


CREATE TABLE IF NOT EXISTS public.lotes_plantas_madre (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre_lote         TEXT NOT NULL,
  fecha_adquisicion   DATE NOT NULL,
  origen_tipo         TEXT NOT NULL CHECK (origen_tipo IN ('externo','esqueje_produccion','esqueje_material_basico')),
  proveedor           TEXT,
  lote_origen_id      UUID,
  variedad            TEXT NOT NULL,
  cantidad_inicial    INTEGER NOT NULL CHECK (cantidad_inicial > 0),
  cantidad_actual     INTEGER NOT NULL,
  esquejes_extraidos  INTEGER NOT NULL DEFAULT 0,
  notas               TEXT,
  creado_en           TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.lotes_plantas_madre ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pm_all" ON public.lotes_plantas_madre
  FOR ALL USING (puede_acceder_usuario(usuario_id)) WITH CHECK (puede_acceder_usuario(usuario_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lotes_plantas_madre TO authenticated;


CREATE TABLE IF NOT EXISTS public.lotes_esquejes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  planta_madre_id   UUID REFERENCES public.lotes_plantas_madre(id),
  nombre_lote       TEXT NOT NULL,
  fecha_adquisicion DATE NOT NULL,
  origen_tipo       TEXT NOT NULL CHECK (origen_tipo IN ('externo','plantas_madre_propio','lote_produccion_propio')),
  proveedor         TEXT,
  lote_origen_id    UUID,
  variedad          TEXT NOT NULL,
  stock_inicial     INTEGER NOT NULL CHECK (stock_inicial > 0),
  stock_actual      INTEGER NOT NULL,
  notas             TEXT,
  creado_en         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.lotes_esquejes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "esquejes_all" ON public.lotes_esquejes
  FOR ALL USING (puede_acceder_usuario(usuario_id)) WITH CHECK (puede_acceder_usuario(usuario_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lotes_esquejes TO authenticated;


CREATE TABLE IF NOT EXISTS public.bajas_material (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lote_id       UUID NOT NULL,
  lote_tipo     TEXT NOT NULL CHECK (lote_tipo IN ('semillas','esquejes','plantas_madre')),
  fecha_baja    DATE NOT NULL,
  cantidad_baja NUMERIC NOT NULL CHECK (cantidad_baja > 0),
  motivo_baja   TEXT NOT NULL,
  creado_en     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.bajas_material ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bajas_all" ON public.bajas_material
  FOR ALL USING (puede_acceder_usuario(usuario_id)) WITH CHECK (puede_acceder_usuario(usuario_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bajas_material TO authenticated;


-- ── LOTES DE PRODUCCIÓN ───────────────────────────
CREATE TABLE IF NOT EXISTS public.lotes_produccion (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id            UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  origen_semilla_id     UUID REFERENCES public.lotes_semillas(id),
  origen_esqueje_id     UUID REFERENCES public.lotes_esquejes(id),
  origen_pm_id          UUID REFERENCES public.lotes_plantas_madre(id),
  lote_padre_id         UUID REFERENCES public.lotes_produccion(id),
  etapa_origen_division TEXT CHECK (etapa_origen_division IN ('nursery','vegetativa','floracion','cosecha')),
  motivo_division       TEXT,
  nombre_base           TEXT NOT NULL,
  nombre_agregado       TEXT,
  nombre_completo       TEXT NOT NULL,
  etapa_actual          TEXT NOT NULL DEFAULT 'nursery'
                          CHECK (etapa_actual IN ('nursery','vegetativa','floracion','cosecha','curado_secado','flores','completado','cerrado')),
  cantidad_inicial      INTEGER,
  fecha_inicio          DATE NOT NULL,
  fecha_cierre          DATE,
  motivo_cierre         TEXT,
  rnc_id                UUID REFERENCES public.variedades_rnc(id),
  plantas_descartadas   INTEGER DEFAULT 0,
  notas                 TEXT,
  creado_en             TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.lotes_produccion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "lotes_produccion_all" ON public.lotes_produccion
  FOR ALL USING (puede_acceder_usuario(usuario_id)) WITH CHECK (puede_acceder_usuario(usuario_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lotes_produccion TO authenticated;


-- ── ETAPAS ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.etapa_nursery (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id             UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  origen_material     TEXT NOT NULL CHECK (origen_material IN ('semillas','esquejes','plantas_madre')),
  fecha_inicio        DATE NOT NULL,
  fecha_fin           DATE,
  metodo_ingreso      TEXT NOT NULL CHECK (metodo_ingreso IN ('bandejas','directo')),
  bandejas            INTEGER,
  alveolos            INTEGER,
  cantidad_ingreso    INTEGER NOT NULL,
  material_utilizado  NUMERIC,
  cantidad_egreso     INTEGER,
  bajas               INTEGER DEFAULT 0,
  plantas_descartadas INTEGER DEFAULT 0,
  notas               TEXT,
  creado_en           TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_nursery ENABLE ROW LEVEL SECURITY;
CREATE POLICY "nursery_all" ON public.etapa_nursery
  FOR ALL USING (puede_acceder_lote(lote_id)) WITH CHECK (puede_acceder_lote(lote_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.etapa_nursery TO authenticated;


CREATE TABLE IF NOT EXISTS public.etapa_vegetativa (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id             UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  fecha_inicio        DATE NOT NULL,
  fecha_fin           DATE,
  cantidad_ingreso    INTEGER NOT NULL,
  cantidad_egreso     INTEGER,
  bajas               INTEGER DEFAULT 0,
  plantas_descartadas INTEGER DEFAULT 0,
  notas               TEXT,
  creado_en           TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_vegetativa ENABLE ROW LEVEL SECURITY;
CREATE POLICY "vegetativa_all" ON public.etapa_vegetativa
  FOR ALL USING (puede_acceder_lote(lote_id)) WITH CHECK (puede_acceder_lote(lote_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.etapa_vegetativa TO authenticated;


CREATE TABLE IF NOT EXISTS public.etapa_floracion (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id             UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  fecha_inicio        DATE NOT NULL,
  fecha_fin           DATE,
  cantidad_ingreso    INTEGER NOT NULL,
  cantidad_egreso     INTEGER,
  bajas               INTEGER DEFAULT 0,
  plantas_descartadas INTEGER DEFAULT 0,
  notas               TEXT,
  creado_en           TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_floracion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "floracion_all" ON public.etapa_floracion
  FOR ALL USING (puede_acceder_lote(lote_id)) WITH CHECK (puede_acceder_lote(lote_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.etapa_floracion TO authenticated;


CREATE TABLE IF NOT EXISTS public.etapa_cosecha (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id             UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  fecha_inicio        DATE NOT NULL,
  fecha_fin           DATE,
  peso_humedo_total   NUMERIC,
  plantas_descartadas INTEGER DEFAULT 0,
  notas               TEXT,
  creado_en           TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_cosecha ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cosecha_all" ON public.etapa_cosecha
  FOR ALL USING (puede_acceder_lote(lote_id)) WITH CHECK (puede_acceder_lote(lote_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.etapa_cosecha TO authenticated;


CREATE TABLE IF NOT EXISTS public.etapa_curado_secado (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id             UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  fecha_inicio        DATE,
  fecha_fin           DATE,
  peso_inicial_humedo NUMERIC,
  tiene_empaque       BOOLEAN NOT NULL DEFAULT FALSE,
  tara_empaque        NUMERIC,
  unidad              TEXT NOT NULL DEFAULT 'gramos' CHECK (unidad IN ('gramos','kg')),
  peso_seco_final     NUMERIC,
  notas               TEXT,
  creado_en           TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.etapa_curado_secado ENABLE ROW LEVEL SECURITY;
CREATE POLICY "curado_all" ON public.etapa_curado_secado
  FOR ALL USING (puede_acceder_lote(lote_id)) WITH CHECK (puede_acceder_lote(lote_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.etapa_curado_secado TO authenticated;


-- ── FLORES COSECHADAS ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.flores_cosechadas (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lote_id          UUID NOT NULL REFERENCES public.lotes_produccion(id) ON DELETE CASCADE,
  stock_inicial    NUMERIC NOT NULL,
  stock_actual     NUMERIC NOT NULL,
  fecha_disponible DATE,
  notas            TEXT,
  creado_en        TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.flores_cosechadas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "flores_all" ON public.flores_cosechadas
  FOR ALL USING (puede_acceder_lote(lote_id)) WITH CHECK (puede_acceder_lote(lote_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.flores_cosechadas TO authenticated;


-- ── ANÁLISIS DE CALIDAD ───────────────────────────
CREATE TABLE IF NOT EXISTS public.analisis_calidad (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flores_id         UUID NOT NULL REFERENCES public.flores_cosechadas(id) ON DELETE CASCADE,
  fecha_analisis    DATE NOT NULL,
  preparado_por     TEXT,
  thc_pct           NUMERIC(5,2),
  cbd_pct           NUMERIC(5,2),
  cbn_pct           NUMERIC(5,2),
  cbg_pct           NUMERIC(5,2),
  humedad_pct       NUMERIC(5,2),
  tipo_analitica    TEXT,
  entidad_analitica TEXT,
  id_cromatografia  TEXT,
  otro_compuesto    TEXT,
  otro_valor        NUMERIC(10,4),
  otro_unidad       TEXT,
  informe_url       TEXT,
  informe_nombre    TEXT,
  creado_en         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.analisis_calidad ENABLE ROW LEVEL SECURITY;
CREATE POLICY "analisis_all" ON public.analisis_calidad
  FOR ALL USING (puede_acceder_flores(flores_id)) WITH CHECK (puede_acceder_flores(flores_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.analisis_calidad TO authenticated;


-- ── ENTREGAS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.entregas (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flores_id         UUID NOT NULL REFERENCES public.flores_cosechadas(id) ON DELETE CASCADE,
  nro_reprocann     TEXT NOT NULL,
  cantidad_otorgada NUMERIC NOT NULL CHECK (cantidad_otorgada > 0),
  fecha_entrega     DATE NOT NULL,
  notas             TEXT,
  creado_en         TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
CREATE POLICY "entregas_all" ON public.entregas
  FOR ALL USING (puede_acceder_flores(flores_id)) WITH CHECK (puede_acceder_flores(flores_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.entregas TO authenticated;


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
CREATE POLICY "correcciones_all" ON public.entregas_correcciones
  FOR ALL USING (puede_acceder_entrega(entrega_id)) WITH CHECK (puede_acceder_entrega(entrega_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.entregas_correcciones TO authenticated;


-- ── MATERIAL DOCUMENTOS ───────────────────────────
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
CREATE POLICY "material_docs_select" ON public.material_documentos
  FOR SELECT USING (
    es_superadmin()
    OR (lote_tipo = 'semillas' AND EXISTS (SELECT 1 FROM public.lotes_semillas      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'esquejes' AND EXISTS (SELECT 1 FROM public.lotes_esquejes      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'pm'       AND EXISTS (SELECT 1 FROM public.lotes_plantas_madre WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
  );
CREATE POLICY "material_docs_insert" ON public.material_documentos
  FOR INSERT WITH CHECK (
    es_superadmin()
    OR (lote_tipo = 'semillas' AND EXISTS (SELECT 1 FROM public.lotes_semillas      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'esquejes' AND EXISTS (SELECT 1 FROM public.lotes_esquejes      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'pm'       AND EXISTS (SELECT 1 FROM public.lotes_plantas_madre WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
  );
CREATE POLICY "material_docs_update" ON public.material_documentos
  FOR UPDATE
  USING (
    es_superadmin()
    OR (lote_tipo = 'semillas' AND EXISTS (SELECT 1 FROM public.lotes_semillas      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'esquejes' AND EXISTS (SELECT 1 FROM public.lotes_esquejes      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'pm'       AND EXISTS (SELECT 1 FROM public.lotes_plantas_madre WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
  ) WITH CHECK (
    es_superadmin()
    OR (lote_tipo = 'semillas' AND EXISTS (SELECT 1 FROM public.lotes_semillas      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'esquejes' AND EXISTS (SELECT 1 FROM public.lotes_esquejes      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'pm'       AND EXISTS (SELECT 1 FROM public.lotes_plantas_madre WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
  );
CREATE POLICY "material_docs_delete" ON public.material_documentos
  FOR DELETE USING (
    es_superadmin()
    OR (lote_tipo = 'semillas' AND EXISTS (SELECT 1 FROM public.lotes_semillas      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'esquejes' AND EXISTS (SELECT 1 FROM public.lotes_esquejes      WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
    OR (lote_tipo = 'pm'       AND EXISTS (SELECT 1 FROM public.lotes_plantas_madre WHERE id = lote_id AND puede_acceder_usuario(usuario_id)))
  );
GRANT SELECT, INSERT, UPDATE, DELETE ON public.material_documentos TO authenticated;


-- ── DOCUMENTOS ONG ────────────────────────────────
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
CREATE POLICY "docs_ong_select" ON public.documentos_ong
  FOR SELECT USING (
    es_superadmin()
    OR EXISTS (SELECT 1 FROM rt_organizaciones WHERE ong_id = documentos_ong.ong_id AND rt_id = auth.uid())
  );
CREATE POLICY "docs_ong_insert" ON public.documentos_ong
  FOR INSERT WITH CHECK (
    es_superadmin()
    OR EXISTS (SELECT 1 FROM rt_organizaciones WHERE ong_id = documentos_ong.ong_id AND rt_id = auth.uid())
  );
CREATE POLICY "docs_ong_delete" ON public.documentos_ong
  FOR DELETE USING (subido_por = auth.uid() OR es_superadmin());


-- ── ESTABLECIMIENTOS ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.establecimientos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      TEXT NOT NULL,
  calle       TEXT,
  nro         TEXT,
  ciudad      TEXT,
  partido     TEXT,
  provincia   TEXT,
  latitud     FLOAT8,
  longitud    FLOAT8,
  activo      BOOLEAN DEFAULT TRUE,
  creado_en   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.establecimientos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "establecimientos_all" ON public.establecimientos
  FOR ALL USING (puede_acceder_usuario(usuario_id)) WITH CHECK (puede_acceder_usuario(usuario_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.establecimientos TO authenticated;


-- ── PACIENTES ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pacientes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  numero        INTEGER NOT NULL,
  nombre        TEXT NOT NULL,
  apellido      TEXT NOT NULL,
  nro_reprocann TEXT,
  tel_contacto  TEXT,
  activo        BOOLEAN DEFAULT TRUE,
  creado_en     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.pacientes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pacientes_all" ON public.pacientes
  FOR ALL USING (puede_acceder_usuario(usuario_id)) WITH CHECK (puede_acceder_usuario(usuario_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pacientes TO authenticated;


-- ── ACTIVIDADES LOG ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.actividades_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tipo        TEXT NOT NULL,
  descripcion TEXT NOT NULL,
  lote_id     UUID REFERENCES public.lotes_produccion(id) ON DELETE SET NULL,
  meta        JSONB,
  creado_en   TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.actividades_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "actividades_all" ON public.actividades_log
  FOR ALL USING (puede_acceder_usuario(usuario_id)) WITH CHECK (puede_acceder_usuario(usuario_id));
GRANT SELECT, INSERT ON public.actividades_log TO authenticated;


-- ── STORAGE BUCKETS ───────────────────────────────
INSERT INTO storage.buckets (id, name, public)
  VALUES ('analisis-calidad', 'analisis-calidad', false)
  ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public)
  VALUES ('material-basico-docs', 'material-basico-docs', false)
  ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public)
  VALUES ('documentos-ong', 'documentos-ong', false)
  ON CONFLICT (id) DO NOTHING;

CREATE POLICY "storage_analisis_insert" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'analisis-calidad');
CREATE POLICY "storage_analisis_select" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'analisis-calidad');

CREATE POLICY "storage_matdocs_insert" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'material-basico-docs');
CREATE POLICY "storage_matdocs_select" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'material-basico-docs');

CREATE POLICY "storage_docong_insert" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'documentos-ong');
CREATE POLICY "storage_docong_select" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'documentos-ong');
CREATE POLICY "storage_docong_delete" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'documentos-ong');
