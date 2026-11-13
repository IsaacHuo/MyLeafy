/** Local controller: reads credentials from stdin, uses encrypted RPC, emits aggregate results only. */
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { seal, unseal } from './probe-school-rpc.mjs';

const run = promisify(execFile);
const wrapper = fileURLToPath(new URL('../ecs/workbench-safe.py', import.meta.url));
const instance = ['-i', 'i-2ze251tg6q9u5s25jkq4', '-r', 'cn-beijing'];
const id = `myleafy-school-probe-${Date.now()}-${randomBytes(3).toString('hex')}`;
const directory = `/dev/shm/${id}`;
const shellQuote = value => `'${value.replaceAll("'", "'\\''")}'`;
const remote = async (command, timeout = 20000) => run('python3', [wrapper, 'exec', ...instance,
  '--timeout', String(Math.ceil(timeout / 1000)), '--command', command], { timeout: timeout + 10000, maxBuffer: 65536 });

function recognize(image) {
  return new Promise((resolve, reject) => {
    const child = spawn('/tmp/myleafy-vpn-captcha-probe-20261110', [], { stdio: ['pipe', 'pipe', 'pipe'] });
    const chunks = [];
    child.stdout.on('data', chunk => chunks.push(chunk));
    child.stderr.resume();
    child.on('error', reject);
    child.on('close', code => {
      try { if (code !== 0) throw new Error('ocr_failed'); resolve(JSON.parse(Buffer.concat(chunks).toString())); }
      catch { reject(new Error('ocr_failed')); }
    });
    child.stdin.end(Buffer.from(image, 'base64'));
  });
}

let state, rpc, credentials;
try {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const input = Buffer.concat(chunks);
  credentials = JSON.parse(input.toString()); input.fill(0); chunks.forEach(chunk => chunk.fill(0));
  await remote(`mkdir -m 711 ${directory}`);
  for (const name of ['probe-auth.mjs', 'probe-school-rpc.mjs']) {
    await run('python3', [wrapper, 'upload', fileURLToPath(new URL(name, import.meta.url)), `${directory}/${name}`, ...instance],
      { timeout: 60000, maxBuffer: 65536 });
  }
  const keys = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const publicKey = keys.publicKey.export({ type: 'spki', format: 'pem' });
  await remote(`systemd-run --quiet --collect --unit=${id} -p MemoryMax=192M -p MemorySwapMax=0 -p RuntimeMaxSec=135 -p LimitCORE=0 -p NoNewPrivileges=yes -p ProtectSystem=strict -p ProtectHome=yes -p PrivateTmp=yes -p CapabilityBoundingSet= /usr/local/bin/node ${directory}/probe-school-rpc.mjs ${directory}/public.json ${Buffer.from(publicKey).toString('base64')}`);
  let metadata;
  for (let attempt = 0; attempt < 10; attempt++) {
    const result = await remote(`test ! -f ${directory}/public.json || cat ${directory}/public.json`);
    if (result.stdout.trim()) { metadata = JSON.parse(result.stdout); break; }
    await delay(200);
  }
  if (!metadata) throw new Error('probe_not_ready');
  rpc = async (path, value) => {
    const body = JSON.stringify(seal(value, metadata.publicKey));
    const code = `const r=await fetch(${JSON.stringify(`http://127.0.0.1:${metadata.port}${path}`)},{method:"POST",headers:{"Content-Type":"application/json"},body:${JSON.stringify(body)}});console.log(await r.text());`;
    const response = await remote(`/usr/local/bin/node --input-type=module -e ${shellQuote(code)}`, 45000);
    return unseal(JSON.parse(response.stdout.trim()), keys.privateKey);
  };
  state = await rpc('/start', credentials);
  credentials.account = ''; credentials.password = '';
  while (state.stage === 'captcha') {
    const recognized = await recognize(state.image);
    const groups = new Map();
    for (const result of recognized) {
      if (/^[a-z0-9]{4}$/.test(result.text) && result.confidence >= 0.85) {
        const group = groups.get(result.text) ?? []; group.push(result.confidence); groups.set(result.text, group);
      }
    }
    const candidate = [...groups.entries()].filter(([, group]) => group.length >= 2).sort((a, b) => b[1].length - a[1].length)[0];
    if (candidate) state = await rpc('/answer', { token: state.token, captcha: candidate[0] });
    else if (state.attempt < 3) state = await rpc('/answer', { token: state.token, refresh: true });
    else state = await rpc('/cancel', { token: state.token });
  }
  console.log(JSON.stringify(state));
  process.exitCode = state.stage === 'result' && state.report?.tunnel?.result === 'school_timetable_received' &&
    state.report?.cleanup === 'school_confirmed' ? 0 : 1;
} catch {
  credentials && (credentials.account = '', credentials.password = '');
  if (rpc && state?.token) await rpc('/cancel', { token: state.token }).catch(() => {});
  console.log(JSON.stringify({ result: 'probe_local_failed' }));
  process.exitCode = 1;
}
