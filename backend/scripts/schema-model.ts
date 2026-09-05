export type Column = {
  table_schema: string; table_name: string; column_name: string; ordinal_position: number;
  data_type: string; udt_name: string; is_nullable: string; column_default: string | null;
  is_identity: string; is_generated: string; generation_expression: string | null;
};
export type Constraint = { schema: string; table_name: string; name: string; type: string; definition: string };
export type SourceSchema = {
  provenance: string; migrations: string[]; columns: Column[]; constraints: Constraint[];
  indexes: { schemaname: string; tablename: string; indexname: string; indexdef: string }[];
  policies: Record<string, unknown>[]; functions: { schema: string; name: string; args: string; definition: string }[];
  cron: { jobname: string; schedule: string; command: string }[];
};
export function quote(name: string): string {
  if (!/^[a-zA-Z_][a-zA-Z_0-9]*$/.test(name)) throw new Error(`Invalid schema identifier: ${name}`);
  return `"${name}"`;
}
export function targetTable(schema: string, name: string): string {
  if (!['public', 'private', 'auth'].includes(schema)) throw new Error(`Unmapped schema: ${schema}`);
  return schema === 'public' ? name : `${schema}_${name}`;
}
export function primaryKey(source: SourceSchema, schema: string, table: string): string[] {
  const key = source.constraints.find(c => c.schema === schema && c.table_name === table && c.type === 'p');
  if (!key) throw new Error(`Cannot migrate a table without a primary key: ${schema}.${table}`);
  return key.definition.match(/^PRIMARY KEY \(([^)]+)\)$/)![1].split(',').map(x => x.trim());
}
