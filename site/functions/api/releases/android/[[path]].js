// Public, read-only release routes use the same environment binding as share pages.
export async function onRequest({request,env}) {
  const url=new URL(request.url);
  const action=url.pathname.slice('/api/releases/android/'.length);
  const error=(status,message)=>Response.json({error:message},{status,headers:{'Cache-Control':'no-store'}});
  if(!['latest','download'].includes(action))return error(404,'发行接口不存在。');
  if(request.method!=='GET')return error(405,'只支持读取发行信息。');
  if(!env.MYLEAFY_PUBLIC_API?.fetch)return error(503,'网站发行服务尚未绑定。');
  const upstreamURL=new URL(`https://myleafy-public.internal/v1/releases/android/${action}`);
  if(action==='download'&&url.searchParams.get('file')==='checksum')upstreamURL.searchParams.set('file','checksum');
  try {
    const response=await env.MYLEAFY_PUBLIC_API.fetch(new Request(upstreamURL,{redirect:'manual'}));
    const headers=new Headers(response.headers);headers.set('Cache-Control','no-store');
    return new Response(response.body,{status:response.status,headers});
  }catch {
    console.error(JSON.stringify({event:'website_release_backend_unavailable',action}));
    return error(502,'无法连接网站发行服务，请稍后重试。');
  }
}
