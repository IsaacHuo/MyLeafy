import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ValidationRequest = {
  post_id?: string;
  object_path?: string;
  display_name?: string;
};

export type SupportedExtension = "pdf" | "xlsx" | "docx" | "md";

const canonicalContentTypes: Record<SupportedExtension, string> = {
  pdf: "application/pdf",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  md: "text/markdown",
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const token = bearerToken(request);
  if (!token) return json({ error: "Missing authentication." }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) return json({ error: "Attachment validation is not configured." }, 500);

  const client = createClient(url, serviceRoleKey, { auth: { persistSession: false } });
  const { data: authData, error: authError } = await client.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Invalid authentication." }, 401);

  const body = await readJSON<ValidationRequest>(request);
  const postID = normalized(body.post_id);
  const objectPath = normalized(body.object_path);
  const displayName = sanitizedDisplayName(body.display_name);
  const extension = supportedExtension(displayName);
  if (!postID || !objectPath || !displayName || !extension) {
    return json({ error: "附件信息无效。" }, 400);
  }

  const { data: link, error: linkError } = await client
    .from("profile_auth_links")
    .select("profile_id")
    .eq("auth_user_id", authData.user.id)
    .maybeSingle();
  if (linkError || !link?.profile_id) return json({ error: "Community profile is unavailable." }, 403);

  const expectedPrefix = `posts/${link.profile_id}/${postID}/`;
  if (!objectPath.startsWith(expectedPrefix) || !objectPath.toLowerCase().endsWith(`.${extension}`)) {
    return json({ error: "Upload path does not belong to the current profile." }, 403);
  }

  try {
    const validated = await validatedAttachment(client, objectPath, extension);
    const { data: receiptID, error: receiptError } = await client.rpc(
      "edge_record_community_attachment_validation_v1",
      {
        p_auth_user_id: authData.user.id,
        p_post_id: postID,
        p_object_path: objectPath,
        p_display_name: displayName,
        p_content_type: canonicalContentTypes[extension],
        p_file_extension: extension,
        p_byte_size: validated.size,
        p_sha256: validated.sha256,
      },
    );
    if (receiptError || !receiptID) throw new Error(receiptError?.message ?? "receipt_not_created");
    return json({
      receipt_id: receiptID,
      byte_size: validated.size,
      sha256: validated.sha256,
      content_type: canonicalContentTypes[extension],
      file_extension: extension,
    });
  } catch (error) {
    console.warn(
      "community-validate-attachment: rejected",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "附件验证失败，请确认文件未损坏且格式正确。" }, 422);
  }
}

if (import.meta.main) Deno.serve(handler);

async function validatedAttachment(client: any, path: string, extension: SupportedExtension) {
  const { data, error } = await client.storage.from("community-attachments").download(path);
  if (error || !data) throw new Error("object_unavailable");
  if (!isContentTypeAllowed(extension, data.type)) throw new Error("content_type_mismatch");
  const bytes = new Uint8Array(await data.arrayBuffer());
  if (!isAttachmentSizeAllowed(bytes.length)) throw new Error("invalid_object_size");

  switch (extension) {
    case "pdf":
      if (!isPDF(bytes)) throw new Error("invalid_pdf");
      break;
    case "docx":
      if (!isOOXML(bytes, "word/document.xml")) throw new Error("invalid_docx");
      break;
    case "xlsx":
      if (!isOOXML(bytes, "xl/workbook.xml")) throw new Error("invalid_xlsx");
      break;
    case "md":
      if (!isUTF8Markdown(bytes)) throw new Error("invalid_markdown");
      break;
  }

  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return {
    size: bytes.length,
    sha256: Array.from(new Uint8Array(digest))
      .map((value) => value.toString(16).padStart(2, "0"))
      .join(""),
  };
}

export function isPDF(bytes: Uint8Array): boolean {
  if (bytes.length < 10) return false;
  const header = new TextDecoder().decode(bytes.subarray(0, 5));
  if (header !== "%PDF-") return false;
  const tail = new TextDecoder().decode(bytes.subarray(Math.max(0, bytes.length - 2048)));
  return tail.includes("%%EOF");
}

export function isAttachmentSizeAllowed(byteSize: number): boolean {
  return Number.isInteger(byteSize) && byteSize >= 1 && byteSize <= MAX_ATTACHMENT_BYTES;
}

export function isContentTypeAllowed(extension: SupportedExtension, value: string): boolean {
  const contentType = value.split(";", 1)[0].trim().toLowerCase();
  if (extension === "md") {
    return contentType === "text/markdown"
      || contentType === "text/plain"
      || contentType === "text/x-markdown";
  }
  return contentType === canonicalContentTypes[extension];
}

export function isUTF8Markdown(bytes: Uint8Array): boolean {
  if (bytes.includes(0)) return false;
  try {
    new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return true;
  } catch {
    return false;
  }
}

