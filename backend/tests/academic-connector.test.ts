import { generateKeyPairSync } from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createAcademicConnector } from '../src/academic-connector/app';
import { BJFUWebVpn, type GatewayResponse, type GatewayTransport, validateAcademicRequest, validateCookies } from '../src/academic-connector/gateway';
import { AcademicOperations, type AcademicGateway } from '../src/academic-connector/operations';

const response = (body: string, status = 200, headers: GatewayResponse['headers'] = {}): GatewayResponse => ({ status, body: Buffer.from(body), headers });
const key = generateKeyPairSync('rsa', { modulusLength: 1024 }).publicKey.export({ format: 'jwk' });
const initial = `<Auth><TwfID>synthetic-vpn-session</TwfID><RndImg>0</RndImg><RSA_ENCRYPT_KEY>${Buffer.from(key.n!, 'base64url').toString('hex')}</RSA_ENCRYPT_KEY><RSA_ENCRYPT_EXP>65537</RSA_ENCRYPT_EXP><CSRF_RAND_CODE>synthetic-csrf</CSRF_RAND_CODE></Auth>`;
const schoolResponse = { status: 200, url: 'http://newjwxt.bjfu.edu.cn/verifycode.servlet', contentType: 'image/jpeg', bodyBase64: 'YWJj', cookies: { JSESSIONID: 'synthetic-school-cookie' } };
const inputs = (account = 'synthetic-account') => ({ vpnAccount: account, vpnPassword: 'synthetic-password' });
const cleanups: Array<() => Promise<unknown>> = [];
afterEach(async () => { for (const cleanup of cleanups.splice(0)) await cleanup(); });
function operations(gateway: AcademicGateway, options: ConstructorParameters<typeof AcademicOperations>[0] = {}) {
  const service = new AcademicOperations({ gateway: () => gateway, ...options });
  cleanups.push(() => service.shutdown()); return service;
}
function fakeGateway(): AcademicGateway {
  return { authenticate: vi.fn(async () => {}), request: vi.fn(async () => structuredClone(schoolResponse)), close: vi.fn(async () => true) };
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; });
  return { promise, resolve };
}

