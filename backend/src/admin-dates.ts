import { Temporal } from "@js-temporal/polyfill";
import { ApiError } from "./http";

export const utc = (date: Date) => date.toISOString().replace("Z", "000Z");
export function dateBoundary(
  value: unknown,
  timezone = "Asia/Shanghai",
  end = false,
): string | null {
  if (value == null || value === "") return null;
  try {
    const date = String(value);
    if (/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      let day = Temporal.PlainDate.from(date);
      if (end) day = day.add({ days: 1 });
      return day
        .toZonedDateTime(timezone)
        .toInstant()
        .toString({ fractionalSecondDigits: 6 });
    }
    return Temporal.Instant.from(date).toString({ fractionalSecondDigits: 6 });
  } catch {
    throw new ApiError(400, "bad_request", "日期或时区无效。");
  }
}
export function dayRange(days: number, timezone: string, now = new Date()) {
  try {
    const today = Temporal.Instant.from(now.toISOString())
      .toZonedDateTimeISO(timezone)
      .toPlainDate();
    const start = today.subtract({ days: days - 1 });
    return {
      today: today.toString(),
      startDate: start.toString(),
      since: dateBoundary(start.toString(), timezone)!,
      until: utc(now),
    };
  } catch {
    throw new ApiError(400, "bad_request", "时区无效。");
  }
}
