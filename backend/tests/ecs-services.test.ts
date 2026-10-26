import {expect,it,vi} from 'vitest';
import {createHash} from 'node:crypto';
import {checkServices,verifyCandidateAsset} from '../scripts/ecs/check-services.mjs';

const bytes=new TextEncoder().encode('retained-apk-bytes');
const expected={sizeBytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),versionCode:12,versionName:'1.2.8',commit:'a'.repeat(40)};
const asset={id:7,size:bytes.length,name:'MyLeafy-Android-1.2.8.apk'};
it('downloads the retained bytes without forwarding credentials to the asset host',async()=>{
 const request=vi.fn().mockResolvedValueOnce(new Response(null,{status:302,headers:{location:'https://release-assets.githubusercontent.com/example?signature=private'}})).mockResolvedValueOnce(new Response(bytes));
 expect(await verifyCandidateAsset(asset,expected,{Authorization:'Bearer secret'},request)).toEqual({verified:true,sizeBytes:bytes.length,versionCode:12});
 expect(request.mock.calls[0][1].headers.Authorization).toBe('Bearer secret');
 expect(request.mock.calls[1][1].headers).toBeUndefined();
 expect(request.mock.calls[1][1].redirect).toBe('error');
});
it('rejects substituted bytes, oversized bodies and untrusted download hosts',async()=>{
 await expect(verifyCandidateAsset(asset,expected,{},vi.fn().mockResolvedValue(new Response(new Uint8Array(bytes.length))))).rejects.toThrow('candidate_integrity');
 await expect(verifyCandidateAsset(asset,expected,{},vi.fn().mockResolvedValue(new Response(new Uint8Array(bytes.length+1))))).rejects.toThrow('candidate_size');
 const request=vi.fn().mockResolvedValue(new Response(null,{status:302,headers:{location:'https://attacker.invalid/apk'}}));
 await expect(verifyCandidateAsset(asset,expected,{},request)).rejects.toThrow('candidate_redirect');expect(request).toHaveBeenCalledTimes(1);
});
it('verifies provider access and a matching private candidate with read-only requests',async()=>{
 const request=vi.fn().mockResolvedValueOnce(Response.json({data:[{name:'example.test',status:'verified'}]})).mockResolvedValueOnce(Response.json({})).mockResolvedValueOnce(Response.json([{id:9,draft:true,tag_name:'android-candidate-12',target_commitish:expected.commit,assets:[asset]}])).mockResolvedValueOnce(new Response(bytes));
 const report=await checkServices({ENVIRONMENT:'production',EMAIL_API_KEY:'email-secret',EMAIL_FROM:'MyLeafy <support@example.test>',GITHUB_RELEASE_TOKEN:'github-secret'},{candidate:{github_release_id:9,github_asset_id:7,metadata:JSON.stringify(expected)},request});
 expect(report).toMatchObject({ok:true,emailSent:false,releaseDispatchAttempted:false,candidateDownload:{verified:true}});
 for(const call of request.mock.calls)expect(call[1].method??'GET').toBe('GET');
 expect(JSON.stringify(report)).not.toContain('secret');
});
it('reports failed credentials and missing sender verification as failures',async()=>{
 const request=vi.fn().mockImplementation(()=>Promise.resolve(new Response(null,{status:403})));
 expect(await checkServices({GITHUB_RELEASE_TOKEN:'secret'},{request})).toMatchObject({ok:false,emailProviderHTTP:403,githubHTTP:403});
 expect(await checkServices({}, {request})).toMatchObject({ok:false,githubCredentialConfigured:false});
});
