-- Grant the backend service role only the table access used by the
-- authenticated checkout, billing portal, and Stripe webhook Edge Functions.
-- RLS remains enabled; service_role bypasses RLS as intended for trusted backend code.

grant select on public.household_members to service_role;

grant select, insert, update on public.subscriptions to service_role;

grant select, update on public.household_app_access to service_role;
