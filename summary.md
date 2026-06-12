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

---

### 3. Conexión Supabase ↔ HTML
Se agregó al v3 el bloque de conexión:
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script>
const SUPABASE_URL = 'https://jqkyifuyaxxwugrnjfnq.supabase.co';
const SUPABASE_KEY = '...anon key...';
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
</script>
```
El cliente `sb` está disponible globalmente en el HTML para hacer consultas.

---

### 4. Deploy en GitHub Pages
El proyecto está publicado en:
`https://gcorreatedesco.github.io/agrotrace-portal/agrotrace_prototipo_v3.html`

**Comandos git usados:**
```bash
git pull
git add agrotrace_prototipo_v3.html supabase_schema.sql
git commit -m "Add prototipo v3 with Supabase connection and schema SQL"
git push

git add agrotrace_prototipo_v3.html
git commit -m "Add Supabase anon key"
git push
```

---

## Stack actual
| Capa | Tecnología |
|---|---|
| Frontend | HTML + CSS + JS vanilla |
| Base de datos | PostgreSQL vía Supabase (plan Free) |
| Hosting | GitHub Pages |
| Autenticación | Supabase Auth (pendiente de implementar) |
| Backend | No hay — acceso directo desde JS con supabase-js |

## Proyecto Supabase
- URL: `https://jqkyifuyaxxwugrnjfnq.supabase.co`
- Plan: Free (East US - Ohio)
- Estado: Healthy
