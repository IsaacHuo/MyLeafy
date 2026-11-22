import { Hono } from 'hono';
import { ApiError, readJSON } from '../http';
import { validateAcademicRequest, validateCookies } from './gateway';
import { AcademicOperations } from './operations';

export function createAcademicConnector(operations: AcademicOperations, options: {
  now?: () => number; deployCommit?: string; onError?: (code: string, requestID: string) => void;
} = {}) {
  const app = new Hono<{ Variables: { requestID: string } }>();
  const starts = new Map<string, { count: number; reset: number }>();
  const rateTimer = setInterval(() => {
    const now = (options.now ?? Date.now)();
    for (const [key, value] of starts) if (value.reset <= now) starts.delete(key);
  }, 60000); rateTimer.unref();

  app.use('*', async (c, next) => {
    const requestID = crypto.randomUUID(); c.set('requestID', requestID);
    c.header('Cache-Control', 'no-store'); c.header('X-Request-ID', requestID);
    c.header('X-Content-Type-Options', 'nosniff');
    // Native clients have no Origin. No browser origin is admitted to this credential endpoint.
    if (c.req.header('Origin')) throw new ApiError(403, 'academic_origin_denied', '请在 MyLeafy App 中连接教务。');
    await next();
  });
  const token = (authorization: string | undefined): string => {
    if (!authorization?.startsWith('Bearer ') || !/^[A-Za-z0-9_-]{43}$/.test(authorization.slice(7))) {
      throw new ApiError(401, 'academic_operation_token_required', '本次教务连接已失效，请重新同步。', true);
    }
    return authorization.slice(7);
  };
  app.get('/health', c => c.json({ status: 'ok', commit: options.deployCommit ?? null }));
  app.post('/v1/academic/operations', async c => {
    const now = (options.now ?? Date.now)();
    // The listener is loopback-only; Caddy replaces X-Real-IP with the actual remote address.
    const address = c.req.header('X-Real-IP') ?? 'unknown';
    if (starts.size > 4096 && !starts.has(address)) throw new ApiError(429, 'academic_rate_limited', '请求较多，请稍后再试。', true);
    let rate = starts.get(address);
    if (!rate || rate.reset <= now) { rate = { count: 0, reset: now + 60000 }; starts.set(address, rate); }
    if (++rate.count > 10) throw new ApiError(429, 'academic_rate_limited', '连接尝试过于频繁，请稍后再试。', true);
    const body = await readJSON(c.req.raw, 65536);
    if (body.campus !== 'bjfu' || body.portal !== 'undergraduate' || typeof body.vpnAccount !== 'string' ||
        !body.vpnAccount.trim() || body.vpnAccount.trim().length > 128 || typeof body.vpnPassword !== 'string' ||
        !body.vpnPassword || body.vpnPassword.length > 1024) throw new ApiError(400, 'invalid_request', '请填写北林 VPN 账号和密码。');
    try {
      const result = await operations.start({ vpnAccount: body.vpnAccount.trim(), vpnPassword: body.vpnPassword,
        cookies: validateCookies(body.cookies) }, c.req.raw.signal);
      return c.json(result, 201);
    } finally { body.vpnPassword = ''; }
  });
  app.post('/v1/academic/operations/:id/requests', async c => {
    const authorization = token(c.req.header('Authorization'));
    const body = await readJSON(c.req.raw, 98304);
    return c.json(await operations.request(c.req.param('id'), authorization, validateAcademicRequest(body), c.req.raw.signal));
  });
  app.delete('/v1/academic/operations/:id', async c => {
    await operations.close(c.req.param('id'), token(c.req.header('Authorization')));
    return c.body(null, 204);
  });
  app.onError((error, c) => {
    const known = error instanceof ApiError;
    const code = known ? error.code : 'academic_internal_error';
    options.onError?.(code, c.get('requestID'));
    return new Response(JSON.stringify({ errorEnvelope: { code, message: known ? error.message : '教务连接服务暂时不可用，请稍后重试。', retryable: known ? error.retryable : true }, request_id: c.get('requestID') }),
      { status: known ? error.status : 500, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Request-ID': c.get('requestID') } });
  });
  app.notFound(c => c.json({ errorEnvelope: { code: 'not_found', message: '教务接口不存在。', retryable: false } }, 404));
  return { app, shutdown: async () => { clearInterval(rateTimer); await operations.shutdown(); } };
}
