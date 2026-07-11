import { afterEach, describe, expect, it, vi } from "vitest";
import { actionRequest, AdminApiError, meRequest } from "./client";

afterEach(() => vi.unstubAllGlobals());

describe("admin BFF client errors and audit warnings", () => {
  it("emits a visible audit warning event when the business action succeeded without audit", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ data: { ok: true }, meta: { request_id: "req-1", audit_logged: false, duration_ms: 4 } }), { status: 200, headers: { "Content-Type": "application/json" } })));
    const warning = new Promise<CustomEvent>((resolve) => window.addEventListener("leafy-admin-audit-warning", (event) => resolve(event as CustomEvent), { once: true }));
    await actionRequest("testAction");
    await expect(warning).resolves.toMatchObject({ detail: { action: "testAction", requestID: "req-1" } });
  });

  it("keeps structured 403 errors and includes the request ID", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ error: "无权操作", errorEnvelope: { code: "forbidden", message: "无权操作", retryable: false } }), { status: 403, headers: { "Content-Type": "application/json", "X-Request-ID": "req-403" } })));
    await expect(meRequest()).rejects.toMatchObject({ status: 403, code: "forbidden", message: expect.stringContaining("req-403") });
  });

  it("maps fetch failures to a retryable network error", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("offline"); }));
    await expect(meRequest()).rejects.toEqual(expect.objectContaining<Partial<AdminApiError>>({ status: 0, code: "network_error", retryable: true }));
  });
});
