import { beforeEach, describe, expect, it, vi } from "vitest";
import { actionRequest } from "./client";
import { dataProvider } from "./dataProvider";
import { saveCampusScope } from "./session";

vi.mock("./client", () => ({
  actionRequest: vi.fn(),
  exportRequest: vi.fn(),
}));

const mockedAction = vi.mocked(actionRequest);

describe("admin data provider campus scope", () => {
  beforeEach(() => {
    localStorage.clear();
    mockedAction.mockReset();
  });

  it("injects campus scope into campus-owned resources", async () => {
    saveCampusScope("campus-a");
    mockedAction.mockResolvedValue({ data: { items: [{ id: "p1" }], total: 1, page: 0, pageSize: 20 }, meta: {} });
    await dataProvider.getList("posts", { pagination: { page: 1, perPage: 20 }, sort: { field: "created_at", order: "DESC" }, filter: {} });
    expect(mockedAction).toHaveBeenCalledWith("listPosts", expect.objectContaining({ campusID: "campus-a" }));
  });

  it("does not inject campus scope into global resources", async () => {
    saveCampusScope("campus-a");
    mockedAction.mockResolvedValue({ data: { items: [], total: 0, page: 0, pageSize: 20 }, meta: {} });
    await dataProvider.getList("postgraduate", { pagination: { page: 1, perPage: 20 }, sort: { field: "created_at", order: "DESC" }, filter: {} });
    expect(mockedAction).toHaveBeenCalledWith("listPostgraduateSources", expect.not.objectContaining({ campusID: expect.anything() }));
  });

  it("scopes global search to the selected campus", async () => {
    saveCampusScope("campus-a");
    mockedAction.mockResolvedValue({ data: [], meta: {} });
    await dataProvider.globalSearch("测试");
    expect(mockedAction).toHaveBeenCalledWith("globalSearch", { query: "测试", resources: undefined, campusID: "campus-a" });
  });

  it("preserves numeric rating identifiers when deleting", async () => {
    mockedAction.mockResolvedValue({ data: { id: "teacher:341:user-1", teacher_id: 341, user_id: "user-1" }, meta: {} });
    await dataProvider.delete("ratings", {
      id: "teacher:341:user-1",
      previousData: { id: "teacher:341:user-1", target: "teacher", teacher_id: 341, user_id: "user-1" },
    });
    expect(mockedAction).toHaveBeenCalledWith("deleteTeacherRating", { teacherID: 341, userID: "user-1" });
  });

  it("passes date-only filter boundaries without converting them in the browser", async () => {
    mockedAction.mockResolvedValue({ data: { items: [], total: 0, page: 0, pageSize: 20 }, meta: {} });
    await dataProvider.getList("feedback", {
      pagination: { page: 1, perPage: 20 },
      sort: { field: "created_at", order: "DESC" },
      filter: { start: "2026-07-01", end: "2026-07-13" },
    });
    expect(mockedAction).toHaveBeenCalledWith("listFeedback", expect.objectContaining({ start: "2026-07-01", end: "2026-07-13" }));
  });

  it("loads moderation report evidence through the dedicated detail action", async () => {
    saveCampusScope("campus-a");
    mockedAction.mockResolvedValue({ data: { report: { id: "report-1" }, evidence: {} }, meta: {} });
    await dataProvider.getOne("reports", { id: "report-1" });
    expect(mockedAction).toHaveBeenCalledWith("getModerationReport", { id: "report-1", campusID: "campus-a" });
  });

  it("requires an explicit campus before creating catalog records", async () => {
    saveCampusScope("all");
    await expect(dataProvider.create("teachers", { data: { name: "测试", unit: "学院" } }))
      .rejects.toThrow("新增前必须先选择具体学校");
    expect(mockedAction).not.toHaveBeenCalled();

    saveCampusScope("campus-a");
    mockedAction.mockResolvedValue({ data: { id: 1, name: "测试", unit: "学院" }, meta: {} });
    await dataProvider.create("teachers", { data: { name: "测试", unit: "学院" } });
    expect(mockedAction).toHaveBeenCalledWith("upsertTeacher", expect.objectContaining({ campusID: "campus-a" }));
  });

  it("uploads banner images directly and submits only the private object path", async () => {
    saveCampusScope("campus-a");
    const file = new File(["banner"], "banner.png", { type: "image/png" });
    mockedAction
      .mockResolvedValueOnce({
        data: {
          path: "campus-a/pending/admin-1/upload.png",
          signed_url: "https://storage.example/upload?token=signed",
          max_bytes: 2 * 1024 * 1024,
        },
        meta: {},
      })
      .mockResolvedValueOnce({ data: { id: "banner-1", status: "published" }, meta: {} });
    const upload = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", upload);

    await dataProvider.create("community-banners", {
      data: {
        title: "测试",
        subtitle: "测试 Banner",
        imageDataURL: { rawFile: file },
      },
    });

    expect(mockedAction).toHaveBeenNthCalledWith(1, "prepareCommunityBannerImageUpload", {
      campusID: "campus-a",
      mimeType: "image/png",
      byteSize: file.size,
    });
    expect(upload).toHaveBeenCalledWith(
      "https://storage.example/upload?token=signed",
      expect.objectContaining({ method: "PUT", body: expect.any(FormData) }),
    );
    expect(mockedAction).toHaveBeenNthCalledWith(2, "createCommunityBanner", expect.objectContaining({
      campusID: "campus-a",
      imageUploadPath: "campus-a/pending/admin-1/upload.png",
      imageDataURL: undefined,
    }));
    vi.unstubAllGlobals();
  });
});
