import { jpegDimensions, normalizedUUID, postUploadPrefix } from "./index.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("community upload validator rejects non-JPEG data", () => {
  assert(jpegDimensions(new Uint8Array([1, 2, 3, 4])) === null, "expected rejection");
});

Deno.test("community upload validator reads bounded JPEG dimensions", () => {
  const jpeg = new Uint8Array([
    0xff, 0xd8,
    0xff, 0xc0, 0x00, 0x11, 0x08,
    0x02, 0x00,
    0x03, 0x20,
    0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
  ]);
  const dimensions = jpegDimensions(jpeg);
  assert(dimensions?.width === 800, "expected width");
  assert(dimensions?.height === 512, "expected height");
});

Deno.test("community upload validator canonicalizes uppercase Swift UUIDs before path checks", () => {
  const uppercasePostID = "2BF7A34C-5E2A-4B93-9CAD-97FB9BF93C2E";
  const profileID = "74aca285-d506-4654-ad05-f161ba46db2c";
  const postID = normalizedUUID(uppercasePostID);

  assert(postID === uppercasePostID.toLowerCase(), "expected canonical lowercase UUID");
  assert(
    postUploadPrefix(profileID, postID!) ===
      "posts/74aca285-d506-4654-ad05-f161ba46db2c/2bf7a34c-5e2a-4b93-9cad-97fb9bf93c2e",
    "expected path prefix to match the lowercase Storage object path",
  );
});

Deno.test("community upload validator rejects malformed UUID input", () => {
  assert(normalizedUUID("not-a-uuid") === null, "expected malformed UUID rejection");
});
