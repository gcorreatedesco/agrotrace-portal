// Edge Function: crear-rt
// El Superadmin llama a esta función para crear un nuevo Responsable Técnico.
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
      JSON.stringify({ error: 'Solo el superadmin puede crear RTs' }),
      { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  try {
    const { email, password, nombre } = await req.json()

    if (!email || !password || !nombre) {
      return new Response(
        JSON.stringify({ error: 'email, password y nombre son obligatorios' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Crear usuario con rol 'rt' en los metadatos
    // El trigger on_auth_user_created lo usará para crear el perfil automáticamente
    const { data, error: createError } = await supabaseAdmin.auth.admin.createUserWithPassword(
      email,
      password,
      {
        user_metadata: {
          rol: 'rt',
          nombre_contacto: nombre,
        },
      }
    )

    if (createError) throw new Error(createError.message)

    return new Response(
      JSON.stringify({
        ok: true,
        user_id: data.user.id,
        email: data.user.email,
        mensaje: `RT ${nombre} creado exitosamente. Puede loguearse con ${email}`
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (e) {
    console.error('Error en crear-rt:', e)
    return new Response(
      JSON.stringify({ error: e.message || 'Error interno' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
