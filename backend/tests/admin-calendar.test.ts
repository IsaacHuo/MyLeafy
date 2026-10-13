import { describe, expect, it } from "vitest";
import { calendarRecords } from "../src/admin-calendar";
describe("native calendar contract", () => {
  it("accepts the native fields and existing snake aliases", () => {
    expect(
      calendarRecords(
        [
          {
            id: "one",
            title: "假期",
            startDateString: "2026-10-01",
            endDateString: "2026-10-07",
            kind: "holiday",
          },
        ],
        "semester",
      ),
    ).toHaveLength(1);
    expect(
      calendarRecords(
        [{ id: "two", title: "节气", date_string: "2026-10-08" }],
        "solar",
      ),
    ).toHaveLength(1);
  });
  it("rejects malformed rows before activation rather than breaking clients", () => {
    for (const value of [
      [{ title: "缺少 ID" }],
      [
        {
          id: "same",
          title: "假期",
          startDateString: "2026-02-30",
          endDateString: "2026-03-01",
          kind: "holiday",
        },
      ],
      [
        {
          id: "same",
          title: "假期",
          startDateString: "2026-10-07",
          endDateString: "2026-10-01",
          kind: "holiday",
        },
      ],
      [
        {
          id: "same",
          title: "假期",
          startDateString: "2026-10-01",
          endDateString: "2026-10-07",
          kind: "not-real",
        },
      ],
    ])
      expect(() => calendarRecords(value, "semester")).toThrow();
  });
});
