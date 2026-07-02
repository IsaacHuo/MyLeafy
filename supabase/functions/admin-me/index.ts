import {
  authenticateAdmin,
  errorResponse,
  json,
  mapFunctionError,
  okOptions,
} from "../_shared/admin-core.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return okOptions();
  }

  if (request.method !== "GET" && request.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Method not allowed.", { retryable: false });
  }

  try {
    const context = await authenticateAdmin(request);
    if (context instanceof Response) {
      return context;
    }

    return json({ admin: context.admin });
  } catch (error) {
    return mapFunctionError(error);
  }
});
