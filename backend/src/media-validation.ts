// Ported from the existing Supabase validators; keep byte-level acceptance contracts.
const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;
export type SupportedExtension = "pdf" | "xlsx" | "docx" | "md";

export const canonicalContentTypes: Record<SupportedExtension, string> = {
  pdf: "application/pdf",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  md: "text/markdown",
};

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
    new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
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

export function supportedExtension(name: string | null): SupportedExtension | null {
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

export function normalizedUUID(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const candidate = value.trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(candidate)
    ? candidate
    : null;
}

export function jpegDimensions(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let offset = 2;
  const startOfFrame = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
  while (offset + 3 < bytes.length) {
    if (bytes[offset] !== 0xff) return null;
    while (offset < bytes.length && bytes[offset] === 0xff) offset += 1;
    const marker = bytes[offset++];
    if (marker === 0xd9 || marker === 0xda) return null;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 1 >= bytes.length) return null;
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return null;
    if (startOfFrame.has(marker)) {
      if (length < 7) return null;
      const height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      const width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      return width > 0 && height > 0 ? { width, height } : null;
    }
    offset += length;
  }
  return null;
}
