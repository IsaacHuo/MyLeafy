# Admin data provenance checklist

Source inventory verified against the Studio resource configuration, provider action mappings and Worker list registry. Each row maps visible DTO fields to its action and raw D1 table. Derived/joined fields pass through adminHydrate; direct columns pass through the role projection and JSON decoding. This inventory is not a claim that every production record has been inspected.

| Resource | List action | Raw table | Display fields | Resource filters |
|---|---|---|---|---|
| campuses | listCampuses | campuses | id, display_name, connector_kind, is_community_enabled, status | status (where offered) |
| campus-requests | listCampusRequests | campus_membership_requests | request_type, school_name, requester.nickname, status, admin_note, created_at | status (where offered) |
| posts | listPosts | posts | title, category, display_status, upload_state, author.nickname, image_count, like_count, created_at | status (where offered) |
| polls | listPolls | community_polls | question, status, total_vote_count, closes_at, created_at | status (where offered) |
| comments | listComments | comments | body, post.title, author.nickname, status, created_at | status (where offered) |
| reports | listModerationReports | community_reports | target_type, reason, detail, status, created_at | status (where offered), targetType |
| profiles | listProfiles | profiles | nickname, display_name, edu_id, community_access_status, muted_until, created_at | status (where offered), muted |
| feedback | listFeedback | feedback_submissions | issue_type, body, contact, status, created_at | status (where offered), issueType |
| announcements | listAnnouncements | site_announcements | title, level, status, published_at, expires_at | status (where offered) |
| community-banners | listCommunityBanners | community_banners | signed_image_url, title, subtitle, revision, destination_kind, status, published_at, expires_at | status (where offered) |
| postgraduate | listPostgraduateSources | postgraduate_sources | title, source_kind, trust_level, school, exam_year, status | status (where offered), kind, trustLevel |
| postgraduate-suggestions | listPostgraduateSuggestions | postgraduate_source_suggestions | title, source_kind, school, exam_year, status, created_at | status (where offered), kind |
| suggestions | listCatalogSuggestions | catalog_suggestions | suggestion_type, name, unit, category, status, created_at | status (where offered), type |
| teachers | listTeachers | teachers | name, unit, rating_average, rating_count, status | status (where offered) |
| courses | listCourses | course_catalog | name, unit, category, credit, rating_average, status | status (where offered), category |
| dishes | listDishes | dish_catalog | name, location, rating_average, rating_count, status | status (where offered), location |
| ratings / Teacher | listTeacherRatings | teacher_ratings | teacher.name, dish.name, course.name, user.nickname, stars, updated_at | status (where offered), teacherID, dishID, courseID, userID, stars |
| ratings / Course | listCourseRatings | course_ratings | teacher.name, dish.name, course.name, user.nickname, stars, updated_at | status (where offered), teacherID, dishID, courseID, userID, stars |
| ratings / Dish | listDishRatings | dish_ratings | teacher.name, dish.name, course.name, user.nickname, stars, updated_at | status (where offered), teacherID, dishID, courseID, userID, stars |
| admins | listAdmins | admin_accounts | username, display_name, role, active, last_login_at | status (where offered) |
| sessions | listAdminSessions | admin_sessions | admin.display_name, is_current, last_seen_at, expires_at, revoked_at | status (where offered), status, adminID |
| audit-logs | listAuditLogs | admin_audit_logs | admin.display_name, action, target_type, outcome, duration_ms, error_code, created_at | status (where offered), action, adminID |
| semester-configs | listSemesterRuntimeConfigs | semester_runtime_configs | campus_id, semester_id, semester_start_date, supported_weeks, graduate_timetable_term_code, is_active | status (where offered) |
| national-calendar | listNationalCalendarRuntimeConfigs | national_calendar_runtime_configs | year, is_active, holidays, solar_terms, updated_at | status (where offered) |

All offered list controls send their query conditions to adminList. Search uses the registry search columns; ordering uses an allowed physical column plus a stable primary-key tie-breaker. Pagination and export reuse the same filtering path. Date filters use admin-dates.ts: Asia/Shanghai by default, start midnight inclusive, following end-date midnight exclusive. Rating date filters use updated_at; other resources use created_at. Global resources omit campus scoping; campus requests in the unified queue explicitly preserve their global scope.

## Derived fields and details

- Nested author/user/requester/reporter profiles: profile foreign key -> profiles -> role projection. Sensitive education IDs/contact fields remain super-admin only.
- Post media: post_id -> post_images/post_attachments -> actual counts and signed URLs. Declared counts determine publication completeness; they are not the displayed actual media count.
- Profile content counts: grouped posts/comments by author_id. Recent App activity uses app_activity and its profile foreign key.
- Ratings: target_id + user_id -> raw rating row -> composite object ID; target names hydrate from teachers/course_catalog/dish_catalog. Counts, star distribution and weighted means are checked against raw ratings.
- Session object IDs derive from the protected session token hash, with current-session status; session active/revoked/expired filters use actual revocation and expiration values.
- Post/report/profile detail actions reuse the same role projection; report evidence resolves the reported post, comment and profile.

## Metrics and special pages

| Display | API/query | Raw evidence |
|---|---|---|
| Total/completed profiles | overview, listProfiles | Non-demo profiles / is_profile_complete |
| App active today/7d/30d/range and trend | overview -> activitySummary; activityStart/End profile drilldown | Distinct app_activity.profile_id, event campus snapshot, occurrence boundaries and collection metadata |
| New profiles/posts/comments | overview, corresponding list | Record creation in the same natural-day range |
| Pending/overdue reports and feedback | overview, workQueue, corresponding list | open + reviewed states, created_at age, resolved/closed separate |
| Current hidden content / period hide transitions | overview | Current status / moderation_events after collection start |
| Teacher average and stars | overview | teacher_ratings raw rows, weighted star total / row count |
| Unified work queue | workQueue | Seven registered resource queries, oldest-first and bounded samples |
| Android candidate/release state | listAndroidReleases | android release/candidate/publication-operation records; GitHub reconciliation follows existing release contract |
| Environment/deployment/tasks/queues | operationalHealth, diagnosticList | Deployment binding, backend_control, scheduled_runs, change_outbox, file_delete_jobs; absent logs/performance explicitly uncollected |
| Data quality | dataQuality | Raw ratings, interaction rows, related objects, media declarations/rows, semester and calendar records; bounded samples |

The SELECT-only production audit receipt records check time and mismatch/unverifiable counts in admin-data-audit.json. Historical foreground usage cannot be reconstructed. Tests use differing samples for the corrected filters, identity/session cases, time boundaries, rating deletion, permissions and global queues; browser acceptance covers every resource in both themes.
