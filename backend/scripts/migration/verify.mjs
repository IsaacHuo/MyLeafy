import { basename, resolve } from 'node:path';
import { backupKey, tableSummary, Vault } from './snapshot.mjs';

const directory=process.argv[2];if(!directory)throw new Error('Usage: verify.mjs BACKUP_DIRECTORY');
const vault=new Vault(directory,backupKey(),basename(resolve(directory)));
const manifest=await vault.getJSON('manifest');
if(!manifest.complete)throw new Error('Incomplete database backup');
await vault.get(manifest.schema.name,manifest.schema);
let totalRows=0;
for(const table of Object.values(manifest.tables)){
  let count=0;const seen=new Set();
  for(const chunk of table.chunks){
    const rows=await vault.getJSON(chunk.name,chunk);
    const summary=tableSummary(rows,table.primaryKey);
    if(summary.sha256!==chunk.row_summary.sha256||summary.count!==chunk.row_summary.count)throw new Error('Table row checksum mismatch');
    for(const row of rows){
      const key=JSON.stringify(table.primaryKey.map(k=>row[k]));
      if(seen.has(key))throw new Error('Duplicate primary key across export chunks');seen.add(key);
    }
    count+=rows.length;
  }
  if(count!==table.count)throw new Error('Export table row count mismatch');totalRows+=count;
}
const files=await vault.getJSON('files-manifest');
if(!files.complete||files.backup_id!==manifest.id||Object.keys(files.objects).length!==manifest.tables.source_storage_objects.count)throw new Error('Incomplete file backup');
for(const object of Object.values(files.objects))await vault.get(object.chunk.name,object.chunk);
console.log(JSON.stringify({backup_id:manifest.id,verified:true,tables:Object.keys(manifest.tables).length,rows:totalRows,files:Object.keys(files.objects).length}));
