import { afterEach, describe, expect, it, vi } from "vitest";
import { __test, onRequest } from "./[[path]].js";

afterEach(() => vi.unstubAllGlobals());

const env = {
  SUPABASE_URL: "https://project.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "publishable",
  ADMIN_PROXY_SECRET: "proxy-secret",
};

describe("admin BFF security helpers", () => {
  it('forwards bounded multipart banner uploads only with same-origin provenance and a session', async () => {
    const fetch = vi.fn(async request => {
      expect(request.method).toBe('PUT');
      expect(new URL(request.url).searchParams.get('ticket')).toBe('signed-ticket');
      expect(request.headers.get('authorization')).toBe('Bearer session');
      expect(await request.text()).toContain('name="cacheControl"\r\n\r\n3600');
      return new Response('{}', {headers:{'content-type':'application/json'}});
    });
    const make = origin => {
      const body='--leafy\r\nContent-Disposition: form-data; name="cacheControl"\r\n\r\n3600\r\n--leafy--\r\n';
      return new Request('https://myleafy.space/api/admin/banner-upload?ticket=signed-ticket',{method:'PUT',headers:{Origin:origin,Cookie:'leafy_admin_session=session','Content-Type':'multipart/form-data; boundary=leafy'},body});
    };
    const backend={MYLEAFY_BACKEND_PROVIDER:'cloudflare',MYLEAFY_ADMIN_API:{fetch}};
    expect((await onRequest({request:make('https://myleafy.space'),env:backend})).status).toBe(200);
    expect((await onRequest({request:make('https://evil.example'),env:backend})).status).toBe(403);
    expect(fetch).toHaveBeenCalledOnce();
  });
  it("only routes the five explicit endpoints", () => {
    expect(__test.routeName("/api/admin/actions")).toBe("actions");
    expect(__test.routeName("/api/admin/raw-sql")).toBeNull();
  });

  it("requires same origin and the CSRF header", () => {
    const valid = new Request("https://myleafy.space/api/admin/actions", { headers: { Origin: "https://myleafy.space", "X-Leafy-Admin-CSRF": "1" } });
    const invalid = new Request("https://myleafy.space/api/admin/actions", { headers: { Origin: "https://evil.example", "X-Leafy-Admin-CSRF": "1" } });
    expect(__test.validateSameOrigin(valid)).toBeNull();
    expect(__test.validateSameOrigin(invalid)).toMatch(/Cross-origin/);
  });

  it("accepts a same-origin GET provenance when browsers omit Origin", () => {
    const request = new Request("https://myleafy.space/api/admin/me", { headers: { Referer: "https://myleafy.space/admin", "X-Leafy-Admin-CSRF": "1" } });
    expect(__test.validateSameOrigin(request)).toBeNull();
  });

  it("creates an HttpOnly strict cookie scoped to the admin API", () => {
    const cookie = __test.sessionCookie("secret-token", new Date(Date.now() + 60_000).toISOString());
    expect(cookie).toContain("leafy_admin_session=secret-token");
    expect(cookie).toContain("HttpOnly");
    expect(cookie).toContain("Secure");
    expect(cookie).toContain("SameSite=Strict");
    expect(cookie).toContain("Path=/api/admin");
  });

  it("reads and clears only the named session cookie", () => {
    expect(__test.readCookie("a=1; leafy_admin_session=abc%20123", "leafy_admin_session")).toBe("abc 123");
    expect(__test.clearSessionCookie()).toContain("Max-Age=0");
  });

  it("requires JSON and rejects declared oversized bodies", () => {
    expect(__test.validateJSONRequest(new Request("https://myleafy.space/api/admin/actions", {
      method: "POST", headers: { "Content-Type": "text/plain" }, body: "{}",
    }))?.code).toBe("bad_request");
    expect(__test.validateJSONRequest(new Request("https://myleafy.space/api/admin/actions", {
      method: "POST", headers: { "Content-Type": "application/json", "Content-Length": String(300_000) }, body: "{}",
    }))?.code).toBe("payload_too_large");
  });

  it("moves the login token into the HttpOnly cookie and strips it from JSON", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({
      token: "upstream-secret",
      admin: { id: "a1", role: "operator" },
      permissions: [],
      session: { expires_at: new Date(Date.now() + 60_000).toISOString() },
    }), { status: 200, headers: { "Content-Type": "application/json" } })));
    const response = await onRequest({ request: apiRequest("login", "POST"), env });
    expect(response.headers.get("set-cookie")).toContain("HttpOnly");
    expect(await response.text()).not.toContain("upstream-secret");
  });

  it("clears the cookie on 401 but not on 403", async () => {
    for (const status of [401, 403]) {
      vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ error: "denied" }), { status, headers: { "Content-Type": "application/json" } })));
      const response = await onRequest({ request: apiRequest("actions", "POST", "leafy_admin_session=token"), env });
      expect(Boolean(response.headers.get("set-cookie"))).toBe(status === 401);
    }
  });

  it("uses the private Worker entrypoint without Supabase credentials and strips the token", async () => {
    const publicFetch = vi.fn();
    vi.stubGlobal("fetch", publicFetch);
    const boundFetch = vi.fn(async (request) => {
      expect(new URL(request.url).pathname).toBe("/admin/login");
      expect(request.headers.has("apikey")).toBe(false);
      expect(request.headers.has("x-leafy-admin-proxy")).toBe(false);
      return new Response(JSON.stringify({ token: "private-worker-session", admin: { id: "test", role: "viewer" }, expires_at: new Date(Date.now() + 60000).toISOString() }), { headers: { "Content-Type": "application/json" } });
    });
    const response = await onRequest({ request: apiRequest("login", "POST"), env: { MYLEAFY_BACKEND_PROVIDER: "cloudflare", MYLEAFY_ADMIN_API: { fetch: boundFetch } } });
    expect(response.status).toBe(200);
    expect(response.headers.get("set-cookie")).toContain("HttpOnly");
    expect(await response.text()).not.toContain("private-worker-session");
    expect(boundFetch).toHaveBeenCalledOnce();
    expect(publicFetch).not.toHaveBeenCalled();
  });

  it("fails a missing Cloudflare binding without silently using the legacy backend", async () => {
    const publicFetch = vi.fn();
    vi.stubGlobal("fetch", publicFetch);
    const response = await onRequest({ request: apiRequest("login", "POST"), env: { ...env, MYLEAFY_BACKEND_PROVIDER: "cloudflare" } });
    expect(response.status).toBe(500);
    expect(publicFetch).not.toHaveBeenCalled();
  });
});

function apiRequest(route, method, cookie) {
  return new Request(`https://myleafy.space/api/admin/${route}`, {
    method,
    headers: {
      Origin: "https://myleafy.space",
      "X-Leafy-Admin-CSRF": "1",
      ...(method === "POST" ? { "Content-Type": "application/json" } : {}),
      ...(cookie ? { Cookie: cookie } : {}),
    },
    ...(method === "POST" ? { body: "{}" } : {}),
  });
}
