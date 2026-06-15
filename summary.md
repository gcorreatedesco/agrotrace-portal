# AgroTrace — Resumen de sesión

## Lo que construimos

### 1. Prototipo v3 (agrotrace_prototipo_v3.html)
Archivo HTML/CSS/JS con toda la interfaz del sistema. Es la versión más avanzada.

**Funcionalidades implementadas:**
- Sidebar con navegación completa
- Dashboard con métricas, alertas y actividad reciente
- Mis lotes productivos con filtros por etapa
- Sublotes expandibles con árbol visual
- Click en lote → abre detalle dinámico
- Historial de etapas completadas (clickeando en la timeline)
- Confirmación de campos auto-traídos (fecha inicio, cantidad ingreso)
- Búsqueda de lotes desde el sidebar
- Wizard "Nuevo lote" (4 pasos completos)
- Stock de material básico con barras de progreso
- Formulario de baja de material básico
- Formulario "Nuevo lote de material básico" (Semillas / Esquejes / Plantas Madre)

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

**Configuración Supabase usada:**
- Enable Data API: ✅ activado
- Automatically expose new tables: ❌ desactivado
- Enable automatic RLS: ✅ activado

**Permisos aplicados manualmente (por tener "expose new tables" desactivado):**
```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;
```
Estos GRANTs son permanentes y parte del esquema definitivo. Deben aplicarse cada vez que se creen tablas nuevas.

---

### 3. Conexión Supabase ↔ HTML (implementada en esta sesión)
El frontend ahora lee y escribe datos reales en Supabase. Ya no usa arrays hardcodeados.

**Qué está conectado:**
- Dashboard y lista de lotes → carga desde `lotes_produccion`
- Stock → carga desde `lotes_semillas`, `lotes_esquejes`, `lotes_plantas_madre`
- Wizard "Nuevo lote" → guarda en `lotes_produccion` + `etapa_nursery` + descuenta stock
- Formulario "Nuevo material básico" → guarda en la tabla correspondiente
- Formulario de baja → guarda en `bajas_material` + actualiza `stock_actual`
- Búsqueda → índice reconstruido desde datos reales

**Mecanismo de autenticación actual (provisorio):**
Auto-login con credenciales hardcodeadas en el HTML (`DEV_EMAIL` / `DEV_PASSWORD`). No hay pantalla de login todavía. El usuario de Supabase Auth se creó manualmente desde el dashboard de Supabase.

```js
const DEV_EMAIL    = '...';  // usuario creado en Supabase > Authentication > Users
const DEV_PASSWORD = '...';
```

---

### 4. Deploy en GitHub Pages
El proyecto está publicado en:
`https://gcorreatedesco.github.io/agrotrace-portal/agrotrace_prototipo_v3.html`

La URL de GitHub Pages está configurada en Supabase → Authentication → URL Configuration como Site URL permitida.

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

## Próximos pasos
1. Cargar material básico y lotes reales desde la interfaz (base de datos vacía, lista para usar)
2. Implementar login real con Supabase Auth — reemplazar el auto-login por una pantalla de login conectada a `index.html`
