"""Provision a dedicated Workbench identity for the existing MyLeafy ECS only."""
import argparse,json,os,re,subprocess,time
from pathlib import Path
from alibabacloud_tea_openapi.models import Config
from alibabacloud_sts20150401.client import Client as STS
from alibabacloud_ram20150501.client import Client as RAM
from alibabacloud_ram20150501.models import CreateUserRequest,CreatePolicyRequest,AttachPolicyToUserRequest,CreateAccessKeyRequest,GetUserRequest,GetPolicyRequest
INSTANCE='i-2ze251tg6q9u5s25jkq4'
USER='myleafy-github-ecs-20261026'
POLICY='MyLeafyGithubECSDeploy20261026'
REPOSITORY='IsaacHuo/MyLeafy'

def policy(account):
 if not re.fullmatch(r'[0-9]{6,}',str(account)):raise ValueError('Invalid account ID')
 target=f'acs:ecs:cn-beijing:{account}:instance/{INSTANCE}'
 return {'Version':'1','Statement':[
  {'Effect':'Allow','Action':['ecs-workbench:LoginECSInstance','ecs:StartTerminalSession'],'Resource':target},
  {'Effect':'Allow','Action':['ecs:DescribeInstances','ecs:DescribeCloudAssistantStatus','ecs-workbench:ChatMessages','ecs-workbench:EndSessions'],'Resource':'*'},
  {'Effect':'Allow','Action':'ram:CreateServiceLinkedRole','Resource':'*','Condition':{'StringEquals':{'ram:ServiceName':'workbench.ecs.aliyuncs.com'}}},
 ]}

def save(path,value):
 fd=os.open(path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
 with os.fdopen(fd,'w') as out:json.dump(value,out,indent=2)

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--directory',required=True);parser.add_argument('--apply',action='store_true');args=parser.parse_args()
 directory=Path(args.directory);directory.mkdir(parents=True,exist_ok=True,mode=0o700)
 profiles=json.loads((Path.home()/'.workbench/config.json').read_text());operator=profiles['profiles'][profiles['current']]
 if operator['mode']!='AK':raise SystemExit('Use the configured SDK chain for non-AK operator credentials')
 def config(endpoint,keys=operator):return Config(access_key_id=keys['access_key_id'],access_key_secret=keys['access_key_secret'],endpoint=endpoint,connect_timeout=10000,read_timeout=20000)
 account=STS(config('sts.aliyuncs.com')).get_caller_identity().body.to_map()['AccountId']
 document=policy(account);policy_path=directory/'ci-policy.json'
 if not policy_path.exists():save(policy_path,document)
 if not args.apply:print(json.dumps({'prepared':True,'user':USER,'instance':INSTANCE,'applied':False}));return
 ram=RAM(config('ram.aliyuncs.com'));credential_path=directory/'ci-credentials.json'
 if credential_path.exists():
  keys=json.loads(credential_path.read_text())
  if keys['user']!=USER or keys['account']!=account or keys['instance']!=INSTANCE:raise ValueError('Saved CI identity mismatch')
 else:
  for request,method,absent in [(GetUserRequest(user_name=USER),ram.get_user,'EntityNotExist.User'),(GetPolicyRequest(policy_name=POLICY,policy_type='Custom'),ram.get_policy,'EntityNotExist.Policy')]:
   try:method(request)
   except Exception as error:
    if getattr(error,'code',None)==absent:continue
    raise
   raise ValueError('Existing cloud identity requires ownership inspection')
  # No console login profile or password is created.
  ram.create_user(CreateUserRequest(user_name=USER,display_name='MyLeafy GitHub ECS deploy',comments='Managed MyLeafy deployment identity for '+INSTANCE))
  ram.create_policy(CreatePolicyRequest(policy_name=POLICY,policy_document=json.dumps(document),description='MyLeafy Workbench deployment to '+INSTANCE+' only'))
  ram.attach_policy_to_user(AttachPolicyToUserRequest(user_name=USER,policy_name=POLICY,policy_type='Custom'))
  access=ram.create_access_key(CreateAccessKeyRequest(user_name=USER)).body.to_map()['AccessKey']
  keys={'user':USER,'account':account,'instance':INSTANCE,'access_key_id':access['AccessKeyId'],'access_key_secret':access['AccessKeySecret']}
  save(credential_path,keys)
 for attempt in range(4):
  try:identity=STS(config('sts.aliyuncs.com',keys)).get_caller_identity().body.to_map();break
  except Exception as error:
   if getattr(error,'code',None)!='InvalidAccessKeyId.NotFound' or attempt==3:raise
   time.sleep(2**(attempt+1))
 if identity.get('AccountId')!=account or identity.get('IdentityType')=='Account':raise ValueError('CI must use a dedicated identity in the same account')
 for environment in ['staging','production']:
  for name,value in [('ALIYUN_WORKBENCH_ACCESS_KEY_ID',keys['access_key_id']),('ALIYUN_WORKBENCH_ACCESS_KEY_SECRET',keys['access_key_secret'])]:
   subprocess.run(['gh','secret','set',name,'--repo',REPOSITORY,'--env',environment],input=value,text=True,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  print(json.dumps({'environment':environment,'dedicatedCISecretsConfigured':True,'valuesOmitted':True}))
 report={'user':USER,'policy':POLICY,'instance':INSTANCE,'environments':['staging','production'],'consoleLoginCreated':False}
 report_path=directory/'ci-provisioned.json'
 if not report_path.exists():save(report_path,report)
 elif json.loads(report_path.read_text())!=report:raise ValueError('Existing CI provisioning report mismatch')

if __name__=='__main__':
 try:main()
 except Exception as error:
  print(json.dumps({'failed':True,'errorType':type(error).__name__,'code':getattr(error,'code',None),'detailsOmitted':True}));raise SystemExit(1)
