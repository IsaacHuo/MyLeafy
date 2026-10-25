"""Prepare protected production configuration from locally retained originals."""
import argparse,json,os
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--originals',required=True);parser.add_argument('--output',required=True);args=parser.parse_args()
originals=json.loads(Path(args.originals).read_text())
for name in ['AUTH_SECRET','MEDIA_SIGNING_SECRET']:
 if len(originals.get(name,''))<32:raise SystemExit('Missing retained '+name)
values={k:v for k,v in originals.items() if k in ['AUTH_SECRET','MEDIA_SIGNING_SECRET','EMAIL_API_KEY','EMAIL_FROM','TEST_EMAIL_RECIPIENT','RELEASE_PUBLISH_TOKEN','GITHUB_RELEASE_TOKEN','ANDROID_SIGNING_CERTIFICATE_SHA256']}
values.update(ENVIRONMENT='production',API_ORIGIN='https://api.myleafy.space',SITE_ORIGIN='https://myleafy.space',DATA_DIRECTORY='/var/lib/myleafy/production',PORT='3100')
# Missing publisher credentials are deliberately not substituted or rotated here.
missing=[k for k in ['RELEASE_PUBLISH_TOKEN','GITHUB_RELEASE_TOKEN','ANDROID_SIGNING_CERTIFICATE_SHA256'] if not values.get(k)]
fd=os.open(args.output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as out:
 for name,value in values.items():out.write(name+'='+json.dumps(value,ensure_ascii=False)+'\n')
print(json.dumps({'prepared':True,'missing':missing,'valuesOmitted':True}))
