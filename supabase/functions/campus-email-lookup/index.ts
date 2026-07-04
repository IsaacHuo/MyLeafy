import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type LookupRequest = {
  email?: string | null;
  campus_id?: string | null;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Method not allowed.", false);
  }

  try {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader) {
      return errorResponse(401, "unauthorized", "Missing Authorization header.");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return errorResponse(500, "backend_unavailable", "Missing Supabase environment variables.");
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return errorResponse(401, "unauthorized", userError?.message ?? "Supabase session missing or invalid.");
    }

    const body = await readBody(request);
    const email = normalizeEmail(body.email);
    if (!email || !isValidEmail(email)) {
      return errorResponse(400, "bad_request", "请输入有效的邮箱地址。", false);
    }

    const campusID = normalizeCampusID(body.campus_id);
    if (campusID !== "bjfu") {
      return errorResponse(400, "bad_request", "邮箱别名登录目前仅支持北京林业大学入口。", false);
    }

    const { data: eduID, error: lookupError } = await adminClient.rpc("lookup_verified_edu_id_by_email", {
      p_email: email,
      p_campus_id: campusID,
    });

    if (lookupError) {
      return errorResponse(500, "backend_unavailable", lookupError.message);
    }

    const normalizedEduID = normalizeText(eduID);
    if (!normalizedEduID) {
      return errorResponse(
        404,
        "not_found",
        "没有找到这个邮箱对应的北林学号；请先用学号登录并绑定邮箱。",
        false,
      );
    }

    return json({ edu_id: normalizedEduID });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return errorResponse(500, "internal_error", message);
  }
});

async function readBody(request: Request): Promise<LookupRequest> {
  try {
    return (await request.json()) as LookupRequest;
  } catch {
    return {};
  }
}

function normalizeText(value: unknown): string | null {
  const trimmed = typeof value === "string" ? value.trim() : "";
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeEmail(value: string | null | undefined): string | null {
  return normalizeText(value)?.toLowerCase() ?? null;
}

function normalizeCampusID(value: string | null | undefined): string {
  return normalizeText(value)?.toLowerCase() ?? "bjfu";
}

function isValidEmail(email: string): boolean {
  return /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i.test(email);
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}

function errorResponse(status: number, code: string, message: string, retryable = status >= 500) {
  return json({
    error: message,
    errorEnvelope: {
      code,
      message,
      retryable,
    },
  }, status);
}
