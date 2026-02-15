// supabase/functions/_shared/env.ts

function required(name: string): string {
    const value = Deno.env.get(name);
    if (!value) {
      throw new Error(`Missing environment variable: ${name}`);
    }
    return value;
  }
  
  // Variáveis obrigatórias
  export const SUPABASE_URL = required("SUPABASE_URL");
  export const SUPABASE_ANON_KEY = required("SUPABASE_ANON_KEY");
  
  // Resend (usado na função de e-mail)
  export const RESEND_API_KEY = required("RESEND_API_KEY");
  export const RESEND_FROM =
    Deno.env.get("RESEND_FROM") || "no-reply@example.com";
  
  // CORS
  export const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ||
    "http://127.0.0.1:5500")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  