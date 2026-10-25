/** Provider-independent SQL identifier quoting and derived-schema classification. */
export const quote=name=>'"'+name.replaceAll('"','""')+'"';
export function inspectSchema(schema){
 const virtual=schema.filter(s=>s.type==='table'&&/^CREATE VIRTUAL TABLE/i.test(s.sql));
 const tables=schema.filter(s=>s.type==='table'&&!virtual.some(v=>s.name===v.name||s.name.startsWith(v.name+'_')));
 return {tables,virtual,other:schema.filter(s=>s.type!=='table')};
}
