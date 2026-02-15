// =============================================
// EDGE FUNCTION: send-confirmation-email (versão alinhada ao schema/RLS)
// =============================================

import "@supabase/functions-js/edge-runtime.d.ts";
import { Resend } from "resend";
import { createClient } from "@supabase/supabase-js";
import {
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  RESEND_API_KEY,
  RESEND_FROM,
  ALLOWED_ORIGINS,
} from "../shared/env.ts";


// --------- ENV ---------
if (!RESEND_API_KEY) throw new Error("Missing RESEND_API_KEY");
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) throw new Error("Missing Supabase envs");

const resend = new Resend(RESEND_API_KEY);

// --------- Types ---------
interface RequestBody {
  orderId?: string;
}

interface ResendResult {
  data?: { id: string };
  error?: { message: string; name: string };
}

// --------- Helpers ---------
const uuidRe =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function pickCorsOrigin(req: Request) {
  const origin = req.headers.get("origin") || "";
  if (ALLOWED_ORIGINS.includes("*")) return "*";
  if (ALLOWED_ORIGINS.includes(origin)) return origin;
  return null;
}

function corsHeadersFor(req: Request) {
  const origin = pickCorsOrigin(req) || "null";
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

function badRequest(body: unknown, req: Request) {
  return new Response(JSON.stringify(body), {
    status: 400,
    headers: { ...corsHeadersFor(req), "Content-Type": "application/json" },
  });
}
function forbidden(body: unknown, req: Request) {
  return new Response(JSON.stringify(body), {
    status: 403,
    headers: { ...corsHeadersFor(req), "Content-Type": "application/json" },
  });
}
function methodNotAllowed(req: Request) {
  return new Response(JSON.stringify({ success: false, message: "Method Not Allowed" }), {
    status: 405,
    headers: { ...corsHeadersFor(req), "Content-Type": "application/json" },
  });
}
function ok(body: unknown, req: Request) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { ...corsHeadersFor(req), "Content-Type": "application/json" },
  });
}
function badGateway(body: unknown, req: Request) {
  return new Response(JSON.stringify(body), {
    status: 502,
    headers: { ...corsHeadersFor(req), "Content-Type": "application/json" },
  });
}
function serverError(req: Request) {
  return new Response(JSON.stringify({ success: false, message: "Internal error" }), {
    status: 500,
    headers: { ...corsHeadersFor(req), "Content-Type": "application/json" },
  });
}

// --------- HTML template ---------
function buildHtml(orderId: string) {
  return `
  <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto;">
    <h2 style="color: #1a73e8;">Pedido Confirmado!</h2>
    <p>Olá! Obrigado por comprar conosco.</p>
    <p>Seu pedido <strong>#${orderId}</strong> foi confirmado com sucesso.</p>
    <p>Você receberá atualizações por e-mail assim que for enviado.</p>
    <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;" />
    <p style="font-size: 12px; color: #888;">Este é um e-mail automático. Por favor, não responda.</p>
  </div>`;
}

// --------- Handler ---------
Deno.serve(async (req) => {
  // Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req) });
  }

  if (req.method !== "POST") {
    return methodNotAllowed(req);
  }

  // CORS: origin whitelist
  const originOk = pickCorsOrigin(req);
  if (!originOk) {
    return forbidden({ success: false, message: "Origin not allowed" }, req);
  }

  // Auth: exige Bearer JWT (usuário logado)
  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7)
    : null;

  if (!token) {
    return forbidden(
      { success: false, message: "Missing Authorization Bearer token" },
      req,
    );
  }

  // Parse body
  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return badRequest({ success: false, message: "Invalid JSON" }, req);
  }

  const orderId = String(body?.orderId || "").trim();

  if (!uuidRe.test(orderId)) {
    return badRequest(
      { success: false, message: "Invalid orderId (must be UUID v4)" },
      req,
    );
  }

  // Supabase client como "usuário" (usa ANON + Authorization do request)
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  // Verifica se o pedido é acessível pelo usuário autenticado e busca o e-mail
  // Usamos a view view_orders_with_customers para obter order_id + customer_email
  const { data, error } = await supabase
    .from("view_orders_with_customers")
    .select("order_id, customer_email")
    .eq("order_id", orderId)
    .maybeSingle();

  if (error) {
    console.error("Query error:", error);
    return serverError(req);
  }

  // Se não veio linha, ou o pedido não existe ou não pertence ao usuário (RLS filtra)
  if (!data || !data.customer_email) {
    return forbidden(
      { success: false, message: "Not allowed to notify this order" },
      req,
    );
  }

  const targetEmail = String(data.customer_email).trim();

  // Envia e-mail
  try {
    const result = await resend.emails.send({
      from: RESEND_FROM,
      to: targetEmail,
      subject: "Seu pedido foi confirmado com sucesso!",
      html: buildHtml(orderId),
    });

    const resendResult = result as ResendResult;
    if (resendResult?.error) {
      console.error("Resend error:", resendResult.error);
      return badGateway(
        { success: false, message: "Failed to send email" },
        req,
      );
    }
  } catch (e) {
    console.error("Resend exception:", e);
    return badGateway(
      { success: false, message: "Failed to send email" },
      req,
    );
  }

  return ok(
    { success: true, message: "Confirmation email sent" },
    req,
  );
});