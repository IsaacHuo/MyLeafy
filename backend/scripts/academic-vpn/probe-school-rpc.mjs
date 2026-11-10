/** Ephemeral loopback-only school probe. All bridge messages are end-to-end encrypted. */
import { constants, createCipheriv, createDecipheriv, generateKeyPairSync, privateDecrypt, publicEncrypt, randomBytes } from 'node:crypto';
import { writeFile, unlink } from 'node:fs/promises';
import http from 'node:http';
import https from 'node:https';
import { pathToFileURL } from 'node:url';
import { probe } from './probe-auth.mjs';

export function seal(value, publicKey) {
  const key = randomBytes(32), iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(value)), cipher.final()]);
  const wrapped = publicEncrypt({ key: publicKey, padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, key);
  key.fill(0);
  return { key: wrapped.toString('base64'), iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: data.toString('base64') };
}

export function unseal(envelope, privateKey) {
  const key = privateDecrypt({ key: privateKey, padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, Buffer.from(envelope.key, 'base64'));
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
  const bytes = Buffer.concat([decipher.update(Buffer.from(envelope.data, 'base64')), decipher.final()]);
  key.fill(0);
  try { return JSON.parse(bytes.toString()); } finally { bytes.fill(0); }
}

export function encodeSchoolLogin(key, account, password) {
  let [secret, shifts, extra] = key.trim().split('#');
  if (!secret || /[<>]/.test(secret) || !/^\d+$/.test(shifts ?? '') || extra !== undefined) throw new Error('school_invalid_key');
  const input = account + '%%%' + password;
  let output = '';
  for (let i = 0; i < input.length; i++) {
    output += input[i];
    if (i < 20 && i < shifts.length) {
      const count = Math.min(Number(shifts[i]), secret.length);
      output += secret.slice(0, count); secret = secret.slice(count);
    }
  }
  // Browser forms replace unpaired UTF-16 units after the school's interleaving.
  return output.toWellFormed();
}

function schoolClient(session) {
  const cookies = new Map();
  return async function request(path, body, redirects = 0) {
    if (!path.startsWith('/') || path.startsWith('//') || redirects > 6) throw new Error('school_invalid_redirect');
    return new Promise((resolve, reject) => {
      const headers = { Cookie: [`TWFID=${session}`, ...cookies.values()].join('; '), 'User-Agent': 'Mozilla/5.0',
        'Cache-Control': 'no-cache', Pragma: 'no-cache',
        Referer: 'https://vpn1.bjfu.edu.cn/web/1/http/0/newjwxt.bjfu.edu.cn/' };
      if (body !== undefined) headers['Content-Type'] = 'application/x-www-form-urlencoded';
      const req = https.request({ hostname: 'vpn1.bjfu.edu.cn', path: `/web/1/http/0/newjwxt.bjfu.edu.cn${path}`,
        method: body !== undefined ? 'POST' : 'GET', headers, timeout: 10000 }, response => {
        for (const cookie of response.headers['set-cookie'] ?? []) {
          const pair = cookie.split(';')[0], name = pair.split('=')[0];
          if (name.toLowerCase() !== 'twfid') cookies.set(name, pair);
        }
        if ([301, 302, 303, 307, 308].includes(response.statusCode) && response.headers.location) {
          response.resume();
          const location = response.headers.location;
          let next;
          try {
            const url = new URL(location, 'https://vpn1.bjfu.edu.cn/web/1/http/0/newjwxt.bjfu.edu.cn' + path);
            const prefix = '/web/1/http/0/newjwxt.bjfu.edu.cn';
            if (url.hostname === 'newjwxt.bjfu.edu.cn' && url.protocol === 'http:') next = url.pathname + url.search;
            else if (url.hostname === 'vpn1.bjfu.edu.cn' && url.protocol === 'https:' && url.pathname.startsWith(prefix + '/')) next = url.pathname.slice(prefix.length) + url.search;
            else throw new Error('school_invalid_redirect');
          } catch { reject(new Error('school_invalid_redirect')); return; }
          request(next, [307, 308].includes(response.statusCode) ? body : undefined, redirects + 1).then(resolve, reject);
          return;
        }
        const chunks = []; let size = 0;
        response.on('data', chunk => { size += chunk.length; if (size > 2 * 1024 * 1024) response.destroy(); else chunks.push(chunk); });
        response.on('error', reject);
        response.on('end', () => resolve({ status: response.statusCode, bytes: Buffer.concat(chunks) }));
      });
      req.on('timeout', () => req.destroy(new Error('school_timeout')));
      req.on('error', reject); req.end(body);
    });
  };
}

async function startServer(metadataPath, clientPublicKey) {
  const keys = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const token = randomBytes(24).toString('hex');
  let started = false, flow, decision, replyTarget;
  const respond = (res, value) => { if (res && !res.writableEnded) res.end(JSON.stringify(seal(value, clientPublicKey))); };
  const server = http.createServer(async (req, res) => {
    try {
      if (req.method !== 'POST') throw new Error('invalid_request');
      const chunks = []; let size = 0;
      for await (const chunk of req) { size += chunk.length; if (size > 16000) throw new Error('oversize'); chunks.push(chunk); }
      const payload = unseal(JSON.parse(Buffer.concat(chunks).toString()), keys.privateKey);
      if (req.url === '/start' && !started) {
        started = true; replyTarget = res;
        flow = probe(payload, undefined, async ({ session }) => {
          const request = schoolClient(session);
          await request('/');
          let authenticated = false;
          for (let attempt = 0; attempt < 3; attempt++) {
            const key = (await request('/Logon.do?method=logon&flag=sess')).bytes.toString().trim();
            encodeSchoolLogin(key, '', ''); // Reject invalid school keys before credentials are submitted.
            const image = await request('/verifycode.servlet');
            const waiting = new Promise((resolve, reject) => { decision = { resolve, reject }; });
            respond(replyTarget, { stage: 'captcha', token, image: image.bytes.toString('base64'), attempt: attempt + 1 });
            const action = await waiting;
            if (action.refresh) continue;
            const effectiveKey = (await request('/Logon.do?method=logon&flag=sess', '')).bytes.toString().trim();
            const body = new URLSearchParams({ useDogCode: '', encoded: encodeSchoolLogin(effectiveKey, payload.account, payload.password), RANDOMCODE: action.captcha }).toString();
            const login = (await request('/Logon.do?method=logon', body)).bytes.toString();
            if (/验证码[^<\n]{0,20}(错误|不正确)/.test(login)) {
              if (attempt < 2) continue;
              return { result: 'school_captcha_rejected' };
            }
            if (/(密码|口令)[^<\n]{0,20}(错误|不正确)/.test(login)) return { result: 'school_credentials_rejected' };
            const verified = (await request('/jsxsd/framework/xsMain.jsp')).bytes.toString();
            authenticated = !/name=["']RANDOMCODE["']|verifycode\.servlet/.test(verified) && /退出系统|安全退出|个人信息|学生课表|成绩查询/.test(verified);
            if (!authenticated) return { result: 'school_authentication_unconfirmed' };
            break;
          }
          if (!authenticated) return { result: 'school_captcha_unreliable' };
          for (const path of ['/jsxsd/xskb/xskb_list.do', '/jsxsd/xskb/xskb_list.do?xnxq01id=2026-2027-1']) {
            const table = await request(path), html = table.bytes.toString();
            if (/id=["']kbtable["']|class=["'][^"']*kbcontent/.test(html)) {
              const selected = html.match(/<option\b(?=[^>]*\bselected)(?=[^>]*\bvalue=["']([^"']+)["'])[^>]*>/i)?.[1];
              return { result: 'school_timetable_received', schoolAuthenticated: true, responseBytes: table.bytes.length,
                selectedSemester: selected?.match(/^\d{4}-\d{4}-[12]$/)?.[0] ?? null,
                arrangementBlocks: (html.match(/class=["'][^"']*kbcontent/g) ?? []).length };
            }
          }
          return { result: 'school_authenticated_timetable_unresolved', schoolAuthenticated: true };
        });
        flow.then(report => { respond(replyTarget, { stage: 'result', report }); setTimeout(shutdown, 500); });
      } else if (req.url === '/answer' && payload.token === token && decision) {
        if (!payload.refresh && !/^[a-z0-9]{4}$/.test(payload.captcha ?? '')) throw new Error('invalid_captcha');
        replyTarget = res; const pending = decision; decision = null; pending.resolve(payload);
      } else if (req.url === '/cancel' && payload.token === token) {
        replyTarget = res; decision?.reject(new Error('school_cancelled'));
      } else throw new Error('invalid_request');
    } catch { respond(res, { stage: 'error', code: 'probe_request_rejected' }); }
  });
  async function shutdown() {
    decision?.reject(new Error('school_cancelled'));
    await flow?.catch(() => {});
    server.close(); await unlink(metadataPath).catch(() => {});
    process.exit(0);
  }
  process.once('SIGTERM', shutdown); process.once('SIGINT', shutdown);
  setTimeout(shutdown, 115000).unref();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  await writeFile(metadataPath, JSON.stringify({ port: server.address().port, publicKey: keys.publicKey.export({ type: 'spki', format: 'pem' }) }), { mode: 0o600, flag: 'wx' });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await startServer(process.argv[2], Buffer.from(process.argv[3], 'base64').toString());
}
