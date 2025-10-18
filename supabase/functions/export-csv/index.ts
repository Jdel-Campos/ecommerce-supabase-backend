// =============================================
// EDGE FUNCTION: export-csv (versão final e compatível com Supabase local)
// =============================================
// Gera um CSV com os pedidos de um cliente usando a view view_orders_with_customers.
// Aceita requisições POST com { "customerId": <id_do_cliente> }

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js";

// =============================================
// CONFIGURAÇÕES DE CORS
// =============================================
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// =============================================
// FUNÇÃO PRINCIPAL
// =============================================
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
    // 1️⃣ Valida o corpo da requisição
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

    const { customerId } = body;

    if (!customerId) {
      return new Response(
        JSON.stringify({ success: false, message: "Missing required field: customerId" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 422 }
      );
    }

    // =============================================
    // 2️⃣ Cria cliente Supabase com chave Service Role
    // =============================================
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      console.error("❌ Variáveis de ambiente ausentes.");
      return new Response(
        JSON.stringify({ success: false, message: "Missing Supabase environment variables" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // =============================================
    // 3️⃣ Busca os pedidos do cliente
    // =============================================
    const { data, error } = await supabase
      .from("view_orders_with_customers")
      .select("order_id, status, total_amount, order_date_formatted, customer_name, customer_email")
      .eq("customer_id", customerId);

    if (error) {
      console.error("❌ Supabase query error:", error);
      return new Response(
        JSON.stringify({ success: false, message: "Error fetching orders", error }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
      );
    }

    if (!data || data.length === 0) {
      return new Response(
        JSON.stringify({ success: false, message: "No orders found for this customer" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 404 }
      );
    }

    // =============================================
    // 4️⃣ Gera o conteúdo CSV
    // =============================================
    const header = Object.keys(data[0]);
    const csvRows = data.map((row) =>
      Object.values(row)
        .map((value) => `"${String(value).replace(/"/g, '""')}"`) // Escapa aspas
        .join(",")
    );
    const csvContent = [header.join(","), ...csvRows].join("\n");

    // =============================================
    // 5️⃣ Retorna o CSV
    // =============================================
    console.log(`✅ CSV gerado para o cliente ID: ${customerId}`);

    return new Response(csvContent, {
      headers: {
        ...corsHeaders,
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename=orders_${customerId}_${new Date().toISOString().split("T")[0]}.csv`,
      },
      status: 200,
    });
  } catch (error) {
    console.error("💥 Unexpected error:", error);
    return new Response(
      JSON.stringify({ success: false, message: "Failed to generate CSV", error }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});
