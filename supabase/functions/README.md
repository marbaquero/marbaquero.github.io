# Supabase Edge Functions — customer billing

These functions are source-only until deployed and configured. They are designed for the central customer platform project, not the legacy family-data project.

## create-checkout-session

- Requires a signed-in Supabase user and household owner membership.
- Creates a Stripe-hosted subscription checkout.
- Family plan uses one recurring monthly price.
- Full Setup uses the $49 recurring price plus the $99 one-time price in the same checkout.
- Does not activate application access. The verified webhook is the source of truth.

Required Supabase function secrets:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `STRIPE_SECRET_KEY` (Stripe test key during testing)
- `STRIPE_FAMILY_MONTHLY_PRICE_ID`
- `STRIPE_FULL_SETUP_MONTHLY_PRICE_ID`
- `STRIPE_FULL_SETUP_FEE_PRICE_ID`
- `PORTAL_RETURN_URL` (must be the final HTTPS portal URL)

## create-billing-portal-session

- Requires a signed-in household owner.
- Creates a Stripe customer portal session for the linked Stripe customer.
- Uses the same `STRIPE_SECRET_KEY` and `PORTAL_RETURN_URL` secrets.

## stripe-webhook

Configure the Stripe webhook endpoint to this function and subscribe to:
- `checkout.session.completed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.paid`
- `invoice.payment_failed`

Required secrets:
- `STRIPE_WEBHOOK_SECRET`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

The webhook validates the Stripe signature and enables app access only for active/trialing subscriptions. It disables access for past-due, canceled, unpaid, and incomplete states.

## Deployment gate

Before deployment, verify the three Stripe Price IDs in Stripe test mode. Do not substitute guessed IDs. Confirm the exact portal return URL and set the webhook signing secret in Supabase. Keep production mode disabled until end-to-end test purchases, cancellations, and failed-payment tests pass.
