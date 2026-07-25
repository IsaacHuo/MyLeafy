import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { actionConfirmation, RecordDetailContent } from "./ResourcePages";
import { resourceConfigs } from "./config";

describe("admin action confirmations", () => {
  it("identifies a rating even when the user nickname is blank", () => {
    const action = resourceConfigs.ratings.actions?.[0];
    if (!action) throw new Error("Missing rating delete action");
    const confirmation = actionConfirmation("ratings", {
      id: "teacher:341:user-1",
      teacher_id: 341,
      user_id: "user-1",
      teacher: { name: "测试教师" },
      user: { nickname: "" },
      stars: 4,
      updated_at: "2026-07-13T08:00:00Z",
    }, action);

    expect(confirmation.summary).toContain("评分：测试教师 · 4 星 · 用户：user-1");
    expect(confirmation.summary).not.toContain("undefined");
    expect(confirmation.summary).not.toMatch(/^删除/);
  });

  it("renders signed post images instead of raw JSON", () => {
    render(<RecordDetailContent resource="posts" detail={{
      post: {
        id: "post-1",
        title: "图片帖子",
        body: "正文",
        status: "pending_review",
        upload_state: "publish_failed",
        images: [{
          id: "image-1",
          signed_url: "https://example.com/full.jpg",
          thumbnail_signed_url: "https://example.com/thumb.jpg",
        }],
      },
      comments: [],
    }} />);

    const image = screen.getByRole("img", { name: "帖子图片 1" });
    expect(image).toHaveAttribute("src", "https://example.com/thumb.jpg");
    expect(screen.getByText("自动发布失败")).toBeInTheDocument();
    expect(screen.queryByText(/signed_url/)).not.toBeInTheDocument();
  });

  it("explains that retry publish revalidates image completeness", () => {
    const action = resourceConfigs.posts.actions?.find((candidate) => candidate.action === "retryPostPublish");
    if (!action) throw new Error("Missing retry action");
    const confirmation = actionConfirmation("posts", { id: "post-1", title: "图片帖子" }, action);
    expect(confirmation.impact).toContain("完整上传");
  });
});
