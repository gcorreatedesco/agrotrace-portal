# AgroTrace — Próximos pasos

> ⚠️ **DOCUMENTO HISTÓRICO (2026-07-06) — NO refleja el estado actual.**
> Varios ítems marcados como pendientes acá ya están implementados (panel de alertas, mobile, `variedades_rnc`, multi-tenancy RT, RLS 3 niveles, reportes REPROCANN).
> El **estado vivo del proyecto** (pendientes reales, prioridades) vive en la memoria del proyecto (`MEMORY.md` + archivos `project_*`).
> Se conserva este archivo solo como referencia histórica del roadmap original y por el SQL de ejemplo que contiene.

## Estado al inicio de esta sesión (2026-07-06)

| Módulo | Estado |
|--------|--------|
| Login con Supabase Auth + redirect por rol | ✅ Completo |
| Portal ONG (`agrotrace_prototipo_v3.html`) | ✅ Completo |
| Portal RT (`portal_rt.html`) — datos hardcodeados | ✅ UI lista |
| Portal Superadmin (`portal_superadmin.html`) | ✅ Publicado |
| Wizard Nuevo Lote + avance de etapas | ✅ Completo |
| División en sublotes (Modelo B) | ✅ Completo |
| Stock material básico + historial | ✅ Completo |
| Entregas a pacientes + correcciones | ✅ Completo |
| Cierre de lotes (agotado + anticipado) | ✅ Completo |
| Tabla `variedades_rnc` en Supabase | ❌ SQL listo, sin ejecutar |
| Multi-tenancy (portal RT con datos reales) | ❌ Pendiente |
| Panel de alertas activas | ❌ Pendiente |
| Sistema de Reportes | ❌ Pendiente |
| Adaptación mobile | ❌ Pendiente |
| Auth real en alta ONG por RT | ❌ Pendiente |

## Pendientes incorporados en esta sesión

### Resumen de la sesión (2026-08-03)
- Se ajustó el wizard de alta de lote para eliminar la fecha fin de Nursery en el paso inicial.
- Se dejó el flujo más coherente con la lógica de negocio: la fecha fin se usa al cerrar realmente la etapa Nursery.
- Se priorizaron próximos trabajos para pacientes, reportes, estrategia de desarrollo con main branch, demo interactiva y adaptación mobile.

1. **Listado de pacientes por ONG**
   - Analizar la posibilidad de incorporar un módulo donde cada ONG pueda cargar y administrar su listado de pacientes.
   - Definir si será parte del modelo de datos, el flujo de alta/edición y la visibilidad por ONG.

2. **Sistema de reportes**
   - Diseñar e implementar reportes con distintos objetivos:
     - informes REPROCANN,
     - control de superficie de producción y/o cantidad de plantas para el RT,
     - exportación de base para backup de ONG y RT (exportable e importable).

3. **Estrategia de desarrollo seguro con main branch**
   - Definir un flujo de trabajo para modificar SQL e interfaz sin romper la base de datos ni generar incompatibilidades con cambios posteriores.
   - Incorporar buenas prácticas: migraciones SQL versionadas, backup previo, validación previa al deploy y rollback simple.

4. **Demo interactiva para evaluación**
   - Crear una demo usable para que RTs y ONGs puedan probar el sistema y evaluar flujo, permisos y experiencia.
   - Incluir usuarios de prueba con roles reales y escenarios guiados.

5. **Adaptación mobile y prueba en laptop**
   - Verificar el layout desde celular.
   - Definir cómo probar el sistema desde una laptop en formato mobile (por ejemplo, responsive mode en navegador).

---

## Paso 1 — Crear tabla variedades_rnc en Supabase
Ejecutar en **Supabase → SQL Editor**:

```sql
CREATE TABLE public.variedades_rnc (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nro_rnc     TEXT UNIQUE NOT NULL,
  cultivar    TEXT NOT NULL,
  especie     TEXT,                   -- 'CANNABIS' | 'CÁÑAMO'
  activa      BOOLEAN DEFAULT TRUE,
  fecha_carga TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.variedades_rnc ENABLE ROW LEVEL SECURITY;

CREATE POLICY "autenticados pueden leer variedades"
  ON public.variedades_rnc FOR SELECT TO authenticated USING (true);

CREATE POLICY "solo superadmin gestiona variedades"
  ON public.variedades_rnc FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM perfiles WHERE id = auth.uid() AND rol = 'superadmin'
  ));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.variedades_rnc TO authenticated;
```

