import { DatabaseSync } from 'node:sqlite';
import { readFile, readdir, writeFile, chmod } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { backupKey, tableSummary, Vault } from './snapshot.mjs';
import { encodeRow, identityRows, quote } from './convert.mjs';

export async function materialize(directory,output,key){
  const vault=new Vault(directory,key,basename(resolve(directory)));
  const manifest=await vault.getJSON('manifest'),files=await vault.getJSON('files-manifest');
  if(!manifest.complete||!files.complete||manifest.id!==files.backup_id)throw new Error('Only a complete, verified backup can be converted');
  const mapping=JSON.parse(await readFile(new URL('../../contracts/table-mapping.json',import.meta.url),'utf8'));
  const load=async table=>{
    const source=manifest.tables[table];if(!source)throw new Error(`Missing source table: ${table}`);
    const rows=[];
    for(const chunk of source.chunks){
      const part=await vault.getJSON(chunk.name,chunk);
      const summary=tableSummary(part,source.primaryKey);
      if(summary.sha256!==chunk.row_summary.sha256||summary.count!==chunk.row_summary.count)throw new Error('Source row checksum mismatch');
      rows.push(...part);
    }
    if(rows.length!==source.count)throw new Error('Source count mismatch');
    tableSummary(rows,source.primaryKey);return rows;
  };
  await writeFile(output,'',{flag:'wx',mode:0o600});
  const db=new DatabaseSync(output),summaries={};
  try{
    db.exec('PRAGMA foreign_keys=OFF; BEGIN;');
    const migrations=new URL('../../migrations/',import.meta.url);
    for(const name of (await readdir(migrations)).filter(name=>name.endsWith('.sql')).sort())db.exec(await readFile(new URL(name,migrations),'utf8'));
    db.exec("UPDATE backend_control SET mode='importing'; UPDATE migration_control SET importing=1;");
    const insert=(table,row)=>{
      const keys=Object.keys(row);
      db.prepare(`INSERT INTO ${quote(table)}(${keys.map(quote).join(',')}) VALUES(${keys.map(()=>'?').join(',')})`).run(...keys.map(k=>row[k]));
    };
    const identity=identityRows(await load('source_auth_users'),await load('source_auth_identities'));
    for(const table of ['auth_users','identity_user','identity_account']){
      for(const row of identity[table])insert(table,row);
      summaries[table]=tableSummary(identity[table],['id']);
    }
    for(const [table,meta] of Object.entries(mapping)){
      const encoded=(await load(table)).map(row=>encodeRow(meta,row));
      for(const row of encoded)insert(table,row);
      const columns=meta.columns.filter(c=>!c.generated).map(c=>quote(c.name)).join(',');
      const actual=db.prepare(`SELECT ${columns} FROM ${quote(table)}`).all().map(row=>({...row}));
      const expected=tableSummary(encoded,meta.primaryKey);
      if(tableSummary(actual,meta.primaryKey).sha256!==expected.sha256)throw new Error(`Converted data mismatch: ${table}`);
      summaries[table]=expected;
    }
    const objects=Object.values(files.objects);
    if(objects.length!==manifest.tables.source_storage_objects.count)throw new Error('Storage inventory is incomplete');
    for(const object of objects){
      await vault.get(object.chunk.name,object.chunk);
      let owner=null,post=null,attached=false;
      if(object.bucket==='community-images'){
        const image=db.prepare('SELECT p.id,p.author_id FROM post_images i JOIN posts p ON p.id=i.post_id WHERE i.path=? OR i.thumbnail_path=?').get(object.path,object.path);
        if(image){post=image.id;owner=image.author_id;attached=true;}
        else{const profile=db.prepare('SELECT id FROM profiles WHERE avatar_path=? OR cover_path=?').get(object.path,object.path);if(profile){owner=profile.id;attached=true;}}
      }else if(object.bucket==='community-attachments'){
        const attachment=db.prepare('SELECT p.id,p.author_id FROM post_attachments a JOIN posts p ON p.id=a.post_id WHERE a.path=?').get(object.path);
        if(attachment){post=attachment.id;owner=attachment.author_id;attached=true;}
      }else if(object.bucket==='community-banner-assets')attached=Boolean(db.prepare('SELECT id FROM community_banners WHERE image_path=?').get(object.path));
      else throw new Error('Unmapped Storage bucket');
      // Preserve orphans in R2 and the inventory; never infer access from storage.owner.
      if(!owner){
        const parts=object.path.split('/');
        if(['posts','avatars','profile-covers'].includes(parts[0])){
          owner=db.prepare('SELECT id FROM profiles WHERE id=?').get(parts[1])?.id??null;
          if(parts[0]==='posts')post=db.prepare('SELECT id FROM posts WHERE id=? AND author_id IS ?').get(parts[2],owner)?.id??null;
        }
      }
      insert('file_objects',{bucket:object.bucket,path:object.path,owner_id:owner,post_id:post,sha256:object.chunk.sha256,byte_size:object.chunk.bytes,content_type:object.content_type,state:attached?'attached':'uploaded'});
    }
    if(db.prepare('PRAGMA foreign_key_check').all().length)throw new Error('Converted database has orphaned foreign keys');
    if(db.prepare('PRAGMA integrity_check').get().integrity_check!=='ok')throw new Error('Converted database integrity check failed');
    db.exec("UPDATE migration_control SET importing=0; UPDATE backend_control SET mode='read_only'; COMMIT; PRAGMA foreign_keys=ON;");
    const report={backup_id:manifest.id,verified:true,tables:summaries,files:objects.length};
    await vault.putJSON('conversion-report',report);return report;
  }catch(error){
    try{db.exec('ROLLBACK');}catch{}
    throw error;
  }finally{db.close();await chmod(output,0o600);}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const [directory,output]=process.argv.slice(2);
  if(!directory||!output)throw new Error('Usage: materialize.mjs BACKUP_DIRECTORY NEW_PRIVATE_SQLITE_FILE');
  const report=await materialize(directory,output,backupKey());
  console.log(JSON.stringify({backup_id:report.backup_id,verified:true,tables:Object.keys(report.tables).length,files:report.files}));
}
