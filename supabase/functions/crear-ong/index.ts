// Edge Function: crear-ong
// El Superadmin llama a esta función para crear una nueva ONG y su usuario admin.
// Requiere JWT válido del superadmin en el header Authorization.

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

  // Verificar que el llamante es superadmin
  const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(
    authHeader.replace('Bearer ', '')
  )
  if (userError || !user) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders })
  }

  const { data: perfil } = await supabaseAdmin
    .from('perfiles').select('rol').eq('id', user.id).single()

  if (perfil?.rol !== 'superadmin') {
    return new Response(
      JSON.stringify({ error: 'Solo el superadmin puede crear ONGs' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  try {
    const {
      nombre_org,
      email_admin,
      password_admin,
      nombre_admin,
      cuit,
      localidad,
      reprocann,
      rt_id,
    } = await req.json()

    if (!nombre_org || !email_admin || !password_admin || !nombre_admin) {
      return new Response(
        JSON.stringify({
          error: 'nombre_org, email_admin, password_admin y nombre_admin son obligatorios'
        }),
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
        reprocann: reprocann || null,
        activa: true,
      })
      .select()
      .single()

    if (orgError) throw new Error('Error al crear organización: ' + orgError.message)

    // 2. Si se proporciona un RT, asignar la ONG a ese RT
    if (rt_id) {
      const { error: linkError } = await supabaseAdmin
        .from('rt_organizaciones')
        .insert({ rt_id, ong_id: org.id })
      if (linkError) throw new Error('Error al asignar RT: ' + linkError.message)
    }

    // 3. Crear el usuario admin de la ONG con rol 'ong'
    // El trigger on_auth_user_created lo usará para crear el perfil automáticamente
    const { data, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email: email_admin,
      password: password_admin,
      user_metadata: {
        rol: 'ong',
        ong_id: org.id,
        nombre_contacto: nombre_admin,
      },
    })

    if (createError) throw new Error('Error al crear usuario: ' + createError.message)

    return new Response(
      JSON.stringify({
        ok: true,
        org_id: org.id,
        user_id: data.user.id,
        nombre_org: org.nombre,
        email_admin: data.user.email,
        mensaje: `ONG "${nombre_org}" y su usuario admin creados. El admin puede loguearse con ${email_admin}`
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (e) {
    console.error('Error en crear-ong:', e)
    return new Response(
      JSON.stringify({ error: e.message || 'Error interno' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