export function isOOXML(bytes: Uint8Array, requiredDocumentEntry: string): boolean {
  if (bytes.length < 4 || bytes[0] !== 0x50 || bytes[1] !== 0x4b) return false;
  const entries = zipEntryNames(bytes);
  return entries.has("[Content_Types].xml")
    && entries.has("_rels/.rels")
    && entries.has(requiredDocumentEntry);
}

export function zipEntryNames(bytes: Uint8Array): Set<string> {
  const entries = new Set<string>();
  const decoder = new TextDecoder();
  const endRecordOffset = endOfCentralDirectoryOffset(bytes);
  if (endRecordOffset === null) return entries;

  const entriesOnDisk = littleEndian16(bytes, endRecordOffset + 8);
  const totalEntries = littleEndian16(bytes, endRecordOffset + 10);
  const centralDirectorySize = littleEndian32(bytes, endRecordOffset + 12);
  const centralDirectoryOffset = littleEndian32(bytes, endRecordOffset + 16);
  const centralDirectoryEnd = centralDirectoryOffset + centralDirectorySize;
  if (
    littleEndian16(bytes, endRecordOffset + 4) !== 0
    || littleEndian16(bytes, endRecordOffset + 6) !== 0
    || entriesOnDisk !== totalEntries
    || totalEntries === 0
    || centralDirectoryEnd > endRecordOffset
  ) {
    return new Set();
  }

  let offset = centralDirectoryOffset;
  for (let index = 0; index < totalEntries; index += 1) {
    if (offset + 46 > centralDirectoryEnd || littleEndian32(bytes, offset) !== 0x02014b50) {
      return new Set();
    }
    const fileNameLength = littleEndian16(bytes, offset + 28);
    const extraLength = littleEndian16(bytes, offset + 30);
    const commentLength = littleEndian16(bytes, offset + 32);
    const localHeaderOffset = littleEndian32(bytes, offset + 42);
    const nameStart = offset + 46;
    const nameEnd = nameStart + fileNameLength;
    const next = nameEnd + extraLength + commentLength;
    if (
      nameEnd > centralDirectoryEnd
      || next > centralDirectoryEnd
      || localHeaderOffset + 30 > centralDirectoryOffset
      || littleEndian32(bytes, localHeaderOffset) !== 0x04034b50
    ) {
      return new Set();
    }

    const name = decoder.decode(bytes.subarray(nameStart, nameEnd));
    const localNameLength = littleEndian16(bytes, localHeaderOffset + 26);
    const localNameStart = localHeaderOffset + 30;
    const localNameEnd = localNameStart + localNameLength;
    if (
      !name
      || name.startsWith("/")
      || name.includes("\\")
      || name.split("/").includes("..")
      || localNameEnd > centralDirectoryOffset
      || decoder.decode(bytes.subarray(localNameStart, localNameEnd)) !== name
      || entries.has(name)
    ) {
      return new Set();
    }
    entries.add(name);
    offset = next;
  }
  if (offset !== centralDirectoryEnd) return new Set();
  return entries;
}

function endOfCentralDirectoryOffset(bytes: Uint8Array): number | null {
  const minimumRecordSize = 22;
  if (bytes.length < minimumRecordSize) return null;
  const searchStart = Math.max(0, bytes.length - minimumRecordSize - 0xffff);
  for (let offset = bytes.length - minimumRecordSize; offset >= searchStart; offset -= 1) {
    if (
      littleEndian32(bytes, offset) === 0x06054b50
      && offset + minimumRecordSize + littleEndian16(bytes, offset + 20) === bytes.length
    ) {
      return offset;
    }
  }
  return null;
}

function littleEndian16(bytes: Uint8Array, offset: number) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function littleEndian32(bytes: Uint8Array, offset: number) {
  return (
    bytes[offset]
    | (bytes[offset + 1] << 8)
    | (bytes[offset + 2] << 16)
    | (bytes[offset + 3] << 24)
  ) >>> 0;
}

function supportedExtension(name: string | null): SupportedExtension | null {
  const extension = name?.split(".").pop()?.toLowerCase();
  return extension === "pdf" || extension === "xlsx" || extension === "docx" || extension === "md"
    ? extension
    : null;
}

export function sanitizedDisplayName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const name = value
    .replace(/[\u0000-\u001f\u007f/\\:]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!name || name.length > 180) return null;
  return name;
}

function bearerToken(request: Request) {
  const value = request.headers.get("Authorization") ?? "";
  const [scheme, token] = value.split(/\s+/, 2);
  return scheme.toLowerCase() === "bearer" && token ? token : null;
}

function normalized(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

async function readJSON<T>(request: Request): Promise<T> {
  try {
    return await request.json() as T;
  } catch {
    return {} as T;
  }
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
