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
    .select('rol, ong_id')
    .eq('id', user.id)
    .maybeSingle()

  const rol = perfil?.rol
  if (!rol || !['superadmin', 'rt', 'ong'].includes(rol)) {
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

  const { table, operation, record, filters, userId } = body
  if (!table || !operation || !record) {
    return new Response(JSON.stringify({ error: 'Faltan table/operation/record' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const targetUserId = userId || body.usuario_id || user.id

  if (rol === 'ong' && targetUserId !== user.id) {
    return new Response(JSON.stringify({ error: 'No podés operar sobre otro usuario' }), {
      status: 403,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  if (rol === 'rt') {
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
    let query = supabaseAdmin.from(table)

    if (operation === 'insert') {
      const { data, error } = await query.insert(record).select().single()
      if (error) throw error
      return new Response(JSON.stringify({ ok: true, data }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (operation === 'update') {
      let q = query.update(record)
      if (filters && typeof filters === 'object') {
        Object.entries(filters).forEach(([k, v]) => q = q.eq(k, v))
      }
      const { data, error } = await q.select().single()
      if (error) throw error
      return new Response(JSON.stringify({ ok: true, data }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (operation === 'delete') {
      let q = query.delete()
      if (filters && typeof filters === 'object') {
        Object.entries(filters).forEach(([k, v]) => q = q.eq(k, v))
      }
      const { error } = await q
      if (error) throw error
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    throw new Error('Operación no soportada')
  } catch (e) {
    console.error('Error en escribir-datos:', e)
    return new Response(JSON.stringify({ error: e.message || 'Error interno' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
