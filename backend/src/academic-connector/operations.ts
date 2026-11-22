import { createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { ApiError } from '../http';
import { BJFUWebVpn, type AcademicRequest, type AcademicResponse } from './gateway';

export interface AcademicGateway {
  authenticate(account: string, password: string, signal?: AbortSignal): Promise<void>;
  request(request: AcademicRequest, signal?: AbortSignal): Promise<AcademicResponse>;
  close(): Promise<boolean>;
}
interface Operation {
  id: string; token: string; accountKey: string; gateway: AcademicGateway; controller: AbortController;
  idleDeadline: number; deadline: number; requestRunning: boolean;
  released?: Promise<boolean>;
  expired?: boolean;
}
export interface StartOperation { vpnAccount: string; vpnPassword: string; cookies?: Record<string, string> }
export interface StartedOperation { operationID: string; operationToken: string; expiresAt: string; idleTimeoutSeconds: number }

function expired(): ApiError { return new ApiError(410, 'academic_operation_expired', '本次连接已结束，请重新同步。', true); }
function cancelled(): ApiError { return new ApiError(499, 'academic_cancelled', '本次同步已取消。'); }

export class AcademicOperations {
  private readonly operations = new Map<string, Operation>();
  private readonly accountKeys = new Set<string>();
  private readonly hashingKey = randomBytes(32);
  private readonly closing = new Set<Promise<boolean>>();
  private readonly cleanupTimer: ReturnType<typeof setInterval>;
  private stopping = false;
  constructor(private readonly options: {
    gateway?: (cookies: Record<string, string>) => AcademicGateway;
    maximumOperations?: number; idleMilliseconds?: number; lifetimeMilliseconds?: number;
    now?: () => number; onCleanupFailure?: () => void;
  } = {}) {
    this.cleanupTimer = setInterval(() => { void this.expire(); }, 1000);
    this.cleanupTimer.unref();
  }
  get count(): number { return this.operations.size; }
  private now(): number { return (this.options.now ?? Date.now)(); }
  private idleMilliseconds(): number { return this.options.idleMilliseconds ?? 120000; }

  async start(input: StartOperation, signal?: AbortSignal): Promise<StartedOperation> {
    if (this.stopping) throw new ApiError(503, 'academic_service_stopping', '教务连接服务正在维护，请稍后重试。', true);
    if (signal?.aborted) throw cancelled();
    if (this.accountKeys.size >= (this.options.maximumOperations ?? 2)) throw new ApiError(503, 'academic_service_busy', '教务连接服务繁忙，请稍后重试或改用校园网直连。', true);
    const accountKey = createHmac('sha256', this.hashingKey).update(input.vpnAccount).digest('hex');
    if (this.accountKeys.has(accountKey)) throw new ApiError(409, 'academic_operation_busy', '这个 VPN 账号已有同步正在进行，请稍候再试。', true);
    const gateway = (this.options.gateway ?? (cookies => new BJFUWebVpn(undefined, cookies)))(input.cookies ?? {});
    const now = this.now();
    const operation: Operation = { id: randomUUID(), token: randomBytes(32).toString('base64url'), accountKey, gateway,
      controller: new AbortController(), idleDeadline: now + this.idleMilliseconds(),
      deadline: now + (this.options.lifetimeMilliseconds ?? 300000), requestRunning: false };
    this.operations.set(operation.id, operation); this.accountKeys.add(accountKey);
    const abort = () => { void this.release(operation); };
    signal?.addEventListener('abort', abort, { once: true });
    try {
      await gateway.authenticate(input.vpnAccount, input.vpnPassword, operation.controller.signal);
      if (signal?.aborted || operation.controller.signal.aborted || !this.operations.has(operation.id)) throw operation.expired ? expired() : cancelled();
      operation.idleDeadline = this.now() + this.idleMilliseconds();
      return { operationID: operation.id, operationToken: operation.token,
        expiresAt: new Date(operation.deadline).toISOString(), idleTimeoutSeconds: this.idleMilliseconds() / 1000 };
    } catch (error) { await this.release(operation); throw operation.expired ? expired() : error; }
    finally { input.vpnPassword = ''; signal?.removeEventListener('abort', abort); }
  }

  private authorized(id: string, token: string): Operation {
    const operation = this.operations.get(id);
    if (!operation || Buffer.byteLength(token) !== Buffer.byteLength(operation.token) ||
        !timingSafeEqual(Buffer.from(token), Buffer.from(operation.token))) {
      throw new ApiError(404, 'academic_operation_not_found', '找不到本次教务连接，请重新同步。', true);
    }
    if (this.now() >= operation.deadline || this.now() >= operation.idleDeadline) {
      operation.expired = true;
      void this.release(operation); throw expired();
    }
    return operation;
  }

  async request(id: string, token: string, request: AcademicRequest, signal?: AbortSignal): Promise<AcademicResponse> {
    const operation = this.authorized(id, token);
    if (signal?.aborted) { await this.release(operation); throw cancelled(); }
    if (operation.requestRunning) throw new ApiError(409, 'academic_request_busy', '正在处理本次教务请求，请稍候。', true);
    operation.requestRunning = true; operation.idleDeadline = this.now() + this.idleMilliseconds();
    const abort = () => { void this.release(operation); };
    signal?.addEventListener('abort', abort, { once: true });
    try {
      const response = await operation.gateway.request(request, operation.controller.signal);
      if (operation.controller.signal.aborted || signal?.aborted || !this.operations.has(id)) throw operation.expired ? expired() : cancelled();
      operation.idleDeadline = this.now() + this.idleMilliseconds();
      return response;
    } catch (error) { await this.release(operation); throw operation.expired ? expired() : error; }
    finally { operation.requestRunning = false; signal?.removeEventListener('abort', abort); }
  }

  async close(id: string, token: string): Promise<void> {
    const operation = this.authorized(id, token);
    const confirmed = await this.release(operation);
    if (!confirmed) throw new ApiError(502, 'vpn_logout_unconfirmed', '本次连接已释放，但未能确认学校 VPN 已退出。', true);
  }

  private release(operation: Operation): Promise<boolean> {
    if (operation.released) return operation.released;
    if (this.operations.get(operation.id) === operation) {
      this.operations.delete(operation.id);
      operation.controller.abort();
    }
    // Gateway.close is idempotent; release is safe across cancellation, expiry and shutdown.
    const closing = operation.gateway.close().catch(() => false).finally(() => this.accountKeys.delete(operation.accountKey));
    operation.released = closing;
    this.closing.add(closing);
    void closing.then(confirmed => { if (!confirmed) this.options.onCleanupFailure?.(); }).finally(() => this.closing.delete(closing));
    return closing;
  }

  async expire(): Promise<void> {
    const now = this.now();
    await Promise.all([...this.operations.values()].filter(op => now >= op.deadline || now >= op.idleDeadline).map(op => {
      op.expired = true; return this.release(op);
    }));
  }
  async shutdown(): Promise<void> {
    this.stopping = true; clearInterval(this.cleanupTimer);
    await Promise.all([...this.operations.values()].map(op => this.release(op)));
    await Promise.all([...this.closing]); this.hashingKey.fill(0);
  }
}
