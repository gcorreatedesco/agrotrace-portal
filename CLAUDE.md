# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proyecto

**AgroTrace** — plataforma web de trazabilidad de producción de cannabis medicinal bajo el marco regulatorio REPROCANN (Argentina). La unidad de trazabilidad es el **lote** (no la planta individual). El sistema es multi-usuario: cada productor ve solo sus datos, el admin ve todo.

Repositorio GitHub: `github.com/gcorreatedesco/agrotrace-portal`

## Stack actual

- **Frontend:** HTML + CSS + JS vanilla. Cada pantalla es **un único `.html` autocontenido** con `<style>` y `<script>` inline — no hay archivos `.css`/`.js` separados, ni imports entre archivos. Migración futura planificada a React + Vite.
- **Backend:** Supabase (PostgreSQL + Auth + RLS + Edge Functions). El SDK v2 se carga desde CDN. Los portales `portal_superadmin.html` y `portal_rt.html` **ya usan datos reales de Supabase**. `agrotrace_prototipo_v3.html` aún usa arrays hardcodeados. La `anon key` es pública por diseño — la seguridad la provee RLS.
- **Base de datos:** 13+ tablas PostgreSQL definidas en `supabase_schema.sql` (ERD v5), creadas en Supabase con RLS activado. URL del proyecto: `https://jqkyifuyaxxwugrnjfnq.supabase.co`.
- **Edge Functions:** Deno/TypeScript, deployadas en Supabase. Manejan operaciones privilegiadas que requieren `service_role_key` (crear usuarios, etc.). Ver sección específica más abajo.
- No hay build, bundler, linter ni test runner. No hay `package.json`.

## Cómo ejecutar y desplegar

- **Ver una pantalla:** abrir el `.html` directamente en Chrome (`file://`) — no requiere servidor.
- **Producción:** GitHub Pages sirve `index.html`. Preview público: `https://gcorreatedesco.github.io/agrotrace-portal/` — un push a `main` lo actualiza.
- **App principal (v3):** `https://gcorreatedesco.github.io/agrotrace-portal/agrotrace_prototipo_v3.html`

GitHub Pages (repo público, gratis, HTTPS) es el hosting elegido para la etapa inicial. Al migrar a React + Vite habrá que reevaluar (Vercel/Netlify automatizan el build step).

## Archivos en el repositorio

| Archivo | Descripción |
|---------|-------------|
| `index.html` | Landing / login. `doLogin()` usa `sb.auth.signInWithPassword()` real. Redirige según rol: superadmin → `portal_superadmin.html`, rt → `portal_rt.html`, ong → `agrotrace_prototipo_v3.html`. |
| `portal_superadmin.html` | **Portal Superadmin.** Gestión de ONGs (crear, activar/desactivar, ver datos completos) y RTs. Conectado a Supabase real. Llama a Edge Functions `crear-ong` y `crear-rt`. |
| `portal_rt.html` | **Portal RT (Responsable Técnico).** Lista ONGs asignadas, modo supervisión (navega a v3 en contexto de esa ONG). Conectado a Supabase real con multi-tenancy por RT. Panel de alertas activas con 5 tipos de alerta y snooze por localStorage. |
| `agrotrace_prototipo_v3.html` | **Portal ONG.** App completa con sidebar, dashboard, lotes, sublotes, stock, wizards. Panel de alertas dinámico en el dashboard (Nursery > 25 días, stock < 10%). Conectado a Supabase real. |
| `agrotrace_prototipo_v2.html` | Versión anterior, referencia histórica. |
| `supabase_schema.sql` | Schema SQL completo (13+ tablas, RLS). Ejecutar en Supabase > SQL Editor para recrear la base. |
| `supabase/functions/crear-ong/index.ts` | Edge Function: crea org + usuario auth con rol `ong`. Incluye rollback si falla la creación del usuario. |
| `supabase/functions/crear-rt/index.ts` | Edge Function: crea usuario auth con rol `rt`. |
| `supabase/functions/solicitar-acceso/index.ts` | Edge Function: flujo de solicitud de acceso (estado sin verificar). |
| `AgroTrace_Arquitectura_Backend.html` | Documento de diseño: justificación de Supabase y arquitectura de datos. |
| `AgroTrace_Guia_Implementacion.html` | Documento de diseño: guía paso a paso del prototipo al sistema real. |
| `Proximospasos.md` | Hoja de ruta detallada. Leer antes de implementar integración con Supabase. |
| `summary.md` | Resumen de lo construido en las últimas sesiones. |

Los dos `AgroTrace_*.html` son documentación renderizada, no código de la app.

