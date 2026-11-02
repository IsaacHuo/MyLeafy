import type { BackendEnv } from "./auth";
import { adminGuard, type AdminContext } from "./admin-auth";
import { ApiError } from "./http";
import { actionKinds, validateQuery } from "./monitoring/model";

export async function auditMonitorDenial(env:BackendEnv,context:AdminContext,action:string){
  try{
    const state=await env.DB.prepare('SELECT mode FROM backend_control WHERE id=1').first<{mode:string}>();
    if(state?.mode==='active')await env.DB.prepare("INSERT INTO admin_audit_logs(admin_id,action,target_type,request_id,outcome,error_code) VALUES(?,?,'monitoring',?,'failure','forbidden')").bind(context.id,action,context.requestId).run();
  }catch{console.error(JSON.stringify({event:'monitor_access_audit_failed',request_id:context.requestId}));}
}

export async function adminMonitoring(
  env: BackendEnv,
  context: AdminContext,
  action: keyof typeof actionKinds,
  params: Record<string, unknown>,
) {
  adminGuard(env, context, "super_admin");
  try {
    validateQuery(actionKinds[action],params);
  } catch (error) {
    throw new ApiError(400, "bad_request", (error as Error).message);
  }
  const port = env.ENVIRONMENT === "production" ? 3140 : 3141;
  if (!env.MONITOR_TOKEN)
    throw new ApiError(503, "monitoring_unavailable", "监控尚未配置。", true);
  try {
    const response = await fetch(
      `http://127.0.0.1:${port}/query/${actionKinds[action]}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${env.MONITOR_TOKEN}`,
        },
        body: JSON.stringify(params),
        signal: AbortSignal.timeout(6000),
      },
    );
    const body = (await response.json()) as any;
    if (!response.ok)
      throw new ApiError(
        response.status === 400 ? 400 : 503,
        response.status === 400 ? "bad_request" : "monitoring_unavailable",
        response.status === 400
          ? String(body.error)
          : "监控暂时不可用，业务服务不受影响。",
        true,
      );
    return body;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(
      503,
      "monitoring_unavailable",
      "监控暂时不可用，业务服务不受影响。",
      true,
    );
  }
}
