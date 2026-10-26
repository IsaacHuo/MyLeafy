"""Plan a complete DNS import; applying requires the saved plan and filing approval."""
import argparse, hashlib, json, os, re
from pathlib import Path
import dns.zonefile, dns.rdatatype, dns.name, dns.rdataclass, dns.tokenizer
from alibabacloud_tea_openapi.models import Config
from alibabacloud_alidns20150109.client import Client
from alibabacloud_alidns20150109.models import DescribeDomainRecordsRequest, AddDomainRecordRequest
DOMAIN='myleafy.space'
SERVICE_HOSTS=['@','www','api','downloads','api-staging','downloads-staging','staging']

def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def identity(r):return (r['RR'],r['Type'],r.get('Line','default'),r['Value'],r.get('Priority',0))
def desired_records(source):
 text=Path(source).read_text(encoding='utf-8-sig')
 # Cloudflare exports its apex SOA owner without a final dot even though every
 # other owner is absolute. Normalize only that known export form.
 text=re.sub(r'(?im)^('+re.escape(DOMAIN)+r')(?=[ \t]+(?:[0-9]+[ \t]+)?(?:IN[ \t]+)?SOA[ \t])',r'\1.',text)
 manager=dns.zonefile.RRSetsReaderManager(dns.name.from_text(DOMAIN),True,dns.rdataclass.IN)
 with manager.writer(True) as transaction:
  reader=dns.zonefile.Reader(dns.tokenizer.Tokenizer(text),dns.rdataclass.IN,transaction,allow_directives={'$ORIGIN','$TTL'})
  # Cloudflare flattens service CNAMEs alongside apex NS/TXT. Those service
  # addresses are replaced by A records below, so only skip that zone-rule check.
  check=transaction._check_put_rdataset[-1]
  transaction._check_put_rdataset[-1]=lambda tx,name,data: None if name.to_text() in SERVICE_HOSTS else check(tx,name,data)
  reader.read()
 output=[{'RR':rr,'Type':'A','Value':'8.141.82.15','TTL':600,'Line':'default'} for rr in SERVICE_HOSTS]
 for rdataset in manager.rrsets:
  if rdataset.name.is_absolute():raise ValueError('Out-of-zone record owner')
  rr=rdataset.name.to_text()
  kind=dns.rdatatype.to_text(rdataset.rdtype)
  if kind=='SOA' or kind=='NS' and rr=='@' or rr in SERVICE_HOSTS and kind in ['A','AAAA','CNAME']:continue
  if kind not in ['A','AAAA','CNAME','MX','TXT','CAA','SRV','NS']:raise ValueError('Unsupported source DNS record type: '+kind)
  for data in rdataset:
   value=data.to_text(origin=dns.name.from_text(DOMAIN),relativize=False);record={'RR':rr,'Type':kind,'Value':value,'TTL':max(600,rdataset.ttl),'Line':'default'}
   if kind=='MX':record.update(Value=data.exchange.derelativize(dns.name.from_text(DOMAIN)).to_text().rstrip('.'),Priority=data.preference)
   elif kind in ['CNAME','NS']:record['Value']=data.target.derelativize(dns.name.from_text(DOMAIN)).to_text().rstrip('.')
   elif kind=='TXT':record['Value']=b''.join(data.strings).decode('utf-8')
   if kind=='CNAME' and any(v in record['Value'].lower() for v in ['pages.dev','workers.dev','r2.dev','cloudflare']):raise ValueError('Additional Cloudflare service requires explicit target mapping: '+rr)
   if identity(record) not in {identity(r) for r in output}:output.append(record)
 return output

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--source');parser.add_argument('--plan',required=True);parser.add_argument('--apply',action='store_true');parser.add_argument('--filing-approved',action='store_true');args=parser.parse_args()
 config=json.loads((Path.home()/'.workbench/config.json').read_text());profile=config['profiles'][config['current']]
 if profile['mode']!='AK':raise SystemExit('Use the configured SDK chain for non-AK profiles')
 client=Client(Config(access_key_id=profile['access_key_id'],access_key_secret=profile['access_key_secret'],endpoint='alidns.aliyuncs.com',connect_timeout=10000,read_timeout=20000))
 current=[];page=1
 while True:
  body=client.describe_domain_records(DescribeDomainRecordsRequest(domain_name=DOMAIN,page_size=500,page_number=page)).body.to_map()
  current+=body.get('DomainRecords',{}).get('Record',[])
  if len(current)>=body['TotalCount']:break
  page+=1
 current=sorted(current,key=lambda r:r['RecordId'])
 if not args.apply:
  if not args.source:raise SystemExit('--source Cloudflare BIND export required')
  desired=desired_records(args.source)
  for r in current:
   if r['RR'] in SERVICE_HOSTS and r['Type'] in ['A','AAAA','CNAME'] and identity(r) not in {identity(d) for d in desired}:raise SystemExit('Existing service record conflicts; preserve and review it before changing DNS')
  plan={'version':1,'domain':DOMAIN,'sourceSHA256':hashlib.sha256(Path(args.source).read_bytes()).hexdigest(),'currentSHA256':digest(current),'add':[r for r in desired if identity(r) not in {identity(c) for c in current}],'preservedExisting':len(current)}
  fd=os.open(args.plan,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
  with os.fdopen(fd,'w') as out:json.dump(plan,out,ensure_ascii=False,indent=2)
  print(json.dumps({'planned':len(plan['add']),'existingPreserved':len(current),'applied':False}));return
 if not args.filing_approved:raise SystemExit('Filing and owner acceptance are required before applying')
 plan=json.loads(Path(args.plan).read_text())
 if plan['version']!=1 or plan['domain']!=DOMAIN or plan['currentSHA256']!=digest(current):raise SystemExit('DNS changed since planning; regenerate the plan')
 completed=[]
 try:
  for record in plan['add']:
   # This operation adds only the reviewed records. It never deletes other DNS data.
   result=client.add_domain_record(AddDomainRecordRequest(domain_name=DOMAIN,rr=record['RR'],type=record['Type'],value=record['Value'],ttl=record['TTL'],line=record['Line'],priority=record.get('Priority')))
   completed.append({'recordId':result.body.record_id,'RR':record['RR'],'Type':record['Type']})
 finally:
  Path(args.plan+'.applied.json').write_text(json.dumps({'domain':DOMAIN,'created':completed,'expected':len(plan['add']),'complete':len(completed)==len(plan['add'])},indent=2))
 print(json.dumps({'applied':len(completed),'domain':DOMAIN}))
if __name__=='__main__':main()
