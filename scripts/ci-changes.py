"""Dependency-aware CI selection. Used by the single required CI gate."""
import argparse
import json
import os
import subprocess

PLATFORMS = ('ios', 'android', 'backend', 'site', 'supabase')


def scope_selection(scope):
    if scope not in (*PLATFORMS, 'all'):
        raise ValueError(f'Unknown validation scope: {scope}')
    return {name: scope in ('all', name) for name in PLATFORMS}


def affected(paths):
    result = dict.fromkeys(PLATFORMS, False)
    for path in paths:
        if path == '.editorconfig':
            result.update(ios=True, android=True)
        if path in ('.swiftformat', 'scripts/format-swift.sh'):
            result['ios'] = True
        workflow_platform = {
            '.github/workflows/ios-ci.yml': ('ios',),
            '.github/workflows/android-ci.yml': ('android',),
            '.github/workflows/android-prepare.yml': ('android',),
            '.github/workflows/android-release.yml': ('android',),
            '.github/workflows/backend-ci.yml': ('backend',),
            '.github/workflows/site-ci.yml': ('site',),
            '.github/workflows/supabase-ci.yml': ('supabase',),
            '.github/workflows/cloudflare-staging.yml': ('backend', 'site'),
            '.github/workflows/cloudflare-production.yml': ('backend', 'site'),
            '.github/workflows/cloudflare-recovery.yml': ('backend', 'site'),
            '.github/workflows/release.yml': ('ios',),
        }.get(path)
        if workflow_platform is not None:
            result.update(dict.fromkeys(workflow_platform, True))
            continue
        if path.startswith(('.github/workflows/', 'scripts/ci-', 'scripts/test_ci_')):
            return dict.fromkeys(result, True)
        if path.startswith(('leafy/', 'leafyTests/', 'leafyWidget/', 'LeafyWidgetShared/',
                            'LeafyShareExtension/', 'LeafyExternalImportShared/', 'Config/', 'leafy.xcodeproj/')):
            result['ios'] = True
        if path.startswith('leafy/'):
            result['backend'] = True  # backend's contract scan reads Swift sources
        if path.startswith('android/'):
            result['android'] = True
        if path.startswith('backend/'):
            result.update(backend=True, site=True)
        if path.startswith('site/'):
            result['site'] = True
        if path.startswith('site/src/admin/'):
            result['backend'] = True  # admin action registry is a server contract
        if path.startswith('contracts/'):
            result.update(ios=True, android=True, backend=True, site=True)
        if path.startswith('supabase/'):
            result['supabase'] = True
        if path == 'scripts/check-layer-boundaries.sh':
            result.update(ios=True, supabase=True)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--base')
    parser.add_argument('--head')
    parser.add_argument('--scope', choices=(*PLATFORMS, 'all'))
    args = parser.parse_args()
    if args.scope:
        if args.base or args.head:
            parser.error('--scope cannot be combined with --base/--head')
        selected = scope_selection(args.scope)
    elif not args.base or not args.head:
        parser.error('provide --scope or both --base and --head')
    elif set(args.base) == {'0'}:
        paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', args.head], text=True).splitlines()
        selected = affected(paths)
    else:
        subprocess.run(['git', 'diff', '--check', args.base, args.head], check=True)
        paths = subprocess.check_output(['git', 'diff', '--name-only', args.base, args.head], text=True).splitlines()
        selected = affected(paths)
    print(json.dumps(selected))
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for name, value in selected.items():
            output.write(f'{name}={str(value).lower()}\n')
