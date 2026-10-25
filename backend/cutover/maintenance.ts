// Operator-only source freeze. Deploy only after cutover approval, using the
// existing environment's bindings/routes. Never part of the ECS application.
import {DurableObject,WorkerEntrypoint} from 'cloudflare:workers';
const maintenance=()=>Response.json({migration_source_frozen:true,error:'服务迁移维护中，请稍后重试。',errorEnvelope:{code:'maintenance',message:'服务迁移维护中，请稍后重试。',retryable:true}},{status:503,headers:{'Cache-Control':'no-store','Retry-After':'60'}});
export class AdminAPI extends WorkerEntrypoint {fetch(){return maintenance();}}
export class ChangeSignals extends DurableObject {
  constructor(ctx,env){super(ctx,env);for(const socket of ctx.getWebSockets())socket.close(1012,'Migration maintenance');}
  fetch(){return maintenance();}
  webSocketMessage(socket){socket.close(1012,'Migration maintenance');}
  alarm(){for(const socket of this.ctx.getWebSockets())socket.close(1012,'Migration maintenance');}
}
export default {fetch:maintenance,scheduled(){}};
