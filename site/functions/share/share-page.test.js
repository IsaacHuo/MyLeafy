import { describe, expect, it } from "vitest";
import { onRequestGet } from "./[[path]].js";

async function request(pathname) {
  return onRequestGet({ request: new Request(`https://myleafy.space${pathname}`), env: {} });
}

describe("share page function", () => {
  it("renders a valid timetable invite in the shared dark shell", async () => {
    const response = await request("/share/timetable/ABCDEFGHJKL2");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("leafy://timetable-invite?code=ABCDEFGHJKL2");
    expect(html).toContain("box-sizing: border-box");
    expect(html).toContain("background: #091611");
  });

  it("returns a recoverable 404 for an invalid invite", async () => {
    const response = await request("/share/timetable/ABCDE2");
    const html = await response.text();

    expect(response.status).toBe(404);
    expect(html).toContain("This timetable link is incomplete.");
    expect(html).not.toContain("leafy://timetable");
    expect(html).toContain("https://myleafy.space/support");
  });

  it("accepts only a structurally valid community post UUID", async () => {
    const valid = await request("/share/community/post/123e4567-e89b-12d3-a456-426614174000");
    const invalid = await request("/share/community/post/------------------------------------");
    const invalidHTML = await invalid.text();

    expect(valid.status).toBe(200);
    expect(invalid.status).toBe(404);
    expect(invalidHTML).not.toContain("leafy://community-post");
  });
});
