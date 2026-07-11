# AgroTrace — Resumen de sesión (2026-07-10, continuación)

## Lo que se hizo en esta sesión

### 1. Multi-tenancy en `portal_rt.html`

| Cambio | Descripción |
|--------|-------------|
| `init()` | Ahora carga el nombre real del RT desde `perfiles` vía Supabase. Ya no usa sessionStorage. |
| `cargarONGsSupabase()` | Ahora filtra por RT: `rt_organizaciones WHERE rt_id = CURRENT_USER_ID`. Antes traía TODAS las ONGs. |
| `cargarDetallesONGs()` | Mismo filtro por RT vía `rt_organizaciones`. |
| `supervisar()` | Ahora es `async`. Antes de navegar a v3, busca el `id` del admin ONG en `perfiles WHERE ong_id = ongId` y lo guarda en `sessionStorage` como `agrotrace_supervisando_ong_usuario_id`. |
| `cerrarSesion()` | Ahora llama a `sb.auth.signOut()` antes de limpiar sessionStorage. |

### 2. Modo supervisión en `agrotrace_prototipo_v3.html`

| Cambio | Descripción |
|--------|-------------|
| `cargarLotes()` | Si `agrotrace_supervisando_ong_usuario_id` está en sessionStorage, agrega `.eq('usuario_id', ongUid)` al query. |
| `cargarMaterial()` | Mismo filtro para `lotes_semillas`, `lotes_esquejes`, `lotes_plantas_madre`. |
| `volverPortalRT()` | Limpia `agrotrace_supervisando_ong_usuario_id` además de los otros keys. |

**Nota:** El modo supervisión funciona completo solo después de ejecutar el SQL de RLS (ver abajo).

---

## SQL a ejecutar en Supabase (en orden)

### SQL 1 — Tabla `variedades_rnc` (necesaria para portal superadmin)

```sql
CREATE TABLE IF NOT EXISTS public.variedades_rnc (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nro_rnc     TEXT UNIQUE NOT NULL,
  cultivar    TEXT NOT NULL,
  especie     TEXT,
  activa      BOOLEAN DEFAULT TRUE,
  fecha_carga TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.variedades_rnc ENABLE ROW LEVEL SECURITY;

CREATE POLICY "autenticados pueden leer variedades"
  ON public.variedades_rnc FOR SELECT TO authenticated USING (true);

CREATE POLICY "solo superadmin gestiona variedades"
  ON public.variedades_rnc FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'superadmin'));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.variedades_rnc TO authenticated;
```

### SQL 2 — Políticas RLS para modo supervisión RT

Ejecutar todo junto. Permite que el RT vea los datos de las ONGs que supervisa.

```sql
-- Helper: retorna true si el usuario actual es RT de la ONG del usuario dado
CREATE OR REPLACE FUNCTION public.es_rt_de_usuario(uid UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM perfiles p
    JOIN rt_organizaciones r ON r.ong_id = p.ong_id
    WHERE p.id = uid AND r.rt_id = auth.uid()
  );
END;
$$;

-- lotes_produccion
CREATE POLICY "rt_ve_lotes_supervisados" ON public.lotes_produccion
  FOR SELECT USING (public.es_rt_de_usuario(usuario_id));

-- etapa_nursery
CREATE POLICY "rt_ve_nursery_supervisado" ON public.etapa_nursery
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM lotes_produccion WHERE id = lote_id AND public.es_rt_de_usuario(usuario_id))
  );

-- etapa_vegetativa
CREATE POLICY "rt_ve_vegetativa_supervisada" ON public.etapa_vegetativa
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM lotes_produccion WHERE id = lote_id AND public.es_rt_de_usuario(usuario_id))
  );

-- etapa_floracion
CREATE POLICY "rt_ve_floracion_supervisada" ON public.etapa_floracion
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM lotes_produccion WHERE id = lote_id AND public.es_rt_de_usuario(usuario_id))
  );

-- etapa_cosecha
CREATE POLICY "rt_ve_cosecha_supervisada" ON public.etapa_cosecha
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM lotes_produccion WHERE id = lote_id AND public.es_rt_de_usuario(usuario_id))
  );

-- etapa_curado_secado
CREATE POLICY "rt_ve_curado_supervisado" ON public.etapa_curado_secado
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM lotes_produccion WHERE id = lote_id AND public.es_rt_de_usuario(usuario_id))
  );

-- flores_cosechadas
CREATE POLICY "rt_ve_flores_supervisadas" ON public.flores_cosechadas
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM lotes_produccion WHERE id = lote_id AND public.es_rt_de_usuario(usuario_id))
  );

-- entregas
CREATE POLICY "rt_ve_entregas_supervisadas" ON public.entregas
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM flores_cosechadas fc
      JOIN lotes_produccion lp ON lp.id = fc.lote_id
      WHERE fc.id = flores_id AND public.es_rt_de_usuario(lp.usuario_id)
    )
  );

-- material básico
CREATE POLICY "rt_ve_semillas_supervisadas" ON public.lotes_semillas
  FOR SELECT USING (public.es_rt_de_usuario(usuario_id));

CREATE POLICY "rt_ve_esquejes_supervisados" ON public.lotes_esquejes
  FOR SELECT USING (public.es_rt_de_usuario(usuario_id));

CREATE POLICY "rt_ve_pm_supervisadas" ON public.lotes_plantas_madre
  FOR SELECT USING (public.es_rt_de_usuario(usuario_id));
```

---

## Acciones en el Dashboard de Supabase

### Fix Edge Function `crear-rt` (bloqueante para crear RTs desde superadmin)

1. **Dashboard → Edge Functions → `crear-rt` → Eliminar**
2. **Edge Functions → Create new function** → nombre exacto: `crear-rt`
3. Pegar el contenido de `supabase/functions/crear-rt/index.ts`
4. **Settings → desactivar "Enforce JWT Verification"**

### Fix JWT en `crear-ong` e `invitar-ong`

- Dashboard → Edge Functions → `crear-ong` → Settings → desactivar "Enforce JWT Verification"
- Dashboard → Edge Functions → `invitar-ong` → Settings → desactivar "Enforce JWT Verification"

---

## Estado actual de pendientes

| Pendiente | Estado |
|-----------|--------|
| Multi-tenancy portal RT (filtrar ONGs por RT) | ✅ Implementado |
| Modo supervisión: ver lotes de ONG supervisada (código) | ✅ Implementado |
| Modo supervisión: RLS para ver datos de ONG supervisada | ❌ SQL listo — ejecutar en Supabase |
| Tabla `variedades_rnc` | ❌ SQL listo — ejecutar en Supabase |
| Fix Edge Function `crear-rt` | ❌ Acción en Dashboard |
| Fix JWT `crear-ong` / `invitar-ong` | ❌ Acción en Dashboard |
| Panel de alertas activas | ❌ Pendiente |
| Sistema de Reportes | ❌ Pendiente |
| Adaptación mobile | ❌ Pendiente |
