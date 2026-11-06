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
    if (!url || !anonKey || !serviceKey || !stripeKey) {
      return json({ error: "Billing service is not configured" }, 503);
    }
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
    const authClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
    const { data: { user }, error: authError } = await authClient.auth.getUser(authorization.slice(7));
    if (authError || !user) return json({ error: "Invalid session" }, 401);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: membership, error: memberError } = await admin.from("household_members")
      .select("household_id").eq("user_id", user.id).eq("role", "owner").limit(1).maybeSingle();
    if (memberError) {
      console.error("Billing membership lookup failed", memberError);
      return json({ error: "Unable to verify household ownership" }, 500);
    }
    if (!membership) return json({ error: "Household owner account required" }, 403);
    const { data: subscription, error: subscriptionError } = await admin.from("subscriptions")
      .select("provider_customer_id").eq("household_id", membership.household_id).maybeSingle();
    if (subscriptionError) {
      console.error("Billing subscription lookup failed", subscriptionError);
      return json({ error: "Unable to retrieve billing account" }, 500);
    }
    if (!subscription?.provider_customer_id) return json({ error: "No Stripe customer is linked to this household yet" }, 404);

    const form = new URLSearchParams();
    form.set("customer", subscription.provider_customer_id);
    form.set("return_url", portalUrl);
    const response = await fetch("https://api.stripe.com/v1/billing_portal/sessions", {
      method: "POST",
      headers: { Authorization: "Bearer " + stripeKey, "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const session = await response.json();
    if (!response.ok) return json({ error: session.error?.message || "Unable to open billing portal" }, 502);
    return json({ url: session.url });
  } catch (error) {
    console.error("create-billing-portal-session failed", error);
    return json({ error: "Unable to open billing portal" }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