describe('fixed school resource transport', () => {
  it('rejects proxy escapes and unsupported resources before network access', () => {
    for (const path of ['//example.test/', '/\\example.test/', '/jsxsd/../Logon.do?method=logon',
      '/jsxsd/%2e%2e/Logon.do?method=logon', '/%2f%2fexample.test', '/jsxsd/kscj/cjcx_list', '/Logon.do?method=delete',
      '/Logon.do?method=logon&method=delete', '/Logon.do?method=logon&flag=other']) {
      expect(() => validateAcademicRequest({ method: 'GET', path })).toThrow();
    }
    expect(() => validateAcademicRequest({ method: 'POST', path: '/verifycode.servlet', bodyBase64: '' })).toThrow();
    expect(() => validateAcademicRequest({ method: 'POST', path: '/Logon.do?method=logon', bodyBase64: 'not-base64!!' })).toThrow();
    expect(() => validateAcademicRequest({ method: 'GET', path: '/', referer: 'https://example.test' })).toThrow();
    expect(() => validateCookies({ TWFID: 'cannot-replace-vpn-session' })).toThrow();
    expect(() => validateCookies({ JSESSIONID: 'invalid\r\nInjected: value' })).toThrow();
    expect(validateAcademicRequest({ method: 'POST', path: '/Logon.do?method=logon&flag=sess', bodyBase64: '' }).method).toBe('POST');
  });

  it('reuses school cookies, follows only allowed redirects and never exposes the VPN session', async () => {
    const sent: Array<{ path: string; cookie?: string; method: string }> = [];
    const transport: GatewayTransport = async (path, options) => {
      sent.push({ path, cookie: options.cookie, method: options.method });
      if (path.includes('login_auth')) return response(initial);
      if (path.includes('login_psw')) {
        const form = new URLSearchParams(options.body!.toString());
        expect(form.get('svpn_name')).toBe('synthetic-account');
        expect(form.get('svpn_password')).not.toContain('synthetic-password');
        return response('<Auth><Result>1</Result><NextAuth>-1</NextAuth></Auth>');
      }
      if (path.includes('logout')) return response('<Auth><ErrorCode>1</ErrorCode></Auth>');
      if (path.endsWith('/jsxsd/xskb/xskb_query.do')) return response('', 302, { location: '/web/1/http/0/newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do', setCookie: ['JSESSIONID=updated-school-cookie; Path=/', 'TWFID=must-not-replace-vpn'] });
      return response('<table id="kbtable"></table>', 200, { contentType: 'text/html' });
    };
    const gateway = new BJFUWebVpn(transport, { JSESSIONID: 'cached-school-cookie' });
    await gateway.authenticate('synthetic-account', 'synthetic-password');
    const result = await gateway.request({ method: 'POST', path: '/jsxsd/xskb/xskb_query.do', bodyBase64: '' });
    expect(sent[2].cookie).toContain('cached-school-cookie');
    expect(sent[3]).toMatchObject({ method: 'GET', cookie: 'TWFID=synthetic-vpn-session; JSESSIONID=updated-school-cookie' });
    expect(result.url).toBe('http://newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do');
    expect(JSON.stringify(result)).not.toContain('synthetic-vpn-session');
    expect(await gateway.close()).toBe(true);
    expect(await gateway.close()).toBe(true);
    expect(sent.filter(item => item.path.includes('logout'))).toHaveLength(1);
    await expect(gateway.request({ method: 'GET', path: '/' })).rejects.toMatchObject({ code: 'academic_operation_expired' });
  });

  it('does not follow a school redirect to another resource or host', async () => {
    const send = vi.fn<GatewayTransport>(async path => path.includes('login_auth') ? response(initial)
      : path.includes('login_psw') ? response('<Auth><Result>1</Result></Auth>')
      : response('', 302, { location: 'http://169.254.169.254/latest/meta-data/' }));
    const gateway = new BJFUWebVpn(send);
    await gateway.authenticate('synthetic', 'synthetic');
    await expect(gateway.request({ method: 'GET', path: '/' })).rejects.toMatchObject({ code: 'academic_redirect_denied' });
    expect(send).toHaveBeenCalledTimes(3);
  });

  it('honors an explicit empty candidate cookie jar when starting a fresh login challenge', async () => {
    const send = vi.fn<GatewayTransport>(async path => path.includes('login_auth') ? response(initial)
      : path.includes('login_psw') ? response('<Auth><Result>1</Result></Auth>') : response('synthetic-key'));
    const gateway = new BJFUWebVpn(send, { JSESSIONID: 'previous-candidate' });
    await gateway.authenticate('synthetic', 'synthetic');
    await gateway.request({ method: 'GET', path: '/Logon.do?method=logon&flag=sess', cookies: {} });
    expect(send.mock.calls.at(-1)?.[1].cookie).toBe('TWFID=synthetic-vpn-session');
  });

  it('gates extra authentication and does not retry a rejected password', async () => {
    for (const result of ['<Auth><Result>0</Result></Auth>', '<Auth><Result>1</Result><NextAuth>2</NextAuth></Auth>']) {
      const send = vi.fn<GatewayTransport>(async path => path.includes('login_auth') ? response(initial) : response(result));
      const gateway = new BJFUWebVpn(send);
      await expect(gateway.authenticate('synthetic', 'synthetic')).rejects.toBeInstanceOf(Error);
      expect(send).toHaveBeenCalledTimes(2);
      await expect(gateway.request({ method: 'GET', path: '/' })).rejects.toMatchObject({ code: 'academic_operation_expired' });
    }
  });

  it('settles a late authentication response before logging out its acquired session', async () => {
    const login = deferred<GatewayResponse>();
    const send = vi.fn<GatewayTransport>(async path => path.includes('login_auth') ? response(initial)
      : path.includes('login_psw') ? login.promise : response('<Auth><ErrorCode>1</ErrorCode></Auth>'));
    const gateway = new BJFUWebVpn(send);
    const authentication = gateway.authenticate('synthetic', 'synthetic');
    await Promise.resolve();
    const closing = gateway.close();
    login.resolve(response('<Auth><Result>1</Result><TwfID>updated-session</TwfID></Auth>'));
    await authentication; expect(await closing).toBe(true);
    expect(send.mock.calls.at(-1)?.[1]).toMatchObject({ method: 'POST', cookie: 'TWFID=updated-session' });
    await expect(gateway.request({ method: 'GET', path: '/' })).rejects.toMatchObject({ code: 'academic_operation_expired' });
  });
});

