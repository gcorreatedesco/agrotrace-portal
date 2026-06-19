// Edge Function: solicitar-acceso
// Recibe datos del formulario de solicitud y envía email al administrador via Resend
// Variables de entorno requeridas (configurar en Supabase Dashboard → Project Settings → Secrets):
//   RESEND_API_KEY  — API key de Resend
//   ADMIN_EMAIL     — email del administrador que recibirá las solicitudes
//   FROM_EMAIL      — email remitente verificado en Resend (ej: noreply@agrotrace.com.ar)

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!;
const ADMIN_EMAIL    = Deno.env.get('ADMIN_EMAIL')!;
const FROM_EMAIL     = Deno.env.get('FROM_EMAIL') ?? 'AgroTrace <onboarding@resend.dev>';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {

  // Preflight CORS
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: corsHeaders });
  }

  try {
    const { nombre, email, ong, perfil, reprocann, notas } = await req.json();

    // Validación básica
    if (!nombre || !email || !ong || !perfil) {
      return new Response(
        JSON.stringify({ error: 'Faltan campos obligatorios' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const perfilLabel = perfil === 'rt' ? 'Responsable Técnico' : 'Admin ONG';

    const htmlEmail = `
      <div style="font-family: sans-serif; max-width: 560px; margin: 0 auto; padding: 24px;">
        <div style="background: #2C1F0E; border-radius: 8px; padding: 20px 24px; margin-bottom: 24px;">
          <h1 style="font-size: 1.2rem; color: #EDF2E8; margin: 0;">AgroTrace</h1>
          <p style="font-size: 0.75rem; color: #8EAA7B; margin: 4px 0 0; text-transform: uppercase; letter-spacing: 0.1em;">Nueva solicitud de acceso</p>
        </div>

        <p style="color: #4A3520; font-size: 0.9rem;">Se recibió una nueva solicitud de acceso al sistema:</p>

        <table style="width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 0.88rem;">
          <tr style="background: #EDF2E8;">
            <td style="padding: 10px 14px; font-weight: 500; color: #2C1F0E; width: 40%;">Nombre</td>
            <td style="padding: 10px 14px; color: #4A3520;">${nombre}</td>
          </tr>
          <tr>
            <td style="padding: 10px 14px; font-weight: 500; color: #2C1F0E; border-top: 1px solid #EDF2E8;">Email de contacto</td>
            <td style="padding: 10px 14px; color: #4A3520; border-top: 1px solid #EDF2E8;">${email}</td>
          </tr>
          <tr style="background: #EDF2E8;">
            <td style="padding: 10px 14px; font-weight: 500; color: #2C1F0E;">Asociación Civil / ONG</td>
            <td style="padding: 10px 14px; color: #4A3520;">${ong}</td>
          </tr>
          <tr>
            <td style="padding: 10px 14px; font-weight: 500; color: #2C1F0E; border-top: 1px solid #EDF2E8;">Perfil solicitado</td>
            <td style="padding: 10px 14px; color: #4A3520; border-top: 1px solid #EDF2E8;">${perfilLabel}</td>
          </tr>
          <tr style="background: #EDF2E8;">
            <td style="padding: 10px 14px; font-weight: 500; color: #2C1F0E;">Nro. REPROCANN</td>
            <td style="padding: 10px 14px; color: #4A3520;">${reprocann || '—'}</td>
          </tr>
          <tr>
            <td style="padding: 10px 14px; font-weight: 500; color: #2C1F0E; border-top: 1px solid #EDF2E8;">Información adicional</td>
            <td style="padding: 10px 14px; color: #4A3520; border-top: 1px solid #EDF2E8;">${notas || '—'}</td>
          </tr>
        </table>

        <div style="background: #FAEEDA; border-left: 3px solid #FAC775; border-radius: 4px; padding: 14px 16px; margin: 20px 0; font-size: 0.83rem; color: #854F0B;">
          <strong>Próximo paso:</strong> Si aprueba esta solicitud, ingrese a
          <strong>Supabase Dashboard → Authentication → Users → Add user</strong>
          con el email <strong>${email}</strong> y asigne el rol <strong>${perfilLabel}</strong>.
          Supabase enviará automáticamente el link de activación.
        </div>

        <p style="font-size: 0.75rem; color: #6B7F5E; margin-top: 24px; border-top: 1px solid #EDF2E8; padding-top: 16px;">
          Este email fue generado automáticamente por AgroTrace · Sistema de Trazabilidad REPROCANN
        </p>
      </div>
    `;

    // Enviar email via Resend
    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: [ADMIN_EMAIL],
        subject: `Nueva solicitud de acceso AgroTrace — ${ong}`,
        html: htmlEmail,
      }),
    });

    if (!resendResponse.ok) {
      const err = await resendResponse.text();
      console.error('Error Resend:', err);
      return new Response(
        JSON.stringify({ error: 'Error al enviar el email' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ ok: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (e) {
    console.error('Error inesperado:', e);
    return new Response(
      JSON.stringify({ error: 'Error interno' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
