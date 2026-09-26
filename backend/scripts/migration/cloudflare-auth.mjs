import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

let cachedOAuth;
let expiresAt=0;
let refreshing;

// Operator-only helper. Credentials stay in memory and never enter reports or argv.
export async function cloudflareToken(force=false) {
  if (process.env.CLOUDFLARE_API_TOKEN?.trim()) return process.env.CLOUDFLARE_API_TOKEN.trim();
  if(!force && cachedOAuth && Date.now()<expiresAt)return cachedOAuth;
  if(refreshing)return refreshing;
  refreshing=readOAuth();
  try{return await refreshing;}finally{refreshing=undefined;}
}
async function readOAuth(){
  const executable = new URL('../../node_modules/.bin/wrangler', import.meta.url).pathname;
  try {
    const { stdout } = await promisify(execFile)(executable, ['auth', 'token', '--json'], {
      timeout: 30000, maxBuffer: 1024 * 1024,
      env: { ...process.env, WRANGLER_SEND_METRICS: 'false' },
    });
    const credentials = JSON.parse(stdout);
    if (typeof credentials.token === 'string' && credentials.token) {
      cachedOAuth=credentials.token;expiresAt=Date.now()+60000;return cachedOAuth;
    }
  } catch { /* Never echo CLI stderr: it may include authentication details. */ }
  throw new Error('Cloudflare authorization unavailable. Run wrangler login or configure CLOUDFLARE_API_TOKEN.');
}

// Only used for repeatable operator reads and immutable object writes.
export async function cloudflareRequest(url,options={}) {
  const {timeoutMs=60000,...requestOptions}=options;
  let refreshed=false;
  for(let attempt=0;attempt<4;attempt++){
    let delay=1000*2**attempt;
    try{
      const response=await fetch(url,{...requestOptions,signal:AbortSignal.timeout(timeoutMs)});
      if(response.status===401&&!refreshed&&!process.env.CLOUDFLARE_API_TOKEN){
        const headers=new Headers(requestOptions.headers);
        if(headers.has('Authorization')){
          await response.body?.cancel();
          headers.set('Authorization',`Bearer ${await cloudflareToken(true)}`);
          requestOptions.headers=headers;refreshed=true;continue;
        }
      }
      if(response.status!==429&&response.status<500)return response;
      if(attempt===3)return response;
      const retry=Number(response.headers.get('retry-after'));
      if(Number.isFinite(retry)&&retry>0)delay=retry*1000;
      await response.body?.cancel();
    }catch(error){
      const transient=['UND_ERR_CONNECT_TIMEOUT','UND_ERR_SOCKET','ECONNRESET','ETIMEDOUT','EAI_AGAIN'].includes(error.cause?.code)||['AbortError','TimeoutError'].includes(error.name);
      if(!transient||attempt===3)throw error;
    }
    console.log(JSON.stringify({event:'cloudflare_transfer_retry',attempt:attempt+1,delay_ms:delay}));
    await new Promise(resolve=>setTimeout(resolve,delay));
  }
  throw new Error('Cloudflare transfer retry budget exhausted');
}
