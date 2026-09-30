"""Publish one verified signed artifact to GitHub and Cloudflare; safe to resume a partial run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.request
import urllib.parse


def gh(*arguments):
    return subprocess.check_output(['gh', *arguments], text=True).strip()


def request(url, method='GET', data=None, token=None, headers=None):
    values = {'User-Agent':'MyLeafyReleasePublisher/1.0', **dict(headers or {})}
    if token:
        values['Authorization'] = f'Bearer {token}'
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=values, method=method), timeout=120) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        # Deliberately omit response bodies/headers and credentials from CI diagnostics.
        raise RuntimeError(f'{method} {url}: HTTP {error.code}') from None


def digest(path):
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''): digest.update(chunk)
        return digest.hexdigest()


def find_release(repository, tag):
    # An Actions token can create a draft that REST's list/by-tag endpoints omit.
    owner, name = repository.split('/')
    query = 'query($owner:String!,$name:String!,$tag:String!){repository(owner:$owner,name:$name){release(tagName:$tag){databaseId}}}'
    result = json.loads(gh('api', 'graphql', '-f', f'query={query}', '-F', f'owner={owner}', '-F', f'name={name}', '-F', f'tag={tag}'))
    node = result['data']['repository']['release']
    return json.loads(gh('api', f"repos/{repository}/releases/{node['databaseId']}")) if node else None


def publish(apk: Path, manifest: Path, origin: str, operation: str):
    info = json.loads(manifest.read_text(encoding='utf-8'))
    token = os.environ['MYLEAFY_RELEASE_PUBLISH_TOKEN']
    tag = f"android-v{info['versionName']}"
    repository = os.environ['GITHUB_REPOSITORY']
    assert origin in ('https://api.myleafy.space', 'https://api-staging.myleafy.space')
    assert info['commit'] == os.environ['RELEASE_SOURCE_SHA']
    assert info['sizeBytes'] == apk.stat().st_size and info['sha256'] == digest(apk)
    checksum = apk.with_suffix('.apk.sha256')
    checksum.write_text(f"{info['sha256']}  {apk.name}\n", encoding='utf-8')
    notes = apk.parent / 'release-notes.md'
    notes.write_text(info['releaseNotes'], encoding='utf-8')
    files = [apk, checksum, manifest]
    release = find_release(repository, tag)
    if release is None:
        payload = apk.parent / 'github-release.json'
        payload.write_text(json.dumps(dict(tag_name=tag,target_commitish=info['commit'],draft=True,
            name=f"MyLeafy Android {info['versionName']}",body=info['releaseNotes'])),encoding='utf-8')
        release = json.loads(gh('api', f'repos/{repository}/releases', '-X', 'POST', '--input', str(payload)))
    assert release['target_commitish'] == info['commit'], 'Release tag belongs to another commit'
    assert release['body'].strip() == info['releaseNotes'].strip(), 'Release notes differ'
    assets = {asset['name']:asset for asset in release['assets']}
    for path in files:
        if path.name not in assets:
            url = release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(path.name)
            assets[path.name] = json.loads(request(url,'POST',path.read_bytes(),os.environ['GH_TOKEN'],
                {'Content-Type':'application/octet-stream','Content-Length':str(path.stat().st_size)}))
    # Verify GitHub assets before opening its draft, including resumed runs.
    verification = apk.parent / 'github-verification'
    verification.mkdir(exist_ok=True)
    for path in files:
        with (verification / path.name).open('wb') as output:
            subprocess.run(['gh','api',f"repos/{repository}/releases/assets/{assets[path.name]['id']}",
                '-H','Accept: application/octet-stream'],stdout=output,check=True)
        assert digest(verification / path.name) == digest(path), f'GitHub artifact mismatch: {path.name}'
    download_origin = 'https://downloads.myleafy.space' if origin == 'https://api.myleafy.space' else 'https://downloads-staging.myleafy.space'
    for path in files:
        key = info['artifactKey'] if path == apk else info['artifactKey'] + ('.sha256' if path == checksum else '-build-info.txt')
        data = path.read_bytes()
        request(f'{origin}/v1/releases/artifacts/{key}?operation={urllib.parse.quote(operation)}', 'PUT', data, token,
                {'Content-Type':'application/octet-stream', 'Content-Length':str(len(data)), 'X-Artifact-SHA256':digest(path)})
        received = request(f'{download_origin}/{key}')
        assert len(received) == len(data) and hashlib.sha256(received).hexdigest() == digest(path), f'Cloudflare readback mismatch: {path.name}'
    opened = False
    try:
        if release['draft']:
            gh('api', f"repos/{repository}/releases/{release['id']}", '-X', 'PATCH', '-F', 'draft=false')
            opened = True
        registered = json.loads(request(f'{origin}/v1/releases/android/publish?operation={urllib.parse.quote(operation)}', 'POST', json.dumps(info).encode(), token, {'Content-Type':'application/json'}))
        assert registered['sha256'] == info['sha256']
    except Exception:
        # Never report success with only one catalogue published. Keep bytes for a safe retry.
        # If registration succeeded but its response was lost, preserve a matching public pair.
        try:
            existing = json.loads(request(f"{origin}/v1/releases/android/{info['packageName']}-{info['versionCode']}"))
            registered = existing if existing['sha256'] == info['sha256'] else None
        except Exception:
            registered = None
        if registered is None:
            if opened:
                gh('api', f"repos/{repository}/releases/{release['id']}", '-X', 'PATCH', '-F', 'draft=true')
            raise
    published = json.loads(gh('api', f"repos/{repository}/releases/{release['id']}"))
    latest = json.loads(request(f"{origin}/v1/releases/android/latest?package={info['packageName']}"))['release']
    assert not published['draft'] and latest['versionCode'] == info['versionCode'] and latest['sha256'] == info['sha256']
    print(f"Published {tag}: Cloudflare and GitHub verified identical APK ({info['sha256']}).")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--origin', default='https://api.myleafy.space')
    parser.add_argument('--operation', required=True)
    args = parser.parse_args()
    publish(args.apk, args.manifest, args.origin, args.operation)
