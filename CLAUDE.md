# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proyecto

**AgroTrace** — plataforma web de trazabilidad de producción de cannabis medicinal bajo el marco regulatorio REPROCANN (Argentina). La unidad de trazabilidad es el **lote** (no la planta individual). El sistema es multi-usuario: cada productor ve solo sus datos, el admin ve todo.

Repositorio GitHub: `github.com/gcorreatedesco/agrotrace-portal`

## Stack actual

- **Frontend:** HTML + CSS + JS vanilla. Cada pantalla es **un único `.html` autocontenido** con `<style>` y `<script>` inline — no hay archivos `.css`/`.js` separados, ni imports entre archivos. Migración futura planificada a React + Vite.
- **Backend:** Supabase planificado (PostgreSQL + Auth + RLS). El SDK está cargado en v3 desde CDN y el cliente `sb` está inicializado, pero **ningún dato real fluye aún** — todo el frontend usa arrays JS hardcodeados. La `anon key` es pública por diseño — la seguridad la provee RLS, no esconder la clave.
- **Base de datos:** 13 tablas PostgreSQL definidas en `supabase_schema.sql` (ERD v5), creadas en Supabase con RLS activado. La conexión entre el HTML y esas tablas aún no está implementada. URL del proyecto: `https://jqkyifuyaxxwugrnjfnq.supabase.co`.
- No hay build, bundler, linter ni test runner. No hay `package.json`.

## Cómo ejecutar y desplegar

- **Ver una pantalla:** abrir el `.html` directamente en Chrome (`file://`) — no requiere servidor.
- **Producción:** GitHub Pages sirve `index.html`. Preview público: `https://gcorreatedesco.github.io/agrotrace-portal/` — un push a `main` lo actualiza.
- **App principal (v3):** `https://gcorreatedesco.github.io/agrotrace-portal/agrotrace_prototipo_v3.html`

GitHub Pages (repo público, gratis, HTTPS) es el hosting elegido para la etapa inicial. Al migrar a React + Vite habrá que reevaluar (Vercel/Netlify automatizan el build step).

## Archivos en el repositorio

| Archivo | Descripción |
|---------|-------------|
| `index.html` | Portal de acceso (login). Auth es demo: `doLogin()` solo valida campos, aún no usa Supabase Auth. |
| `agrotrace_prototipo_v3.html` | **Versión activa.** App completa con sidebar, dashboard, lotes, sublotes, stock, wizards. El SDK de Supabase está cargado y `sb = supabase.createClient(...)` está inicializado, pero **`sb` no se usa en ninguna parte** — todos los datos son hardcodeados. La integración real aún no está implementada. |
| `agrotrace_prototipo_v2.html` | Versión anterior, referencia histórica. |
| `supabase_schema.sql` | Schema SQL completo (13 tablas, RLS). Ejecutar en Supabase > SQL Editor para recrear la base. |
| `AgroTrace_Arquitectura_Backend.html` | Documento de diseño: justificación de Supabase y arquitectura de datos. |
| `AgroTrace_Guia_Implementacion.html` | Documento de diseño: guía paso a paso del prototipo al sistema real. |
| `Proximospasos.md` | Hoja de ruta detallada para la próxima sesión (pasos 1–7 ordenados). Leer antes de implementar integración con Supabase. |
| `summary.md` | Resumen de lo construido en la última sesión. |

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

1. **Autenticación** — roles: `productor`, `inspector`, `operador`, `administrador`. El `index.html` implementa el flujo UI completo pero aún sin Supabase Auth real. La tabla `perfiles` extiende `auth.users` de Supabase.

2. **Material Básico** — stock independiente con tres tipos: Semillas, Esquejes, Plantas Madre. Cada tipo tiene su propia tabla con `stock_actual`. Las bajas se registran en `bajas_material`.

3. **Lotes de Producción** — ciclo de 5 etapas secuenciales: Nursery → Vegetativa → Floración → Cosecha/Curado → Flores Cosechadas. Los lotes pueden dividirse en **sublotes** desde cualquier etapa. Sublotes y lotes principales comparten la tabla `lotes_produccion` (campo `lote_padre_id`).

4. **Reportes** — pendiente de desarrollo.

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

## Decisiones de arquitectura

**Alta de ONGs: solo el Superadmin (desde 2026-07-11)**
El RT no puede crear ONGs. Solo el Superadmin crea ONGs (vía `crear-ong` Edge Function) y las asigna a un RT en el momento del alta. El RT solo supervisa las ONGs que el Superadmin le asignó.
- La Edge Function `invitar-ong` existe en el código local pero **no está deployada en Supabase** y no se usa.
- El portal RT no muestra "Nueva Asociación Civil" — el empty state explica que el Superadmin gestiona el alta.

## Estado de Edge Functions (al 2026-07-11)

| Función | En Supabase | JWT desactivado | Funciona |
|---------|-------------|-----------------|----------|
| `crear-ong` | ✅ | ❌ pendiente | ⚠️ |
| `crear-rt` | ⚠️ nombre incorrecto | ❌ pendiente | ❌ |
| `invitar-ong` | ❌ no deployada | — | — |
| `solicitar-acceso` | ✅ | ? | ? |
