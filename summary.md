# AgroTrace — Resumen de sesión (2026-07-10)

## Lo que se hizo en esta sesión

### 1. Bugs corregidos en `portal_superadmin.html`

| Bug | Descripción | Fix aplicado |
|-----|-------------|--------------|
| `nombre_completo` inexistente | La tabla `perfiles` tiene `nombre`, no `nombre_completo` | Renombrado en `cargarRTs()`, `renderRTs()`, `cargarDemo()`, `abrirModalNuevaONG()` |
| `org_id` inexistente | `rt_organizaciones` tiene `ong_id`, no `org_id` | Corregido en `cargarRTs()` |
| `organizaciones.usuario_id` inexistente | El usuario de una ONG va por `perfiles.ong_id` | `cargarRTs()` reescrita: rt → ong_id → perfiles.ong_id → usuario_id → lotes |
| Join roto en `cargarONGs()` | FK `rt_organizaciones.rt_id` apunta a `auth.users`, no a `perfiles`; Supabase no puede seguir el join automáticamente | Reescrita con 2 queries separadas |
| `email` no existe en `perfiles` | El frontend esperaba `email` al listar RTs | Agregado via migración SQL (ver abajo) |

### 2. Migración SQL ejecutada en Supabase

```sql
-- Agregar email a perfiles
ALTER TABLE public.perfiles ADD COLUMN IF NOT EXISTS email TEXT;

-- Trigger actualizado para guardar email al crear usuario
CREATE OR REPLACE FUNCTION public.handle_new_user() ...

-- Permitir leer perfiles desde el cliente autenticado
GRANT SELECT ON public.perfiles TO authenticated;
```
**Estado: ejecutado exitosamente.**

### 3. Problema identificado en Edge Function `crear-rt`

**Causa del "Failed to fetch" al crear RT:**

La función fue deployada con el nombre interno `clever-endpoint` en vez de `crear-rt`.

| | URL |
|--|-----|
| Lo que llama el frontend | `/functions/v1/crear-rt` |
| Donde existe la función | `/functions/v1/clever-endpoint` |

El frontend llama a una URL que no existe → Supabase devuelve 404 en el preflight OPTIONS → CORS falla → "Failed to fetch".

**Además:** ambas Edge Functions tienen `verify_jwt = true` (default). El preflight OPTIONS del browser no lleva JWT, por lo que Supabase rechaza el OPTIONS antes de llegar al código de la función. Hay que desactivar JWT verification (las funciones hacen su propia verificación de rol superadmin internamente).

---

## Pendientes para la próxima sesión

### Prioridad 1 — Fix Edge Function `crear-rt` (bloqueante)
1. Supabase Dashboard → Edge Functions → eliminar la función `crear-rt` (internamente `clever-endpoint`)
2. Crear nueva función con nombre exacto `crear-rt`
3. Pegar contenido de `supabase/functions/crear-rt/index.ts`
4. En Settings → desactivar "Enforce JWT Verification"

### Prioridad 2 — Fix JWT verification en `crear-ong`
- Supabase Dashboard → Edge Functions → `crear-ong` → Settings → desactivar JWT verification

### Prioridad 3 — Crear usuario RT de prueba manualmente
Mientras las Edge Functions no estén corregidas, crear un RT así:
1. Supabase → Authentication → Users → Create new user (email, password, auto-confirm ✅)
2. Anotar el UUID generado
3. Ejecutar en SQL Editor:
```sql
INSERT INTO public.perfiles (id, nombre, rol, email)
VALUES ('<UUID>', 'Nombre del RT', 'rt', 'email@ejemplo.com')
ON CONFLICT (id) DO UPDATE SET
  rol = 'rt', nombre = EXCLUDED.nombre, email = EXCLUDED.email;
```

### Prioridad 4 — Crear tabla `variedades_rnc`
La vista "Variedades RNC" del superadmin da 404 porque la tabla no existe.
Ejecutar el SQL que está al final de `supabase_schema.sql`:
```sql
CREATE TABLE public.variedades_rnc (
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
```

### Pendientes de más largo plazo
- Multi-tenancy: portal RT con datos reales de Supabase
- Panel de alertas activas
- Sistema de reportes (3 tipos)
- Adaptación mobile
