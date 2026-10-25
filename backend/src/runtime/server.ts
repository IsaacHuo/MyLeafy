import { existsSync } from 'node:fs';
import { isIP } from 'node:net';
import type { HttpBindings, Http2Bindings } from '@hono/node-server';
import { app } from '../index';
import { handleAdminRequest } from '../admin-router';
import type { BackendEnv } from '../auth';
import { ApiError } from '../http';
import { onRequest as adminProxy } from '../../../site/functions/api/admin/[[path]].js';
import { onRequest as releaseProxy } from '../../../site/functions/api/releases/android/[[path]].js';
import { onRequestGet as sharePage } from '../../../site/functions/share/[[path]].js';

export function createHandler(env: BackendEnv, maintenanceFile: string) {
  const apiOrigin = new URL(env.API_ORIGIN), siteOrigin = new URL(env.SITE_ORIGIN);
  const downloadHost = env.ENVIRONMENT === 'production' ? 'downloads.myleafy.space' : 'downloads-staging.myleafy.space';
  const publicAPI = {fetch:(request:Request) => {
    const url=new URL(request.url);
    return app.fetch(new Request(new URL(url.pathname+url.search,apiOrigin),request),env);
  }};
  const siteEnv = {MYLEAFY_PUBLIC_API:publicAPI,MYLEAFY_ADMIN_API:{fetch:(request:Request)=>handleAdminRequest(request,env)}};
  return async (input: Request, bindings?: HttpBindings | Http2Bindings): Promise<Response> => {
    const url = new URL(input.url);
    try {
      if (![apiOrigin.host,siteOrigin.host,downloadHost].includes(url.host)) return new Response('Unknown host',{status:421});
      if (existsSync(maintenanceFile)) return Response.json({error:'服务维护中，请稍后重试。',errorEnvelope:{code:'maintenance',message:'服务维护中，请稍后重试。',retryable:true}},{status:503,headers:{'Retry-After':'60','Cache-Control':'no-store'}});
      const headers = new Headers(input.headers);
      const ip = headers.get('x-real-ip') ?? '';
      for(const name of ['cf-connecting-ip','x-leafy-client-ip','x-forwarded-for','forwarded'])headers.delete(name);
      headers.set('x-leafy-client-ip',isIP(ip)?ip:'0.0.0.0');
      // The existing site proxy consumes this name; it only receives the sanitized value.
      headers.set('cf-connecting-ip',isIP(ip)?ip:'0.0.0.0');
      const origin = url.host===siteOrigin.host ? siteOrigin : apiOrigin;
      const request = new Request(new URL(url.pathname+url.search,origin),new Request(input,{headers}));
      if(url.host===apiOrigin.host) return await app.fetch(request,{...env,...bindings});
      if(url.host===downloadHost) {
        if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405});
        const key=decodeURIComponent(url.pathname.slice(1));
        if(!/^android\/official\/[1-9]\d*\/MyLeafy-Android-\d+\.\d+\.\d+\.apk(?:\.sha256|-build-info\.txt)?$/.test(key))return new Response(null,{status:404});
        const object=await env.RELEASES.get(key,{range:request.headers});
        if(!object)return new Response(null,{status:404});
        const responseHeaders=new Headers({'Content-Type':object.httpMetadata.contentType??'application/octet-stream','Content-Length':String(object.range?.length??object.size),'ETag':object.httpEtag,'Accept-Ranges':'bytes','Cache-Control':'public, max-age=31536000, immutable','X-Content-Type-Options':'nosniff'});
        if(object.range)responseHeaders.set('Content-Range',`bytes ${object.range.offset}-${object.range.offset+object.range.length-1}/${object.size}`);
        const notModified=request.headers.get('if-none-match')===object.httpEtag;
        if(request.method==='HEAD'||notModified)await object.body.cancel();
        return new Response(request.method==='HEAD'||notModified?null:object.body,{status:notModified?304:object.range?206:200,headers:responseHeaders});
      }
      const context={request,env:siteEnv};
      if(url.pathname.startsWith('/api/admin/'))return await adminProxy(context);
      if(url.pathname.startsWith('/api/releases/android/'))return await releaseProxy(context);
      if(url.pathname.startsWith('/share/'))return request.method==='GET'?await sharePage(context):new Response(null,{status:405});
      return new Response(null,{status:404});
    }catch(error) {
      const known=error instanceof ApiError;
      console.error(JSON.stringify({event:'gateway_error',code:known?error.code:'internal_error'}));
      return Response.json({error:known?error.message:'Request failed'},{status:known?error.status:500,headers:{'Cache-Control':'no-store'}});
    }
  };
}
