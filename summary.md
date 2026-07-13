# AgroTrace — Resumen de sesión (2026-07-13)

## Lo que se hizo en esta sesión

### 1. Sidebar usuario — Portal ONG (`agrotrace_prototipo_v3.html`)

Nuevo diseño del bloque de usuario en el sidebar lateral: reemplazó el nombre personal por la **identidad de la organización**.

**Estructura visual:**
```
[O]  Asoc. Civil Los Tilos        ← nombre de la org (trunca con … si es largo)
     admin@lostilos.com           ← email de login
```

**Cambios técnicos:**
- Ícono: `O` fijo en HTML (eliminó el cálculo dinámico de iniciales).
- CSS: nuevas clases `.user-info` (`min-width:0; overflow:hidden` para que el ellipsis funcione en flex), `.user-org` (texto principal, `text-overflow:ellipsis`), `.user-email` (segunda línea, color más tenue). Se eliminó `.user-nm`.
- JS en `initApp()`: reemplazó la lectura de `sessionStorage('agrotrace_user')` por una query real a `perfiles` para obtener `ong_id`, luego query a `organizaciones` para obtener el nombre.
- `title="..."` en el elemento `.user-org` → tooltip con el nombre completo al hacer hover.
- **Modo supervisión** (RT o superadmin accediendo al portal ONG): muestra la identidad propia del supervisor (`RT`/`SA` + nombre + email), no el nombre de la ONG que se está supervisando. La ONG supervisada ya aparece en el banner `rt-bar`.

### 2. Sidebar usuario — Portal RT (`portal_rt.html`)

**Estructura visual:**
```
[RT] Juan García                  ← nombre del RT
     rt@ejemplo.com               ← email de login
```

**Cambios técnicos:**
- Ícono: `RT` fijo en HTML. Se eliminó el cálculo de iniciales (`split/map/join`) que lo sobreescribía en JS.
- CSS: `.user-info`, `.user-email` (reemplaza `.user-role` que mostraba "Responsable Técnico" hardcodeado).
- JS en `init()`:
  - Rama normal: `sb-email` se puebla con `session.user.email`.
  - Rama superadmin supervisando un RT: en lugar de mostrar el nombre del RT supervisado, ahora muestra el nombre del superadmin logueado (`perfiles` del `session.user.id`) con ícono `SA`. El RT supervisado solo aparece en el banner `sa-bar`.

### 3. Fix crítico RLS — flujo completo de lotes

**Síntoma:** `Error guardando cosecha: new row violates row-level security policy for table "etapa_cosecha"`

**Causa raíz:** Todas las tablas de etapas usaban `FOR ALL USING (EXISTS(...))` sin `WITH CHECK` explícito. PostgreSQL especifica que USING debería usarse como WITH CHECK si no se define uno, pero **en la implementación de Supabase/PostgREST las políticas con subquery `EXISTS` en USING no se evalúan correctamente para INSERT** — el INSERT queda sin check válido y la RLS lo bloquea.

**Por qué fallaba en cosecha y no antes:** Las etapas previas (nursery, vegetativa, floración) tenían registros existentes de sesiones anteriores → el código tomaba el camino UPDATE. La cosecha era la primera etapa sin registro previo → tomaba el camino INSERT → RLS bloqueaba.

**Fix:** Reemplazar `FOR ALL USING` por políticas explícitas separadas por operación con `WITH CHECK` en INSERT:

```sql
-- Ejemplo (aplicado a las 8 tablas afectadas):
DROP POLICY IF EXISTS "via lote cosecha" ON public.etapa_cosecha;
CREATE POLICY "cosecha_select" ON public.etapa_cosecha
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid()));
CREATE POLICY "cosecha_insert" ON public.etapa_cosecha
  FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid()));
CREATE POLICY "cosecha_update" ON public.etapa_cosecha
  FOR UPDATE USING (EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid()));
CREATE POLICY "cosecha_delete" ON public.etapa_cosecha
  FOR DELETE USING (EXISTS (SELECT 1 FROM public.lotes_produccion WHERE id = lote_id AND usuario_id = auth.uid()));
```

**Tablas corregidas (misma operación para cada una):**
`etapa_nursery`, `etapa_vegetativa`, `etapa_floracion`, `etapa_cosecha`, `etapa_curado_secado`, `flores_cosechadas`, `entregas`, `analisis_calidad`

