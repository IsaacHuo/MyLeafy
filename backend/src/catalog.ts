import type { Actor, BackendEnv } from './auth';
import { actorGuard, atomic, decode, guard, rows, statement, type Bind } from './db';
import { ApiError, integer, text } from './http';
import { requireCommunity } from './community';

const catalogs={teachers:{table:'teachers',rating:'teacher_ratings',foreignKey:'teacher_id'},courses:{table:'course_catalog',rating:'course_ratings',foreignKey:'course_id'},dishes:{table:'dish_catalog',rating:'dish_ratings',foreignKey:'dish_id'}} as const;
export function catalogKind(kind:string){
  if(!(kind in catalogs))throw new ApiError(404,'not_found','目录不存在。');
  return catalogs[kind as keyof typeof catalogs];
}
export async function catalog(env:BackendEnv,who:Actor,kind:string,url:URL){
  const {table,rating,foreignKey}=catalogKind(kind),search=text(url.searchParams.get('search'),100,false);
  const limit=integer(url.searchParams.has('limit')?Number(url.searchParams.get('limit')):50,1,100),offset=integer(url.searchParams.has('offset')?Number(url.searchParams.get('offset')):0,0,100000);
  const params:Bind[]=[who.profileId,requireCommunity(who)];
  let filter='';
  if(search){
    if([...search].length>=3){filter=` AND t.rowid IN(SELECT rowid FROM ${table}_search WHERE ${table}_search MATCH ?)`;params.push('"'+search.replaceAll('"','""')+'"');}
    else{filter=' AND instr(lower(t.search_text),lower(?))>0';params.push(search);}
  }
  const found=await rows(env.DB,`SELECT t.*,r.stars AS viewer_stars FROM ${table} t LEFT JOIN ${rating} r ON r.${foreignKey}=t.id AND r.user_id=? WHERE t.campus_id=? AND t.status='published'${filter} ORDER BY t.rating_average DESC,t.rating_count DESC,t.id LIMIT ? OFFSET ?`,[...params,limit,offset]);
  return found.map(row=>decode(table,row));
}
export async function rate(env:BackendEnv,who:Actor,kind:string,id:number,stars:number|null){
  const {table,rating,foreignKey}=catalogKind(kind);integer(id,1,Number.MAX_SAFE_INTEGER);if(stars!==null)integer(stars,1,5);
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),
    guard(env.DB,`EXISTS(SELECT 1 FROM ${table} WHERE id=? AND campus_id=? AND status='published')`,[id,requireCommunity(who)]),
    stars===null?statement(env.DB,`DELETE FROM ${rating} WHERE ${foreignKey}=? AND user_id=?`,[id,who.profileId]):statement(env.DB,`INSERT INTO ${rating}(${foreignKey},user_id,stars) VALUES(?,?,?) ON CONFLICT(${foreignKey},user_id) DO UPDATE SET stars=excluded.stars,updated_at=?`,[id,who.profileId,stars,new Date().toISOString().replace('Z','000Z')]),
    statement(env.DB,`UPDATE ${table} SET rating_count=(SELECT count(*) FROM ${rating} WHERE ${foreignKey}=?),rating_average=coalesce((SELECT ((sum(stars)*20+count(*))/(2*count(*)))/10.0 FROM ${rating} WHERE ${foreignKey}=?),0),${[1,2,3,4,5].map(star=>`rating_${star}_count=(SELECT count(*) FROM ${rating} WHERE ${foreignKey}=? AND stars=${star})`).join(',')},updated_at=? WHERE id=? RETURNING *`,[id,id,id,id,id,id,id,new Date().toISOString().replace('Z','000Z'),id]),
  ]);
  return decode(table,result[result.length-2].results[0]);
}