## Convenciones de código (prototipo)

- **Navegación SPA:** una sola página con varios `<div class="view" id="view-XXX">`; solo uno tiene la clase `active`. Se cambia con `showView('id')`. No hay router ni URLs distintas.
- **Datos hardcodeados:** el prototipo aún no persiste nada. Los datos de ejemplo viven en constantes JS al inicio del `<script>` (`LD` = lotes, `SD` = sublotes, `LM` = material básico por tipo). Render manual concatenando strings de HTML (p. ej. `rLC(l)` arma la tarjeta de un lote).
- **Nombres abreviados:** funciones y variables usan abreviaturas (`rLC`, `gw`, `selO`, `OA`, `UI`). Al extender, seguí el estilo del archivo que estás tocando.
- **Supabase en v3:** el cliente `sb` está inicializado globalmente pero no se usa todavía. La integración real requiere reemplazar cada array hardcodeado por consultas `await sb.from('tabla').select(...)` y agregar `async` a las funciones que los llamen.

## Diseño visual — reglas fijas

**Paleta de colores (no modificar sin consenso):**
```css
--soil:   #2C1F0E   /* fondo sidebar, hero */
--bark:   #4A3520
--sage:   #6B7F5E
--leaf:   #8EAA7B   /* acento decorativo */
--mist:   #C8D9BC
--dew:    #EDF2E8   /* fondos informativos */
--cream:  #F7F4EF   /* fondo general */
--accent: #4E7C3F   /* verde principal, botones */
--amber:  #854F0B   /* advertencias */
--purple: #534AB7   /* flores cosechadas, sublotes */
--error:  #B94A3A
```

**Tipografía:** DM Serif Display (títulos) + DM Sans 300/400/500 (cuerpo). Cargadas desde Google Fonts.

**Mobile First:** la interfaz se diseña primero para celular (campo), luego se expande a escritorio (reportes).

## Arquitectura del sistema — módulos

1. **Autenticación y roles** — tres roles activos en producción:
   - `superadmin` → `portal_superadmin.html`
   - `rt` → `portal_rt.html`
   - `ong` → `agrotrace_prototipo_v3.html`

   **Flujo de login:** `index.html` llama a `sb.auth.signInWithPassword()`. Si el login es exitoso, consulta `perfiles` para obtener el `rol` y redirige al portal correspondiente. El JWT de la sesión queda en `localStorage` (manejo automático de Supabase).

   **Alta de usuarios:**
   - RTs: el Superadmin completa el formulario en `portal_superadmin.html` → llama a Edge Function `crear-rt` con su JWT → la función crea el usuario en `auth.users` y el trigger `handle_new_user` inserta en `perfiles`.
   - ONGs: ídem con Edge Function `crear-ong`. También crea el registro en `organizaciones` y lo vincula al RT vía `rt_organizaciones`.

   **Tabla `perfiles`:** extiende `auth.users`. Campos: `id` (FK a auth.users), `nombre`, `rol`, `email`, `ong_id` (solo para rol `ong`). Se populan vía trigger `handle_new_user()` que lee `user_metadata` del JWT.

   **Usuarios en Supabase Auth (producción):**
   - Guillermo Correa — superadmin — `c6bafecb-5df5-4573-ad6d-3d0f328a8010`
   - Responsable Tecnico — rt — `0edfae60-9b1e-4c76-880e-d1851c4148b5`
   - Administrador — superadmin — `2a23866e-4704-49c8-bb35-23a7f483b7fc`

2. **Material Básico** — stock independiente con tres tipos: Semillas, Esquejes, Plantas Madre. Cada tipo tiene su propia tabla con `stock_actual`. Las bajas se registran en `bajas_material`.

3. **Lotes de Producción** — ciclo de 5 etapas secuenciales: Nursery → Vegetativa → Floración → Cosecha/Curado → Flores Cosechadas. Los lotes pueden dividirse en **sublotes** desde cualquier etapa. Sublotes y lotes principales comparten la tabla `lotes_produccion` (campo `lote_padre_id`).