`supabase_schema.sql` fue actualizado con el patrón correcto. El SQL completo para ejecutar en Supabase Dashboard está en el chat de la sesión del 2026-07-13.

---

## Estado actual de pendientes

| Pendiente | Estado |
|-----------|--------|
| Sidebar usuario ONG/RT (org name + email + ícono correcto) | ✅ Implementado (2026-07-13) |
| Fix sidebar: supervisor ve su propia identidad (no la supervisada) | ✅ Implementado (2026-07-13) |
| Fix RLS INSERT en etapas de lote (WITH CHECK explícito) | ❌ SQL listo — ejecutar en Supabase |
| SQL Políticas RLS para modo supervisión RT | ❌ SQL listo en summary anterior — ejecutar en Supabase |
| SQL Tabla `variedades_rnc` | ❌ SQL listo en summary anterior — ejecutar en Supabase |
| Fix Edge Function `crear-rt` | ❌ Acción en Dashboard |
| Fix JWT `crear-ong` | ❌ Acción en Dashboard |
| Sistema de Reportes | ❌ Pendiente |
| Adaptación mobile | ❌ Pendiente |

---

# AgroTrace — Resumen de sesión (2026-07-12)

## Lo que se hizo en esta sesión

### 1. Sistema de alertas — Portal ONG (`agrotrace_prototipo_v3.html`)

**Panel dinámico** en el dashboard (columna derecha, 260px): reemplazó los 2 items hardcodeados. Detecta y muestra alertas en tiempo real sin necesidad de logout/login.

**Tipos de alerta:**
- 🟡 **Nursery > 25 días sin avanzar** — lotes con `etapa_actual = 'nursery'` y `fechaInicioRaw` > 25 días. Muestra nombre del lote y días transcurridos.
- 🟡 **Stock de material básico bajo (<10%)** — recorre `LM.semillas`, `LM.esquejes`, `LM.pm`. Muestra nombre del lote de material, cantidad restante y % del inicial.

**Acciones por alerta:**
- **`Ver lote ↗`** / **`Ver stock ↗`** — deep link directo al lote o al detalle del material.
- **`··· Posponer`** — dropdown 7/15/30 días. Snooze guardado en `localStorage` (clave `agrotrace_alertas_snooze`). La alerta reaparece automáticamente al vencer el plazo.
- La alerta desaparece sola si el problema se resuelve (lote avanza, stock se repone).

**Recálculo automático:** `calcularAlertas()` se llama en 15 puntos del código — en cada operación que modifica lotes o stock (baja de material, avance de etapa, cierre de lote, sublote creado, nuevo material).

**Funciones nuevas:** `calcularAlertas()`, `renderAlertas()`, `getSnoozed()`, `esSnoozedRT()`, `snoozeAlerta()`, `toggleSnooze()`, `irAStock()`.
**Cambios en `mapLote()`:** agrega `fechaInicioRaw: row.fecha_inicio` para que `calcularAlertas` pueda comparar fechas.

---

### 2. Sistema de alertas — Portal RT (`portal_rt.html`)

**Panel full-width** entre las métricas y el grid de ONGs. Se calcula al cargar el portal consultando Supabase.

**5 tipos de alerta:**

| # | Tipo | Condición | Query |
|---|------|-----------|-------|
| 1 | 🟢 Info | ONG inicia nuevo lote (últimos 7 días) | `lotes_produccion WHERE etapa='nursery' AND creado_en >= hace7d` |
| 2 | 🟢 Info | ONG cosecha finalizada (últimos 7 días) | `etapa_curado_secado WHERE fecha_fin >= hace7d` para lotes en 'flores' |
| 3 | 🟡 Warn | Lote en Cosecha sin completar | `etapa_cosecha.fecha_inicio` para lotes en etapa 'cosecha' |
| 4 | 🟡 Warn | ONG sin actividad > 60 días | Max `creado_en` por ONG user < hace60d |
| 5 | 🟡 Warn | Flores disponibles sin entrega > 90 días | `flores_cosechadas.stock_actual > 0` + última `entregas.fecha_entrega` |

**Flujo de queries:** `perfiles` (1 query) → `lotes_produccion` (1 query) → 3 queries paralelas (`etapa_cosecha`, `etapa_curado_secado`, `flores_cosechadas`) → 1 query secuencial de `entregas`.

