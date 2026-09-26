export function toCSV(columns: readonly string[], rows: Record<string, unknown>[]) {
  const lines = [columns.map(csvCell).join(",")];
  for (const row of rows) lines.push(columns.map((column) => csvCell(row[column])).join(","));
  return `\uFEFF${lines.join("\r\n")}`;
}

export function csvCell(value: unknown) {
  const raw = value == null ? "" : typeof value === "object" ? JSON.stringify(value) : String(value);
  const text = /^[=+\-@\t\r]/.test(raw) ? `'${raw}` : raw;
  return `"${text.replace(/"/g, '""')}"`;
}
