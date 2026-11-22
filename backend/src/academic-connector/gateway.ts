import { constants, createPublicKey, publicEncrypt } from 'node:crypto';
import https from 'node:https';
import { ApiError } from '../http';

const gatewayOrigin = 'https://vpn1.bjfu.edu.cn';
export const schoolOrigin = 'http://newjwxt.bjfu.edu.cn';
const resourcePrefix = '/web/1/http/0/newjwxt.bjfu.edu.cn';
const maximumResponseBytes = 2 * 1024 * 1024;

export interface GatewayResponse {
  status: number;
  body: Buffer;
  headers: { contentType?: string; location?: string; setCookie?: string[] };
}
export type GatewayTransport = (path: string, options: {
  method: 'GET' | 'POST'; body?: Buffer; cookie?: string; referer?: string; signal?: AbortSignal;
}) => Promise<GatewayResponse>;
export interface AcademicRequest { method: 'GET' | 'POST'; path: string; bodyBase64?: string; referer?: string; cookies?: Record<string, string> }
export interface AcademicResponse { status: number; url: string; contentType: string; bodyBase64: string; cookies: Record<string, string> }

function failure(code: string, message: string, retryable = false, status = 502): ApiError {
  return new ApiError(status, code, message, retryable);
}
function xml(xml: string, tag: string): string | undefined {
  return xml.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`))?.[1].replace(/^<!\[CDATA\[([\s\S]*)\]\]>$/, '$1');
}

export function validateAcademicRequest(value: Record<string, unknown>): AcademicRequest {
  if (value.method !== 'GET' && value.method !== 'POST') throw failure('academic_request_denied', '不支持这项教务请求。', false, 400);
  if (typeof value.path !== 'string' || value.path.length > 4096 || !value.path.startsWith('/') ||
      /[\\\u0000-\u0020]/.test(value.path) || /%2f|%5c|%2e|%00/i.test(value.path)) {
    throw failure('academic_request_denied', '教务请求地址无效。', false, 400);
  }
  let url: URL;
  try { url = new URL(value.path, schoolOrigin); } catch { throw failure('academic_request_denied', '教务请求地址无效。', false, 400); }
  const allowed = new Set(['/', '/Logon.do', '/verifycode.servlet', '/jsxsd/framework/xsMain.jsp',
    '/jsxsd/framework/xSMain.jsp', '/jsxsd/xskb/xskb_list.do', '/jsxsd/xskb/xskb_query.do']);
  // A transport scoped to timetable/login never becomes an arbitrary school or Internet proxy.
  if (url.origin !== schoolOrigin || value.path.split('?')[0] !== url.pathname || !allowed.has(url.pathname) ||
      (url.pathname === '/Logon.do' && (url.searchParams.getAll('method').length !== 1 ||
        url.searchParams.get('method') !== 'logon' || [...url.searchParams.keys()].some(key => !['method', 'flag'].includes(key)) ||
        url.searchParams.getAll('flag').length > 1 || (url.searchParams.has('flag') && url.searchParams.get('flag') !== 'sess'))) ||
      (value.method === 'POST' && !['/Logon.do', '/jsxsd/xskb/xskb_list.do', '/jsxsd/xskb/xskb_query.do'].includes(url.pathname))) {
    throw failure('academic_request_denied', '这项教务资源暂不支持 VPN 同步。', false, 400);
  }
  if (value.bodyBase64 !== undefined && (typeof value.bodyBase64 !== 'string' || value.bodyBase64.length > 65536 ||
      Buffer.from(value.bodyBase64, 'base64').toString('base64') !== value.bodyBase64 || value.method !== 'POST')) {
    throw failure('academic_request_denied', '教务请求内容无效。', false, 400);
  }
  if (value.referer !== undefined) {
    if (typeof value.referer !== 'string' || value.referer.length > 4096) throw failure('academic_request_denied', '教务来源地址无效。', false, 400);
    try {
      const referer = new URL(value.referer);
      if (referer.origin !== schoolOrigin || referer.username || referer.password) throw new Error();
    } catch { throw failure('academic_request_denied', '教务来源地址无效。', false, 400); }
  }
  return { method: value.method, path: url.pathname + url.search,
    bodyBase64: value.bodyBase64 as string | undefined, referer: value.referer as string | undefined,
    cookies: value.cookies === undefined ? undefined : validateCookies(value.cookies) };
}

export function validateCookies(value: unknown): Record<string, string> {
  if (value === undefined) return {};
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw failure('invalid_request', '教务会话格式无效。', false, 400);
  const entries = Object.entries(value);
  if (entries.length > 64 || JSON.stringify(value).length > 32768 || entries.some(([name, item]) =>
    !name || name.length > 128 || /[\s;=\u0000-\u001f\u007f]/.test(name) || name.toLowerCase() === 'twfid' ||
    typeof item !== 'string' || item.length > 8192 || /[;\u0000-\u001f\u007f]/.test(item))) {
    throw failure('invalid_request', '教务会话格式无效。', false, 400);
  }
  return Object.fromEntries(entries) as Record<string, string>;
}

export const httpsTransport: GatewayTransport = (path, options) => new Promise((resolve, reject) => {
  const headers: Record<string, string> = { 'User-Agent': 'Mozilla/5.0', 'Cache-Control': 'no-cache', Pragma: 'no-cache' };
  if (options.cookie) headers.Cookie = options.cookie;
  if (options.referer) headers.Referer = options.referer;
  if (options.body !== undefined) headers['Content-Type'] = 'application/x-www-form-urlencoded';
  const request = https.request(new URL(path, gatewayOrigin), { method: options.method, headers,
    signal: options.signal, timeout: 10000 }, response => {
    const chunks: Buffer[] = []; let size = 0;
    response.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > maximumResponseBytes) response.destroy(failure('academic_response_too_large', '学校返回的内容过大，请稍后重试。'));
      else chunks.push(chunk);
    });
    response.on('error', reject);
    response.on('end', () => resolve({ status: response.statusCode ?? 502, body: Buffer.concat(chunks), headers: {
      contentType: response.headers['content-type'], location: response.headers.location, setCookie: response.headers['set-cookie'],
    } }));
  });
  request.on('timeout', () => request.destroy(failure('vpn_timeout', '连接北林 VPN 超时，请重试或改用校园网直连。', true)));
  request.on('error', error => {
    if (error instanceof ApiError) reject(error);
    else reject(failure(options.signal?.aborted ? 'academic_cancelled' : 'vpn_unavailable',
      options.signal?.aborted ? '本次同步已取消。' : '暂时无法连接北林 VPN，请重试或改用校园网直连。', !options.signal?.aborted));
  });
  request.end(options.body);
});

export class BJFUWebVpn {
  private session: string | undefined;
  private schoolCookies: Map<string, string>;
  private closing: Promise<boolean> | undefined;
  private closed = false;
  private authenticated = false;
  private authentication: Promise<void> | undefined;
  constructor(private readonly send: GatewayTransport = httpsTransport, cookies: Record<string, string> = {}) {
    this.schoolCookies = new Map(Object.entries(validateCookies(cookies)));
  }

  authenticate(account: string, password: string, signal?: AbortSignal): Promise<void> {
    if (this.closed || this.authentication) return Promise.reject(failure('academic_operation_expired', '本次连接已结束，请重新同步。', true, 410));
    this.authentication = this.authenticateOnce(account, password, signal);
    return this.authentication;
  }

  private async authenticateOnce(account: string, password: string, signal?: AbortSignal): Promise<void> {
    const initial = await this.send('/por/login_auth.csp?apiversion=1', { method: 'GET', signal });
    if (initial.status !== 200) throw failure('vpn_unavailable', '北林 VPN 暂时不可用，请稍后重试。', true);
    const document = initial.body.toString('utf8');
    const session = xml(document, 'TwfID');
    if (!session || !/^[A-Za-z0-9_-]{1,256}$/.test(session)) throw failure('vpn_response_invalid', '北林 VPN 返回了无法识别的登录信息。');
    this.session = session;
    if (this.closed || signal?.aborted) throw failure('academic_cancelled', '本次同步已取消。');
    if (xml(document, 'RndImg') === '1') throw failure('vpn_extra_authentication_required', '北林 VPN 要求额外验证，请改用校园网直连。', false, 422);
    const modulus = xml(document, 'RSA_ENCRYPT_KEY'), exponent = xml(document, 'RSA_ENCRYPT_EXP') ?? '65537';
    const csrf = xml(document, 'CSRF_RAND_CODE');
    if (!modulus || !/^[a-f0-9]{256,1024}$/i.test(modulus) || modulus.length % 2 || !/^\d{1,10}$/.test(exponent) ||
        BigInt(exponent) < 3n || BigInt(exponent) > 0xffffffffn || BigInt(exponent) % 2n === 0n || !csrf || csrf.length > 256) {
      throw failure('vpn_response_invalid', '北林 VPN 返回了无效的登录密钥。');
    }
    let hex = BigInt(exponent).toString(16); if (hex.length % 2) hex = `0${hex}`;
    const key = createPublicKey({ format: 'jwk', key: { kty: 'RSA', n: Buffer.from(modulus, 'hex').toString('base64url'), e: Buffer.from(hex, 'hex').toString('base64url') } });
    const plaintext = Buffer.from(`${password}_${csrf}`);
    let encrypted: string;
    try { encrypted = publicEncrypt({ key, padding: constants.RSA_PKCS1_PADDING }, plaintext).toString('hex'); }
    finally { plaintext.fill(0); }
    const body = Buffer.from(new URLSearchParams({ svpn_name: account, svpn_password: encrypted,
      svpn_req_randcode: csrf, svpn_rand_code: '', mitm: '' }).toString());
    let response: GatewayResponse;
    try { response = await this.send('/por/login_psw.csp?anti_replay=1&encrypt=1&type=cs', { method: 'POST', cookie: `TWFID=${session}`, body, signal }); }
    finally { body.fill(0); }
    if (response.status !== 200) throw failure('vpn_unavailable', '北林 VPN 登录服务暂时不可用。', true);
    const result = response.body.toString('utf8'), updated = xml(result, 'TwfID');
    if (updated) {
      if (!/^[A-Za-z0-9_-]{1,256}$/.test(updated)) throw failure('vpn_response_invalid', '北林 VPN 返回了无效的会话。');
      this.session = updated;
    }
    const next = xml(result, 'NextAuth'), service = xml(result, 'NextService');
    if ((next !== undefined && next !== '-1') || ['auth/sms', 'auth/token'].includes(service ?? '')) {
      throw failure('vpn_extra_authentication_required', '北林 VPN 要求额外验证，请改用校园网直连。', false, 422);
    }
    if (xml(result, 'Result') !== '1') throw failure('vpn_authentication_rejected', '北林 VPN 登录未成功，请检查 VPN 账号、密码及账号使用状态。', false, 401);
    this.authenticated = true;
  }

  async request(input: AcademicRequest, signal?: AbortSignal): Promise<AcademicResponse> {
    if (this.closed || !this.authenticated || !this.session) throw failure('academic_operation_expired', '本次连接已结束，请重新同步。', true, 410);
    let request = validateAcademicRequest(input as unknown as Record<string, unknown>);
    if (request.cookies !== undefined) this.schoolCookies = new Map(Object.entries(request.cookies));
    for (let redirects = 0; redirects <= 6; redirects++) {
      const body = request.bodyBase64 === undefined ? undefined : Buffer.from(request.bodyBase64, 'base64');
      let response: GatewayResponse;
      try { response = await this.send(resourcePrefix + request.path, { method: request.method, body,
        cookie: [`TWFID=${this.session}`, ...[...this.schoolCookies].map(([name, value]) => `${name}=${value}`)].join('; '),
        referer: gatewayOrigin + resourcePrefix + (request.referer ? new URL(request.referer).pathname + new URL(request.referer).search : '/'), signal }); }
      finally { body?.fill(0); }
      if (this.closed || signal?.aborted) throw failure('academic_cancelled', '本次同步已取消。');
      for (const value of response.headers.setCookie ?? []) {
        const pair = value.split(';')[0], separator = pair.indexOf('=');
        if (separator > 0 && pair.slice(0, separator).toLowerCase() !== 'twfid') {
          const cookie = validateCookies({ [pair.slice(0, separator)]: pair.slice(separator + 1) });
          for (const [name, content] of Object.entries(cookie)) this.schoolCookies.set(name, content);
        }
      }
      validateCookies(Object.fromEntries(this.schoolCookies));
      if ([301, 302, 303, 307, 308].includes(response.status) && response.headers.location) {
        const location = new URL(response.headers.location, gatewayOrigin + resourcePrefix + request.path);
        let path: string;
        if (location.origin === schoolOrigin) path = location.pathname + location.search;
        else if (location.origin === gatewayOrigin && location.pathname.startsWith(resourcePrefix + '/')) path = location.pathname.slice(resourcePrefix.length) + location.search;
        else throw failure('academic_redirect_denied', '学校返回了不支持的跳转地址。');
        request = validateAcademicRequest({ method: [307, 308].includes(response.status) ? request.method : 'GET', path,
          bodyBase64: [307, 308].includes(response.status) ? request.bodyBase64 : undefined });
        continue;
      }
      return { status: response.status, url: schoolOrigin + request.path, contentType: response.headers.contentType ?? 'application/octet-stream',
        bodyBase64: response.body.toString('base64'), cookies: Object.fromEntries(this.schoolCookies) };
    }
    throw failure('academic_redirect_denied', '学校页面跳转次数过多，请稍后重试。');
  }

  close(): Promise<boolean> {
    if (this.closing) return this.closing;
    this.closed = true;
    this.closing = (async () => {
      // Settle authentication before logout so a late response cannot resurrect a released session.
      try { await this.authentication; } catch { /* Logout any session acquired before authentication failed. */ }
      const session = this.session; this.session = undefined; this.schoolCookies.clear();
      if (!session) return true;
      try {
        const response = await this.send('/por/logout.csp', { method: 'POST', cookie: `TWFID=${session}`, body: Buffer.alloc(0), signal: AbortSignal.timeout(5000) });
        return response.status === 200 && (xml(response.body.toString(), 'ErrorCode') === '1' || xml(response.body.toString(), 'Result') === '1');
      } catch { return false; }
    })();
    return this.closing;
  }
}
