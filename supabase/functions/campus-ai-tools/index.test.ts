import { handler } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("campus-ai-tools rejects non-POST requests", async () => {
  const response = await handler(
    new Request("https://example.test", { method: "GET" }),
  );
  assert(response.status === 405, "expected method rejection");
  const payload = await response.json();
  assert(payload.ok === false, "expected structured error envelope");
  assert(
    payload.error.code === "method_not_allowed",
    "expected stable error code",
  );
});

Deno.test("campus-ai-tools fails fast when signing or Supabase secrets are absent", async () => {
  const keys = [
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "CAMPUS_AI_TOOL_SIGNING_SECRET",
  ];
  const previous = new Map(keys.map((key) => [key, Deno.env.get(key)]));
  try {
    for (const key of keys) Deno.env.delete(key);
    const response = await handler(
      new Request("https://example.test", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          request_id: "d31f9240-4a1a-4f48-9d94-fdd4e9fbdb1b",
          tool: "web.search",
          arguments: { query: "test" },
        }),
      }),
    );
    assert(response.status === 500, "expected fail-fast configuration error");
    const payload = await response.json();
    assert(
      payload.error.code === "service_not_configured",
      "expected stable error code",
    );
  } finally {
    for (const [key, value] of previous) {
      if (value == null) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
});
