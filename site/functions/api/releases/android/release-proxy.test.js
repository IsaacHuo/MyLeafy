import {expect,it,vi} from 'vitest';
import {onRequest} from './[[path]].js';
import {readFileSync} from 'node:fs';

it('deploys public Android release endpoints through Pages Functions',()=>{
  const routes=JSON.parse(readFileSync('public/_routes.json','utf8'));
  const matches=(pattern,path)=>new RegExp('^'+pattern.replaceAll('*','.*')+'$').test(path);
  for(const path of ['/api/releases/android/latest','/api/releases/android/download']){
    expect(routes.include.some(pattern=>matches(pattern,path))).toBe(true);
    expect(routes.exclude.some(pattern=>matches(pattern,path))).toBe(false);
  }
});

it('reads the bound environment without sending browser credentials or invoking a production URL',async()=>{
  const binding=vi.fn(async request=>{
    expect(request.url).toBe('https://myleafy-public.internal/v1/releases/android/latest');
    expect(request.headers.has('cookie')).toBe(false);expect(request.headers.has('authorization')).toBe(false);
    return Response.json({release:{versionName:'9.9.9',apkUrl:'https://downloads-staging.myleafy.space/test.apk'}});
  });
  const response=await onRequest({request:new Request('https://preview.pages.dev/api/releases/android/latest',{headers:{cookie:'private=session',authorization:'Bearer private'}}),env:{MYLEAFY_PUBLIC_API:{fetch:binding}}});
  expect((await response.json()).release.apkUrl).toContain('downloads-staging');expect(binding).toHaveBeenCalledTimes(1);
});
it('preserves the bound download redirect and checksum selector without fetching APK bytes',async()=>{
  const binding=vi.fn(async request=>{
    expect(request.redirect).toBe('manual');expect(new URL(request.url).search).toBe('?file=checksum');
    return new Response(null,{status:302,headers:{Location:'https://downloads-staging.myleafy.space/test.apk.sha256'}});
  });
  const response=await onRequest({request:new Request('https://preview.pages.dev/api/releases/android/download?file=checksum'),env:{MYLEAFY_PUBLIC_API:{fetch:binding}}});
  expect(response.status).toBe(302);expect(response.headers.get('location')).toContain('downloads-staging');expect(response.headers.get('cache-control')).toBe('no-store');
});
it('cannot proxy private or write routes',async()=>{
  const binding=vi.fn();const env={MYLEAFY_PUBLIC_API:{fetch:binding}};
  expect((await onRequest({request:new Request('https://preview.pages.dev/api/releases/android/candidates'),env})).status).toBe(404);
  expect((await onRequest({request:new Request('https://preview.pages.dev/api/releases/android/latest',{method:'POST'}),env})).status).toBe(405);
  expect(binding).not.toHaveBeenCalled();
});
it('missing or failed bindings surface an error instead of falling back to production',async()=>{
  const request=new Request('https://preview.pages.dev/api/releases/android/latest');
  expect((await onRequest({request,env:{}})).status).toBe(503);
  const log=vi.spyOn(console,'error').mockImplementation(()=>{});
  try {expect((await onRequest({request,env:{MYLEAFY_PUBLIC_API:{fetch:async()=>{throw new Error('unavailable');}}}})).status).toBe(502);}
  finally {log.mockRestore();}
});
