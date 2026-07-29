import { bearerToken, handler, profileStorageRoots } from "./index.ts";
import type { AccountDeletionServices } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function services(
  overrides: Partial<AccountDeletionServices> = {},
): AccountDeletionServices {
  return {
    authenticatedUserID: async () => "auth-user",
    deletionTarget: async () => ({
      profileID: "profile-user",
      isProtectedDemo: false,
    }),
    listObjects: async () => [],
    removeObjects: async () => {},
    deleteCommunityProfile: async () => {},
    deleteAuthUser: async () => {},
    ...overrides,
  };
}

Deno.test("account deletion rejects missing and malformed bearer tokens", async () => {
  const missing = await handler(
    new Request("https://example.test", { method: "POST" }),
    services(),
  );
  const malformed = await handler(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: "Basic value" },
    }),
    services(),
  );

  assert(missing.status === 401, "missing token must be rejected");
  assert(malformed.status === 401, "malformed token must be rejected");
  assert(
    bearerToken(
      new Request("https://example.test", {
        headers: { Authorization: "Bearer signed-token" },
      }),
    ) === "signed-token",
    "expected bearer token parsing",
  );
});

Deno.test("account deletion rejects an invalid authenticated session", async () => {
  const response = await handler(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: "Bearer forged-token" },
    }),
    services({ authenticatedUserID: async () => null }),
  );

  assert(response.status === 401, "forged token must be rejected");
});

Deno.test("account deletion scopes all work to the authenticated user", async () => {
  const calls: string[] = [];
  const response = await handler(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: "Bearer valid-token" },
    }),
    services({
      authenticatedUserID: async () => "authenticated-user",
      deletionTarget: async (id) => {
        calls.push(`profile:${id}`);
        return { profileID: "profile-user", isProtectedDemo: false };
      },
      deleteCommunityProfile: async (id) => {
        calls.push(`profile-delete:${id}`);
      },
      deleteAuthUser: async (id) => {
        calls.push(`auth-delete:${id}`);
      },
    }),
  );

  assert(response.status === 200, "expected successful deletion");
  assert(
    calls.join(",") ===
      "profile:authenticated-user,profile-delete:authenticated-user,auth-delete:authenticated-user",
    "all deletion calls must use the authenticated user id",
  );
});

Deno.test("account deletion leaves database and auth intact when media cleanup fails", async () => {
  let profileDeleted = false;
  let authDeleted = false;
  const response = await handler(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: "Bearer valid-token" },
    }),
    services({
      listObjects: async () => [{ id: "object", name: "avatar.jpg" }],
      removeObjects: async () => {
        throw new Error("storage unavailable");
      },
      deleteCommunityProfile: async () => {
        profileDeleted = true;
      },
      deleteAuthUser: async () => {
        authDeleted = true;
      },
    }),
  );

  assert(response.status === 500, "storage failure must be visible");
  assert(!profileDeleted, "profile must remain retryable");
  assert(!authDeleted, "auth user must remain retryable");
});

Deno.test("account deletion protects demo profiles before media cleanup", async () => {
  let mediaListed = false;
  let profileDeleted = false;
  let authDeleted = false;
  const response = await handler(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: "Bearer valid-token" },
    }),
    services({
      deletionTarget: async () => ({
        profileID: "demo-profile",
        isProtectedDemo: true,
      }),
      listObjects: async () => {
        mediaListed = true;
        return [];
      },
      deleteCommunityProfile: async () => {
        profileDeleted = true;
      },
      deleteAuthUser: async () => {
        authDeleted = true;
      },
    }),
  );

  assert(response.status === 403, "demo deletion must be rejected");
  assert(!mediaListed, "demo media must remain untouched");
  assert(!profileDeleted, "demo profile must remain intact");
  assert(!authDeleted, "demo auth session must remain intact");
});

Deno.test("account deletion succeeds for an authenticated user without a profile", async () => {
  let authDeleted = false;
  const response = await handler(
    new Request("https://example.test", {
      method: "POST",
      headers: { Authorization: "Bearer valid-token" },
    }),
    services({
      deletionTarget: async () => null,
      deleteCommunityProfile: async () => {
        throw new Error("profile deletion should not run");
      },
      deleteAuthUser: async () => {
        authDeleted = true;
      },
    }),
  );

  assert(response.status === 200, "missing profile is an idempotent success");
  assert(authDeleted, "auth user must still be removed");
});

Deno.test("account deletion covers every profile-owned storage namespace", () => {
  const roots = profileStorageRoots("profile-user")
    .map(({ bucket, prefix }) => `${bucket}:${prefix}`)
    .sort();

  assert(
    roots.includes("community-images:avatars/profile-user"),
    "avatar namespace missing",
  );
  assert(
    roots.includes("community-images:profile-covers/profile-user"),
    "cover namespace missing",
  );
  assert(
    roots.includes("community-images:posts/profile-user"),
    "post image namespace missing",
  );
  assert(
    roots.includes("community-attachments:posts/profile-user"),
    "post attachment namespace missing",
  );
});
