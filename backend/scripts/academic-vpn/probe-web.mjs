/** Checks the school's own HTTPS WebVPN resource path, with no native VPN client. */
import { constants, privateDecrypt } from 'node:crypto';
import { readFile, unlink } from 'node:fs/promises';
import https from 'node:https';
import { probe } from './probe-auth.mjs';

const [keyPath, sealed] = process.argv.slice(2);

function page(path, session, cookies) {
  return new Promise(resolve => {
    const request = https.get({ hostname: 'vpn1.bjfu.edu.cn',
      path: `/web/1/http/0/newjwxt.bjfu.edu.cn${path}`, timeout: 10000,
      headers: { Cookie: [`TWFID=${session}`, ...cookies.values()].join('; '), 'User-Agent': 'Mozilla/5.0' } }, response => {
      for (const value of response.headers['set-cookie'] ?? []) {
        const pair = value.split(';')[0];
        cookies.set(pair.split('=')[0], pair);
      }
      const chunks = [];
      let size = 0;
      response.on('data', chunk => {
        size += chunk.length;
        if (size > 512 * 1024) response.destroy(); else chunks.push(chunk);
      });
      response.on('error', () => resolve({ path, result: 'response_failed' }));
      response.on('end', () => {
        const body = Buffer.concat(chunks);
        resolve({ path, status: response.statusCode, bytes: body.length,
          schoolLoginPage: body.includes(Buffer.from('Logon.do')),
          keyShape: path.includes('flag=sess') ? /^[^#\s]+#[^#\s]+$/.test(body.toString()) : undefined,
          image: body[0] === 0xff && body[1] === 0xd8,
          gatewayDenied: /access denied|无权限|没有权限|禁止访问|资源不存在/i.test(body.toString()) });
      });
    });
    request.on('timeout', () => request.destroy());
    request.on('error', () => resolve({ path, result: 'request_failed' }));
  });
}

let plaintext;
try {
  const key = await readFile(keyPath);
  await unlink(keyPath);
  plaintext = privateDecrypt({ key, padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, Buffer.from(sealed, 'base64'));
  key.fill(0);
  const credentials = JSON.parse(plaintext.toString('utf8'));
  plaintext.fill(0);
  const report = await probe(credentials, undefined, async ({ session }) => {
    const cookies = new Map();
    const pages = [];
    for (const path of ['/', '/Logon.do?method=logon&flag=sess', '/verifycode.servlet']) pages.push(await page(path, session, cookies));
    cookies.clear();
    return { mode: 'school_webvpn', pages };
  });
  console.log(JSON.stringify(report));
  process.exitCode = report.cleanup === 'school_confirmed' && report.tunnel?.pages?.[0]?.schoolLoginPage &&
    report.tunnel?.pages?.[1]?.keyShape && report.tunnel?.pages?.[2]?.image ? 0 : 1;
} catch {
  plaintext?.fill(0);
  console.log(JSON.stringify({ result: 'vpn_web_probe_failed' }));
  process.exitCode = 1;
}
