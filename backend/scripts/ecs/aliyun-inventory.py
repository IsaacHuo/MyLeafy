"""Operator-only read inventory. Install official Alibaba SDKs outside tracked files."""
import json, os
from pathlib import Path
from alibabacloud_tea_openapi.models import Config
from alibabacloud_alidns20150109.client import Client as DNS
from alibabacloud_alidns20150109.models import DescribeDomainInfoRequest, DescribeDomainRecordsRequest
from alibabacloud_domain20180129.client import Client as Domain
from alibabacloud_domain20180129.models import QueryDomainByDomainNameRequest
from alibabacloud_ecs20140526.client import Client as ECS
from alibabacloud_ecs20140526.models import DescribeDisksRequest, DescribeSecurityGroupAttributeRequest
p=Path.home()/'.workbench/config.json';profiles=json.loads(p.read_text());profile=profiles['profiles'][profiles['current']]
if profile['mode']!='AK':raise SystemExit('Use configured SDK credential chain for non-AK profiles')
def config(endpoint):
 return Config(access_key_id=profile['access_key_id'],access_key_secret=profile['access_key_secret'],endpoint=endpoint,connect_timeout=10000,read_timeout=20000)
report={}
calls={
 'domain':lambda:Domain(config('domain.aliyuncs.com')).query_domain_by_domain_name(QueryDomainByDomainNameRequest(domain_name='myleafy.space')).body.to_map(),
 'dns':lambda:DNS(config('alidns.aliyuncs.com')).describe_domain_info(DescribeDomainInfoRequest(domain_name='myleafy.space',need_detail_attributes=True)).body.to_map(),
 'records':lambda:DNS(config('alidns.aliyuncs.com')).describe_domain_records(DescribeDomainRecordsRequest(domain_name='myleafy.space',page_size=500)).body.to_map(),
 'disks':lambda:ECS(config('ecs.cn-beijing.aliyuncs.com')).describe_disks(DescribeDisksRequest(region_id='cn-beijing',instance_id='i-2ze251tg6q9u5s25jkq4')).body.to_map(),
 'security':lambda:ECS(config('ecs.cn-beijing.aliyuncs.com')).describe_security_group_attribute(DescribeSecurityGroupAttributeRequest(region_id='cn-beijing',security_group_id='sg-2zej0oh30whkalnokz9r')).body.to_map(),
}
for name,call in calls.items():
 try:report[name]=call()
 except Exception as e:report[name]={'unavailable':True,'errorType':type(e).__name__,'code':getattr(e,'code',None)}
p=Path('backend/.local/ecs/aliyun-inventory.json');p.parent.mkdir(parents=True,exist_ok=True,mode=0o700);fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as f:json.dump(report,f)
print(json.dumps({name:({'unavailable':True,'code':r.get('code')} if r.get('unavailable') else {'read':True,'fields':list(r)}) for name,r in report.items()}))
