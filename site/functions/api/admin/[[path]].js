const cookieName = "leafy_admin_session";
const csrfHeader = "x-leafy-admin-csrf";

export async function onRequest(context) {
  const requestID = context.request.headers.get("x-request-id") || crypto.randomUUID();
  const route = routeName(new URL(context.request.url).pathname);
  if (!route) return apiError(404, "not_found", "Admin API route not found.", requestID);

  const originError = validateSameOrigin(context.request);
  if (originError) return apiError(403, "forbidden", originError, requestID);

  const expectedMethod = route === "me" ? "GET" : "POST";
  if (context.request.method !== expectedMethod) {
    return apiError(405, "method_not_allowed", "Method not allowed.", requestID);
  }

  const supabaseURL = context.env.SUPABASE_URL;
  const publishableKey = context.env.SUPABASE_PUBLISHABLE_KEY;
  const proxySecret = context.env.ADMIN_PROXY_SECRET;
  if (!supabaseURL || !publishableKey || !proxySecret) {
    return apiError(500, "backend_unavailable", "Admin backend environment is incomplete.", requestID);
  }

  const functionName = route === "actions" ? "admin-community" : route === "export" ? "admin-export" : `admin-${route}`;
  const token = readCookie(context.request.headers.get("cookie"), cookieName);
  if (route !== "login" && !token) return unauthorized(requestID);

  const body = expectedMethod === "POST" ? await context.request.text() : undefined;
  let upstream;
  try {
    upstream = await fetch(`${String(supabaseURL).replace(/\/+$/, "")}/functions/v1/${functionName}`, {
      method: expectedMethod,
      headers: {
        Accept: route === "export" ? "text/csv, application/json" : "application/json",
        "Content-Type": "application/json",
        apikey: publishableKey,
        "x-request-id": requestID,
        "x-leafy-admin-proxy": proxySecret,
        "x-leafy-client-ip": context.request.headers.get("cf-connecting-ip") || "0.0.0.0",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      ...(body !== undefined ? { body: body || "{}" } : {}),
    });
  } catch (error) {
    console.error(JSON.stringify({ event: "admin_bff_upstream_failed", request_id: requestID, error: String(error) }));
    return apiError(502, "backend_unavailable", "Unable to reach the admin backend.", requestID, true);
  }

  if (route === "login") return loginResponse(upstream, requestID);
  if (route === "logout") return logoutResponse(upstream, requestID);
  return proxyResponse(upstream, requestID, upstream.status === 401);
}

function routeName(pathname) {
  const match = pathname.match(/^\/api\/admin\/(login|me|logout|actions|export)\/?$/);
  return match?.[1] || null;
}

function validateSameOrigin(request) {
  const origin = request.headers.get("origin");
  const expectedOrigin = new URL(request.url).origin;
  if (origin && origin !== expectedOrigin) return "Cross-origin admin request rejected.";
  if (!origin) {
    const referer = request.headers.get("referer");
    const refererOrigin = safeOrigin(referer);
    if (refererOrigin !== expectedOrigin && request.headers.get("sec-fetch-site") !== "same-origin") {
      return "Admin request is missing same-origin browser provenance.";
    }
  }
  if (request.headers.get(csrfHeader) !== "1") return "Missing admin CSRF header.";
  return null;
}

function safeOrigin(value) {
  try {
    return value ? new URL(value).origin : null;
  } catch {
    return null;
  }
}

async function loginResponse(upstream, requestID) {
  const payload = await readJSON(upstream);
  if (!upstream.ok || !payload?.token) {
    const response = jsonResponse(payload, upstream.status, requestID);
    if (upstream.status === 401) response.headers.append("Set-Cookie", clearSessionCookie());
    return response;
  }
  const expiresAt = payload.expires_at || payload.session?.expires_at;
  const headers = new Headers({ "Content-Type": "application/json; charset=utf-8" });
  headers.set("Set-Cookie", sessionCookie(payload.token, expiresAt));
  headers.set("X-Request-ID", requestID);
  return new Response(JSON.stringify({
    admin: payload.admin,
    permissions: payload.permissions ?? [],
    session: payload.session ?? { expires_at: expiresAt },
  }), { status: 200, headers });
}

async function logoutResponse(upstream, requestID) {
  const response = await proxyResponse(upstream, requestID, upstream.status === 401);
  if (upstream.ok) response.headers.append("Set-Cookie", clearSessionCookie());
  return response;
}

async function proxyResponse(upstream, requestID, clearSession) {
  const headers = new Headers();
  for (const name of ["content-type", "content-disposition", "x-audit-logged"]) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }
  headers.set("Cache-Control", "no-store");
  headers.set("X-Request-ID", upstream.headers.get("x-request-id") || requestID);
  if (clearSession) headers.append("Set-Cookie", clearSessionCookie());
  return new Response(upstream.body, { status: upstream.status, headers });
}

function sessionCookie(token, expiresAt) {
  const parsed = new Date(expiresAt);
  const expires = Number.isFinite(parsed.getTime()) ? parsed : new Date(Date.now() + 12 * 60 * 60 * 1000);
  const maxAge = Math.max(0, Math.floor((expires.getTime() - Date.now()) / 1000));
  return `${cookieName}=${encodeURIComponent(token)}; HttpOnly; Secure; SameSite=Strict; Path=/api/admin; Max-Age=${maxAge}; Expires=${expires.toUTCString()}`;
}

function clearSessionCookie() {
  return `${cookieName}=; HttpOnly; Secure; SameSite=Strict; Path=/api/admin; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT`;
}

function readCookie(header, name) {
  if (!header) return null;
  for (const part of header.split(";")) {
    const [key, ...value] = part.trim().split("=");
    if (key === name) return decodeURIComponent(value.join("="));
  }
  return null;
}

async function readJSON(response) {
  try {
    return await response.json();
  } catch {
    return { error: `Admin backend returned ${response.status}.` };
  }
}

function unauthorized(requestID) {
  const response = apiError(401, "unauthorized", "Admin session is missing or expired.", requestID);
  response.headers.append("Set-Cookie", clearSessionCookie());
  return response;
}

function apiError(status, code, message, requestID, retryable = false) {
  return jsonResponse({ error: message, errorEnvelope: { code, message, retryable, details: { request_id: requestID } } }, status, requestID);
}

function jsonResponse(payload, status, requestID) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Request-ID": requestID,
    },
  });
}

export const __test = { routeName, validateSameOrigin, sessionCookie, clearSessionCookie, readCookie };