**Acciones por alerta:**
- **`Supervisar ↗`** — navega al portal ONG en modo supervisión de esa ONG (llama a `supervisar(ongId, ongNombre)`).
- **`··· Posponer`** — dropdown 7/15/30 días. Snooze en `localStorage` (clave `agrotrace_rt_alertas_snooze`, separado del de ONG).

**Métrica `#met-alertas`** en el header muestra solo la cantidad de warns (no las info).

**Funciones nuevas:** `calcularAlertasRT()`, `renderAlertasRT()`, `accionAlertaRT()`, `getSnoozedRT()`, `esSnoozedRT()`, `snoozeAlertaRT()`, `toggleSnoozeRT()`, `fmtDateRT()`.

---

## Estado actual de pendientes

| Pendiente | Estado |
|-----------|--------|
| Panel de alertas — Portal ONG | ✅ Implementado |
| Panel de alertas — Portal RT | ✅ Implementado |
| SQL Políticas RLS para modo supervisión RT | ❌ SQL listo en summary anterior |
| SQL Tabla `variedades_rnc` | ❌ SQL listo en summary anterior |
| Fix Edge Function `crear-rt` | ❌ Acción en Dashboard |
| Fix JWT `crear-ong` | ❌ Acción en Dashboard |
| Sistema de Reportes | ❌ Pendiente |
| Adaptación mobile | ❌ Pendiente |

---

# AgroTrace — Resumen de sesión (2026-07-11)

## Lo que se hizo en esta sesión

### 1. Bug fix: ONG huérfana en `crear-ong` Edge Function

**Problema:** cuando la creación del usuario auth fallaba (email duplicado, etc.), el registro en `organizaciones` ya estaba insertado y quedaba huérfano (sin usuario admin asociado).

**Fix:** declarar `org` y `newUserId` fuera del bloque `try` para que el `catch` pueda acceder a ellos y hacer rollback:
- Si `newUserId` tiene valor → `DELETE /auth/v1/admin/users/:id`
- Si `org` tiene valor → `DELETE FROM rt_organizaciones WHERE ong_id` + `DELETE FROM organizaciones WHERE id`

Se encontraron 2 ONGs huérfanas de sesiones anteriores:
- `203a1d51-...` — "Asociacion segunda de RT1"
- `af161578-...` — "Asociacion Civil Ojitos Rojos RT1"

SQL para limpiarlas:
```sql
DELETE FROM public.rt_organizaciones WHERE ong_id IN (
  '203a1d51-b6ef-4c8a-ba0a-ef961a649123',
  'af161578-1b62-4f8a-9bf6-d1e93531b0f2'
);
DELETE FROM public.organizaciones WHERE id IN (
  '203a1d51-b6ef-4c8a-ba0a-ef961a649123',
  'af161578-1b62-4f8a-9bf6-d1e93531b0f2'
);
```

### 2. Modal "Ver datos" de ONG en `portal_superadmin.html`

**Nueva funcionalidad:** botón "Ver datos" en cada fila de la tabla de ONGs abre un modal con todos los datos del alta:

| Campo | Fuente |
|-------|--------|
| Nombre | `organizaciones.nombre` |
| CUIT | `organizaciones.cuit` |
| Localidad | `organizaciones.localidad` |
| Nº REPROCANN | `organizaciones.reprocann` |
| RT asignado | `perfiles.nombre` del RT vía `rt_organizaciones` |
| Estado | `organizaciones.activa` |
| Alta en el sistema | `organizaciones.creado_en` |
| Nombre admin | `perfiles.nombre WHERE rol='ong' AND ong_id=...` |
| Email admin | `perfiles.email WHERE rol='ong' AND ong_id=...` |

`cargarONGs()` fue extendida para traer también `cuit`, `creado_en`, y la info del admin ONG desde `perfiles` en una segunda consulta. Todo se almacena en `ALL_ONGS` para que `verONG(id)` solo lea del array en memoria.

---

## Acciones pendientes en Supabase Dashboard

| Acción | Estado |
|--------|--------|
| Ejecutar SQL para borrar 2 ONGs huérfanas | ❌ pendiente |
| Deploy `crear-ong` actualizado (con rollback) | ❌ pendiente |
| Desactivar JWT en `crear-ong` | ❌ pendiente |
| Recrear `crear-rt` con nombre correcto | ❌ pendiente |
| Desactivar JWT en `crear-rt` | ❌ pendiente |

---

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
