import { canonical } from './snapshot.mjs';

const maxInteger=BigInt(Number.MAX_SAFE_INTEGER);
export function timestamp(value){
  const date=new Date(value);if(!Number.isFinite(date.getTime()))throw new Error('Invalid timestamp');
  const fraction=String(value).match(/\.(\d+)(?:Z|[+-])/i)?.[1]??'';
  if(fraction.length>6&&/[1-9]/.test(fraction.slice(6)))throw new Error('Timestamp precision exceeds PostgreSQL microseconds');
  return date.toISOString().slice(0,23)+fraction.padEnd(6,'0').slice(3,6)+'Z';
}
export function normalizeSource(value){
  if(value instanceof Date)return value.toISOString();
  if(Buffer.isBuffer(value))return {encoding:'base64',data:value.toString('base64')};
  if(Array.isArray(value))return value.map(normalizeSource);
  if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,normalizeSource(v)]));
  return value;
}
export function encodeRow(meta,row){
  const result={};
  const known=new Set(meta.columns.map(c=>c.name));
  for(const key of Object.keys(row))if(!known.has(key))throw new Error(`Unmapped source column: ${key}`);
  for(const column of meta.columns){
    if(column.generated)continue;
    if(!(column.name in row))throw new Error(`Missing source column: ${column.name}`);
    const value=row[column.name];
    if(value===null){if(!column.nullable)throw new Error(`Unexpected null: ${column.name}`);result[column.name]=null;continue;}
    switch(column.type){
      case 'boolean':
        if(typeof value!=='boolean')throw new Error(`Invalid boolean: ${column.name}`);
        result[column.name]=value?1:0;break;
      case 'jsonb':result[column.name]=canonical(value);break;
      case 'bigint':case 'integer':{
        if(!/^-?\d+$/.test(String(value)))throw new Error(`Invalid integer: ${column.name}`);
        const integer=BigInt(value);
        // D1's JS/HTTP bindings use JSON numbers. Never silently truncate an ID.
        if(integer>maxInteger||integer< -maxInteger)throw new Error(`Integer exceeds D1 client precision: ${column.name}`);
        result[column.name]=Number(integer);break;
      }
      case 'numeric':case 'double precision':{
        const number=Number(value);
        if(!Number.isFinite(number)||Math.abs(number)>Number.MAX_SAFE_INTEGER)throw new Error(`Unsafe numeric value: ${column.name}`);
        if(column.type==='numeric'&&String(value).replace(/[-.0]/g,'').length>15)throw new Error(`Numeric requires an explicit exact-decimal mapping: ${column.name}`);
        result[column.name]=number;break;
      }
      case 'timestamp with time zone':{
        result[column.name]=timestamp(value);break;
      }
      case 'uuid':case 'text':case 'inet':case 'date':
        if(typeof value!=='string')throw new Error(`Invalid text: ${column.name}`);
        result[column.name]=value;break;
      default:throw new Error(`Unmapped source type: ${column.type}`);
    }
  }
  if(Buffer.byteLength(canonical(result))>1_900_000)throw new Error('Row exceeds the safe D1 size bound');
  return result;
}

export function quote(name){
  if(!/^[a-zA-Z_][a-zA-Z_0-9]*$/.test(name))throw new Error('Invalid SQL identifier');
  return `"${name}"`;
}
export function literal(value){
  if(value===null)return 'NULL';
  if(typeof value==='number'&&Number.isFinite(value))return String(value);
  if(typeof value==='string')return `CAST(X'${Buffer.from(value,'utf8').toString('hex')}' AS TEXT)`;
  throw new Error('SQL export only accepts encoded database values');
}
export function upsertSQL(table,row,primaryKey){
  const keys=Object.keys(row);
  if(!primaryKey.length||primaryKey.some(k=>!(k in row)))throw new Error('Missing primary key');
  const updates=keys.filter(k=>!primaryKey.includes(k));
  const sql=`INSERT INTO ${quote(table)}(${keys.map(quote).join(',')}) VALUES(${keys.map(k=>literal(row[k])).join(',')}) ON CONFLICT(${primaryKey.map(quote).join(',')}) ${updates.length?'DO UPDATE SET '+updates.map(k=>`${quote(k)}=excluded.${quote(k)}`).join(','):'DO NOTHING'};`;
  if(Buffer.byteLength(sql)>95_000)throw new Error('Row needs a bound-parameter import because its SQL exceeds D1 statement limits');
  return sql;
}

/** UUIDs and credential hashes stay stable; sessions are exchanged or recreated. */
export function identityRows(users,identities){
  const output={auth_users:[],identity_user:[],identity_account:[]};
  const seenEmails=new Set(),knownUsers=new Set();
  for(const user of users){
    if(user.deleted_at)continue;
    if(user.phone||user.is_sso_user)throw new Error('Unsupported identity provider requires an explicit migration mapping');
    knownUsers.add(user.id);
    const created=Date.parse(user.created_at),updated=Date.parse(user.updated_at??user.created_at);
    if(!Number.isFinite(created)||!Number.isFinite(updated))throw new Error('Invalid identity timestamps');
    const anonymous=user.is_anonymous===true;
    const email=user.email?.trim().toLowerCase()||`${user.id}@anonymous.invalid`;
    if(!anonymous&&!user.email)throw new Error('Non-anonymous account has no email');
    if(seenEmails.has(email))throw new Error('Identity email collision');seenEmails.add(email);
    if(user.encrypted_password&&!/^\$2[aby]\$\d\d\$/.test(user.encrypted_password))throw new Error('Unsupported password hash algorithm');
    output.auth_users.push({id:user.id,email:user.email||null,email_verified:user.email_confirmed_at?1:0,is_anonymous:anonymous?1:0,banned_until:user.banned_until?timestamp(user.banned_until):null,created_at:timestamp(user.created_at),updated_at:timestamp(user.updated_at??user.created_at)});
    output.identity_user.push({id:user.id,name:user.raw_user_meta_data?.name||email,email,emailVerified:user.email_confirmed_at?1:0,isAnonymous:anonymous?1:0,image:null,createdAt:created,updatedAt:updated});
    if(user.encrypted_password)output.identity_account.push({id:user.id,issuer:'local:credential',accountId:user.id,providerId:'credential',userId:user.id,password:user.encrypted_password,createdAt:created,updatedAt:updated});
  }
  for(const identity of identities){
    if(!knownUsers.has(identity.user_id))continue;
    if(identity.provider!=='email')throw new Error(`Unsupported identity provider: ${identity.provider}`);
  }
  return output;
}
