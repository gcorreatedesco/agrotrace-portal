# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proyecto

**AgroTrace** — plataforma web de trazabilidad de producción de cannabis medicinal bajo el marco regulatorio REPROCANN (Argentina). La unidad de trazabilidad es el **lote** (no la planta individual). El sistema es multi-usuario: cada productor ve solo sus datos, el admin ve todo.

Repositorio GitHub: `github.com/gcorreatedesco/agrotrace-portal`

## Stack actual

- **Frontend:** HTML + CSS + JS vanilla (prototipo). Migración futura planificada a React + Vite.
- **Backend:** pendiente de decidir (Node.js/Express vs Python/FastAPI)
- **Base de datos:** PostgreSQL (ERD definido, aún no implementado)
- No hay build, bundler ni test runner configurado. Abrir los `.html` directamente en Chrome.

## Archivos en el repositorio

| Archivo | Descripción |
|---------|-------------|
| `index.html` | Portal de acceso (login) — único archivo en producción actualmente |

Los archivos de prototipo (`agrotrace_prototipo_v2.html`), ERDs y documentos de diseño se trabajan localmente y aún no están todos versionados.

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
