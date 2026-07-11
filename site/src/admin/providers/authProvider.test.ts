import { beforeEach, describe, expect, it } from "vitest";
import { authProvider } from "./authProvider";
import { AdminApiError } from "./client";
import { readIdentity, saveIdentity } from "./session";

const identity = {
  admin: { id: "a1", username: "admin", display_name: "管理员", role: "operator" as const, active: true },
  permissions: [{ resource: "posts", actions: ["list", "edit"] }],
  session: { expires_at: "2026-07-10T12:00:00.000Z" },
};

describe("admin auth error handling", () => {
  beforeEach(() => {
    localStorage.clear();
    sessionStorage.clear();
    saveIdentity(identity);
  });

  it("clears the identity only for a real 401", async () => {
    await expect(authProvider.checkError?.(new AdminApiError(401, "unauthorized", "expired"))).rejects.toThrow("expired");
    expect(readIdentity()).toBeNull();
  });

  it("keeps the identity for 403 and backend failures", async () => {
    await expect(authProvider.checkError?.(new AdminApiError(403, "forbidden", "denied"))).resolves.toBeUndefined();
    await expect(authProvider.checkError?.(new AdminApiError(502, "backend_unavailable", "down"))).resolves.toBeUndefined();
    expect(readIdentity()).toEqual(identity);
  });
});
