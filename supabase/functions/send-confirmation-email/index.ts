// =============================================
// EDGE FUNCTION: send-confirmation-email (versão final)
// =============================================
// Envia e-mails de confirmação de pedido via Resend.
// Aceita POST com { email, orderId } e suporta CORS.
// =============================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Resend } from "npm:resend@3.2.0";

// =============================================
// CONFIGURAÇÕES GLOBAIS E CORS
// =============================================
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const apiKey = Deno.env.get("RESEND_API_KEY");
if (!apiKey) {
  console.error("❌ Missing RESEND_API_KEY environment variable");
  throw new Error("Missing RESEND_API_KEY");
}

const resend = new Resend(apiKey);

Deno.serve(async (req) => {
  // ✅ Suporte ao preflight CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ✅ Garante que apenas POST é aceito
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({ success: false, message: "Method Not Allowed" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 405 }
      );
    }

    // =============================================
    // 1️⃣ Validação de origem (permite local)
    // =============================================
    const allowedOrigin =
      Deno.env.get("ALLOWED_ORIGIN") ||
      "http://127.0.0.1:5500"; // libera localhost p/ desenvolvimento

    const requestOrigin = req.headers.get("origin") || "";

    if (allowedOrigin !== "*" && requestOrigin !== allowedOrigin) {
      console.warn(`⚠️ Origem não permitida: ${requestOrigin}`);
      return new Response(
        JSON.stringify({ success: false, message: "Forbidden: invalid origin" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 403 }
      );
    }

    // =============================================
    // 2️⃣ Validação e parsing do corpo da requisição
    // =============================================
    let body;
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ success: false, message: "Invalid JSON format" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
      );
    }

    const { email, orderId } = body;

    if (!email || !orderId) {
      return new Response(
        JSON.stringify({ success: false, message: "Missing required fields: email, orderId" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 422 }
      );
    }

    // =============================================
    // 3️⃣ Conteúdo do e-mail
    // =============================================
    console.log(`📧 Enviando e-mail para ${email} (Order ID: ${orderId})`);

    const htmlContent = `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto;">
        <h2 style="color: #1a73e8;">Pedido Confirmado!</h2>
        <p>Olá! Obrigado por comprar conosco.</p>
        <p>Seu pedido <strong>#${orderId}</strong> foi confirmado com sucesso.</p>
        <p>Você receberá atualizações por e-mail assim que for enviado.</p>
        <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;" />
        <p style="font-size: 12px; color: #888;">Este é um e-mail automático. Por favor, não responda.</p>
      </div>
    `;

    // =============================================
    // 4️⃣ Envio via Resend API
    // =============================================
    try {
      const result = await resend.emails.send({
        from: "onboarding@resend.dev",
        to: email,
        subject: "Seu pedido foi confirmado com sucesso!",
        html: htmlContent,
      });

      if (result.error) throw result.error;
    } catch (sendError) {
      console.error("❌ Erro ao enviar e-mail:", sendError);
      return new Response(
        JSON.stringify({ success: false, message: "Failed to send email", error: sendError }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 502 }
      );
    }

    // =============================================
    // 5️⃣ Resposta de sucesso
    // =============================================
    console.log(`✅ E-mail de confirmação enviado para ${email}`);
    return new Response(
      JSON.stringify({ success: true, message: "Confirmation email sent successfully" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  } catch (error) {
    console.error("💥 Unexpected error:", error);
    return new Response(
      JSON.stringify({ success: false, message: "Failed to send confirmation email", error }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});
