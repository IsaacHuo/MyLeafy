import { describe, expect, it } from "vitest";
import { adminActionNames } from "./registry";
import baseline from '../../../docs/engineering/admin-action-baseline.json';

const legacyAdminActionNames = [
  "overview",
  "listCampuses",
  "listCampusRequests",
  "approveCampusRequest",
  "rejectCampusRequest",
  "listPosts",
  "previewCommunityFeed",
  "getPost",
  "retryPostPublish",
  "moderatePost",
  "bulkModeratePosts",
  "listPolls",
  "getPoll",
  "moderatePoll",
  "reviewPollDeletion",
  "listPostPins",
  "pinPost",
  "unpinPost",
  "listComments",
  "listModerationReports",
  "getModerationReport",
  "resolveModerationReport",
  "moderateComment",
  "bulkModerateComments",
  "listProfiles",
  "getProfile",
  "muteProfile",
  "unmuteProfile",
  "listFeedback",
  "updateFeedback",
  "listAnnouncements",
  "createAnnouncement",
  "updateAnnouncement",
  "listCommunityBanners",
  "prepareCommunityBannerImageUpload",
  "createCommunityBanner",
  "updateCommunityBanner",
  "publishCommunityBanner",
  "archiveCommunityBanner",
  "listPostgraduateSources",
  "upsertPostgraduateSource",
  "setPostgraduateSourceStatus",
  "listPostgraduateSuggestions",
  "approvePostgraduateSuggestion",
  "rejectPostgraduateSuggestion",
  "listCatalogSuggestions",
  "approveCatalogSuggestion",
  "rejectCatalogSuggestion",
  "listTeachers",
  "upsertTeacher",
  "setTeacherStatus",
  "listCourses",
  "upsertCourse",
  "setCourseStatus",
  "listDishes",
  "upsertDish",
  "setDishStatus",
  "listTeacherRatings",
  "listDishRatings",
  "deleteTeacherRating",
  "deleteDishRating",
  "listSemesterRuntimeConfigs",
  "upsertSemesterRuntimeConfig",
  "listAdmins",
  "createAdmin",
  "updateAdmin",
  "disableAdmin",
  "listAuditLogs",
  "globalSearch",
  "listAdminSessions",
  "revokeAdminSession",
  "listNationalCalendarRuntimeConfigs",
  "upsertNationalCalendarRuntimeConfig",
] as const;

describe("admin action registry contract", () => {
  it('preserves all 82 accepted actions while adding the six monitoring reads',()=>{
    expect(baseline.count).toBe(82);
    expect(baseline.actions.every(action=>(adminActionNames as readonly string[]).includes(action))).toBe(true);
    expect(adminActionNames).toHaveLength(88);
  });
  it("preserves every legacy action and registers the approved additions", () => {
    expect(new Set(adminActionNames).size).toBe(adminActionNames.length);
    for (const action of [
      ...legacyAdminActionNames,
      "workQueue",
      "operationalHealth",
      "diagnosticList",
      "dataQuality",
      "listCourseRatings",
      "deleteCourseRating",
    ])
      expect(adminActionNames).toContain(action);
  });
});