4. **Alertas** — sistema de monitoreo activo en dos portales:

   **Portal ONG (`agrotrace_prototipo_v3.html`):**
   - Panel en el dashboard (columna derecha). Función `calcularAlertas()` corre al init y en cada operación que modifica datos (15 puntos del código).
   - Alerta 🟡 Nursery > 25 días sin avanzar: usa `l.fechaInicioRaw` (campo agregado a `mapLote`).
   - Alerta 🟡 Stock material básico < 10% del inicial: compara `stock / stockI` en `LM.semillas`, `LM.esquejes`, `LM.pm`.
   - Acciones: **Ver lote/stock ↗** (deep link) + **Posponer** (dropdown 7/15/30d, `localStorage` clave `agrotrace_alertas_snooze`).

   **Portal RT (`portal_rt.html`):**
   - Panel full-width entre métricas y grid de ONGs. Función `calcularAlertasRT()` corre al init.
   - Alerta 🟢 ONG inicia lote (últimos 7 días).
   - Alerta 🟢 ONG cosecha finalizada (últimos 7 días).
   - Alerta 🟡 Lote en Cosecha sin completar (días desde `etapa_cosecha.fecha_inicio`).
   - Alerta 🟡 ONG sin actividad > 60 días (por max `creado_en` de lotes).
   - Alerta 🟡 Flores disponibles sin entrega > 90 días (`flores_cosechadas.stock_actual > 0` + última `entregas.fecha_entrega`).
   - Acción: **Supervisar ↗** (navega al portal ONG en modo supervisión) + **Posponer** (clave `agrotrace_rt_alertas_snooze`).
   - `#met-alertas` muestra solo la cantidad de warns.

5. **Reportes** — pendiente de desarrollo.

## Lógica crítica de negocio

**Descuento de stock al confirmar Nursery:**
- Origen Semillas → descuenta `material_utilizado` de `lotes_semillas.stock_actual`
- Origen Esquejes externos → descuenta `cantidad_ingreso` de `lotes_esquejes.stock_actual`
- Origen Plantas Madre → solo vínculo, sin descuento; incrementa `esquejes_extraidos` (informativo)

**Restricción biológica:** `lotes_esquejes` NO puede tener como origen un "Lote de Semillas propio".

**Sublotes:**
- `nombre_completo` = `nombre_base` (raíz, AUTO, no editable) + " → " + `nombre_agregado` (libre)
- Sub-sublote: "Primavera 2025 → Invernadero Norte → Sector 1"
- La suma de plantas de todos los sublotes debe igualar la cantidad disponible del lote padre
- El lote padre queda "cerrado en [etapa]" y no avanza más

**Transición entre etapas:**
- Vegetativa toma `cantidad_ingreso` del egreso de Nursery (con confirmación del usuario)
- Floración toma `fecha_inicio` de `fecha_fin` de Vegetativa (con confirmación)
- Floración toma `cantidad_ingreso` del egreso de Vegetativa (con confirmación)

## Pendientes de implementación (integración Supabase)

Ver `Proximospasos.md` para el orden recomendado.

| Módulo | Estado |
|--------|--------|
| Panel de alertas — Portal ONG | ✅ Implementado (2026-07-12) |
| Panel de alertas — Portal RT | ✅ Implementado (2026-07-12) |
| Sidebar usuario ONG (org name + email + ícono "O") | ✅ Implementado (2026-07-13) |
| Sidebar usuario RT (nombre + email + ícono "RT" fijo) | ✅ Implementado (2026-07-13) |
| Fix sidebar: supervisor ve su propia identidad (no la supervisada) | ✅ Implementado (2026-07-13) |
| Fix RLS INSERT tablas etapas (WITH CHECK explícito) | ❌ SQL listo en `summary.md` — ejecutar en Supabase |
| SQL Políticas RLS para modo supervisión RT | ❌ SQL listo en `summary.md` — ejecutar en Supabase |
| SQL Tabla `variedades_rnc` | ❌ SQL listo en `summary.md` — ejecutar en Supabase |
| Fix Edge Function `crear-rt` (nombre incorrecto en Dashboard) | ❌ Acción manual en Dashboard |
| Fix JWT `crear-ong` (desactivar en Dashboard) | ❌ Acción manual en Dashboard |
| Sistema de Reportes | ❌ Pendiente |
| Adaptación mobile | ❌ Pendiente |

## Decisiones de arquitectura

**Patrón RLS correcto para tablas con subquery `EXISTS` (desde 2026-07-13)**

Las políticas que usan `EXISTS (SELECT 1 FROM otra_tabla ...)` en la condición **no deben usar `FOR ALL USING`**. En Supabase/PostgREST, ese patrón no aplica correctamente el USING como WITH CHECK para INSERT. El patrón correcto es declarar políticas separadas por operación:

