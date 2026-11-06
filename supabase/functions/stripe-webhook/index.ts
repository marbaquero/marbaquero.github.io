import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const stripeSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!stripeSecret || !supabaseUrl || !serviceKey) return new Response("Webhook not configured", { status: 503 });

  const rawBody = await req.text();
  const signature = req.headers.get("Stripe-Signature") || "";
  if (!(await verifyStripeSignature(rawBody, signature, stripeSecret))) return new Response("Invalid signature", { status: 400 });

  try {
    const event = JSON.parse(rawBody);
    if (!event.id || !event.type) return new Response("Invalid Stripe event", { status: 400 });
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    // Stripe retries delivery. Skip events that have already completed successfully.
    const { data: priorEvent, error: priorError } = await admin
      .from("stripe_webhook_events").select("processed_at").eq("event_id", event.id).maybeSingle();
    if (priorError) throw priorError;
    if (priorEvent?.processed_at) {
      return new Response(JSON.stringify({ received: true, duplicate: true }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }

    const object = event.data?.object || {};
    let householdId = object.metadata?.household_id;
    let planKey = object.metadata?.plan_key;
    let status: string | null = null;
    let customerId: string | null = typeof object.customer === "string" ? object.customer : object.customer?.id || null;
    let subscriptionId: string | null = null;
    let periodStart: string | null = null;
    let periodEnd: string | null = null;

    if (event.type === "checkout.session.completed") {
      householdId ||= object.client_reference_id;
      subscriptionId = typeof object.subscription === "string" ? object.subscription : object.subscription?.id || null;
      if (object.payment_status !== "paid" && object.payment_status !== "no_payment_required") {
        await recordWebhookEvent(admin, event.id, event.type, true);
        return new Response("Checkout not paid", { status: 200 });
      }
      // Keep the subscription status unchanged here: subscription events may arrive first.
    } else if (event.type.startsWith("customer.subscription.")) {
      subscriptionId = object.id;
      status = mapStatus(object.status);
      periodStart = object.current_period_start ? new Date(object.current_period_start * 1000).toISOString() : null;
      periodEnd = object.current_period_end ? new Date(object.current_period_end * 1000).toISOString() : null;
    } else if (event.type === "invoice.payment_failed") {
      subscriptionId = typeof object.subscription === "string" ? object.subscription : object.subscription?.id || null;
      status = "past_due";
    } else if (event.type === "invoice.paid") {
      subscriptionId = typeof object.subscription === "string" ? object.subscription : object.subscription?.id || null;
      status = "active";
    } else {
      await recordWebhookEvent(admin, event.id, event.type, true);
      return new Response(JSON.stringify({ received: true, ignored: event.type }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }

    if (!householdId && subscriptionId) {
      const { data } = await admin.from("subscriptions").select("household_id, plan_key")
        .eq("provider_subscription_id", subscriptionId).maybeSingle();
      householdId = data?.household_id;
      planKey ||= data?.plan_key;
    }
    if (!householdId) throw new Error("Missing household metadata for Stripe event " + event.id);

    const { data: existing, error: lookupError } = await admin.from("subscriptions")
      .select("id").eq("household_id", householdId).maybeSingle();
    if (lookupError) throw lookupError;
    const values: Record<string, unknown> = {
      household_id: householdId,
      ...(planKey ? { plan_key: planKey } : {}),
      ...(status ? { status } : {}),
      billing_provider: "stripe",
      ...(customerId ? { provider_customer_id: customerId } : {}),
      ...(subscriptionId ? { provider_subscription_id: subscriptionId } : {}),
      ...(periodStart ? { current_period_start: periodStart } : {}),
      ...(periodEnd ? { current_period_end: periodEnd } : {}),
      updated_at: new Date().toISOString(),
    };
    const write = existing
      ? await admin.from("subscriptions").update(values).eq("id", existing.id)
      : await admin.from("subscriptions").insert(values);
    if (write.error) throw write.error;

    if (status) {
      const enabled = ["active", "trialing"].includes(status);
      const { error: accessError } = await admin.from("household_app_access")
        .update({ is_enabled: enabled }).eq("household_id", householdId);
      if (accessError) throw accessError;
    }
    await recordWebhookEvent(admin, event.id, event.type, true);
    return new Response(JSON.stringify({ received: true }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (error) {
    console.error("stripe-webhook failed", error);
    // Keep processed_at null so Stripe's retry can safely attempt the event again.
    try {
      const event = JSON.parse(rawBody);
      const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
      await admin.from("stripe_webhook_events").upsert({
        event_id: event.id, event_type: event.type,
        last_error: String(error).slice(0, 1000), processed_at: null,
      }, { onConflict: "event_id" });
    } catch (ledgerError) {
      console.error("stripe-webhook ledger update failed", ledgerError);
    }
    return new Response("Webhook processing failed", { status: 500 });
  }
});

async function recordWebhookEvent(admin: ReturnType<typeof createClient>, eventId: string, eventType: string, complete: boolean) {
  const { error } = await admin.from("stripe_webhook_events").upsert({
    event_id: eventId,
    event_type: eventType,
    processing_started_at: new Date().toISOString(),
    processed_at: complete ? new Date().toISOString() : null,
    last_error: null,
  }, { onConflict: "event_id" });
  if (error) throw error;
}

function mapStatus(value: string): string {
  if (value === "active") return "active";
  if (value === "trialing") return "trialing";
  if (value === "past_due") return "past_due";
  if (value === "canceled") return "canceled";
  if (value === "unpaid") return "unpaid";
  return "incomplete";
}

async function verifyStripeSignature(payload: string, header: string, secret: string): Promise<boolean> {
  const parts = header.split(",").map(v => v.trim());
  const timestamp = parts.find(v => v.startsWith("t="))?.slice(2);
  const signatures = parts.filter(v => v.startsWith("v1=")).map(v => v.slice(3));
  if (!timestamp || !signatures.length || Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(timestamp + "." + payload));
  const expected = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
  return signatures.some(sig => constantTimeEqual(sig, expected));
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
