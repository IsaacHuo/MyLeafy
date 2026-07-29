import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export type StorageListItem = {
  id?: string | null;
  name: string;
};

export type AccountDeletionTarget = {
  profileID: string;
  isProtectedDemo: boolean;
};

export type AccountDeletionServices = {
  authenticatedUserID(token: string): Promise<string | null>;
  deletionTarget(authUserID: string): Promise<AccountDeletionTarget | null>;
  listObjects(
    bucket: string,
    prefix: string,
    limit: number,
    offset: number,
  ): Promise<StorageListItem[]>;
  removeObjects(bucket: string, paths: string[]): Promise<void>;
  deleteCommunityProfile(authUserID: string): Promise<void>;
  deleteAuthUser(authUserID: string): Promise<void>;
};

export async function handler(
  request: Request,
  providedServices?: AccountDeletionServices,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const token = bearerToken(request);
  if (!token) {
    return json({ error: "Authentication required." }, 401);
  }

  let services: AccountDeletionServices;
  try {
    services = providedServices ?? liveServices(token);
  } catch (error) {
    console.error(
      "community-delete-account: configuration unavailable",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "Account deletion is not configured." }, 500);
  }

  const authUserID = await services.authenticatedUserID(token);
  if (!authUserID) {
    return json({ error: "Invalid authentication session." }, 401);
  }

  try {
    const target = await services.deletionTarget(authUserID);
    if (target?.isProtectedDemo) {
      return json(
        {
          error: "Review demo accounts cannot be deleted.",
          code: "DEMO_ACCOUNT_PROTECTED",
        },
        403,
      );
    }
    if (target) {
      await removeProfileMedia(services, target.profileID);
      await services.deleteCommunityProfile(authUserID);
    }
    await services.deleteAuthUser(authUserID);

    console.info(
      "community-delete-account: completed",
      JSON.stringify({
        auth_user_id: authUserID,
        had_profile: target !== null,
      }),
    );
    return json({ deleted: true });
  } catch (error) {
    console.error(
      "community-delete-account: failed",
      JSON.stringify({
        auth_user_id: authUserID,
        error: error instanceof Error ? error.message : "unknown",
      }),
    );
    return json(
      {
        error: "Account deletion failed. Please try again.",
        code: "ACCOUNT_DELETION_FAILED",
      },
      500,
    );
  }
}

if (import.meta.main) {
  Deno.serve((request) => handler(request));
}

export function bearerToken(request: Request): string | null {
  const value = request.headers.get("Authorization") ?? "";
  const [scheme, token] = value.trim().split(/\s+/, 2);
  return scheme?.toLowerCase() === "bearer" && token ? token : null;
}

export function profileStorageRoots(
  profileID: string,
): Array<{ bucket: string; prefix: string }> {
  return [
    { bucket: "community-images", prefix: `avatars/${profileID}` },
    { bucket: "community-images", prefix: `profile-covers/${profileID}` },
    { bucket: "community-images", prefix: `posts/${profileID}` },
    { bucket: "community-attachments", prefix: `posts/${profileID}` },
  ];
}

async function removeProfileMedia(
  services: AccountDeletionServices,
  profileID: string,
): Promise<void> {
  for (const root of profileStorageRoots(profileID)) {
    const paths = await listObjectPathsRecursively(
      services,
      root.bucket,
      root.prefix,
    );
    for (let index = 0; index < paths.length; index += 100) {
      await services.removeObjects(
        root.bucket,
        paths.slice(index, index + 100),
      );
    }
  }
}

async function listObjectPathsRecursively(
  services: AccountDeletionServices,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const pageSize = 100;
  const paths: string[] = [];
  let offset = 0;

  while (true) {
    const items = await services.listObjects(bucket, prefix, pageSize, offset);
    for (const item of items) {
      const path = `${prefix}/${item.name}`;
      if (item.id) {
        paths.push(path);
      } else {
        paths.push(...await listObjectPathsRecursively(services, bucket, path));
      }
    }
    if (items.length < pageSize) break;
    offset += pageSize;
  }

  return paths;
}

function liveServices(token: string): AccountDeletionServices {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceRoleKey) {
    throw new Error("missing_supabase_configuration");
  }

  const userClient = createClient(url, anonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const adminClient = createClient(url, serviceRoleKey, {
    auth: { persistSession: false },
  });

  return {
    async authenticatedUserID(accessToken) {
      const { data, error } = await userClient.auth.getUser(accessToken);
      if (error || !data.user) return null;
      return data.user.id;
    },
    async deletionTarget(authUserID) {
      const { data, error } = await adminClient
        .from("profile_auth_links")
        .select("profile_id, edu_id")
        .eq("auth_user_id", authUserID)
        .maybeSingle();
      if (error) throw error;
      if (!data?.profile_id) return null;
      const eduID = typeof data.edu_id === "string" ? data.edu_id : "";
      return {
        profileID: data.profile_id,
        isProtectedDemo: eduID === "review-demo" ||
          eduID.startsWith("review-demo-"),
      };
    },
    async listObjects(bucket, prefix, limit, offset) {
      const { data, error } = await adminClient.storage.from(bucket).list(
        prefix,
        {
          limit,
          offset,
          sortBy: { column: "name", order: "asc" },
        },
      );
      if (error) throw error;
      return data ?? [];
    },
    async removeObjects(bucket, paths) {
      if (!paths.length) return;
      const { error } = await adminClient.storage.from(bucket).remove(paths);
      if (error) throw error;
    },
    async deleteCommunityProfile(authUserID) {
      const { error } = await adminClient.rpc(
        "edge_delete_community_account",
        { p_auth_user_id: authUserID },
      );
      if (error) throw error;
    },
    async deleteAuthUser(authUserID) {
      const { error } = await adminClient.auth.admin.deleteUser(authUserID);
      if (error) throw error;
    },
  };
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
