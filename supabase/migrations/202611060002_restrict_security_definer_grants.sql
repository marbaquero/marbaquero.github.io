-- Tighten execution grants for central-platform SECURITY DEFINER functions.
-- The onboarding Edge Function uses the service-role-only RPC
-- complete_customer_onboarding; public clients do not need create_household().
-- The RLS helper functions is_household_member/owner remain callable by
-- authenticated users because table policies depend on them and each function
-- returns only the caller's own membership predicate.

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
revoke execute on function public.create_household(text) from public, anon, authenticated;

-- Do not revoke authenticated execution from:
--   public.is_household_member(uuid)
--   public.is_household_owner(uuid)
-- These are authorization predicates used by RLS and check auth.uid() internally.
