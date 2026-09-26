export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string, public retryable=false) { super(message); }
}
export async function readJSON(request: Request, maxBytes=256*1024): Promise<Record<string,unknown>> {
  if (request.headers.get('content-type')?.split(';')[0].trim()!=='application/json') throw new ApiError(400,'invalid_request','Content-Type must be application/json');
  const bytes = await readBytes(request,maxBytes);
  try {
    const value: unknown=JSON.parse(new TextDecoder().decode(bytes));
    if (!value || typeof value!=='object' || Array.isArray(value)) throw new Error();
    return value as Record<string,unknown>;
  } catch { throw new ApiError(400,'invalid_request','Expected a JSON object'); }
}
export async function readBytes(request: Request, maxBytes: number): Promise<Uint8Array> {
  const length=request.headers.get('content-length');
  if (length && Number(length)>maxBytes) throw new ApiError(413,'payload_too_large','Request is too large');
  const reader=request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[]=[];let total=0;
  try { while(true) { const {done,value}=await reader.read();if(done)break;total+=value.byteLength;
    if(total>maxBytes){await reader.cancel();throw new ApiError(413,'payload_too_large','Request is too large');}chunks.push(value);
  }}finally{reader.releaseLock();}
  const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return bytes;
}
export function text(value: unknown,max=10000,required=true):string {
  if(typeof value!=='string') {if(!required && value==null)return '';throw new ApiError(400,'invalid_request','Expected text');}
  const result=value.trim();if((required&&!result)||[...result].length>max)throw new ApiError(400,'invalid_request','Text length is invalid');return result;
}
export function uuid(value: unknown): string {
  if(typeof value!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))throw new ApiError(400,'invalid_request','Expected UUID');return value.toLowerCase();
}
export function integer(value:unknown,min:number,max:number,defaultValue?:number):number{
  if(value===undefined&&defaultValue!==undefined)return defaultValue;
  if(typeof value!=='number'||!Number.isSafeInteger(value)||value<min||value>max)throw new ApiError(400,'invalid_request','Integer is outside the allowed range');return value;
}
export async function sha256(data:string|Uint8Array):Promise<string>{
  const bytes=typeof data==='string'?new TextEncoder().encode(data):data;
  const hash=await crypto.subtle.digest('SHA-256',new Uint8Array(bytes));return Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,'0')).join('');
}
export function canonical(value:unknown):string{
  if(value===null||typeof value!=='object')return JSON.stringify(value);
  if(Array.isArray(value))return `[${value.map(canonical).join(',')}]`;
  return `{${Object.keys(value).sort().map(k=>`${JSON.stringify(k)}:${canonical((value as Record<string,unknown>)[k])}`).join(',')}}`;
}
