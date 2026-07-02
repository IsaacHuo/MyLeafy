import {
  corsHeaders,
  createAdminContext,
  errorResponse,
  json,
} from "../_shared/admin-announcements.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Method not allowed.", { retryable: false });
  }

  const context = await createAdminContext(request);
  if (context instanceof Response) {
    return context;
  }

  const { data, error } = await context.adminClient
    .from("site_announcements")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(100);

  if (error) {
    return errorResponse(500, "backend_unavailable", error.message);
  }

  return json({ announcements: data ?? [] });
});
