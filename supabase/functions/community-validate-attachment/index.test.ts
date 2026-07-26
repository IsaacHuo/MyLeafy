import {
  isOOXML,
  isPDF,
  isAttachmentSizeAllowed,
  isContentTypeAllowed,
  isUTF8Markdown,
  sanitizedDisplayName,
  zipEntryNames,
} from "./index.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("attachment validator recognizes bounded PDF shape", () => {
  assert(isPDF(new TextEncoder().encode("%PDF-1.7\nbody\n%%EOF")), "expected PDF");
  assert(!isPDF(new TextEncoder().encode("not-a-pdf%%EOF")), "expected invalid header");
  assert(!isPDF(new TextEncoder().encode("%PDF-1.7 no trailer")), "expected missing trailer");
});

Deno.test("attachment validator accepts UTF-8 markdown and rejects binary NUL", () => {
  assert(isUTF8Markdown(new TextEncoder().encode("# 课程资料\n")), "expected UTF-8");
  assert(!isUTF8Markdown(new Uint8Array([65, 0, 66])), "expected NUL rejection");
  assert(!isUTF8Markdown(new Uint8Array([0xc3, 0x28])), "expected malformed UTF-8 rejection");
});

Deno.test("attachment validator enforces the 10 MB object limit", () => {
  assert(isAttachmentSizeAllowed(1), "expected one byte to be accepted");
  assert(isAttachmentSizeAllowed(10 * 1024 * 1024), "expected exact limit to be accepted");
  assert(!isAttachmentSizeAllowed(0), "expected empty file rejection");
  assert(!isAttachmentSizeAllowed(10 * 1024 * 1024 + 1), "expected oversized file rejection");
});

Deno.test("attachment validator rejects forged MIME and extension combinations", () => {
  assert(isContentTypeAllowed("pdf", "application/pdf"), "expected PDF MIME");
  assert(!isContentTypeAllowed("pdf", "application/octet-stream"), "expected forged PDF MIME rejection");
  assert(isContentTypeAllowed("md", "text/plain; charset=utf-8"), "expected plain Markdown MIME");
  assert(!isContentTypeAllowed("docx", "application/pdf"), "expected DOCX/PDF mismatch rejection");
});

Deno.test("attachment validator sanitizes display names", () => {
  assert(sanitizedDisplayName("  课程/总结.docx ") === "课程 总结.docx", "expected sanitized name");
  assert(sanitizedDisplayName("") === null, "expected empty rejection");
});

Deno.test("attachment validator reads a consistent OOXML central directory", () => {
  const archive = fakeZip([
    "[Content_Types].xml",
    "_rels/.rels",
    "word/document.xml",
  ]);
  assert(zipEntryNames(archive).has("word/document.xml"), "expected entry");
  assert(isOOXML(archive, "word/document.xml"), "expected DOCX shape");
  assert(!isOOXML(archive, "xl/workbook.xml"), "expected XLSX mismatch");

  const spreadsheet = fakeZip([
    "[Content_Types].xml",
    "_rels/.rels",
    "xl/workbook.xml",
  ]);
  assert(isOOXML(spreadsheet, "xl/workbook.xml"), "expected XLSX shape");
  assert(!isOOXML(spreadsheet, "word/document.xml"), "expected DOCX mismatch");

  const forgedLocalHeaders = fakeLocalHeaders(["[Content_Types].xml", "_rels/.rels", "word/document.xml"]);
  assert(!isOOXML(forgedLocalHeaders, "word/document.xml"), "expected missing central directory rejection");
});

function fakeZip(names: string[]): Uint8Array {
  const localParts = names.map((name) => {
    const encoded = new TextEncoder().encode(name);
    const header = new Uint8Array(30 + encoded.length);
    header.set([0x50, 0x4b, 0x03, 0x04], 0);
    header[26] = encoded.length & 0xff;
    header[27] = (encoded.length >> 8) & 0xff;
    header.set(encoded, 30);
    return header;
  });
  const localSize = localParts.reduce((sum, part) => sum + part.length, 0);
  let localOffset = 0;
  const centralParts = names.map((name, index) => {
    const encoded = new TextEncoder().encode(name);
    const header = new Uint8Array(46 + encoded.length);
    header.set([0x50, 0x4b, 0x01, 0x02], 0);
    header[28] = encoded.length & 0xff;
    header[29] = (encoded.length >> 8) & 0xff;
    writeLittleEndian32(header, 42, localOffset);
    header.set(encoded, 46);
    localOffset += localParts[index].length;
    return header;
  });
  const centralSize = centralParts.reduce((sum, part) => sum + part.length, 0);
  const end = new Uint8Array(22);
  end.set([0x50, 0x4b, 0x05, 0x06], 0);
  end[8] = names.length & 0xff;
  end[9] = (names.length >> 8) & 0xff;
  end[10] = names.length & 0xff;
  end[11] = (names.length >> 8) & 0xff;
  writeLittleEndian32(end, 12, centralSize);
  writeLittleEndian32(end, 16, localSize);

  const result = new Uint8Array(localSize + centralSize + end.length);
  let offset = 0;
  for (const part of [...localParts, ...centralParts, end]) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function fakeLocalHeaders(names: string[]): Uint8Array {
  const parts = names.map((name) => {
    const encoded = new TextEncoder().encode(name);
    const header = new Uint8Array(30 + encoded.length);
    header.set([0x50, 0x4b, 0x03, 0x04], 0);
    header[26] = encoded.length & 0xff;
    header[27] = (encoded.length >> 8) & 0xff;
    header.set(encoded, 30);
    return header;
  });
  const result = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function writeLittleEndian32(bytes: Uint8Array, offset: number, value: number) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}
