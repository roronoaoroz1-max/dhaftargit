// =========================================================
// DHAFTAR SUPABASE CONNECTION
// =========================================================

// Replace these two values with your actual Supabase details.
const SUPABASE_URL =
  "https://fteeevnioarkhpcplsyq.supabase.co";

const SUPABASE_PUBLISHABLE_KEY =
  "sb_publishable_yw-S8Fr5BRAWa_kRWD5QXQ_ejJPaoHZ";

const supabaseClient =
  window.supabase.createClient(
    SUPABASE_URL,
    SUPABASE_PUBLISHABLE_KEY,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    }
  );
