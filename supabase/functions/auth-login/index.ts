// =============================================
// EDGE FUNCTION: auth-login (versão integrada ao Supabase Auth)
// =============================================
// Caminho: supabase/functions/auth-login/index.ts

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

// ===== CORS CONFIG =====
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  // ✅ Preflight CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // ✅ Garante que apenas POST é aceito
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ message: 'Método não permitido' }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ✅ Recebe corpo da requisição
    let payload: unknown
    try {
      payload = await req.json()
    } catch {
      return new Response(
        JSON.stringify({ message: 'Formato de JSON inválido' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { email, password } = payload as {
      email?: unknown
      password?: unknown
    }

    const normalizedEmail = typeof email === 'string' ? email.trim() : ''
    const passwordValue = typeof password === 'string' ? password : ''

    if (!normalizedEmail || !passwordValue) {
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
      email: normalizedEmail,
      password: passwordValue,
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
    const message = err instanceof Error ? err.message : 'Erro desconhecido'
    console.error('💥 Erro inesperado no login:', err)
    return new Response(
      JSON.stringify({ message: 'Erro interno do servidor', details: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
});