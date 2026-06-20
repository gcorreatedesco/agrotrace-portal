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
- Botón "⚠ Eliminar totalidad del lote" en Registrar Baja (rojo, extremo opuesto a acciones principales)
- Formulario "Nuevo lote de material básico" (Semillas / Esquejes / Plantas Madre)
- Múltiples orígenes para Esquejes y Plantas Madre (externo, lote producción propio, material básico propio)
- Variedad auto-completada desde lote de origen (campo readonly con confirmación)
- Detalle clickeable por cada lote de Material Básico
- Historial desplegable en detalle de MB: uso en lotes productivos + registro de bajas
- Lotes con stock = 0 se ocultan automáticamente del listado y dropdowns
- Banner de supervisión RT (barra verde oscura) cuando viene del portal RT

**Pestañas históricas — Mis Lotes Productivos:**
- Pestaña "Lotes Productivos Activos" — lotes en ciclo activo
- Pestaña "Lotes Productivos Terminados" — lotes con flores agotadas y ciclo cerrado
- Pestaña "Lotes Cerrados Sin Terminar" — lotes cerrados anticipadamente con motivo

**Cierre de lotes:**
- Banner "Existencias agotadas" en Panel de Flores cuando stock = 0 → botón "Cerrar lote"
- Botón "Cerrar lote anticipadamente" en Topbar del Detalle → pide motivo obligatorio
- Ambos guardan `fecha_cierre` y `motivo_cierre` en `lotes_produccion`

**Pestañas históricas — Stock de Material Básico:**
- Pestaña "Stock Activo" — lotes con stock > 0
- Pestaña "Material Agotado / Descartado" — lotes con stock = 0

**Botón de retorno en Topbar:**
- Pantalla Detalle de Lote → `← Mis Lotes`
- Pantalla Detalle de Material Básico → `← Stock`

**Entregas a pacientes (Panel de Flores Cosechadas):**
- Formulario inline: Nro. REPROCANN, fecha, cantidad (gramos), nombre de quien entrega, notas
- Validación de stock disponible antes de confirmar
- Descuento automático de `flores_cosechadas.stock_actual`
- Historial de entregas colapsable con total acumulado al pie
- Correcciones de entregas: formulario inline por entrega, guarda valores anteriores y nuevos en `entregas_correcciones`, ajusta stock automáticamente si cambia la cantidad
- Desplegable "Correcciones (N)" por entrega con historial completo de cambios y registro original

---

### 2. Portal de acceso (index.html)
Pantalla de login con selección de perfil y formulario de solicitud de acceso.

**Perfiles IAM definidos (3 niveles operativos):**
| Perfil | Rol | Descripción |
|--------|-----|-------------|
| Superadmin | `superadmin` | Acceso total al sistema — puede operar datos productivos directamente |
| Resp. Técnico | `rt` | Supervisión de ONGs bajo su cargo → redirige a `portal_rt.html` |
| Admin ONG | `ong` | Gestión de producción de su organización |

**Comportamiento actual (banco de prueba):**
- Sin autenticación real — el botón "Ingresar" redirige directo al sistema
- El rol seleccionado se guarda en `sessionStorage` bajo la clave `agrotrace_role`
- El nombre de usuario se guarda en `sessionStorage` bajo la clave `agrotrace_user`
- Aviso visible: "Modo banco de prueba — sin autenticación real"

**Formulario de solicitud de acceso (implementado):**
- Acceso desde "¿No tiene cuenta? Solicitar acceso" en la pantalla de roles
- Campos: Nombre completo, Email de contacto, Nombre de Asociación Civil / ONG, Perfil solicitado (Admin ONG / *Responsable Técnico — en itálica*), Nro. REPROCANN (opcional), Información adicional (opcional)
- Al enviar: llama a la Edge Function `solicitar-acceso` en Supabase
- Muestra pantalla de confirmación "Solicitud enviada"

---

### 3. Portal RT (portal_rt.html) — nuevo
Panel de supervisión para el Responsable Técnico.