```sql
-- CORRECTO
CREATE POLICY "tabla_select" ON public.mi_tabla
  FOR SELECT USING (EXISTS (...));
CREATE POLICY "tabla_insert" ON public.mi_tabla
  FOR INSERT WITH CHECK (EXISTS (...));
CREATE POLICY "tabla_update" ON public.mi_tabla
  FOR UPDATE USING (EXISTS (...));
CREATE POLICY "tabla_delete" ON public.mi_tabla
  FOR DELETE USING (EXISTS (...));

-- INCORRECTO (falla INSERT silenciosamente en Supabase)
CREATE POLICY "tabla_all" ON public.mi_tabla
  FOR ALL USING (EXISTS (...));
```

Las políticas directas sin subquery (`auth.uid() = usuario_id`) sí pueden usar `FOR ALL USING` sin problemas.

**Sidebar usuario: el sidebar siempre muestra la identidad del usuario logueado (desde 2026-07-13)**

El sidebar nunca muestra la identidad de la entidad supervisada — eso se muestra en los banners de supervisión (`sa-bar`, `rt-bar`). Estructura por rol:
- **ONG**: ícono `O`, nombre de la organización (de `organizaciones.nombre` via `ong_id`), email.
- **RT**: ícono `RT` fijo, nombre personal del RT (de `perfiles.nombre`), email.
- **Superadmin supervisando desde portal RT**: ícono `SA`, nombre del superadmin, email.
- **RT o superadmin supervisando desde portal ONG**: ícono `RT`/`SA`, nombre propio, email.

**Alta de ONGs: solo el Superadmin (desde 2026-07-11)**
El RT no puede crear ONGs. Solo el Superadmin crea ONGs (vía `crear-ong` Edge Function) y las asigna a un RT en el momento del alta. El RT solo supervisa las ONGs que el Superadmin le asignó.
- La Edge Function `invitar-ong` existe en el código local pero **no está deployada en Supabase** y no se usa.
- El portal RT no muestra "Nueva Asociación Civil" — el empty state explica que el Superadmin gestiona el alta.

## Edge Functions — arquitectura y estado

### Patrón de implementación

Todas las Edge Functions siguen este patrón:
1. Verificar header `Authorization: Bearer <jwt>`
2. Resolver el usuario con `supabaseAdmin.auth.getUser(token)`
3. Consultar `perfiles` para validar que `rol = 'superadmin'`
4. Ejecutar operación
5. En caso de error: **rollback explícito** (ver abajo)

### Por qué desactivar JWT verification en Supabase Dashboard

El preflight `OPTIONS` del browser NO lleva JWT. Con `verify_jwt=true` (default), Supabase rechaza el `OPTIONS` con 401 sin headers CORS → el browser reporta "Failed to fetch". **La verificación de rol se hace internamente en cada función**, por eso es seguro desactivar el verify del gateway.

### Patrón de rollback en `crear-ong`

La creación de una ONG es un proceso de 2 pasos: 1) insertar en `organizaciones`, 2) crear usuario en `auth.users`. Si el paso 2 falla (email duplicado, etc.), el paso 1 ya se ejecutó → ONG huérfana. El fix es declarar `org` y `newUserId` **fuera del bloque `try`** para que el `catch` pueda acceder a ellos y hacer DELETE si corresponde.

### Cómo llama el frontend a las Edge Functions

```js
const { data: { session } } = await sb.auth.getSession()
const res = await fetch('https://jqkyifuyaxxwugrnjfnq.supabase.co/functions/v1/crear-ong', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${session.access_token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({ nombre_org, email_admin, password_admin, nombre_admin, cuit, localidad, reprocann, rt_id })
})
```

La API REST de Auth (`/auth/v1/admin/users`) requiere tanto `Authorization: Bearer <key>` como `apikey: <key>` y devuelve un objeto plano `{ id, email }` (no `{ user: { id, email } }`).

### Estado de Edge Functions (al 2026-07-11)

| Función | En Supabase | JWT desactivado | Estado |
|---------|-------------|-----------------|--------|
| `crear-ong` | ✅ URL correcta | ❌ pendiente | ⚠️ falla preflight hasta desactivar JWT |
| `crear-rt` | ⚠️ nombre interno incorrecto (`clever-endpoint`) | ❌ pendiente | ❌ 404 |
| `invitar-ong` | ❌ no deployada | — | No se usa — el RT no crea ONGs |
| `solicitar-acceso` | ✅ | ? | Sin verificar |

**Fix pendiente `crear-rt`:** eliminar la función `crear-rt` en Dashboard (que internamente se llama `clever-endpoint`) y crearla de nuevo con el nombre exacto `crear-rt`, luego desactivar JWT.

**Fix pendiente `crear-ong`:** solo desactivar JWT en Dashboard → Edge Functions → `crear-ong` → Settings.
