-- Stripe webhook idempotency ledger.
-- Apply only after review in the central customer-platform project.
-- No legacy family-care tables or data are modified.

create table if not exists public.stripe_webhook_events (
  event_id text primary key,
  event_type text not null,
  processing_started_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text
);

alter table public.stripe_webhook_events enable row level security;

revoke all on public.stripe_webhook_events from anon, authenticated;
grant select, insert, update on public.stripe_webhook_events to service_role;

comment on table public.stripe_webhook_events is
  'Private idempotency ledger for verified Stripe webhook events; service-role only.';
