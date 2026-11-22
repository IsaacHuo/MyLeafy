import { serve } from '@hono/node-server';
import { readFileSync } from 'node:fs';
import { AcademicOperations } from './operations';
import { createAcademicConnector } from './app';

const environment = process.env.ENVIRONMENT;
if (environment !== 'production' && environment !== 'staging') throw new Error('ENVIRONMENT must be staging or production');
// Public release identity only. This process never reads the business API's credential environment.
const release = JSON.parse(readFileSync(`/opt/myleafy/${environment}/current/site/dist/release.json`, 'utf8')) as { environment: string; commit: string };
if (release.environment !== environment || !/^[a-f0-9]{40}$/.test(release.commit)) throw new Error('Academic connector release identity is invalid');
const operations = new AcademicOperations({ onCleanupFailure: () => {
  console.error(JSON.stringify({ event: 'academic_cleanup_unconfirmed' }));
} });
const connector = createAcademicConnector(operations, { deployCommit: release.commit, onError: (code, requestID) => {
  console.error(JSON.stringify({ event: 'academic_error', code, request_id: requestID }));
} });
const server = serve({ hostname: '127.0.0.1', port: environment === 'production' ? 3130 : 3131, fetch: connector.app.fetch });
let stopping = false;
async function shutdown() {
  if (stopping) return;
  stopping = true;
  const closed = new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  await connector.shutdown(); await closed;
}
for (const signal of ['SIGTERM', 'SIGINT']) process.once(signal, () => {
  void shutdown().catch(() => { console.error(JSON.stringify({ event: 'academic_shutdown_failed' })); process.exitCode = 1; });
});
