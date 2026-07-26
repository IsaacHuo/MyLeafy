import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-cleanup-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type CleanupSummary = {
  inspected: number;
  purged: number;
  skipped_for_report: number;
  failures: Array<{ post_id: string; error: string }>;
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cleanupSecret = Deno.env.get("COMMUNITY_MEDIA_CLEANUP_SECRET");
  const bearer = bearerToken(request);
  const suppliedSecret = request.headers.get("x-cleanup-secret");
  if (!url || !serviceRoleKey) return json({ error: "Cleanup is not configured." }, 500);
  if (bearer !== serviceRoleKey && (!cleanupSecret || suppliedSecret !== cleanupSecret)) {
    return json({ error: "Unauthorized." }, 401);
  }

  const client = createClient(url, serviceRoleKey, { auth: { persistSession: false } });
  const now = new Date();
  const stalePendingBefore = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();

  const { error: stalePendingError } = await client
    .from("posts")
    .update({
      status: "deleted",
      media_purge_after: now.toISOString(),
      updated_at: now.toISOString(),
    })
    .eq("status", "pending_review")
    .lt("created_at", stalePendingBefore);
  if (stalePendingError) return json({ error: stalePendingError.message }, 500);

  const { data: candidates, error } = await client
    .from("posts")
    .select("id,author_id")
    .eq("status", "deleted")
    .eq("media_cleanup_hold", false)
    .is("media_purged_at", null)
    .lte("media_purge_after", now.toISOString())
    .limit(100);
  if (error) return json({ error: error.message }, 500);

  const summary: CleanupSummary = {
    inspected: candidates?.length ?? 0,
    purged: 0,
    skipped_for_report: 0,
    failures: [],
  };

  for (const candidate of candidates ?? []) {
    const postID = String(candidate.id);
    const { count: openReports, error: reportError } = await client
      .from("community_reports")
      .select("id", { count: "exact", head: true })
      .eq("post_id", postID)
      .in("status", ["open", "reviewed"]);
    if (reportError) {
      summary.failures.push({ post_id: postID, error: reportError.message });
      continue;
    }
    if ((openReports ?? 0) > 0) {
      summary.skipped_for_report += 1;
      continue;
    }

    try {
      const profileID = String(candidate.author_id);
      const basePath = `posts/${profileID}/${postID}`;
      const [{ data: images }, { data: attachments }] = await Promise.all([
        client.from("post_images").select("path,thumbnail_path").eq("post_id", postID),
        client.from("post_attachments").select("path").eq("post_id", postID),
      ]);
      const imagePaths = (images ?? []).flatMap((image: any) =>
        [image.path, image.thumbnail_path].filter((path): path is string => typeof path === "string" && path.length > 0)
      );
      const attachmentPaths = (attachments ?? [])
        .map((attachment: any) => attachment.path)
        .filter((path): path is string => typeof path === "string" && path.length > 0);
      const [orphanFullImages, orphanThumbnails, orphanAttachments] = await Promise.all([
        listObjectPaths(client, "community-images", `${basePath}/full`),
        listObjectPaths(client, "community-images", `${basePath}/thumb`),
        listObjectPaths(client, "community-attachments", basePath),
      ]);
      const allImagePaths = [...new Set([...imagePaths, ...orphanFullImages, ...orphanThumbnails])];
      const allAttachmentPaths = [...new Set([...attachmentPaths, ...orphanAttachments])];

      if (allImagePaths.length) {
        const { error: removeError } = await client.storage.from("community-images").remove(allImagePaths);
        if (removeError) throw removeError;
      }
      if (allAttachmentPaths.length) {
        const { error: removeError } = await client.storage.from("community-attachments").remove(allAttachmentPaths);
        if (removeError) throw removeError;
      }

      const [{ error: imageDeleteError }, { error: attachmentDeleteError }] = await Promise.all([
        client.from("post_images").delete().eq("post_id", postID),
        client.from("post_attachments").delete().eq("post_id", postID),
      ]);
      if (imageDeleteError) throw imageDeleteError;
      if (attachmentDeleteError) throw attachmentDeleteError;

      const { error: updateError } = await client
        .from("posts")
        .update({ media_purged_at: now.toISOString(), updated_at: now.toISOString() })
        .eq("id", postID);
      if (updateError) throw updateError;
      summary.purged += 1;
    } catch (cleanupError) {
      summary.failures.push({
        post_id: postID,
        error: cleanupError instanceof Error ? cleanupError.message : "unknown",
      });
    }
  }

  return json(summary, summary.failures.length ? 207 : 200);
}

if (import.meta.main) Deno.serve(handler);

async function listObjectPaths(client: any, bucket: string, prefix: string): Promise<string[]> {
  const { data, error } = await client.storage.from(bucket).list(prefix, {
    limit: 1000,
    sortBy: { column: "name", order: "asc" },
  });
  if (error) throw error;
  return (data ?? [])
    .filter((item: any) => typeof item.name === "string" && item.name.length > 0 && item.id)
    .map((item: any) => `${prefix}/${item.name}`);
}

function bearerToken(request: Request) {
  const value = request.headers.get("Authorization") ?? "";
  const [scheme, token] = value.split(/\s+/, 2);
  return scheme.toLowerCase() === "bearer" && token ? token : null;
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
