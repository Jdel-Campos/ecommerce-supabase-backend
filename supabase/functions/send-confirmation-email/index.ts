// =============================================
// EDGE FUNCTION: send-confirmation-email (hardened)
// =============================================

import "@supabase/functions-js/edge-runtime.d.ts";
import { Resend } from "resend";
import { createClient } from "@supabase/supabase-js";

// --------- ENV ---------
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const RESEND_FROM = Deno.env.get("RESEND_FROM") || "no-reply@example.com";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") || "http://127.0.0.1:5500")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

if (!RESEND_API_KEY) throw new Error("Missing RESEND_API_KEY");
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) throw new Error("Missing Supabase envs");

const resend = new Resend(RESEND_API_KEY);

// --------- Types ---------
interface RequestBody {
  email?: string;
  orderId?: string;
}

interface ResendResult {
  data?: { id: string };
  error?: { message: string; name: string };
}

// --------- Helpers ---------
const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
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
    "Vary": "Origin",
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
    return forbidden({ success: false, message: "Missing Authorization Bearer token" }, req);
  }

  // Parse body
  let body: RequestBody;
  try {
    body = await req.json() as RequestBody;
  } catch {
    return badRequest({ success: false, message: "Invalid JSON" }, req);
  }

  const email = String(body?.email || "").trim();
  const orderId = String(body?.orderId || "").trim();

  if (!emailRe.test(email)) {
    return badRequest({ success: false, message: "Invalid email" }, req);
  }
  if (!uuidRe.test(orderId)) {
    return badRequest({ success: false, message: "Invalid orderId (must be UUID v4)" }, req);
  }

  // Supabase client como "usuário" (usa ANON + Authorization do request)
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  // Verifica se o pedido pertence ao usuário autenticado
  // SELECT o.id FROM orders o
  // JOIN customers c ON c.id = o.customer_id
  // WHERE o.id = :orderId AND c.user_id = auth.uid();
  const { data: rows, error: qErr } = await supabase
    .from("orders")
    .select("id, customers!inner(user_id)")
    .eq("id", orderId)
    .limit(1);

  if (qErr) {
    console.error("Query error:", qErr);
    return serverError(req);
  }
  const ownsOrder =
    Array.isArray(rows) &&
    rows.length === 1 &&
    Array.isArray(rows[0]?.customers) &&
    rows[0].customers.length > 0 &&
    rows[0].customers[0]?.user_id != null; // PostgREST vai garantir match pelo header Authorization

  if (!ownsOrder) {
    // Opcional: permitir admin; aqui mantive apenas dono
    return forbidden({ success: false, message: "Not allowed to notify this order" }, req);
  }

  // Envia e-mail
  try {
    const result = await resend.emails.send({
      from: RESEND_FROM,
      to: email,
      subject: "Seu pedido foi confirmado com sucesso!",
      html: buildHtml(orderId),
    });

    const resendResult = result as ResendResult;
    if (resendResult?.error) {
      console.error("Resend error:", resendResult.error);
      return badGateway({ success: false, message: "Failed to send email" }, req);
    }
  } catch (e) {
    console.error("Resend exception:", e);
    return badGateway({ success: false, message: "Failed to send email" }, req);
  }

  return ok({ success: true, message: "Confirmation email sent" }, req);
});
