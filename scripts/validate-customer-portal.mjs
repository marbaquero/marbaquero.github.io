import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(path, import.meta.url), "utf8");
const portal = await read("../portal.html");
const webhook = await read("../supabase/functions/stripe-webhook/index.ts");
const checkout = await read("../supabase/functions/create-checkout-session/index.ts");
const billing = await read("../supabase/functions/create-billing-portal-session/index.ts");
const onboarding = await read("../supabase/functions/complete-onboarding/index.ts");

// Parse every inline browser script so syntax errors fail CI.
const scripts = [...portal.matchAll(/<script>([\\s\\S]*?)<\\/script>/gi)].map((m) => m[1]);
assert.ok(scripts.length > 0, "portal must contain its application script");
for (const script of scripts) new Function(script);

// Commercial configuration shown to customers must remain consistent.
assert.match(portal, /Family Plan — \$29\/month/);
assert.match(portal, /Full Setup — \$99 setup \+ \$49\/month/);
assert.match(portal, /value="family"/);
assert.match(portal, /value="full_setup"/);

// Browser code may contain only the publishable Supabase key, never privileged secrets.
assert.match(portal, /sb_publishable_/);
assert.doesNotMatch(portal, /service_role|sk_live_|sk_test_|whsec_/i);

// Payment endpoints must authenticate the caller and enforce household ownership.
for (const source of [checkout, billing]) {
  assert.match(source, /auth\\.getUser/);
  assert.match(source, /eq\("user_id", user\.id\)/);
  assert.match(source, /eq\("role", "owner"\)/);
  assert.match(source, /Bearer /);
}
assert.match(checkout, /STRIPE_FAMILY_MONTHLY_PRICE_ID/);
assert.match(checkout, /STRIPE_FULL_SETUP_MONTHLY_PRICE_ID/);
assert.match(checkout, /STRIPE_FULL_SETUP_FEE_PRICE_ID/);
assert.match(checkout, /subscription_data\[metadata\]\[household_id\]/);

// Onboarding must use the verified JWT identity, not a user ID supplied by the browser.
assert.match(onboarding, /ctx\.userClaims\?\.id/);
assert.match(onboarding, /complete_customer_onboarding/);
assert.doesNotMatch(onboarding, /payload\.user_id/);

// Webhook must authenticate Stripe, be retryable, and use subscription lifecycle events.
assert.match(webhook, /verifyStripeSignature\(rawBody, signature, stripeSecret\)/);
assert.match(webhook, /stripe_webhook_events/);
assert.match(webhook, /processed_at/);
assert.match(webhook, /event\.type\.startsWith\("customer\.subscription\."/);
assert.doesNotMatch(webhook, /invoice\.payment_(?:succeeded|failed)/);

console.log("Customer portal checks passed.");
