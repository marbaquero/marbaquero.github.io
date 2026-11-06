import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "https://marbaquero.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")!;
    const portalUrl = Deno.env.get("PORTAL_RETURN_URL") || "https://marbaquero.github.io/portal.html";
    const familyPrice = Deno.env.get("STRIPE_FAMILY_MONTHLY_PRICE_ID");
    const fullSetupMonthly = Deno.env.get("STRIPE_FULL_SETUP_MONTHLY_PRICE_ID");
    const fullSetupFee = Deno.env.get("STRIPE_FULL_SETUP_FEE_PRICE_ID");
    if (!url || !anonKey || !serviceKey || !stripeKey || !familyPrice || !fullSetupMonthly || !fullSetupFee) {
      return json({ error: "Payment service is not configured" }, 503);
    }

    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
    const accessToken = authorization.slice(7);
    const authClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
    const { data: { user }, error: authError } = await authClient.auth.getUser(accessToken);
    if (authError || !user) return json({ error: "Invalid session" }, 401);

    const { plan_key } = await req.json();
    if (!["family", "full_setup"].includes(plan_key)) return json({ error: "Invalid plan" }, 400);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: membership, error: memberError } = await admin
      .from("household_members").select("household_id, role")
      .eq("user_id", user.id).eq("role", "owner").limit(1).maybeSingle();
    if (memberError || !membership) return json({ error: "Household owner account required" }, 403);

    const { data: currentSub } = await admin.from("subscriptions")
      .select("status, provider_subscription_id")
      .eq("household_id", membership.household_id).maybeSingle();
    if (currentSub?.provider_subscription_id && ["active", "trialing", "past_due"].includes(currentSub.status)) {
      return json({ error: "A subscription already exists. Manage it from the billing portal." }, 409);
    }

    const form = new URLSearchParams();
    form.set("mode", "subscription");
    form.set("success_url", portalUrl + "?checkout=success");
    form.set("cancel_url", portalUrl + "?checkout=cancel");
    form.set("client_reference_id", membership.household_id);
    form.set("customer_email", user.email || "");
    form.set("line_items[0][price]", plan_key === "family" ? familyPrice : fullSetupMonthly);
    form.set("line_items[0][quantity]", "1");
    if (plan_key === "full_setup") {
      form.set("line_items[1][price]", fullSetupFee);
      form.set("line_items[1][quantity]", "1");
    }
    form.set("metadata[household_id]", membership.household_id);
    form.set("metadata[plan_key]", plan_key);
    form.set("subscription_data[metadata][household_id]", membership.household_id);
    form.set("subscription_data[metadata][plan_key]", plan_key);

    const stripeResponse = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: { Authorization: "Bearer " + stripeKey, "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const session = await stripeResponse.json();
    if (!stripeResponse.ok) return json({ error: session.error?.message || "Unable to create checkout session" }, 502);
    return json({ url: session.url }, 200);
  } catch (error) {
    console.error("create-checkout-session failed", error);
    return json({ error: "Unable to start checkout" }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
