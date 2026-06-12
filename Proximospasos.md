# AgroTrace — Próximos pasos

## Estado al inicio de la próxima sesión
- Prototipo v3 publicado en GitHub Pages con conexión a Supabase activa
- Base de datos con 13 tablas creadas y vacías
- El HTML todavía usa datos hardcodeados — NO lee de Supabase todavía

---

## Paso 1 — Verificar que la conexión funciona
Antes de programar, confirmar que `sb` (cliente Supabase) responde:

Abrir la consola del navegador en el v3 y ejecutar:
```js
const { data, error } = await sb.from('lotes_produccion').select('*')
console.log(data, error)
```
Si devuelve `[]` (array vacío) sin error → conexión OK.

---

## Paso 2 — Autenticación con Supabase Auth
Conectar el `index.html` (login) con Supabase Auth para que los usuarios puedan registrarse e iniciar sesión.

- `sb.auth.signUp({ email, password })` — registro
- `sb.auth.signInWithPassword({ email, password })` — login
- `sb.auth.signOut()` — logout
- `sb.auth.getUser()` — obtener usuario activo

Al hacer login exitoso → redirigir a `agrotrace_prototipo_v3.html`.

---

## Paso 3 — Cargar lotes reales desde Supabase
Reemplazar el array hardcodeado `LD` por una consulta real.

**Función a reemplazar en v3:**
```js
// HOY (datos falsos):
const LD = [ {id:1, n:'Primavera 2025'...} ]

// MAÑANA (datos reales):
async function cargarLotes() {
  const { data } = await sb
    .from('lotes_produccion')
    .select('*')
    .order('creado_en', { ascending: false })
  // renderizar con los datos reales
}
```

---

## Paso 4 — Guardar nuevo lote en Supabase
Conectar el wizard "Nuevo lote" (4 pasos) para que al hacer click en "Crear lote →" guarde en la base de datos.

Tablas involucradas:
1. `lotes_produccion` — datos generales del lote
2. `etapa_nursery` — datos del paso 3 del wizard
3. Descuento de stock en `lotes_semillas` o `lotes_esquejes`

---

## Paso 5 — Guardar material básico
Conectar el formulario "Nuevo lote de material básico" para que guarde en:
- `lotes_semillas`
- `lotes_esquejes`
- `lotes_plantas_madre`

Y conectar el formulario de baja para que guarde en `bajas_material` y descuente `stock_actual`.

---

## Paso 6 — Funcionalidades pendientes del prototipo
Estas pantallas todavía no existen en el v3 y hay que construirlas:

1. **Formulario Cosecha y Curado** — guardar en `etapa_cosecha_curado`
2. **Formulario Flores Cosechadas** — guardar en `flores_cosechadas`
3. **Entregas a pacientes** — guardar en `entregas` (campo `nro_reprocann` obligatorio)
4. **Formulario división en sublotes** — crear nuevo registro en `lotes_produccion` con `lote_padre_id`
5. **Detalle dinámico por etapa** — hoy siempre muestra Floración, debe adaptarse a la etapa actual del lote

---

## Paso 7 — Política de admin
Agregar en Supabase una política RLS que permita al rol `administrador` ver todos los datos de todos los productores.

```sql
CREATE POLICY "admin ve todo" ON public.lotes_produccion
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.perfiles WHERE id = auth.uid() AND rol = 'administrador')
  );
```
Repetir para cada tabla.

---

## Orden recomendado para la próxima sesión
1. Verificar conexión (Paso 1)
2. Autenticación login (Paso 2)
3. Cargar lotes reales en dashboard (Paso 3)
4. Guardar nuevo lote (Paso 4)

Con eso el ciclo básico de uso estará funcionando con datos reales.
