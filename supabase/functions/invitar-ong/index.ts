// Edge Function: invitar-ong
// El RT llama a esta función para crear una ONG y enviar invitación al Admin ONG.
// Requiere JWT válido del RT en el header Authorization.
// Variables de entorno disponibles automáticamente en Supabase Edge Functions:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {

  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: corsHeaders })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders })
  }

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Verificar que el llamante es un RT o superadmin autenticado
  const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(
    authHeader.replace('Bearer ', '')
  )
  if (userError || !user) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders })
  }

  const { data: perfil, error: perfilErr } = await supabaseAdmin
    .from('perfiles').select('rol').eq('id', user.id).single()

  console.log('[invitar-ong] user.id:', user.id, '| perfil:', perfil, '| error:', perfilErr)

  if (!perfil || !['rt', 'superadmin'].includes(perfil.rol)) {
    return new Response(
      JSON.stringify({ error: 'Forbidden', user_id: user.id, perfil, perfilErr }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  try {
    const {
      nombre_org, cuit, localidad, direccion, email_org, telefono,
      nombre_contacto, email_contacto, reprocann, fecha_inscripcion, notas,
      rt_id: rt_id_solicitado,   // opcional — superadmin puede pasar el RT a asignar
    } = await req.json()

    if (!nombre_org || !email_contacto) {
      return new Response(
        JSON.stringify({ error: 'nombre_org y email_contacto son obligatorios' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 1. Crear la organización
    const { data: org, error: orgError } = await supabaseAdmin
      .from('organizaciones')
      .insert({
        nombre: nombre_org,
        cuit: cuit || null,
        localidad: localidad || null,
        direccion: direccion || null,
        email: email_org || null,
        telefono: telefono || null,
        reprocann: reprocann || null,
        fecha_inscripcion: fecha_inscripcion || null,
        notas: notas || null,
      })
      .select()
      .single()

    if (orgError) throw new Error('Error al crear organización: ' + orgError.message)

    // 2. Vincular RT con la organización (si corresponde)
    // Si lo llama un RT: usa su propio ID. Si lo llama el superadmin con rt_id_solicitado: usa ese.
    const rt_efectivo = rt_id_solicitado || (perfil.rol === 'rt' ? user.id : null)
    if (rt_efectivo) {
      const { error: linkError } = await supabaseAdmin
        .from('rt_organizaciones')
        .insert({ rt_id: rt_efectivo, ong_id: org.id })
      if (linkError) throw new Error('Error al vincular RT: ' + linkError.message)
    }

    // 3. Invitar al Admin ONG por email
    // El trigger on_auth_user_created crea la fila en perfiles al aceptar.
    const { error: inviteError } = await supabaseAdmin.auth.admin.inviteUserByEmail(
      email_contacto,
      {
        data: {
          rol: 'ong',
          ong_id: org.id,
          nombre_contacto: nombre_contacto || null,
        },
        redirectTo: 'https://gcorreatedesco.github.io/agrotrace-portal/',
      }
    )

    if (inviteError) throw new Error('Error al enviar invitación: ' + inviteError.message)

    return new Response(
      JSON.stringify({ ok: true, org_id: org.id, org_nombre: org.nombre }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (e) {
    console.error('Error en invitar-ong:', e)
    return new Response(
      JSON.stringify({ error: e.message || 'Error interno' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
