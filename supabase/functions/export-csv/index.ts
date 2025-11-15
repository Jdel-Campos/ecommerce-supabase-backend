// =============================================
// EDGE FUNCTION: export-csv (hardened, RLS-friendly)
// POST { "customerId": "<uuid>" }
// Requer Authorization: Bearer <JWT do usuário>
// =============================================

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

// ---------- ENV ----------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") || "http://127.0.0.1:5500")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error("Missing SUPABASE_URL/SUPABASE_ANON_KEY");
}

// ---------- Types ----------
interface RequestBody {
  customerId?: string;
}

// ---------- Helpers ----------
const uuidV4Re = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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
    header.map((k) => sanitizeCell(row[k])).join(",")
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
    return json({ success: false, message: "Missing Authorization Bearer token" }, 403, req);
  }

  // Body
  let body: RequestBody;
  try {
    body = await req.json() as RequestBody;
  } catch {
    return json({ success: false, message: "Invalid JSON format" }, 400, req);
  }

  const customerId = String(body?.customerId || "").trim();
  if (!uuidV4Re.test(customerId)) {
    return json({ success: false, message: "Invalid customerId (UUID v4 expected)" }, 422, req);
  }

  // Supabase client como "usuário" (RLS aplicada)
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  // 1) Ownership check: o customerId informado pertence ao auth.uid()?
  // SELECT 1 FROM customers WHERE id=:customerId AND user_id = auth.uid();
  const { data: custRows, error: custErr } = await supabase
    .from("customers")
    .select("id") // RLS deve permitir apenas do próprio usuário
    .eq("id", customerId)
    .limit(1);

  if (custErr) {
    console.error("Customer check error:", custErr);
    return json({ success: false, message: "Ownership check failed" }, 500, req);
  }
  if (!Array.isArray(custRows) || custRows.length === 0) {
    return json({ success: false, message: "Not allowed to export this customer" }, 403, req);
  }

  // 2) Busca dados na view (RLS respeitada via security_invoker)
  const { data, error } = await supabase
    .from("view_orders_with_customers")
    .select(
      "order_id, customer_id, status, total_amount, order_created_at, order_date_formatted, customer_name, customer_email"
    )
    .eq("customer_id", customerId);

  if (error) {
    console.error("Query error:", error);
    return json({ success: false, message: "Error fetching orders" }, 500, req);
  }

  if (!data || data.length === 0) {
    return json({ success: false, message: "No orders found for this customer" }, 404, req);
  }

  // 3) Gera CSV
  const csv = buildCsv(data as Array<Record<string, unknown>>);
  const fileName = `orders_${customerId}_${new Date().toISOString().slice(0, 10)}.csv`;

  return new Response(csv, {
    status: 200,
    headers: {
      ...corsHeadersFor(req),
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename=${fileName}`,
    },
  });
});