- Cards de ONGs bajo supervisión con métricas: lotes activos, stock de flores, entregas/mes
- Badge de estado por ONG: Activa / Con alertas
- Alertas visibles por card
- Botón "Supervisar" → guarda ONG en `sessionStorage` y abre v3 con banner de supervisión
- Botón "← Cambiar organización" en v3 → vuelve al portal RT
- Datos simulados (hardcodeados) por ahora — se conectará a Supabase al implementar multi-tenancy

---

### 4. Sistema de notificación de solicitudes — Edge Function

**Edge Function `solicitar-acceso`** (`supabase/functions/solicitar-acceso/index.ts`):
- Recibe datos del formulario via POST
- Envía email HTML al administrador via Resend con todos los datos del solicitante
- Incluye en el email el próximo paso a seguir (crear usuario en Supabase Dashboard)
- Desplegada en Supabase Edge Functions ✅

**Secrets configurados en Supabase (Project Settings → Secrets):**
| Secret | Valor |
|--------|-------|
| `RESEND_API_KEY` | API Key de Resend (re_...) |
| `ADMIN_EMAIL` | Email del administrador |
| `FROM_EMAIL` | `AgroTrace <onboarding@resend.dev>` |

**Estado:** Deploy exitoso. Pendiente verificar envío real de email (error en API Key al momento de cortar la sesión — regenerar en resend.com y actualizar el secret `RESEND_API_KEY` en Supabase).

---

### 5. Base de datos en Supabase (supabase_schema.sql)
13 tablas PostgreSQL + 1 tabla de correcciones que implementan el ERD completo.

**Tablas:**
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
- `entregas` — entregas a pacientes (nro_reprocann obligatorio)
- `entregas_correcciones` — historial de correcciones de entregas
- `material_documentos` — documentos de origen adjuntos a lotes de material básico (rótulo/estampilla + factura)

Todas con **Row Level Security (RLS)** activado.

**Migraciones aplicadas (ejecutar en Supabase SQL Editor si se recrea la base):**
```sql
-- lotes_plantas_madre: origen_tipo ampliado
ALTER TABLE public.lotes_plantas_madre
  DROP CONSTRAINT IF EXISTS lotes_plantas_madre_origen_tipo_check;
ALTER TABLE public.lotes_plantas_madre
  ADD CONSTRAINT lotes_plantas_madre_origen_tipo_check
    CHECK (origen_tipo IN ('externo','esqueje_produccion','esqueje_material_basico'));
ALTER TABLE public.lotes_plantas_madre
  DROP CONSTRAINT IF EXISTS lotes_plantas_madre_lote_origen_id_fkey;

-- lotes_produccion: campos de cierre
ALTER TABLE public.lotes_produccion
  ADD COLUMN IF NOT EXISTS fecha_cierre DATE,
  ADD COLUMN IF NOT EXISTS motivo_cierre TEXT;

-- entregas: campo registrado_por
ALTER TABLE public.entregas
  ADD COLUMN IF NOT EXISTS registrado_por TEXT;

-- nueva tabla correcciones de entregas
CREATE TABLE IF NOT EXISTS public.entregas_correcciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entrega_id          UUID NOT NULL REFERENCES public.entregas(id) ON DELETE CASCADE,
  nro_reprocann_ant   TEXT,
  cantidad_ant        NUMERIC,
  notas_ant           TEXT,
  registrado_por_ant  TEXT,
  nro_reprocann_nvo   TEXT,
  cantidad_nvo        NUMERIC,
  notas_nvo           TEXT,
  corregido_por       TEXT,
  fecha_correccion    TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.entregas_correcciones ENABLE ROW LEVEL SECURITY;
CREATE POLICY "via entregas correcciones" ON public.entregas_correcciones
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.entregas e
      JOIN public.flores_cosechadas fc ON fc.id = e.flores_id
      JOIN public.lotes_produccion lp ON lp.id = fc.lote_id
      WHERE e.id = entrega_id AND lp.usuario_id = auth.uid()
    )
  );

-- permisos tabla correcciones
GRANT SELECT, INSERT, UPDATE, DELETE ON public.entregas_correcciones TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.entregas_correcciones TO authenticated;
```

**Trigger pendiente de ejecutar (auto-crear perfil al activar cuenta):**
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

