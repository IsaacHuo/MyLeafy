type AdminRecord = Record<string, any> & { id: string | number };
type GetListParams = {
  pagination?: { page: number; perPage: number };
  sort?: { field: string; order: string };
  filter?: Record<string, unknown>;
  signal?: AbortSignal;
};
type GetOneParams = { id: string | number };
type CreateParams = { data: Record<string, any> };
type UpdateParams = CreateParams &
  GetOneParams & { previousData?: Record<string, any> };
type DeleteParams = GetOneParams & { previousData?: Record<string, any> };
type UpdateManyParams = CreateParams & { ids: (string | number)[] };
type DeleteManyParams = { ids: (string | number)[] };
import type { ExportRequest, GlobalSearchResult } from "../contracts";
import { actionRequest, exportRequest } from "./client";
import { readCampusScope } from "./session";

type ListResult = {
  items: AdminRecord[];
  total: number;
  page: number;
  pageSize: number;
};

const listActions: Record<string, string> = {
  "android-releases": "listAndroidReleases",
  campuses: "listCampuses",
  "campus-requests": "listCampusRequests",
  posts: "listPosts",
  polls: "listPolls",
  comments: "listComments",
  reports: "listModerationReports",
  profiles: "listProfiles",
  feedback: "listFeedback",
  announcements: "listAnnouncements",
  "community-banners": "listCommunityBanners",
  postgraduate: "listPostgraduateSources",
  "postgraduate-suggestions": "listPostgraduateSuggestions",
  suggestions: "listCatalogSuggestions",
  teachers: "listTeachers",
  courses: "listCourses",
  dishes: "listDishes",
  ratings: "listTeacherRatings",
  "semester-configs": "listSemesterRuntimeConfigs",
  "national-calendar": "listNationalCalendarRuntimeConfigs",
  admins: "listAdmins",
  sessions: "listAdminSessions",
  "audit-logs": "listAuditLogs",
};

const getOneActions: Record<string, string> = {
  posts: "getPost",
  polls: "getPoll",
  reports: "getModerationReport",
  profiles: "getProfile",
};

const unscopedActions = new Set([
  "listAndroidReleases",
  "requestAndroidPublication",
  "revokeAndroidRelease",
  "listCampuses",
  "listCampusRequests",
  "approveCampusRequest",
  "rejectCampusRequest",
  "listPostgraduateSources",
  "listPostgraduateSuggestions",
  "upsertPostgraduateSource",
  "setPostgraduateSourceStatus",
  "approvePostgraduateSuggestion",
  "rejectPostgraduateSuggestion",
  "listNationalCalendarRuntimeConfigs",
  "upsertNationalCalendarRuntimeConfig",
  "listAdmins",
  "createAdmin",
  "updateAdmin",
  "disableAdmin",
  "listAdminSessions",
  "revokeAdminSession",
  "listAuditLogs",
]);

