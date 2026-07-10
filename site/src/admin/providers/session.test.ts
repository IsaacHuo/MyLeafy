import { beforeEach, describe, expect, it } from "vitest";
import { clearIdentity, readIdentity, saveIdentity } from "./session";

const identity = {
  admin: { id: "a1", username: "admin", display_name: "管理员", role: "super_admin" as const, active: true },
  permissions: [{ resource: "posts", actions: ["list"] }],
  session: { expires_at: "2026-07-10T12:00:00.000Z" },
};

describe("admin browser session storage", () => {
  beforeEach(() => {
    localStorage.clear();
    sessionStorage.clear();
  });

  it("removes the legacy JavaScript-readable token", () => {
    localStorage.setItem("leafy-admin-session", JSON.stringify({ token: "legacy-secret" }));
    saveIdentity({ ...identity, token: "must-not-persist" } as typeof identity);
    expect(localStorage.getItem("leafy-admin-session")).toBeNull();
    expect(sessionStorage.getItem("leafy-admin-identity")).not.toContain("must-not-persist");
    expect(readIdentity()).toEqual(identity);
  });

  it("clears only the identity snapshot and any legacy token", () => {
    saveIdentity(identity);
    localStorage.setItem("leafy-admin-session", "secret");
    clearIdentity();
    expect(sessionStorage.getItem("leafy-admin-identity")).toBeNull();
    expect(localStorage.getItem("leafy-admin-session")).toBeNull();
  });
});
