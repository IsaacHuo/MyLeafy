import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

let cachedOAuth;
let expiresAt=0;

// Operator-only helper. Credentials stay in memory and never enter reports or argv.
export async function cloudflareToken() {
  if (process.env.CLOUDFLARE_API_TOKEN?.trim()) return process.env.CLOUDFLARE_API_TOKEN.trim();
  if(cachedOAuth && Date.now()<expiresAt)return cachedOAuth;
  const executable = new URL('../../node_modules/.bin/wrangler', import.meta.url).pathname;
  try {
    const { stdout } = await promisify(execFile)(executable, ['auth', 'token', '--json'], {
      timeout: 30000, maxBuffer: 1024 * 1024,
      env: { ...process.env, WRANGLER_SEND_METRICS: 'false' },
    });
    const credentials = JSON.parse(stdout);
    if (typeof credentials.token === 'string' && credentials.token) {
      cachedOAuth=credentials.token;expiresAt=Date.now()+60000;return cachedOAuth;
    }
  } catch { /* Never echo CLI stderr: it may include authentication details. */ }
  throw new Error('Cloudflare authorization unavailable. Run wrangler login or configure CLOUDFLARE_API_TOKEN.');
}
