import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const token = bearerToken(request);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!token) return json({ error: "Missing authentication." }, 401);
  if (!url || !serviceRoleKey) return json({ error: "Attachment download is not configured." }, 500);

  const client = createClient(url, serviceRoleKey, { auth: { persistSession: false } });
  const { data: authData, error: authError } = await client.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Invalid authentication." }, 401);

  const body = await readJSON<{ attachment_id?: string }>(request);
  const attachmentID = normalized(body.attachment_id);
  if (!attachmentID) return json({ error: "Missing attachment." }, 400);

  const { data: link } = await client
    .from("profile_auth_links")
    .select("profile_id")
    .eq("auth_user_id", authData.user.id)
    .maybeSingle();
  if (!link?.profile_id) return json({ error: "Community profile is unavailable." }, 403);

  const [{ data: profile }, { data: attachment, error: attachmentError }] = await Promise.all([
    client.from("profiles").select("community_campus_id").eq("id", link.profile_id).maybeSingle(),
    client.from("post_attachments").select("*").eq("id", attachmentID).maybeSingle(),
  ]);
  if (attachmentError || !attachment || !profile?.community_campus_id) {
    return json({ error: "Attachment is unavailable." }, 404);
  }

  const { data: post } = await client
    .from("posts")
    .select("campus_id,status")
    .eq("id", attachment.post_id)
    .maybeSingle();
  if (!post || post.status !== "published" || post.campus_id !== profile.community_campus_id) {
    return json({ error: "Attachment is unavailable." }, 404);
  }

  const { data: signed, error: signedError } = await client.storage
    .from("community-attachments")
    .createSignedUrl(attachment.path, 10 * 60);
  if (signedError || !signed?.signedUrl) return json({ error: "Unable to prepare attachment." }, 503);

  return json({
    url: signed.signedUrl,
    display_name: attachment.display_name,
    content_type: attachment.content_type,
    byte_size: attachment.byte_size,
    expires_in: 600,
  });
}

if (import.meta.main) Deno.serve(handler);

function bearerToken(request: Request) {
  const value = request.headers.get("Authorization") ?? "";
  const [scheme, token] = value.split(/\s+/, 2);
  return scheme.toLowerCase() === "bearer" && token ? token : null;
}

function normalized(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

async function readJSON<T>(request: Request): Promise<T> {
  try {
    return await request.json() as T;
  } catch {
    return {} as T;
  }
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
