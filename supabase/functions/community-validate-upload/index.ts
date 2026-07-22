import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ValidationRequest = {
  kind?: "post" | "avatar" | "cover";
  post_id?: string;
  full_path?: string;
  thumbnail_path?: string;
  object_path?: string;
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const token = bearerToken(request);
  if (!token) return json({ error: "Missing authentication." }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) return json({ error: "Upload validation is not configured." }, 500);

  const client = createClient(url, serviceRoleKey, { auth: { persistSession: false } });
  const { data: authData, error: authError } = await client.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Invalid authentication." }, 401);

  const body = await readJSON<ValidationRequest>(request);
  const kind = normalized(body.kind) ?? "post";
  const postID = normalized(body.post_id);
  const fullPath = normalized(body.full_path);
  const thumbnailPath = normalized(body.thumbnail_path);

  const { data: link, error: linkError } = await client
    .from("profile_auth_links")
    .select("profile_id")
    .eq("auth_user_id", authData.user.id)
    .maybeSingle();
  if (linkError || !link?.profile_id) return json({ error: "Community profile is unavailable." }, 403);

  if (kind === "avatar" || kind === "cover") {
    const objectPath = normalized(body.object_path);
    const prefix = kind === "avatar"
      ? `avatars/${link.profile_id}/`
      : `profile-covers/${link.profile_id}/`;
    if (!objectPath || !objectPath.startsWith(prefix)) {
      return json({ error: "Upload path does not belong to the current profile." }, 403);
    }
    try {
      await validatedJPEG(client, objectPath, kind === "avatar" ? 512 : 1800);
      return json({ validated: true });
    } catch (error) {
      console.warn("community-validate-upload: rejected", error instanceof Error ? error.message : "unknown");
      return json({ error: "图片验证失败，请重新选择图片。" }, 422);
    }
  }

  if (kind !== "post" || !postID || !fullPath || !thumbnailPath) {
    return json({ error: "Invalid upload validation request." }, 400);
  }

  const prefix = `posts/${link.profile_id}/${postID}`;
  if (!fullPath.startsWith(`${prefix}/full/`) || !thumbnailPath.startsWith(`${prefix}/thumb/`)) {
    return json({ error: "Upload path does not belong to the current profile." }, 403);
  }

  try {
    const full = await validatedJPEG(client, fullPath, 1600);
    const thumbnail = await validatedJPEG(client, thumbnailPath, 480);
    const { data: receiptID, error: receiptError } = await client.rpc(
      "edge_record_community_upload_validation",
      {
        p_auth_user_id: authData.user.id,
        p_post_id: postID,
        p_full_path: fullPath,
        p_thumbnail_path: thumbnailPath,
        p_full_sha256: full.sha256,
        p_thumbnail_sha256: thumbnail.sha256,
        p_full_size: full.size,
        p_thumbnail_size: thumbnail.size,
        p_full_width: full.width,
        p_full_height: full.height,
        p_thumbnail_width: thumbnail.width,
        p_thumbnail_height: thumbnail.height,
      },
    );
    if (receiptError || !receiptID) throw new Error(receiptError?.message ?? "receipt_not_created");
    return json({ receipt_id: receiptID });
  } catch (error) {
    console.warn("community-validate-upload: rejected", error instanceof Error ? error.message : "unknown");
    return json({ error: "图片验证失败，请重新选择图片。" }, 422);
  }
}

if (import.meta.main) Deno.serve(handler);

async function validatedJPEG(client: any, path: string, maxDimension: number) {
  const { data, error } = await client.storage.from("community-images").download(path);
  if (error || !data) throw new Error("object_unavailable");
  const bytes = new Uint8Array(await data.arrayBuffer());
  if (bytes.length < 4 || bytes.length > 1_048_576) throw new Error("invalid_object_size");
  const dimensions = jpegDimensions(bytes);
  if (!dimensions || dimensions.width > maxDimension || dimensions.height > maxDimension) {
    throw new Error("invalid_jpeg_dimensions");
  }
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return {
    size: bytes.length,
    width: dimensions.width,
    height: dimensions.height,
    sha256: Array.from(new Uint8Array(digest)).map((value) => value.toString(16).padStart(2, "0")).join(""),
  };
}

export function jpegDimensions(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let offset = 2;
  const startOfFrame = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
  while (offset + 3 < bytes.length) {
    if (bytes[offset] !== 0xff) return null;
    while (offset < bytes.length && bytes[offset] === 0xff) offset += 1;
    const marker = bytes[offset++];
    if (marker === 0xd9 || marker === 0xda) return null;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 1 >= bytes.length) return null;
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return null;
    if (startOfFrame.has(marker)) {
      if (length < 7) return null;
      const height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      const width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      return width > 0 && height > 0 ? { width, height } : null;
    }
    offset += length;
  }
  return null;
}

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
