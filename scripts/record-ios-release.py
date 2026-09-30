"""Record an Apple-released binary's source; never builds or uploads an unsigned archive."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def versions(project):
    return (set(re.findall(r'MARKETING_VERSION = ([0-9.]+);', project)),
            set(re.findall(r'CURRENT_PROJECT_VERSION = ([0-9]+);', project)))


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--version',required=True);parser.add_argument('--build',required=True);parser.add_argument('--commit',required=True)
    args=parser.parse_args()
    assert re.fullmatch(r'\d+\.\d+(?:\.\d+)?',args.version) and args.build.isdigit() and re.fullmatch('[a-f0-9]{40}',args.commit)
    assert versions(Path('leafy.xcodeproj/project.pbxproj').read_text(encoding='utf-8'))==({args.version},{args.build}), 'App and extension versions must match'
    assert subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()==args.commit
    subprocess.run(['git','merge-base','--is-ancestor',args.commit,'origin/main'],check=True)
    tag='v'+args.version
    subprocess.run(['git','config','user.name','github-actions[bot]'],check=True)
    subprocess.run(['git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com'],check=True)
    existing=subprocess.run(['git','rev-parse','--verify',f'refs/tags/{tag}'],capture_output=True,text=True)
    if existing.returncode == 0:
        assert subprocess.check_output(['git','cat-file','-t',f'refs/tags/{tag}'],text=True).strip()=='tag', 'Release tag must be annotated'
        assert subprocess.check_output(['git','rev-parse',f'{tag}^{{commit}}'],text=True).strip()==args.commit, 'Release tag is immutable'
    else:
        subprocess.run(['git','tag','-a',tag,args.commit,'-m',f'MyLeafy iOS {args.version}, build {args.build}, Apple release confirmed; source {args.commit}'],check=True)
    subprocess.run(['git','push','origin',tag],check=True)
    body=Path(os.environ['RUNNER_TEMP'])/'ios-release-notes.md'
    body.write_text(f'iOS {args.version} / build {args.build}\n\nReleased through App Store Connect.\nSource: {args.commit}\n\nNo unsigned archive or signing material is attached.\n',encoding='utf-8')
    releases=json.loads(subprocess.check_output(['gh','api',f"repos/{os.environ['GITHUB_REPOSITORY']}/releases?per_page=100"],text=True))
    released=next((r for r in releases if r['tag_name']==tag),None)
    if released:
        assert not released['draft'] and not released['prerelease'] and not released['assets'], 'Existing iOS release does not match the source-only record'
        assert args.commit in released['body'] and f'build {args.build}' in released['body'], 'Existing release identifies different source or build'
    else:
        subprocess.run(['gh','release','create',tag,'--verify-tag','--title',f'MyLeafy iOS {args.version}','--notes-file',str(body)],check=True)
