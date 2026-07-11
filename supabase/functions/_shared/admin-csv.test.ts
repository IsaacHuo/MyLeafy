import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { csvCell, toCSV } from "./admin-csv.ts";

Deno.test("admin CSV uses a UTF-8 BOM and escapes quotes", () => {
  assertEquals(toCSV(["name"], [{ name: 'A "quoted" value' }]), '\uFEFF"name"\r\n"A ""quoted"" value"');
});

Deno.test("admin CSV neutralizes spreadsheet formulas", () => {
  assertStringIncludes(csvCell("=HYPERLINK(\"https://evil.example\")"), "'=HYPERLINK");
  assertEquals(csvCell("normal"), '"normal"');
});
