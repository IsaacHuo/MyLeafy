import mapping from '../contracts/table-mapping.json';
import { ApiError } from './http';
import type { Actor } from './auth';

export type Row=Record<string,unknown>;
export type Bind=string|number|null|ArrayBuffer;
const tables:Record<string,{columns:{name:string;type:string;generated:boolean;nullable:boolean}[];primaryKey:string[]}>=mapping;
export function encode(table:string,row:Row):Row{
  const meta=tables[table];if(!meta)throw new Error(`Unknown internal table: ${table}`);
  const output:Row={};for(const [name,value]of Object.entries(row)){
    const col=meta.columns.find(c=>c.name===name);if(!col||col.generated)throw new ApiError(400,'invalid_request','Unknown or generated field');
    output[name]=value===null?null:col.type==='jsonb'?JSON.stringify(value):col.type==='boolean'?(value?1:0):value;
  }return output;
}
export function decode(table:string,row:Row):Row{
  const meta=tables[table];const output:Row={...row};if(!meta)return output;
  for(const c of meta.columns){const value=row[c.name];if(value==null)continue;
    if(c.type==='jsonb'&&typeof value==='string')output[c.name]=JSON.parse(value);
    if(c.type==='boolean')output[c.name]=value===1||value===true;
  }return output;
}
export function statement(db:D1Database,sql:string,params:Bind[]=[]){return db.prepare(sql).bind(...params);}
export function guard(db:D1Database,sql:string,params:Bind[]=[]){return statement(db,`INSERT INTO mutation_assertions(ok) SELECT CASE WHEN (${sql}) THEN 1 ELSE 0 END`,params);}
export function actorGuard(db:D1Database,actor:Actor,community=false):D1PreparedStatement{
  return guard(db,`EXISTS(SELECT 1 FROM profile_auth_links l JOIN profiles p ON p.id=l.profile_id JOIN auth_users u ON u.id=l.auth_user_id JOIN identity_session s ON s.userId=u.id WHERE l.auth_user_id=? AND l.profile_id=? AND s.id=? AND s.expiresAt>? AND (u.banned_until IS NULL OR u.banned_until<=?)${community?" AND p.community_access_status='approved' AND p.community_campus_id=? AND EXISTS(SELECT 1 FROM campuses c WHERE c.id=p.community_campus_id AND c.status='active' AND c.is_community_enabled=1)":''})`,[actor.authId,actor.profileId,actor.sessionId,Date.now(),new Date().toISOString(),...(community?[actor.campusId]:[])]);
}
export function writeGuard(db:D1Database){return guard(db,"EXISTS(SELECT 1 FROM backend_control WHERE id=1 AND mode='active') AND EXISTS(SELECT 1 FROM migration_control WHERE id=1 AND importing=0)");}
export async function atomic(db:D1Database,operations:D1PreparedStatement[]):Promise<D1Result<Row>[]> {
  try{return await db.batch<Row>([writeGuard(db),...operations,db.prepare('DELETE FROM mutation_assertions')]);}
  catch(error){const message=error instanceof Error?error.message:'';
    if(/mutation_precondition|UNIQUE constraint|FOREIGN KEY constraint|CHECK constraint/.test(message))throw new ApiError(409,'state_conflict','The operation is no longer allowed; refresh and retry');
    throw error;
  }
}
export function outbox(db:D1Database,room:string){return statement(db,'INSERT INTO change_outbox(id,room) VALUES(?,?)',[crypto.randomUUID(),room]);}
