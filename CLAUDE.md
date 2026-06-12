# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proyecto

**AgroTrace** — plataforma web de trazabilidad de producción de cannabis medicinal bajo el marco regulatorio REPROCANN (Argentina). La unidad de trazabilidad es el **lote** (no la planta individual). El sistema es multi-usuario: cada productor ve solo sus datos, el admin ve todo.

Repositorio GitHub: `github.com/gcorreatedesco/agrotrace-portal`

## Stack actual

- **Frontend:** HTML + CSS + JS vanilla. Cada pantalla es **un único `.html` autocontenido** con `<style>` y `<script>` inline — no hay archivos `.css`/`.js` separados, ni imports entre archivos. Migración futura planificada a React + Vite.
- **Backend:** aún no implementado. Los documentos de diseño (`AgroTrace_Arquitectura_Backend.html`) **recomiendan Supabase** (PostgreSQL + Auth + API automática + Row Level Security por `productor_id`). El aislamiento entre productores se hará con RLS, no en el cliente. El frontend se conecta a Supabase desde el navegador con el Supabase JS SDK; la `anon key` es pública por diseño (lo que protege los datos es el RLS, no esconder la clave).
- **Base de datos:** PostgreSQL (ERD definido, aún no implementado).
- No hay build, bundler, linter ni test runner. No hay `package.json`.

## Cómo ejecutar y desplegar

- **Ver una pantalla:** abrir el `.html` directamente en Chrome (`file://`) — no requiere servidor.
- **Producción:** GitHub Pages sirve `index.html`. Preview público: https://gcorreatedesco.github.io/agrotrace-portal/ — un push a `main` lo actualiza.

### Decisión de hosting del frontend: GitHub Pages (etapa inicial)

Para empezar, el frontend se aloja en **GitHub Pages**, no en Vercel. GitHub Pages y Vercel cumplen el mismo rol (servir archivos estáticos); ninguno guarda datos — eso es Supabase. GitHub Pages ya está activo, es gratis y con HTTPS, y evita configurar un servicio extra. Vale recordar:

- **Repo público:** GitHub Pages gratis lo exige. Es seguro aquí porque el frontend no tiene secretos (la lógica REPROCANN, el descuento de stock y la `anon key` se protegen vía Supabase + RLS, no escondiendo el código).
- **Reevaluar al migrar a React + Vite:** ahí hace falta un paso de *build*. GitHub Pages lo soporta vía GitHub Action; Vercel/Netlify lo hacen automático. Recién entonces conviene comparar de nuevo.

## Archivos en el repositorio

| Archivo | Descripción |
|---------|-------------|
| `index.html` | Portal de acceso (login). Es lo que se publica en GitHub Pages. |
| `agrotrace_prototipo_v2.html` | Prototipo funcional de la app interna (dashboard, lotes, sublotes, stock, alta de lote). Aún no enlazado desde `index.html`. |
| `AgroTrace_Arquitectura_Backend.html` | Documento de diseño: justificación del backend (Supabase) y arquitectura de datos. |
| `AgroTrace_Guia_Implementacion.html` | Documento de diseño: guía paso a paso del prototipo al sistema real. |

Los dos `AgroTrace_*.html` son **documentación renderizada como página**, no código de la app. No están enlazados ni forman parte del producto.

## Convenciones de código (prototipo)

- **Navegación SPA:** una sola página con varios `<div class="view" id="view-XXX">`; solo uno tiene la clase `active`. Se cambia con `showView('id')`. No hay router ni URLs distintas.
- **Datos hardcodeados:** el prototipo no persiste nada. Los datos de ejemplo viven en constantes JS al inicio del `<script>` (`LD` = lotes, `SD` = sublotes, `LM` = material básico por tipo). Render manual concatenando strings de HTML (p. ej. `rLC(l)` arma la tarjeta de un lote).
- **Nombres abreviados:** funciones y variables del prototipo usan abreviaturas (`rLC`, `gw`, `selO`, `OA`, `UI`). Al extender, seguí el estilo del archivo que estás tocando.
- **Auth es demo:** en `index.html`, `doLogin()` solo valida campos y muestra un `alert` — no autentica ni redirige al prototipo todavía.

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

1. **Autenticación** — roles: `productor`, `inspector`, `operador`, `administrador`. El `index.html` ya implementa el flujo completo: selección de rol → login → recuperación de contraseña.

2. **Material Básico** — stock independiente con tres tipos: Semillas, Esquejes, Plantas Madre. Cada tipo tiene su propia tabla con `stock_actual` calculado automáticamente. Las bajas se registran en una tabla compartida `BAJAS_MATERIAL`.

3. **Lotes de Producción** — ciclo de 5 etapas secuenciales: Nursery → Vegetativa → Floración → Cosecha/Curado → Flores Cosechadas. Cada lote referencia su material de origen. Los lotes pueden dividirse en **sublotes** desde cualquier etapa (Nursery, Vegetativa, Floración).

4. **Reportes** — pendiente de desarrollo.

## Lógica crítica de negocio

**Descuento de stock al confirmar Nursery:**
- Origen Semillas → descuenta `material_utilizado` de `LOTES_SEMILLAS.stock_actual`
- Origen Esquejes externos → descuenta `cantidad_ingreso` de `LOTES_ESQUEJES.stock_actual`
- Origen Plantas Madre → solo vínculo, sin descuento; incrementa `esquejes_extraidos` (informativo)

**Sublotes:**
- `nombre_completo` = `nombre_base` (raíz, AUTO no editable) + " → " + `nombre_agregado` (libre)
- Sub-sublote: "Primavera 2025 → Invernadero Norte → Sector 1"
- La suma de plantas de todos los sublotes debe igualar la cantidad disponible del lote padre
- El lote padre queda "cerrado en [etapa]" y no avanza más

**Transición entre etapas:**
- Vegetativa toma `cantidad_ingreso` del egreso de Nursery (con confirmación del usuario)
- Floración toma `fecha_inicio` de `fecha_fin` de Vegetativa (con confirmación)
- Floración toma `cantidad_ingreso` del egreso de Vegetativa (con confirmación)

**Restricción biológica importante:** `LOTES_ESQUEJES` NO puede tener como origen "Lote de Semillas propio".

## Pendientes de implementación (prototipo)

1. Formularios de nuevo material básico (Semillas / Esquejes / Plantas Madre)
2. Formulario Cosecha y Curado
3. Formulario Flores Cosechadas con entregas a pacientes (campo `nro_reprocann` obligatorio)
4. Botón "Avanzar a siguiente etapa" con lógica real
5. "Guardar borrador" y "Guardar registro" funcionales
6. Formulario de división en sublotes desde el detalle del lote
7. Click en lote individual → abrir detalle de ese lote específico