**Configuración Supabase:**
- Enable Data API: ✅
- Automatically expose new tables: ❌
- Enable automatic RLS: ✅

---

### 6. Conexión Supabase ↔ HTML
El frontend lee y escribe datos reales en Supabase.

**Qué está conectado:**
- Dashboard y lista de lotes → carga desde `lotes_produccion` (activos, terminados, cerrados)
- Stock → carga desde `lotes_semillas`, `lotes_esquejes`, `lotes_plantas_madre` (activo e histórico)
- Wizard "Nuevo lote" → guarda en `lotes_produccion` + `etapa_nursery` + descuenta stock
- Avance de etapas → guarda en tabla correspondiente + actualiza `etapa_actual`
- Cierre de lotes → actualiza `etapa_actual`, `fecha_cierre`, `motivo_cierre`
- Formulario "Nuevo material básico" → guarda en la tabla correspondiente + sube documentos a Storage bucket `material-basico-docs` + registra en `material_documentos`
- Formulario de baja → guarda en `bajas_material` + actualiza `stock_actual`
- Eliminar totalidad → registra baja total + pone stock en 0 + oculta lote
- Historial de MB → consulta `lotes_produccion`, `etapa_nursery`, `bajas_material`
- Entregas → guarda en `entregas` + descuenta `flores_cosechadas.stock_actual`
- Correcciones → guarda en `entregas_correcciones` + actualiza `entregas` + ajusta stock
- Búsqueda → índice reconstruido desde datos reales
- Formulario solicitud de acceso → llama a Edge Function `solicitar-acceso`

**Autenticación actual (provisorio):**
Portal de acceso no autentica — redirige directamente al sistema con el rol seleccionado guardado en `sessionStorage`.

---

### 7. Documentación generada

| Archivo | Descripción | Versión |
|---------|-------------|---------|
| `AgroTrace_Lexico_UI.html` | Léxico común de interfaz — términos visuales + glosario IAM | v1.1 |
| `AgroTrace_Modelo_Negocio_Roles.html` | Modelo de negocio y estructura de roles | v1.0 |
| `AgroTrace_Guia_Auth_IAM.html` | Guía de Auth e IAM — pasos, recursos, glosario 21 términos | v1.1 |
| `AgroTrace_Guia_SMTP_Email.html` | Configuración de email transaccional con Resend vía Supabase | v1.0 |
| `AgroTrace_Sist_Auth_Por_Solicitud.html` | Sistema de autenticación por solicitud — Opción A y B, procedimiento de deploy | v1.1 |

---

### 8. Deploy
`https://gcorreatedesco.github.io/agrotrace-portal/agrotrace_prototipo_v3.html`

**Proyecto Supabase:**
- URL: `https://jqkyifuyaxxwugrnjfnq.supabase.co`
- Plan: Free (East US - Ohio)
- Edge Function desplegada: `solicitar-acceso`

---

## Pendientes identificados

1. **Verificar Edge Function** — regenerar API Key en resend.com, actualizar secret `RESEND_API_KEY` en Supabase, probar formulario de solicitud end-to-end.
2. **Ejecutar trigger** `on_auth_user_created` en Supabase SQL Editor (ver sección 5).
3. **Personalizar template "Invite user"** en Supabase → Authentication → Email Templates (texto en español incluido en `AgroTrace_Sist_Auth_Por_Solicitud.html`).
4. **Autenticación real** — conectar `index.html` con `sb.auth.signInWithPassword`. Al implementarlo: vincular `registrado_por` en `entregas` y `corregido_por` en `entregas_correcciones` al usuario autenticado.
5. **Lotes cerrados por división en sublotes** — el lote padre queda cerrado en la etapa donde se dividió.
6. **Historial de entregas por paciente** — vista que agrupe todas las entregas a un mismo Nro. REPROCANN.
7. **Política RLS para rol administrador** — ver todos los datos de todos los productores.
8. **Multi-tenancy** — tabla `organizaciones` + `rt_organizaciones`, actualizar RLS, conectar portal RT con datos reales.
9. **Módulo Reportes** — timeline, stock, CSV/PDF.