const providerImplementation = {
  getList: async (resource: string, params: GetListParams) => {
    let action = requireMapping(listActions, resource);
    const filter = { ...(params.filter ?? {}) } as Record<string, unknown>;
    if (resource === "ratings" && filter.id) {
      const parsed = /^(teacher|dish|course):(\d+):(.+)$/.exec(
        String(filter.id),
      );
      if (!parsed) throw new Error("评分 ID 无效。");
      filter.target = parsed[1];
      filter[`${parsed[1]}ID`] = Number(parsed[2]);
      filter.userID = parsed[3];
      delete filter.id;
    }
    if (resource === "ratings")
      action =
        filter.target === "dish"
          ? "listDishRatings"
          : filter.target === "course"
            ? "listCourseRatings"
            : "listTeacherRatings";
    const response = await actionRequest<ListResult>(
      action,
      withCampus(action, {
        ...filter,
        page: Math.max(0, (params.pagination?.page ?? 1) - 1),
        pageSize: params.pagination?.perPage ?? 20,
        sortField: params.sort?.field,
        sortOrder: params.sort?.order,
        timezone: filter.timezone ?? "Asia/Shanghai",
      }),
      params.signal,
    );
    return { data: response.data.items, total: response.data.total };
  },
  getOne: async (resource: string, params: GetOneParams) => {
    const action = requireMapping(getOneActions, resource);
    const response = await actionRequest<Record<string, unknown>>(
      action,
      withCampus(action, { id: params.id }),
    );
    return { data: response.data };
  },
  create: async (resource: string, params: CreateParams) => {
    if (
      campusScopedCreateResources.has(resource) &&
      readCampusScope() === "all"
    ) {
      throw new Error("新增前必须先选择具体学校。");
    }
    const action = createAction(resource);
    const data =
      resource === "community-banners"
        ? await uploadBannerImage(params.data)
        : params.data;
    const response = await actionRequest<AdminRecord>(
      action,
      withCampus(action, data),
    );
    return { data: ensureID(response.data) };
  },
  update: async (resource: string, params: UpdateParams) => {
    const action = updateAction(resource);
    const data =
      resource === "community-banners"
        ? await uploadBannerImage(params.data)
        : params.data;
    const response = await actionRequest<AdminRecord>(
      action,
      withCampus(action, { id: params.id, ...data }),
    );
    return { data: ensureID(response.data, params.id) };
  },
  updateMany: async (resource: string, params: UpdateManyParams) => {
    const action =
      resource === "posts"
        ? "bulkModeratePosts"
        : resource === "comments"
          ? "bulkModerateComments"
          : null;
    if (!action)
      throw new Error(`Resource ${resource} does not support bulk update.`);
    await actionRequest(
      action,
      withCampus(action, { ids: params.ids, ...params.data }),
    );
    return { data: params.ids };
  },
  delete: async (resource: string, params: DeleteParams) => {
    const action = deleteAction(
      resource,
      params.previousData as Record<string, unknown> | undefined,
    );
    const payload =
      resource === "ratings"
        ? ratingDeletePayload(params.previousData as Record<string, unknown>)
        : { id: params.id };
    const response = await actionRequest<AdminRecord>(
      action,
      withCampus(action, payload),
    );
    return { data: ensureID(response.data, params.id) };
  },
  deleteMany: async (resource: string, params: DeleteManyParams) => {
    if (resource === "posts" || resource === "comments") {
      return dataProvider.updateMany(resource, {
        ids: params.ids,
        data: { status: "hidden", reason: "批量下架" },
      });
    }
    throw new Error(`Resource ${resource} does not support bulk delete.`);
  },
  execute: async <T>(
    action: string,
    params: Record<string, unknown> = {},
    signal?: AbortSignal,
  ) => {
    const response = await actionRequest<T>(
      action,
      withCampus(action, params),
      signal,
    );
    return response.data;
  },
  globalSearch: async (query: string, resources?: string[]) => {
    const response = await actionRequest<GlobalSearchResult[]>(
      "globalSearch",
      withCampus("globalSearch", { query, resources }),
    );
    return response.data;
  },
  download: async (request: ExportRequest) => {
    const campusID = readCampusScope();
    const { blob, filename } = await exportRequest({
      ...request,
      filters: {
        ...(request.filters ?? {}),
        ...(campusID !== "all" ? { campusID } : {}),
      },
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    URL.revokeObjectURL(url);
  },
};

const campusScopedCreateResources = new Set([
  "teachers",
  "courses",
  "dishes",
  "community-banners",
]);

export const dataProvider = providerImplementation;
export type AdminDataProvider = typeof dataProvider;

function withCampus(action: string, params: Record<string, unknown>) {
  const campusID = readCampusScope();
  return campusID === "all" || unscopedActions.has(action)
    ? params
    : { ...params, campusID: params.campusID ?? campusID };
}

function requireMapping(mapping: Record<string, string>, resource: string) {
  const action = mapping[resource];
  if (!action) throw new Error(`Unsupported admin resource: ${resource}`);
  return action;
}

function createAction(resource: string) {
  return requireMapping(
    {
      announcements: "createAnnouncement",
      "community-banners": "createCommunityBanner",
      postgraduate: "upsertPostgraduateSource",
      teachers: "upsertTeacher",
      courses: "upsertCourse",
      dishes: "upsertDish",
      admins: "createAdmin",
      "semester-configs": "upsertSemesterRuntimeConfig",
      "national-calendar": "upsertNationalCalendarRuntimeConfig",
    },
    resource,
  );
}

function updateAction(resource: string) {
  return requireMapping(
    {
      announcements: "updateAnnouncement",
      "community-banners": "updateCommunityBanner",
      postgraduate: "upsertPostgraduateSource",
      teachers: "upsertTeacher",
      courses: "upsertCourse",
      dishes: "upsertDish",
      admins: "updateAdmin",
      feedback: "updateFeedback",
      "semester-configs": "upsertSemesterRuntimeConfig",
      "national-calendar": "upsertNationalCalendarRuntimeConfig",
    },
    resource,
  );
}

type BannerImageUploadTarget = {
  path: string;
  signed_url: string;
  max_bytes: number;
};

async function uploadBannerImage(data: Record<string, unknown>) {
  const value = data.imageDataURL as
    | { rawFile?: File }
    | Array<{ rawFile?: File }>
    | string
    | undefined;
  if (!value || typeof value === "string") return data;
  const candidate = Array.isArray(value) ? value[0] : value;
  if (!candidate?.rawFile) return { ...data, imageDataURL: undefined };

  const file = candidate.rawFile;
  if (file.type !== "image/jpeg" && file.type !== "image/png") {
    throw new Error("Banner 图片只支持 JPEG 或 PNG。");
  }
  if (file.size <= 0 || file.size > 2 * 1024 * 1024) {
    throw new Error("Banner 图片不得超过 2 MB。");
  }

  const campusID = readCampusScope();
  const prepared = await actionRequest<BannerImageUploadTarget>(
    "prepareCommunityBannerImageUpload",
    {
      campusID,
      mimeType: file.type,
      byteSize: file.size,
    },
  );
  const form = new FormData();
  form.append("cacheControl", "31536000");
  form.append("", file);
  let uploadResponse: Response;
  try {
    uploadResponse = await fetch(prepared.data.signed_url, {
      method: "PUT",
      headers: { "x-upsert": "false" },
      body: form,
    });
  } catch {
    throw new Error("无法连接图片存储，请检查网络后重试。");
  }
  if (!uploadResponse.ok) {
    const payload = await uploadResponse.json().catch(() => ({}));
    throw new Error(
      payload?.message ?? payload?.error ?? "Banner 图片上传失败，请重试。",
    );
  }

  return {
    ...data,
    imageDataURL: undefined,
    imageUploadPath: prepared.data.path,
  };
}

function deleteAction(resource: string, record?: Record<string, unknown>) {
  if (resource === "sessions") return "revokeAdminSession";
  if (resource === "admins") return "disableAdmin";
  if (resource === "ratings")
    return record?.target === "dish" || record?.dish_id
      ? "deleteDishRating"
      : record?.course_id
        ? "deleteCourseRating"
        : "deleteTeacherRating";
  throw new Error(`Resource ${resource} does not support delete.`);
}

function ratingDeletePayload(record: Record<string, unknown>) {
  return record?.dish_id
    ? { dishID: record.dish_id, userID: record.user_id }
    : record?.course_id
      ? { courseID: record.course_id, userID: record.user_id }
      : { teacherID: record.teacher_id, userID: record.user_id };
}

function ensureID<T extends AdminRecord>(value: T, fallback?: string | number) {
  return value?.id == null && fallback != null
    ? { ...value, id: fallback }
    : value;
}
