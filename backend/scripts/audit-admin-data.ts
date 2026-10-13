import { dataQuality } from "../src/admin-insights";
import type { AdminContext } from "../src/admin-auth";
import type { BackendEnv } from "../src/auth";
import { writeFileSync } from "node:fs";
// Operator-run audit. The adapter accepts SELECT only, and never prints credentials or personal records.
const account = process.env.CLOUDFLARE_ACCOUNT_ID,
  token = process.env.CLOUDFLARE_API_TOKEN;
if (!account || !token) throw new Error("Cloudflare credentials are required");
const database = "7eb5c92e-ccfd-4a56-9b80-6dcb8e81225d";
const db = {
  prepare(sql: string) {
    return {
      bind(...params: unknown[]) {
        return {
          async all() {
            if (!/^SELECT\s/i.test(sql))
              throw new Error("Audit allows SELECT only");
            const response = await fetch(
              `https://api.cloudflare.com/client/v4/accounts/${account}/d1/database/${database}/query`,
              {
                method: "POST",
                headers: {
                  Authorization: `Bearer ${token}`,
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({ sql, params }),
              },
            );
            const body = (await response.json()) as any;
            if (!response.ok || !body.success)
              throw new Error(`D1 audit failed: HTTP ${response.status}`);
            return { results: body.result[0].results };
          },
        };
      },
    };
  },
};
const result = await dataQuality(
  { DB: db } as unknown as BackendEnv,
  { role: "super_admin" } as AdminContext,
  {},
);
const receipt = {
  environment: "production",
  readOnly: true,
  ...result,
  checks: result.checks.map(({ samples, ...check }) => ({
    ...check,
    sampleCount: samples.length,
  })),
};
writeFileSync(
  new URL("../../docs/engineering/admin-data-audit.json", import.meta.url),
  JSON.stringify(receipt, null, 2) + "\n",
);
console.log(JSON.stringify(receipt));
