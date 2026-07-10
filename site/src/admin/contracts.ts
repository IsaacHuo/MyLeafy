export type AdminRole = "super_admin" | "operator" | "viewer";

// admin-community action metadata uses the minimum permitted role as its permission value.
export type AdminPermission = AdminRole;

export type ApiMetadata = {
  request_id?: string;
  total?: number;
  page?: number;
  page_size?: number;
  next_cursor?: string | null;
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
  label: string;
  description?: string;
  href?: string;
  metadata?: Record<string, unknown>;
};

export type GlobalSearchResponse = {
  results: readonly GlobalSearchResult[];
  meta?: ApiMetadata;
};

export type ExportFormat = "csv" | "json";

export type ExportRequest = {
  resource: string;
  format: ExportFormat;
  filters?: Record<string, unknown>;
  sort?: {
    field: string;
    order: "ASC" | "DESC";
  };
  fields?: readonly string[];
  ids?: readonly (string | number)[];
};
