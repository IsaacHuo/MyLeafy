/** Application-owned storage contracts; no cloud-provider runtime types. */
export type SQLValue = string | number | null | ArrayBuffer | Uint8Array;
export type SQLRow = Record<string, unknown>;
export type SQLResult<T = SQLRow> = { results: T[]; success: boolean; meta: { changes: number; last_row_id: number } };
export interface SQLStatement {
  bind(...values: unknown[]): SQLStatement;
  all<T = SQLRow>(): Promise<SQLResult<T>>;
  run<T = SQLRow>(): Promise<SQLResult<T>>;
  first<T = SQLRow>(column?: string): Promise<T | null>;
}
export interface Database {
  prepare(sql: string): SQLStatement;
  batch<T = SQLRow>(statements: SQLStatement[]): Promise<SQLResult<T>[]>;
}
export type ObjectMetadata = {
  size: number; httpEtag: string; customMetadata: Record<string, string>;
  httpMetadata: { contentType?: string; cacheControl?: string; contentDisposition?: string; contentEncoding?: string; contentLanguage?: string };
};
export type StoredObject = ObjectMetadata & {
  body: ReadableStream<Uint8Array>; arrayBuffer(): Promise<ArrayBuffer>;
  range?: { offset: number; length: number };
};
export interface ObjectStore {
  put(key: string, body: Uint8Array | ReadableStream<Uint8Array> | null, options: {
    onlyIf?: { etagDoesNotMatch: string }; sha256?: string;
    customMetadata?: Record<string, string>; httpMetadata?: ObjectMetadata['httpMetadata'];
  }): Promise<ObjectMetadata | null>;
  head(key: string): Promise<ObjectMetadata | null>;
  get(key: string, options?: { range?: Headers }): Promise<StoredObject | null>;
  delete(key: string): Promise<void>;
}
export type ScheduledEvent = { cron: string; scheduledTime: number };
