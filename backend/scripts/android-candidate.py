"""Prepare a private candidate or claim an approved publication. No rebuilding on publish."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('publish-android-release.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
origin = 'https://api.myleafy.space'


def verify(apk, version=None):
    tools = Path(os.environ['ANDROID_HOME']) / 'build-tools' / '36.0.0'
    report = subprocess.check_output([str(tools/'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
    badging = subprocess.check_output([str(tools/'aapt'), 'dump', 'badging', str(apk)], text=True)
    package, code, name = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging).groups()
    certificates = set(x.lower() for x in re.findall(r'^Signer (?:#\d+|\(.+\)) certificate SHA-256 digest: ([a-fA-F0-9]{64})\s*$', report, re.MULTILINE))
    assert len(certificates) == 1 and package == 'com.myleafy.android'
    minimum = int(re.search(r"sdkVersion:'(\d+)'", badging).group(1))
    assert minimum == 29 and re.fullmatch(r'\d+\.\d+\.\d+', name)
    if version: assert name == version
    return dict(packageName=package,versionCode=int(code),versionName=name,minSdk=minimum,
                certificateSha256=certificates.pop(),sizeBytes=apk.stat().st_size,sha256=publisher.digest(apk))


def download_asset(release, name, output):
    asset = next(asset for asset in release['assets'] if asset['name'] == name)
    with output.open('wb') as stream:
        subprocess.run(['gh','api',f"repos/{os.environ['GITHUB_REPOSITORY']}/releases/assets/{asset['id']}",
                        '-H','Accept: application/octet-stream'], stdout=stream, check=True)
    return asset['id']


def describe(apk, source):
    identity = verify(apk)
    version, code = identity['versionName'], identity['versionCode']
    manifest = apk.with_name(apk.name+'-build-info.txt')
    info = dict(id=f'com.myleafy.android-{code}',channel='official',**identity,
                releaseNotes=Path('docs/operations/android-release-notes.md').read_text(encoding='utf-8').strip(),
                commit=source,artifactKey=f'android/official/{code}/{apk.name}',
                githubReleaseUrl=f'https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v{version}')
    if manifest.exists():
        stored=json.loads(manifest.read_text(encoding='utf-8'))
        assert stored['commit']==source and all(stored[key]==value for key,value in identity.items())
        info=stored
    manifest.write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    checksum = apk.with_suffix('.apk.sha256')
    checksum.write_text(f"{info['sha256']}  {apk.name}\n",encoding='utf-8')
    return info


def prepare(apk, source):
    info=describe(apk,source)
    version,code=info['versionName'],info['versionCode']
    manifest=apk.with_name(apk.name+'-build-info.txt')
    checksum=apk.with_suffix('.apk.sha256')
    tag = f'android-candidate-{code}'
    repo = os.environ['GITHUB_REPOSITORY']
    release = publisher.find_release(repo, tag)
    if release:
        assert release['draft'] and release['target_commitish'] == source
    else:
        payload = apk.parent / 'candidate-release.json'
        payload.write_text(json.dumps(dict(tag_name=tag,target_commitish=source,draft=True,
            name=f'MyLeafy Android {version} candidate',body=info['releaseNotes']+f"\n\n[candidate-run-id: {os.environ['GITHUB_RUN_ID']}]")),encoding='utf-8')
        release = json.loads(publisher.gh('api',f'repos/{repo}/releases','-X','POST','--input',str(payload)))
    for path in (apk,manifest,checksum):
        if not any(asset['name']==path.name for asset in release['assets']):
            publisher.gh('release','upload',tag,str(path))
    release = json.loads(publisher.gh('api',f"repos/{repo}/releases/{release['id']}"))
    for path in (apk,manifest,checksum):
        output=apk.parent/('verified-'+path.name)
        download_asset(release,path.name,output)
        assert publisher.digest(output)==publisher.digest(path), 'Candidate asset changed'
    asset=next(asset for asset in release['assets'] if asset['name']==apk.name)
    publisher.request(origin+'/v1/releases/android/candidates','POST',json.dumps(dict(info,
        githubReleaseId=release['id'],githubAssetId=asset['id'],preparationRunId=int(os.environ['GITHUB_RUN_ID']))).encode(),
        os.environ['MYLEAFY_RELEASE_PUBLISH_TOKEN'],{'Content-Type':'application/json'})
    print(f'Private candidate ready: Android {version}, code {code}, commit {source}.')


def select(source, output):
    subprocess.run(['git','merge-base','--is-ancestor',source,'origin/main'],check=True)
    checks=json.loads(publisher.gh('api',f"repos/{os.environ['GITHUB_REPOSITORY']}/commits/{source}/check-runs?per_page=100"))
    assert any(c['name']=='CI result' and c['conclusion']=='success' and c['app']['slug']=='github-actions' for c in checks['check_runs']), 'CI result must pass'
    gradle=Path('android/app/build.gradle.kts').read_text(encoding='utf-8')
    version=re.search(r'versionName = "([^"]+)"',gradle).group(1)
    code=int(re.search(r'versionCode = (\d+)',gradle).group(1))
    latest=json.loads(publisher.request(origin+'/v1/releases/android/latest'))['release']
    skip=latest is not None and latest['versionCode']>=code
    formal=publisher.find_release(os.environ['GITHUB_REPOSITORY'],f'android-v{version}')
    skip=skip or (formal is not None and not formal['draft'])
    reuse=False;output.mkdir(parents=True,exist_ok=True)
    apk=output/f'MyLeafy-Android-{version}.apk'
    if not skip:
        existing=publisher.find_release(os.environ['GITHUB_REPOSITORY'],f'android-candidate-{code}')
        if existing:
            assert existing['draft']
            source=existing['target_commitish']
            subprocess.run(['git','merge-base','--is-ancestor',source,'origin/main'],check=True)
            names={asset['name'] for asset in existing['assets']}
            if {apk.name,apk.name+'-build-info.txt'}<=names:
                download_asset(existing,apk.name,apk)
                download_asset(existing,apk.name+'-build-info.txt',apk.with_name(apk.name+'-build-info.txt'))
            else:
                run=re.search(r'\[candidate-run-id: (\d+)\]',existing['body'])
                assert run, 'Incomplete candidate has no original build reference'
                publisher.gh('run','download',run.group(1),'-n',f'android-candidate-bytes-{code}','-D',str(output))
                stored=json.loads(apk.with_name(apk.name+'-build-info.txt').read_text(encoding='utf-8'))
                assert stored['commit']==source and stored['versionCode']==code and publisher.digest(apk)==stored['sha256']
            reuse=True
    with open(os.environ['GITHUB_OUTPUT'],'a') as values:
        values.write(f'skip={str(skip).lower()}\nreuse={str(reuse).lower()}\n')
    with open(os.environ['GITHUB_ENV'],'a') as values:
        values.write(f'RELEASE_SOURCE_SHA={source}\nRELEASE_APK={apk}\nRELEASE_VERSION_CODE={code}\n')


def claim(operation, output):
    payload = publisher.request(origin+f'/v1/releases/android/operations/{operation}/claim','POST',
        json.dumps({'runId':int(os.environ['GITHUB_RUN_ID'])}).encode(),os.environ['MYLEAFY_RELEASE_PUBLISH_TOKEN'],{'Content-Type':'application/json'})
    info=json.loads(payload)
    release=json.loads(publisher.gh('api',f"repos/{os.environ['GITHUB_REPOSITORY']}/releases/{info['githubReleaseId']}"))
    assert release['draft'] and release['target_commitish']==info['commit']
    output.mkdir(parents=True,exist_ok=True)
    apk=output/f"MyLeafy-Android-{info['versionName']}.apk"
    assert download_asset(release,apk.name,apk)==info['githubAssetId']
    manifest=apk.with_name(apk.name+'-build-info.txt')
    download_asset(release,manifest.name,manifest)
    stored=json.loads(manifest.read_text(encoding='utf-8'))
    assert stored=={key:value for key,value in info.items() if key not in ('githubAssetId','githubReleaseId')}
    assert all(info[key]==value for key,value in verify(apk).items())
    with open(os.environ['GITHUB_ENV'],'a') as environment:
        environment.write(f"RELEASE_SOURCE_SHA={info['commit']}\nRELEASE_APK={apk}\nRELEASE_MANIFEST={manifest}\n")


if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('mode',choices=['select','describe','prepare','claim','fail'])
    parser.add_argument('--apk',type=Path);parser.add_argument('--source');parser.add_argument('--operation');parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if args.mode=='select': select(args.source,args.output)
    elif args.mode=='describe': describe(args.apk,args.source)
    elif args.mode=='prepare': prepare(args.apk,args.source)
    elif args.mode=='claim': claim(args.operation,args.output)
    else: publisher.request(origin+f'/v1/releases/android/operations/{args.operation}/fail','POST',
        json.dumps({'runId':int(os.environ['GITHUB_RUN_ID'])}).encode(),os.environ['MYLEAFY_RELEASE_PUBLISH_TOKEN'],{'Content-Type':'application/json'})
