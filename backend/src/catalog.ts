import type { Actor, BackendEnv } from './auth';
import { actorGuard, atomic, decode, guard, rows, statement, type Bind, type Row } from './db';
import { ApiError, integer, text } from './http';
import { requireCommunity } from './community';

const catalogs={teachers:{table:'teachers',rating:'teacher_ratings',foreignKey:'teacher_id'},courses:{table:'course_catalog',rating:'course_ratings',foreignKey:'course_id'},dishes:{table:'dish_catalog',rating:'dish_ratings',foreignKey:'dish_id'}} as const;
export function catalogKind(kind:string){
  if(!(kind in catalogs))throw new ApiError(404,'not_found','目录不存在。');
  return catalogs[kind as keyof typeof catalogs];
}
export async function catalog(env:BackendEnv,who:Actor,kind:string,url:URL):Promise<Row[]>{
  const {table,rating,foreignKey}=catalogKind(kind),search=text(url.searchParams.get('search'),100,false);
  const limit=integer(url.searchParams.has('limit')?Number(url.searchParams.get('limit')):50,1,100),offset=integer(url.searchParams.has('offset')?Number(url.searchParams.get('offset')):0,0,100000);
  const params:Bind[]=[who.profileId,requireCommunity(who)];
  let filter='';
  const value=text(url.searchParams.get('filter_value'),200,false);
  for(const [column,input]of Object.entries({id:url.searchParams.get('id'),...(kind==='teachers'?{unit:value}:kind==='courses'?{category:url.searchParams.get('category')||value}:{location:url.searchParams.get('location')||value,canteen:url.searchParams.get('canteen')})})){
    if(!input||input==='all')continue;
    // Canteens are a prefix of the existing location field, not a new column.
    filter+=column==='canteen'?' AND instr(t.location,?)=1':` AND t.${column}=?`;params.push(text(input,200));
  }
  if(search){
    if([...search].length>=3){filter+=` AND t.rowid IN(SELECT rowid FROM ${table}_search WHERE ${table}_search MATCH ?)`;params.push('"'+search.replaceAll('"','""')+'"');}
    else{filter+=' AND instr(lower(t.search_text),lower(?))>0';params.push(search);}
  }
  const found=await rows(env.DB,`SELECT t.*,r.stars AS viewer_stars,r.created_at AS rating_created_at,r.updated_at AS rating_updated_at FROM ${table} t LEFT JOIN ${rating} r ON r.${foreignKey}=t.id AND r.user_id=? WHERE t.campus_id=? AND t.status='published'${filter} ORDER BY t.rating_average DESC,t.rating_count DESC,t.name,t.id LIMIT ? OFFSET ?`,[...params,limit,offset]);
  return found.map(({rating_created_at,rating_updated_at,...row})=>({...decode(table,row),viewer_rating:row.viewer_stars==null?null:{[foreignKey]:row.id,user_id:who.profileId,stars:row.viewer_stars,created_at:rating_created_at,updated_at:rating_updated_at}}));
}
export async function ownRatings(env:BackendEnv,who:Actor,kind:string){
  const {table,rating,foreignKey}=catalogKind(kind);
  return rows(env.DB,`SELECT r.* FROM ${rating} r JOIN ${table} t ON t.id=r.${foreignKey} WHERE r.user_id=? AND t.campus_id=? ORDER BY r.updated_at DESC,r.${foreignKey}`,[who.profileId,requireCommunity(who)]);
}
export async function suggestCatalog(env:BackendEnv,who:Actor,body:Row){
  if(body.user_id!=null&&body.user_id!==who.profileId)throw new ApiError(403,'forbidden','不能为其他用户提交。');
  const kind=text(body.suggestion_type,20);if(!['teacher','course','dish'].includes(kind))throw new ApiError(400,'bad_request','目录类型无效。');
  const credit=body.credit==null?null:Math.round(Number(body.credit)*10)/10;
  if(credit!==null&&(!Number.isFinite(credit)||credit<0||credit>999.9))throw new ApiError(400,'bad_request','学分无效。');
  const initial=body.initial_stars==null?null:integer(body.initial_stars,1,5),id=crypto.randomUUID();
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),statement(env.DB,'INSERT INTO catalog_suggestions(id,user_id,campus_id,suggestion_type,name,unit,teacher_name,category,credit,initial_stars,note) VALUES(?,?,?,?,?,?,?,?,?,?,?) RETURNING *',[id,who.profileId,requireCommunity(who),kind,text(body.name,200),text(body.unit,200),text(body.teacher_name,200,kind==='course')||null,text(body.category,100,false)||null,credit,initial,text(body.note,2000,false)||null])]);
  return {...decode('catalog_suggestions',result[result.length-2].results[0]),submitted:true};
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
