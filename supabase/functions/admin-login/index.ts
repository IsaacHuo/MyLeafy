import {
  appendAuditLog,
  createAdminClient,
  errorResponse,
  json,
  mapFunctionError,
  normalizeText,
  okOptions,
  readJSON,
} from "../_shared/admin-core.ts";

type LoginRequest = {
  username?: string | null;
  password?: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return okOptions();
  }

  if (request.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Method not allowed.", { retryable: false });
  }

  try {
    const body = await readJSON<LoginRequest>(request);
    const username = normalizeText(body.username);
    const password = typeof body.password === "string" ? body.password : "";

    if (!username || !password) {
      return errorResponse(400, "bad_request", "账号和密码不能为空。");
    }

    const adminClient = createAdminClient();
    const { data, error } = await adminClient.rpc("admin_login", {
      p_username: username,
      p_password: password,
      p_expires_in_hours: 12,
    });

    if (error) {
      const message = error.message.includes("ADMIN_INVALID_CREDENTIALS")
        ? "账号或密码错误。"
        : error.message;
      return errorResponse(
        error.message.includes("ADMIN_INVALID_CREDENTIALS") ? 401 : 500,
        error.message.includes("ADMIN_INVALID_CREDENTIALS") ? "unauthorized" : "backend_unavailable",
        message,
      );
    }

    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.token) {
      return errorResponse(401, "unauthorized", "账号或密码错误。");
    }

    const requestInfo = {
      ipAddress: request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || null,
      userAgent: request.headers.get("user-agent"),
    };

    await appendAuditLog({
      adminClient,
      admin: {
        id: row.admin_id,
        username: row.username,
        display_name: row.display_name,
        role: row.role,
        active: true,
      },
      tokenHash: "",
      requestInfo,
    }, "login", { username });

    return json({
      token: row.token,
      expires_at: row.expires_at,
      admin: {
        id: row.admin_id,
        username: row.username,
        display_name: row.display_name,
        role: row.role,
      },
    });
  } catch (error) {
    return mapFunctionError(error);
  }
});