describe('operation ownership and release', () => {
  it('requires its exact token and separates concurrent students', async () => {
    const first = fakeGateway(), second = fakeGateway(); let created = 0;
    const service = operations(first, { gateway: () => created++ === 0 ? first : second });
    const a = await service.start(inputs('student-a')), b = await service.start(inputs('student-b'));
    await expect(service.request(a.operationID, b.operationToken, { method: 'GET', path: '/' })).rejects.toMatchObject({ code: 'academic_operation_not_found' });
    await service.request(a.operationID, a.operationToken, { method: 'GET', path: '/' });
    expect(first.request).toHaveBeenCalledOnce(); expect(second.request).not.toHaveBeenCalled();
    await service.close(a.operationID, a.operationToken); expect(service.count).toBe(1);
    expect(first.close).toHaveBeenCalledOnce(); expect(second.close).not.toHaveBeenCalled();
  });

  it('does not start a replacement for the same account while the previous logout is pending', async () => {
    const gateway = fakeGateway(), logout = deferred<boolean>(); gateway.close = vi.fn(() => logout.promise);
    const service = operations(gateway);
    const a = await service.start(inputs());
    const closing = service.close(a.operationID, a.operationToken);
    await expect(service.start(inputs())).rejects.toMatchObject({ code: 'academic_operation_busy' });
    logout.resolve(true); await closing;
    const next = await service.start(inputs()); expect(next.operationID).not.toBe(a.operationID);
  });

  it('releases on cancellation and rejects a delayed response', async () => {
    const gateway = fakeGateway(), pending = deferred<typeof schoolResponse>(); gateway.request = vi.fn(() => pending.promise);
    const service = operations(gateway), a = await service.start(inputs()), controller = new AbortController();
    const result = service.request(a.operationID, a.operationToken, { method: 'GET', path: '/' }, controller.signal);
    controller.abort(); pending.resolve(schoolResponse);
    await expect(result).rejects.toMatchObject({ code: 'academic_cancelled' });
    expect(service.count).toBe(0); expect(gateway.close).toHaveBeenCalledOnce();
  });

  it('expires idle sessions and reports unconfirmed logout', async () => {
    let now = 0;
    const gateway = fakeGateway(), service = operations(gateway, { now: () => now, idleMilliseconds: 10, lifetimeMilliseconds: 30 });
    const a = await service.start(inputs()); now = 11; await service.expire();
    expect(service.count).toBe(0); expect(gateway.close).toHaveBeenCalledOnce();
    await expect(service.request(a.operationID, a.operationToken, { method: 'GET', path: '/' })).rejects.toBeInstanceOf(Error);
    gateway.close = vi.fn(async () => false);
    const b = await service.start(inputs());
    await expect(service.close(b.operationID, b.operationToken)).rejects.toMatchObject({ code: 'vpn_logout_unconfirmed' });
    expect(service.count).toBe(0);
  });

  it('enforces the absolute deadline even when requests keep refreshing idle time', async () => {
    let now = 0;
    const gateway = fakeGateway(), service = operations(gateway, { now: () => now, idleMilliseconds: 10, lifetimeMilliseconds: 30 });
    const a = await service.start(inputs());
    for (now = 9; now < 30; now += 9) await service.request(a.operationID, a.operationToken, { method: 'GET', path: '/' });
    await expect(service.request(a.operationID, a.operationToken, { method: 'GET', path: '/' })).rejects.toMatchObject({ code: 'academic_operation_expired' });
    expect(service.count).toBe(0); expect(gateway.close).toHaveBeenCalledOnce();
  });

  it('marks an expired in-flight request as timeout rather than user cancellation', async () => {
    let now = 0;
    const gateway = fakeGateway(), pending = deferred<typeof schoolResponse>(); gateway.request = vi.fn(() => pending.promise);
    const service = operations(gateway, { now: () => now, idleMilliseconds: 10 });
    const a = await service.start(inputs());
    const fetching = service.request(a.operationID, a.operationToken, { method: 'GET', path: '/' });
    now = 11; await service.expire(); pending.resolve(schoolResponse);
    await expect(fetching).rejects.toMatchObject({ code: 'academic_operation_expired' });
    expect(gateway.close).toHaveBeenCalledOnce();
  });
});

describe('native API boundary', () => {
  it('does not require community login, refuses browser origins and keeps credentials out of results', async () => {
    const gateway = fakeGateway(), service = operations(gateway), errors: string[] = [];
    const connector = createAcademicConnector(service, { onError: code => errors.push(code) });
    cleanups.push(() => connector.shutdown());
    const input = { campus: 'bjfu', portal: 'undergraduate', ...inputs() };
    const denied = await connector.app.request('/v1/academic/operations', { method: 'POST', headers: { Origin: 'https://example.test', 'Content-Type': 'application/json' }, body: JSON.stringify(input) });
    expect(denied.status).toBe(403); expect(gateway.authenticate).not.toHaveBeenCalled();
    const started = await connector.app.request('/v1/academic/operations', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input) });
    expect(started.status).toBe(201); expect(started.headers.get('Cache-Control')).toBe('no-store');
    const operation = await started.json() as { operationID: string; operationToken: string };
    expect(JSON.stringify(operation)).not.toContain(input.vpnPassword);
    const fetched = await connector.app.request(`/v1/academic/operations/${operation.operationID}/requests`, { method: 'POST', headers: { Authorization: `Bearer ${operation.operationToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ method: 'GET', path: '/verifycode.servlet' }) });
    expect(fetched.status).toBe(200);
    const closed = await connector.app.request(`/v1/academic/operations/${operation.operationID}`, { method: 'DELETE', headers: { Authorization: `Bearer ${operation.operationToken}` } });
    expect(closed.status).toBe(204); expect(errors).toEqual(['academic_origin_denied']);
  });

  it('hides unexpected errors and limits repeated unauthenticated starts', async () => {
    const gateway = fakeGateway(); gateway.authenticate = vi.fn(async () => { throw new Error('synthetic-private-password-and-cookie'); });
    const connector = createAcademicConnector(operations(gateway)); cleanups.push(() => connector.shutdown());
    for (let i = 0; i < 10; i++) {
      const result = await connector.app.request('/v1/academic/operations', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ campus: 'bjfu', portal: 'undergraduate', ...inputs() }) });
      expect(result.status).toBe(500); expect(await result.text()).not.toContain('synthetic-private');
    }
    const limited = await connector.app.request('/v1/academic/operations', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    expect(limited.status).toBe(429);
  });
});
