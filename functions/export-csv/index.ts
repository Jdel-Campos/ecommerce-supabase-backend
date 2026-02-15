// =============================================
// EDGE FUNCTION: export-csv (RLS-friendly, user-scoped)
// Exporta os pedidos do usuário autenticado em CSV.
// POST {}  (body pode ser vazio)
// Requer Authorization: Bearer <JWT do usuário>
// =============================================

  import "@supabase/functions-js/edge-runtime.d.ts";
  import { createClient } from "@supabase/supabase-js";
  import {
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    ALLOWED_ORIGINS,
  } from "../shared/env.ts";

// ---------- ENV ----------

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error("Missing SUPABASE_URL/SUPABASE_ANON_KEY");
}

// ---------- Helpers ----------
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
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

function json(res: unknown, status: number, req: Request) {
  return new Response(JSON.stringify(res), {
    status,
    headers: { ...corsHeadersFor(req), "Content-Type": "application/json" },
  });
}

function sanitizeCell(v: unknown): string {
  // Escapa aspas e neutraliza fórmulas (CSV injection)
  const s = String(v ?? "");
  const needsNeutralize = /^[=\-+@]/.test(s);
  const safe = needsNeutralize ? "'" + s : s;
  return `"${safe.replace(/"/g, '""')}"`;
}

function buildCsv(rows: Array<Record<string, unknown>>): string {
  const header = Object.keys(rows[0] || {});
  const headLine = header.join(",");
  const bodyLines = rows.map((row) =>
    header.map((k) => sanitizeCell(row[k])).join(","),
  );
  return [headLine, ...bodyLines].join("\n");
}

// ---------- Handler ----------
Deno.serve(async (req) => {
  // Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req) });
  }

  if (req.method !== "POST") {
    return json({ success: false, message: "Method Not Allowed" }, 405, req);
  }

  // CORS
  if (!pickCorsOrigin(req)) {
    return json({ success: false, message: "Origin not allowed" }, 403, req);
  }

  // Auth: exige Bearer
  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7)
    : null;
  if (!token) {
    return json(
      { success: false, message: "Missing Authorization Bearer token" },
      403,
      req,
    );
  }

  // Se quiser aceitar body pra futuro filtro, podemos parsear,
  // mas hoje não dependemos de nenhum campo do cliente.
  if (req.headers.get("content-length")) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const _body = await req.json();
    } catch {
      // Body inválido? mantemos simples: só avisamos.
      return json(
        { success: false, message: "Invalid JSON format" },
        400,
        req,
      );
    }
  }

  // Supabase client como "usuário" (RLS aplicada)
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  // 1) Descobre o customer vinculado ao usuário autenticado
  // RLS em customers garante que só o próprio cliente é visível.
  const { data: customer, error: custErr } = await supabase
    .from("customers")
    .select("id")
    .maybeSingle();

  if (custErr) {
    console.error("Customer lookup error:", custErr);
    return json(
      { success: false, message: "Failed to resolve current customer" },
      500,
      req,
    );
  }

  if (!customer?.id) {
    return json(
      { success: false, message: "Customer not found for current user" },
      404,
      req,
    );
  }

  const customerId = customer.id as string;

  // 2) Busca dados na view (RLS respeitada via security_invoker)
  const { data, error } = await supabase
    .from("view_orders_with_customers")
    .select(
      "order_id, customer_id, status, total_amount, order_created_at, order_date_formatted, customer_name, customer_email",
    )
    .eq("customer_id", customerId);

  if (error) {
    console.error("Query error:", error);
    return json(
      { success: false, message: "Error fetching orders" },
      500,
      req,
    );
  }

  if (!data || data.length === 0) {
    return json(
      { success: false, message: "No orders found for this customer" },
      404,
      req,
    );
  }

  // 3) Gera CSV
  const csv = buildCsv(data as Array<Record<string, unknown>>);
  const fileName = `orders_${customerId}_${new Date()
    .toISOString()
    .slice(0, 10)}.csv`;

  return new Response(csv, {
    status: 200,
    headers: {
      ...corsHeadersFor(req),
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename=${fileName}`,
    },
  });
});