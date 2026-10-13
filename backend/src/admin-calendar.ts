import { ApiError } from "./http";
import { dateBoundary } from "./admin-dates";
import type { Row } from "./db";

/** Validate the existing native-client wire fields, including the source's accepted snake aliases. */
export function calendarRecords(
  value: unknown,
  kind: "semester" | "holidays" | "solar",
): Row[] {
  let input = value;
  if (typeof input === "string") {
    try {
      input = JSON.parse(input);
    } catch {
      throw new ApiError(422, "invalid_calendar", "校历应为记录数组。");
    }
  }
  if (!Array.isArray(input) || input.length > 500)
    throw new ApiError(
      422,
      "invalid_calendar",
      "校历记录应为数组且不超过 500 项。",
    );
  const ids = new Set<string>();
  return input.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry))
      throw new ApiError(
        422,
        "invalid_calendar",
        `第 ${index + 1} 项格式无效。`,
      );
    const row = entry as Row;
    if (typeof row.id !== "string" || !row.id.trim() || ids.has(row.id))
      throw new ApiError(
        422,
        "invalid_calendar",
        `第 ${index + 1} 项 ID 缺失或重复。`,
      );
    if (typeof row.title !== "string" || !row.title.trim())
      throw new ApiError(
        422,
        "invalid_calendar",
        `第 ${index + 1} 项标题不能为空。`,
      );
    ids.add(row.id);
    const date = (v: unknown) => {
      if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v))
        throw new ApiError(
          422,
          "invalid_calendar",
          `第 ${index + 1} 项日期无效。`,
        );
      dateBoundary(v);
      return v;
    };
    if (kind === "solar") {
      date(row.dateString ?? row.date_string);
      return row;
    }
    const start = date(row.startDateString ?? row.start_date),
      end = date(row.endDateString ?? row.end_date);
    if (start > end)
      throw new ApiError(
        422,
        "invalid_calendar",
        `第 ${index + 1} 项结束日期早于开始日期。`,
      );
    if (
      kind === "semester" &&
      !["holiday", "closure", "solarTerm"].includes(String(row.kind))
    )
      throw new ApiError(
        422,
        "invalid_calendar",
        `第 ${index + 1} 项事件类型无效。`,
      );
    if (kind === "holidays" && row.kind != null && row.kind !== "holiday")
      throw new ApiError(
        422,
        "invalid_calendar",
        `第 ${index + 1} 项节假日类型无效。`,
      );
    if (
      row.academicCategory != null &&
      ![
        "public_holiday",
        "important_date",
        "semester_end",
        "winter_break",
        "summer_break",
      ].includes(String(row.academicCategory))
    )
      throw new ApiError(
        422,
        "invalid_calendar",
        `第 ${index + 1} 项学业分类无效。`,
      );
    return row;
  });
}
