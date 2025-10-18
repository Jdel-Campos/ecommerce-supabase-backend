// =============================================
// EDGE FUNCTION: auth-login (versão integrada ao Supabase Auth)
// =============================================
// Caminho: supabase/functions/auth-login/index.ts

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ===== CORS CONFIG =====
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // ✅ Preflight CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // ✅ Recebe corpo da requisição
    const { email, password } = await req.json()

    if (!email || !password) {
      return new Response(
        JSON.stringify({ message: 'E-mail e senha são obrigatórios' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ✅ Carrega variáveis de ambiente
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      console.error('❌ Variáveis de ambiente ausentes.')
      return new Response(
        JSON.stringify({ message: 'Erro interno: variáveis de ambiente não configuradas.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ✅ Cria cliente Supabase com Service Role
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    // ✅ Usa o Supabase Auth para autenticação
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (error) {
      console.warn('⚠️ Erro de autenticação:', error.message)
      return new Response(
        JSON.stringify({ message: 'Credenciais inválidas' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ✅ Se chegou até aqui, login foi bem-sucedido
    const { user, session } = data

    console.log(`✅ Login bem-sucedido para: ${email}`)

    // ✅ Retorna token + dados do usuário autenticado
    return new Response(
      JSON.stringify({
        message: 'Login realizado com sucesso',
        user,
        session,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('💥 Erro inesperado no login:', err)
    return new Response(
      JSON.stringify({ message: 'Erro interno do servidor', details: err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
