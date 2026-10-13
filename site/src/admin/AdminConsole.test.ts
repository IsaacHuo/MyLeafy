import { describe, expect, it } from "vitest";
import { resourceConfigs } from "./resources/config";
import { listLink } from "./dashboard/Dashboard";
describe("admin console routes", () => {
  it("keeps Chinese resource labels and links precise scoped filters", () => {
    expect(resourceConfigs.posts.label).toBe("帖子");
    const query = new URLSearchParams(
      listLink("feedback", { pending: true }).split("?")[1],
    );
    expect(JSON.parse(query.get("filter")!)).toEqual({
      status: "all",
      pending: true,
    });
  });
});
