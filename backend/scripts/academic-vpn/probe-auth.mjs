/** One-shot BJFU VPN authentication probe. Never prints credentials or school bodies. */
import { constants, createPublicKey, privateDecrypt, publicEncrypt } from 'node:crypto';
import { readFile, unlink } from 'node:fs/promises';
import https from 'node:https';
import { pathToFileURL } from 'node:url';

const origin = 'https://vpn1.bjfu.edu.cn';

export function xmlValue(xml, tag) {
  const match = xml.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
  return match?.[1].replace(/^<!\[CDATA\[([\s\S]*)\]\]>$/, '$1') ?? null;
}

export function schoolPublicKey(xml) {
  const modulus = xmlValue(xml, 'RSA_ENCRYPT_KEY');
  const exponent = xmlValue(xml, 'RSA_ENCRYPT_EXP') ?? '65537';
  if (!modulus || !/^[0-9a-f]{256,1024}$/i.test(modulus) || modulus.length % 2 || !/^\d+$/.test(exponent)) {
    throw new Error('vpn_invalid_login_key');
  }
  const exponentNumber = BigInt(exponent);
  if (exponentNumber < 3n || exponentNumber > 0xffffffffn || exponentNumber % 2n === 0n) {
    throw new Error('vpn_invalid_login_key');
  }
  let exponentHex = exponentNumber.toString(16);
  if (exponentHex.length % 2) exponentHex = `0${exponentHex}`;
  return createPublicKey({ key: {
    kty: 'RSA', n: Buffer.from(modulus, 'hex').toString('base64url'),
    e: Buffer.from(exponentHex, 'hex').toString('base64url'),
  }, format: 'jwk' });
}

export function authenticationResult(xml) {
  const next = xmlValue(xml, 'NextAuth');
  const service = xmlValue(xml, 'NextService');
  if (next === '2' || service === 'auth/sms') return 'vpn_sms_required';
  if (next === '7' || service === 'auth/token') return 'vpn_totp_required';
  if (next === '0') return 'vpn_certificate_required';
  if (next !== null && next !== '-1') return 'vpn_authentication_unsupported';
  return xmlValue(xml, 'Result') === '1' ? 'authenticated' : 'vpn_authentication_rejected';
}

