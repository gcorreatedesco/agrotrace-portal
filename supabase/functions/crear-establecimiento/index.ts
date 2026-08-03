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

  const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(
    authHeader.replace('Bearer ', '')
  )
  if (userError || !user) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders })
  }

  const { data: perfil } = await supabaseAdmin
    .from('perfiles')
    .select('rol')
    .eq('id', user.id)
    .single()

  if (!perfil || !['superadmin', 'rt', 'ong'].includes(perfil.rol)) {
    return new Response(JSON.stringify({ error: 'Usuario no autorizado' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  let body: any = {}
  try {
    body = await req.json()
  } catch {
    body = {}
  }

  const accion = body.accion || 'create'
  const targetUserId = body.usuario_id || body.payload?.usuario_id || user.id
  const payload = body.payload || {}
  const id = body.id || null

  if (perfil.rol === 'ong' && targetUserId !== user.id) {
    return new Response(JSON.stringify({ error: 'No podés operar sobre otro usuario' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  if (perfil.rol === 'rt') {
    const { data: targetPerfil } = await supabaseAdmin
      .from('perfiles')
      .select('ong_id, rol')
      .eq('id', targetUserId)
      .maybeSingle()

    if (!targetPerfil || targetPerfil.rol !== 'ong' || !targetPerfil.ong_id) {
      return new Response(JSON.stringify({ error: 'El usuario objetivo no corresponde a una ONG' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: link } = await supabaseAdmin
      .from('rt_organizaciones')
      .select('ong_id')
      .eq('rt_id', user.id)
      .eq('ong_id', targetPerfil.ong_id)
      .maybeSingle()

    if (!link) {
      return new Response(JSON.stringify({ error: 'No tenés permiso sobre esa ONG' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
  }

  try {
    if (accion === 'update') {
      if (!id) {
        throw new Error('Falta el id del establecimiento')
      }

      const { data: currentRow } = await supabaseAdmin
        .from('establecimientos')
        .select('usuario_id')
        .eq('id', id)
        .maybeSingle()

      if (!currentRow) {
        throw new Error('Establecimiento no encontrado')
      }

      if (perfil.rol === 'ong' && currentRow.usuario_id !== user.id) {
        throw new Error('No podés modificar ese establecimiento')
      }

      if (perfil.rol === 'rt') {
        const { data: targetPerfil } = await supabaseAdmin
          .from('perfiles')
          .select('ong_id')
          .eq('id', currentRow.usuario_id)
          .maybeSingle()

        const { data: link } = await supabaseAdmin
          .from('rt_organizaciones')
          .select('ong_id')
          .eq('rt_id', user.id)
          .eq('ong_id', targetPerfil?.ong_id)
          .maybeSingle()

        if (!link) {
          throw new Error('No tenés permiso sobre ese establecimiento')
        }
      }

      const { data, error } = await supabaseAdmin
        .from('establecimientos')
        .update(payload)
        .eq('id', id)
        .select()
        .single()

      if (error) throw error
      return new Response(JSON.stringify({ ok: true, data }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data, error } = await supabaseAdmin
      .from('establecimientos')
      .insert({ ...payload, usuario_id: targetUserId })
      .select()
      .single()

    if (error) throw error

    return new Response(JSON.stringify({ ok: true, data }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    console.error('Error en crear-establecimiento:', e)
    return new Response(JSON.stringify({ error: e.message || 'Error interno' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
