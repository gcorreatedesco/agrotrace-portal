-- ================================================
-- Migración: corrección de políticas RLS (auditoría 2026-08-23)
-- Ejecutar en Supabase > SQL Editor
-- ================================================

-- FIX 1: organizaciones — RT solo puede SELECT (no UPDATE/DELETE)
-- Antes era FOR ALL, lo que permitía a un RT dar de baja/reactivar ONGs.
DROP POLICY IF EXISTS "rt_organizaciones_asignadas" ON public.organizaciones;
CREATE POLICY "rt_organizaciones_asignadas" ON public.organizaciones
  FOR SELECT USING (
    public.get_my_rol() = 'rt'
    AND EXISTS (SELECT 1 FROM public.rt_organizaciones
                WHERE rt_id = auth.uid() AND ong_id = public.organizaciones.id)
  );

-- FIX 2: material_documentos — separar en 4 políticas con WITH CHECK explícito
-- FOR ALL USING (EXISTS(...)) no aplica correctamente el check en INSERT (comportamiento Supabase/PostgREST).
DROP POLICY IF EXISTS "material_docs_all" ON public.material_documentos;

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
