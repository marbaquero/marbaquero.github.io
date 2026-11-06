import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "jsr:@supabase/server@^1";

interface OnboardingPayload {
  name: string;
  plan_key: "family" | "full_setup";
  locale?: "en" | "es";
  timezone?: string;
}

export default {
  fetch: withSupabase({ auth: ["user", "publishable"] }, async (req, ctx) => {
    if (req.method !== "POST") return Response.json({ error: "POST required" }, { status: 405 });
    const userId = ctx.userClaims?.id;
    if (!userId) return Response.json({ error: "Authentication required" }, { status: 401 });
    let payload: OnboardingPayload;
    try { payload = await req.json(); }
    catch { return Response.json({ error: "Invalid JSON" }, { status: 400 }); }
    const name = payload.name?.trim();
    const planKey = payload.plan_key;
    if (!name || name.length > 100 || !["family", "full_setup"].includes(planKey)) {
      return Response.json({ error: "Invalid name or plan" }, { status: 400 });
    }
    const { data, error } = await ctx.supabaseAdmin.rpc("complete_customer_onboarding", {
      p_user_id: userId, p_name: name, p_plan_key: planKey,
      p_locale: payload.locale === "es" ? "es" : "en",
      p_timezone: payload.timezone || null
    });
    if (error) {
      console.error("Onboarding error:", error);
      return Response.json({ error: "Unable to complete onboarding" }, { status: 400 });
    }
    return Response.json(data, { status: 201 });
  })
};
