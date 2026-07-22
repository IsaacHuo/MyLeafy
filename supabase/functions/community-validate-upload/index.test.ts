import { jpegDimensions } from "./index.ts";

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
