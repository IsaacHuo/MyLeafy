export type AdminRole = "super_admin" | "operator" | "viewer";

export type AdminAccount = {
  id: string;
  username: string;
  display_name: string;
  role: AdminRole;
  active: boolean;
  last_login_at?: string | null;
  created_at?: string;
  updated_at?: string;
};

// admin-community action metadata uses the minimum permitted role as its permission value.
export type AdminPermission = AdminRole;

export type ApiMetadata = {
  request_id?: string;
  audit_logged?: boolean;
  duration_ms?: number;
};

export type ApiResponse<T> = {
  data: T;
  meta?: ApiMetadata;
};

export type StructuredApiError = {
  code: string;
  message: string;
  status: number;
  details?: Record<string, unknown>;
  field_errors?: Record<string, readonly string[]>;
  request_id?: string;
};

export type ApiErrorResponse = {
  error: StructuredApiError;
};

export type GlobalSearchRequest = {
  query: string;
  resources?: readonly string[];
  limit?: number;
};

export type GlobalSearchResult = {
  resource: string;
  id: string | number;
  title: string;
  subtitle?: string;
  status?: string;
  updated_at: string;
  path: string;
};

export type GlobalSearchResponse = ApiResponse<readonly GlobalSearchResult[]>;

export type ExportFormat = "csv";

export type ExportRequest = {
  resource: string;
  format?: ExportFormat;
  filters?: Record<string, unknown>;
  sort?: {
    field: string;
    order: "ASC" | "DESC";
  };
};
export type AdminOverview = {
  summary: {
    operations: {
      totalProfiles: number;
      completeProfiles: number;
      newProfilesToday: number;
      postsToday: number;
      commentsToday: number;
      postsInRange: number;
      commentsInRange: number;
      daily: {
        bucket_date: string;
        posts: number;
        comments: number;
        profiles: number;
      }[];
    };
    moderation: {
      openReports: number;
      overdueReports: number;
      hiddenPostsInRange: number;
    };
    feedback: {
      open: number;
      reviewed: number;
      pending: number;
      overdue: number;
      aging: { label: string; count: number }[];
    };
    teachers: { average: number; totalRatings: number };
  };
  cards: { posts: { hidden: number } };
  analyticsMeta: {
    days: number;
    timezone: string;
    startDate: string;
    startAt: string;
    endAt: string;
    generatedAt: string;
    moderationStartedAt: string;
  };
};
