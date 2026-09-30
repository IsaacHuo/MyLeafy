"""Dependency-aware CI selection. Used by the single required CI gate."""
import argparse
import json
import os
import subprocess


def affected(paths):
    result = dict.fromkeys(('ios', 'android', 'backend', 'site', 'supabase'), False)
    for path in paths:
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
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', required=True)
    args = parser.parse_args()
    if set(args.base) == {'0'}:
        paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', args.head], text=True).splitlines()
    else:
        subprocess.run(['git', 'diff', '--check', args.base, args.head], check=True)
        paths = subprocess.check_output(['git', 'diff', '--name-only', args.base, args.head], text=True).splitlines()
    selected = affected(paths)
    print(json.dumps(selected))
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for name, value in selected.items():
            output.write(f'{name}={str(value).lower()}\n')
