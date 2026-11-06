-- The onboarding RPC accepts a user id and creates a household.
-- It must only be callable by the trusted onboarding Edge Function (service_role).

revoke execute on function public.complete_customer_onboarding(uuid, text, text, text, text)
  from public, anon, authenticated;

grant execute on function public.complete_customer_onboarding(uuid, text, text, text, text)
  to service_role;