Luego probar la carga de CSV desde `portal_superadmin.html`.

---

## Paso 2 — Trigger on_auth_user_created (si no está ejecutado)
Ejecutar en **Supabase → SQL Editor** para que al activar una cuenta nueva se cree automáticamente su perfil:

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.perfiles (id, nombre, rol)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nombre', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'rol', 'ong')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

---

## Paso 3 — Verificar Edge Function solicitar-acceso
1. Ir a resend.com → API Keys → regenerar (si la key actual falla)
2. En Supabase → Project Settings → Secrets → actualizar `RESEND_API_KEY`
3. Probar el formulario de solicitud en `index.html` → "¿No tiene cuenta? Solicitar acceso"
4. Confirmar que llega email al administrador

---

## Paso 4 — Alta ONG por RT (Edge Function invitar-ong)
Flujo:
1. RT completa formulario "Nueva Asociación Civil" en `portal_rt.html`
2. Llamada a Edge Function `invitar-ong` → `sb.auth.admin.inviteUserByEmail()` con metadatos de rol
3. El usuario invitado recibe email → setea contraseña → queda activo en Supabase Auth
4. El trigger `on_auth_user_created` crea su perfil automáticamente

**Antes de implementar:** confirmar campos definitivos del formulario con el cliente (ver pendiente en memoria).

---

## Paso 5 — Multi-tenancy: portal RT con datos reales
Requiere crear la tabla `organizaciones` en Supabase y definir la relación RT → ONGs.

```sql
-- Pendiente de definir campos definitivos post-demo
CREATE TABLE public.organizaciones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre          TEXT NOT NULL,
  cuit            TEXT,
  localidad       TEXT,
  rt_id           UUID REFERENCES public.perfiles(id),
  -- otros campos según formulario definitivo
  creado_en       TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.organizaciones ENABLE ROW LEVEL SECURITY;
```

Con esto, el portal RT carga sus ONGs reales desde Supabase y el botón "Supervisar" pasa el ID real de la ONG.

---

## Paso 6 — Panel de alertas activas (alta prioridad)
Vista centralizada de inconsistencias, warnings y alertas de todos los lotes.

- **Portal ONG:** sección "Alertas" en el sidebar → lista todas las alertas de sus lotes
- **Portal RT:** al supervisar una ONG → panel de alertas de esa ONG visible

Tipos de alertas a considerar:
- Lotes con etapa sin completar hace más de N días
- Stock de material básico por debajo de umbral
- Entregas sin nro_reprocann válido
- Datos de cosecha sin análisis de calidad asociado

Implementar después de definir el layout definitivo de ambos portales.

---

## Paso 7 — Sistema de Reportes
Tres tipos definidos:

### Reporte 1 — Visita RT (para inspección)
- Formato papel A4, blanco y negro, sin gráficos
- Contenido: stock actual MB, lotes activos con etapa, últimas entregas
- Pie: fecha + espacio para firma RT y ONG
- Implementación: HTML con `@media print` + `window.print()`

### Reporte 2 — Regulatorio (presentación REPROCANN)
24 columnas del template oficial. Campos que faltan en la BD:
- Profesión/Título + Nº matrícula del RT → agregar a `perfiles`
- Nro RNC → campo en `lotes_produccion`
- Tipo de Manejo → campo en `lotes_produccion`
- Plantas Descartadas → campo en `etapa_cosecha_curado`
- THC% / CBD% / etc. → tabla nueva `analisis_cromatografico`

### Reporte 3 — Actividades ONG (constancia interna)
- Formato narrativo, cronológico
- Usa paleta y tipografía AgroTrace

---

## Paso 8 — Adaptación mobile
Objetivo: interfaz usable desde celular en campo.

- Sidebar colapsable (menú hamburguesa)
- Formularios de etapas apilados verticalmente
- Cards de lotes con información resumida
- Botones con área táctil mínima 44px
- Afecta principalmente: `agrotrace_prototipo_v3.html`

---

## Orden recomendado para la próxima sesión
1. Paso 1 — Crear tabla `variedades_rnc` (5 min, solo SQL)
2. Paso 2 — Ejecutar trigger si falta (5 min, solo SQL)
3. Paso 3 — Verificar Edge Function `solicitar-acceso`
4. Paso 4 — Alta ONG por RT (requiere definir campos con cliente primero)
5. Paso 5 — Multi-tenancy portal RT
6. Paso 6 — Panel de alertas
