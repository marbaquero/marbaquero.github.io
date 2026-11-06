import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "https://marbaquero.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!["GET", "POST"].includes(req.method)) return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) return json({ error: "Service is not configured" }, 503);

    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
    const accessToken = authorization.slice(7);
    const authClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
    const { data: { user }, error: authError } = await authClient.auth.getUser(accessToken);
    if (authError || !user) return json({ error: "Invalid session" }, 401);

    const payload = req.method === "GET" ? Object.fromEntries(new URL(req.url).searchParams) : await req.json();
    const householdId = typeof payload.household_id === "string" ? payload.household_id : "";
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(householdId)) {
      return json({ error: "A valid household_id is required" }, 400);
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: membership, error: memberError } = await admin
      .from("household_members").select("household_id")
      .eq("household_id", householdId).eq("user_id", user.id).maybeSingle();
    if (memberError || !membership) return json({ error: "Household access denied" }, 403);

    const { data: appAccess, error: appError } = await admin
      .from("household_app_access").select("is_enabled")
      .eq("household_id", householdId).eq("app_key", "inventario").maybeSingle();
    const { data: subscription, error: subError } = await admin
      .from("subscriptions").select("status")
      .eq("household_id", householdId).maybeSingle();
    if (appError || subError) return json({ error: "Unable to verify application access" }, 500);
    if (!appAccess?.is_enabled || !subscription || !["active", "trialing"].includes(subscription.status)) {
      return json({ error: "Inventario is not enabled for this household" }, 403);
    }

    if (req.method === "GET") {
      const { data, error } = await admin.rpc("list_customer_medicines", { p_household_id: householdId });
      if (error) {
        console.error("Inventario list failed", error);
        return json({ error: "Unable to load medicines" }, 500);
      }
      return json({ medicines: data || [] });
    }

    if (payload.action === "create_medicine") {
      const name = typeof payload.name === "string" ? payload.name.trim() : "";
      if (!name || name.length > 160) return json({ error: "Medicine name is required" }, 400);
      const args = {
        p_household_id: householdId,
        p_name: name,
        p_dose: boundedText(payload.dose, 80),
        p_brand: boundedText(payload.brand, 120),
        p_stock_quantity: nonNegativeNumber(payload.stock_quantity),
        p_minimum_threshold: nonNegativeNumber(payload.minimum_threshold),
        p_daily_dose: nonNegativeNumber(payload.daily_dose),
        p_unit: boundedText(payload.unit, 40) || "unidad",
        p_unit_cost: nonNegativeNumber(payload.unit_cost),
      };
      if (Object.values(args).some((v) => v === null || v === "\\u0000")) return json({ error: "Invalid medicine values" }, 400);
      const { data, error } = await admin.rpc("create_customer_medicine", args);
      if (error) {
        console.error("Create medicine failed", error);
        return json({ error: "Unable to save medicine" }, 400);
      }
      return json({ medicine: data }, 201);
    }

    if (payload.action === "dispense") {
      const medicineId = typeof payload.medicine_id === "string" ? payload.medicine_id : "";
      const quantity = positiveNumber(payload.quantity);
      if (!isUuid(medicineId) || quantity === null) return json({ error: "Invalid medicine or quantity" }, 400);
      const { data, error } = await admin.rpc("record_customer_dispensing", {
        p_household_id: householdId,
        p_medicine_id: medicineId,
        p_quantity: quantity,
        p_caregiver_label: boundedText(payload.caregiver_label, 120),
        p_event_date: typeof payload.event_date === "string" ? payload.event_date : new Date().toISOString(),
      });
      if (error) {
        const status = error.code === "P0002" ? 404 : 400;
        return json({ error: error.message === "Insufficient stock" ? "Insufficient stock" : "Unable to record dispensing" }, status);
      }
      return json(data);
    }

    return json({ error: "Unsupported action" }, 400);
  } catch (error) {
    console.error("inventario-api failed", error);
    return json({ error: "Unable to process Inventario request" }, 500);
  }
});

function boundedText(value: unknown, max: number): string {
  if (value === undefined || value === null) return "";
  return typeof value === "string" && value.length <= max ? value.trim() : "\u0000";
}
function nonNegativeNumber(value: unknown): number | null {
  if (value === undefined || value === null || value === "") return 0;
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : null;
}
function positiveNumber(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
}
function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