function request(path, { cookie, body } = {}) {
  return new Promise((resolve, reject) => {
    const headers = { 'User-Agent': 'EasyConnect_Linux_Ubuntu' };
    if (cookie) headers.Cookie = `TWFID=${cookie}`;
    if (body !== undefined) headers['Content-Type'] = 'application/x-www-form-urlencoded';
    const req = https.request(new URL(path, origin), {
      method: body !== undefined ? 'POST' : 'GET', headers, timeout: 10000,
    }, response => {
      const chunks = [];
      let size = 0;
      response.on('data', chunk => {
        size += chunk.length;
        if (size > 2 * 1024 * 1024) response.destroy(new Error('vpn_response_too_large'));
        else chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => {
        if (response.statusCode !== 200) reject(new Error('vpn_unexpected_http_status'));
        else resolve(Buffer.concat(chunks).toString('utf8'));
      });
    });
    req.on('timeout', () => req.destroy(new Error('vpn_request_timeout')));
    req.on('error', reject);
    req.end(body);
  });
}

export async function probe(credentials, send = request, onAuthenticated) {
  let cookie;
  const report = { authenticated: false, cleanup: 'not_needed' };
  try {
    if (typeof credentials.account !== 'string' || !credentials.account ||
        typeof credentials.password !== 'string' || !credentials.password) throw new Error('vpn_credentials_missing');
    const initial = await send('/por/login_auth.csp?apiversion=1');
    cookie = xmlValue(initial, 'TwfID');
    if (!cookie || !/^[a-zA-Z0-9_-]{1,256}$/.test(cookie)) throw new Error('vpn_invalid_session');
    report.serverVersion = xmlValue(initial, 'VPNVERSION')?.match(/^[A-Za-z0-9.]{1,32}$/)?.[0] ?? 'unknown';
    if (xmlValue(initial, 'RndImg') === '1') {
      report.result = 'vpn_captcha_required';
      return report;
    }
    const csrf = xmlValue(initial, 'CSRF_RAND_CODE');
    if (!csrf || csrf.length > 256) throw new Error('vpn_invalid_login_key');
    const password = publicEncrypt({ key: schoolPublicKey(initial), padding: constants.RSA_PKCS1_PADDING },
      Buffer.from(`${credentials.password}_${csrf}`, 'utf8')).toString('hex');
    const body = new URLSearchParams({ svpn_rand_code: '', mitm: '', svpn_req_randcode: csrf,
      svpn_name: credentials.account, svpn_password: password }).toString();
    const response = await send('/por/login_psw.csp?anti_replay=1&encrypt=1&type=cs', { cookie, body });
    const updated = xmlValue(response, 'TwfID');
    if (updated) {
      if (!/^[a-zA-Z0-9_-]{1,256}$/.test(updated)) throw new Error('vpn_invalid_session');
      cookie = updated;
    }
    report.result = authenticationResult(response);
    report.authenticated = report.result === 'authenticated';
    const code = xmlValue(response, 'ErrorCode');
    if (code && /^-?\d{1,10}$/.test(code)) report.schoolErrorCode = code;
    if (report.authenticated) {
      const resources = await send('/por/rclist.csp', { cookie });
      report.resourceResponseBytes = Buffer.byteLength(resources);
      report.includesTimetableHost = resources.includes('newjwxt.bjfu.edu.cn');
      report.academicResourceMentions = (resources.match(/教务/g) ?? []).length;
      report.resourceTagCounts = Object.fromEntries(['Resource', 'Rclist', 'IP', 'Host', 'Tcp', 'Web', 'L3', 'DNS']
        .map(tag => [tag, (resources.match(new RegExp(`<${tag}(?:\\s|>)`, 'gi')) ?? []).length]));
      report.resourceTypes = Object.fromEntries([...resources.matchAll(/<Rc\s[^>]*\btype="(\d+)"/g)]
        .map(match => match[1]).reduce((counts, type) => counts.set(type, (counts.get(type) ?? 0) + 1), new Map()));
      report.allocatesVirtualIP = /<Other\s[^>]*\ballocateVip="1"/.test(resources);
      report.timetableResourceTypes = [...resources.matchAll(/<Rc\s[^>]*>/g)]
        .filter(match => match[0].includes('newjwxt.bjfu.edu.cn'))
        .map(match => match[0].match(/\btype="(\d+)"/)?.[1]).filter(Boolean);
      if (onAuthenticated) report.tunnel = await onAuthenticated({ session: cookie });
    }
  } catch (error) {
    report.result = /^vpn_[a-z_]+$/.test(error.message) ? error.message : 'vpn_probe_failed';
    report.errorType = error.name;
    if (typeof error.code === 'string' && /^[A-Z0-9_]{1,64}$/.test(error.code)) report.transportCode = error.code;
  } finally {
    credentials.password = '';
    credentials.account = '';
    if (cookie) {
      try {
        const response = await send('/por/logout.csp', { cookie, body: '' });
        report.logoutCode = xmlValue(response, 'ErrorCode')?.match(/^-?\d{1,10}$/)?.[0] ?? null;
        report.cleanup = xmlValue(response, 'Result') === '1' || xmlValue(response, 'ErrorCode') === '1'
          ? 'school_confirmed' : 'response_received_unconfirmed';
      } catch { report.cleanup = 'logout_failed'; }
    }
  }
  return report;
}

async function main() {
  const [privateKeyPath, ciphertext] = process.argv.slice(2);
  let clear;
  try {
    const key = await readFile(privateKeyPath);
    await unlink(privateKeyPath);
    clear = privateDecrypt({ key, padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' },
      Buffer.from(ciphertext, 'base64'));
    key.fill(0);
    const credentials = JSON.parse(clear.toString('utf8'));
    clear.fill(0);
    const report = await probe(credentials);
    console.log(JSON.stringify(report));
    process.exitCode = report.authenticated ? 0 : 1;
  } catch {
    clear?.fill(0);
    console.log(JSON.stringify({ result: 'vpn_probe_input_failed' }));
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
