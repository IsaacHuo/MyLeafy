import {
  corsHeaders,
  createAdminContext,
  errorResponse,
  json,
  normalizeText,
  readJSON,
} from "../_shared/admin-announcements.ts";

type UpdateRequest = {
  id?: string | null;
  status?: string | null;
};

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

  const body = await readJSON<UpdateRequest>(request);
  const id = normalizeText(body.id);
  const status = normalizeText(body.status);

  if (!id) {
    return errorResponse(400, "bad_request", "公告 ID 不能为空。");
  }

  if (status !== "archived") {
    return errorResponse(400, "bad_request", "当前仅支持下线公告。");
  }

  const { data, error } = await context.adminClient
    .from("site_announcements")
    .update({ status })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    return errorResponse(500, "backend_unavailable", error.message);
  }

  return json({ announcement: data });
});
