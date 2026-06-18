# AgroTrace — Resumen de sesión

## Lo que construimos

### 1. Prototipo v3 (agrotrace_prototipo_v3.html)
Archivo HTML/CSS/JS con toda la interfaz del sistema. Es la versión más avanzada.

**Funcionalidades implementadas:**
- Sidebar con navegación completa
- Dashboard con métricas, alertas y actividad reciente
- Mis lotes productivos con filtros por etapa
- Sublotes expandibles con árbol visual
- Click en lote → abre detalle dinámico con datos reales de Supabase
- Carga paralela de todas las etapas al abrir un lote
- Historial de etapas completadas (clickeando en la timeline) — editables, sin restricción de solo lectura
- Avance entre etapas: Nursery → Vegetativa → Floración → Cosecha/Curado → Flores Cosechadas
- Guardar borrador por etapa (datos persisten en Supabase)
- Confirmación de campos auto-traídos (fecha inicio, cantidad ingreso)
- Búsqueda de lotes desde el sidebar
- Wizard "Nuevo lote" (4 pasos completos, guarda en Supabase)
- Stock de material básico con barras de progreso
- Formulario de baja de material básico
- Formulario "Nuevo lote de material básico" (Semillas / Esquejes / Plantas Madre)
- Múltiples orígenes para Esquejes y Plantas Madre (externo, lote producción propio, material básico propio)
- Variedad auto-completada desde lote de origen (campo readonly con confirmación)
- Detalle clickeable por cada lote de Material Básico
- Historial desplegable en detalle de MB: uso en lotes productivos + registro de bajas
- Botón "⚠ Eliminar totalidad del lote" (rojo, extremo opuesto a acciones principales)
- Lotes con stock = 0 se ocultan automáticamente del listado y dropdowns

---

### 2. Base de datos en Supabase (supabase_schema.sql)
13 tablas PostgreSQL que implementan el ERD v5 completo.

**Tablas creadas:**
- `perfiles` — usuarios del sistema
- `lotes_semillas` — stock de semillas
- `lotes_plantas_madre` — stock de plantas madre
- `lotes_esquejes` — stock de esquejes
- `bajas_material` — bajas de cualquier material
- `lotes_produccion` — lotes y sublotes de producción
- `etapa_nursery` — datos etapa 1
- `etapa_vegetativa` — datos etapa 2
- `etapa_floracion` — datos etapa 3
- `etapa_cosecha_curado` — datos etapa 4
- `flores_cosechadas` — datos etapa 5
- `analisis_calidad` — análisis de laboratorio
- `entregas` — entregas a pacientes (nro_reprocann)

Todas con **Row Level Security (RLS)** activado — cada productor ve solo sus datos.

**Migración aplicada (ejecutar en Supabase SQL Editor si se recrea la base):**
```sql
-- lotes_plantas_madre: origen_tipo ampliado
ALTER TABLE public.lotes_plantas_madre
  DROP CONSTRAINT IF EXISTS lotes_plantas_madre_origen_tipo_check;
ALTER TABLE public.lotes_plantas_madre
  ADD CONSTRAINT lotes_plantas_madre_origen_tipo_check
    CHECK (origen_tipo IN ('externo','esqueje_produccion','esqueje_material_basico'));
ALTER TABLE public.lotes_plantas_madre
  DROP CONSTRAINT IF EXISTS lotes_plantas_madre_lote_origen_id_fkey;
```

**Configuración Supabase usada:**
- Enable Data API: ✅ activado
- Automatically expose new tables: ❌ desactivado
- Enable automatic RLS: ✅ activado

**Permisos aplicados manualmente:**
```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;
```
Estos GRANTs son permanentes. Deben aplicarse cada vez que se creen tablas nuevas.

---

### 3. Conexión Supabase ↔ HTML
El frontend lee y escribe datos reales en Supabase. Ya no usa arrays hardcodeados.

**Qué está conectado:**
- Dashboard y lista de lotes → carga desde `lotes_produccion`
- Stock → carga desde `lotes_semillas`, `lotes_esquejes`, `lotes_plantas_madre` (excluye stock = 0)
- Wizard "Nuevo lote" → guarda en `lotes_produccion` + `etapa_nursery` + descuenta stock
- Avance de etapas → guarda en tabla correspondiente + actualiza `etapa_actual`
- Formulario "Nuevo material básico" → guarda en la tabla correspondiente
- Formulario de baja → guarda en `bajas_material` + actualiza `stock_actual`
- Eliminar totalidad → registra baja total + pone stock en 0 + oculta lote
- Historial de MB → consulta `lotes_produccion`, `etapa_nursery`, `bajas_material`
- Búsqueda → índice reconstruido desde datos reales

**Mecanismo de autenticación actual (provisorio):**
Auto-login con credenciales hardcodeadas en el HTML (`DEV_EMAIL` / `DEV_PASSWORD`). No hay pantalla de login todavía.

---

### 4. Deploy en GitHub Pages
`https://gcorreatedesco.github.io/agrotrace-portal/agrotrace_prototipo_v3.html`

La URL está configurada en Supabase → Authentication → URL Configuration como Site URL permitida.

---

## Stack actual
| Capa | Tecnología |
|---|---|
| Frontend | HTML + CSS + JS vanilla |
| Base de datos | PostgreSQL vía Supabase (plan Free) |
| Hosting | GitHub Pages |
| Autenticación | Auto-login provisorio con credenciales hardcodeadas |
| Backend | No hay — acceso directo desde JS con supabase-js |

## Proyecto Supabase
- URL: `https://jqkyifuyaxxwugrnjfnq.supabase.co`
- Plan: Free (East US - Ohio)
- Estado: Healthy

---

## Pendientes identificados
1. **Lotes históricos** — análisis pendiente de cómo mostrar lotes: A) dados de baja por defecto, B) ciclo completo, C) ciclo completo con todas las flores entregadas. Propuesta: tabs Activos/Históricos en "Mis Lotes". No implementado aún.
2. **Login real** — conectar `index.html` con `sb.auth.signInWithPassword` / `signUp`. Reemplazar auto-login.
3. **División en sublotes** — crear registro en `lotes_produccion` con `lote_padre_id`.
4. **Política RLS para admin** — política que permita al rol `administrador` ver datos de todos los productores.
5. **Formulario de entregas a pacientes** — guardar en `entregas` (campo `nro_reprocann` obligatorio).
