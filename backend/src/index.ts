import { Hono } from 'hono';
import { ApiError } from './http';
export { ChangeSignals } from './signals';

export const app=new Hono<{Bindings:Env;Variables:{requestId:string}}>();
app.use('*',async(c,next)=>{
  const id=crypto.randomUUID();c.set('requestId',id);
  c.header('X-Request-ID',id);c.header('X-Content-Type-Options','nosniff');c.header('Cache-Control','no-store');
  const origin=c.req.header('origin');
  if(origin&&origin!==c.env.SITE_ORIGIN&&origin!==c.env.API_ORIGIN)throw new ApiError(403,'forbidden','Origin is not allowed');
  if(origin){c.header('Access-Control-Allow-Origin',origin);c.header('Vary','Origin');c.header('Access-Control-Allow-Credentials','true');}
  if(c.req.method==='OPTIONS'){c.header('Access-Control-Allow-Methods','GET,POST,PATCH,DELETE,OPTIONS');c.header('Access-Control-Allow-Headers','Content-Type,Authorization,X-Leafy-Admin-CSRF');return c.body(null,204);}
  await next();
});
app.get('/health',async c=>{
  const check=await c.env.DB.prepare('SELECT 1 AS ok').first<{ok:number}>();
  return c.json({status:check?.ok===1?'ok':'error',environment:c.env.ENVIRONMENT});
});
app.onError((error,c)=>{
  const known=error instanceof ApiError;
  console.error(JSON.stringify({event:'api_error',request_id:c.get('requestId'),code:known?error.code:'internal_error',status:known?error.status:500}));
  return new Response(JSON.stringify({error:known?error.message:'Request failed',errorEnvelope:{code:known?error.code:'internal_error',message:known?error.message:'Request failed',retryable:known?error.retryable:true},request_id:c.get('requestId')}),{status:known?error.status:500,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Request-ID':c.get('requestId')}});
});
export default app;
