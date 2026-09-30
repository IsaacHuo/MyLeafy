"""Candidate recovery uses original bytes; failed uploads never trigger rebuilding."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('candidate', Path(__file__).with_name('android-candidate.py'))
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class CandidateRecoveryTest(unittest.TestCase):
    def exercise(self, complete=False, changed=False, reference=True, formal=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original_directory = Path.cwd()
            os.chdir(root)
            try:
                gradle = root / 'android/app/build.gradle.kts'
                gradle.parent.mkdir(parents=True)
                gradle.write_text('versionName = "1.3.0"\nversionCode = 6\n')
                output = root / 'artifacts'
                apk = output / 'MyLeafy-Android-1.3.0.apk'
                source = 'a' * 40
                stored = dict(commit=source, versionCode=6,
                              sha256=candidate.hashlib.sha256(b'original signed bytes').hexdigest())
                release = dict(draft=True, target_commitish=source,
                    body='[candidate-run-id: 123]' if reference else '',
                    assets=[dict(name=apk.name), dict(name=apk.name+'-build-info.txt')] if complete else [])
                downloads = []

                def restore():
                    apk.write_bytes(b'changed bytes' if changed else b'original signed bytes')
                    apk.with_name(apk.name+'-build-info.txt').write_text(json.dumps(stored))

                def gh(*args):
                    if args[:2] == ('run', 'download'):
                        downloads.append(args)
                        restore()
                        return ''
                    return json.dumps({'check_runs': [dict(name='CI result', conclusion='success',
                                                         app=dict(slug='github-actions'))]})

                def find(repo, tag):
                    if tag == 'android-v1.3.0':
                        return dict(draft=False) if formal else None
                    return release

                def download(release, name, path):
                    downloads.append(name)
                    restore()

                with patch.dict(os.environ, dict(GITHUB_REPOSITORY='IsaacHuo/MyLeafy',
                    GITHUB_OUTPUT=str(root/'output'), GITHUB_ENV=str(root/'environment'))), \
                    patch.object(candidate.subprocess, 'run'), \
                    patch.object(candidate.publisher, 'gh', gh), \
                    patch.object(candidate.publisher, 'find_release', find), \
                    patch.object(candidate.publisher, 'request', return_value=b'{"release":null}'), \
                    patch.object(candidate, 'download_asset', download):
                    if changed or (not reference and not complete and not formal):
                        with self.assertRaises(AssertionError):
                            candidate.select('b'*40, output)
                        self.assertFalse((root/'output').exists())
                    else:
                        candidate.select('b'*40, output)
                        if formal:
                            self.assertIn('skip=true', (root/'output').read_text())
                            self.assertEqual([], downloads)
                        else:
                            self.assertIn('reuse=true', (root/'output').read_text())
                            self.assertIn('RELEASE_SOURCE_SHA='+source, (root/'environment').read_text())
                            self.assertEqual(b'original signed bytes', apk.read_bytes())
                            if complete:
                                self.assertEqual([apk.name, apk.name+'-build-info.txt'], downloads)
                            else:
                                self.assertEqual(('run', 'download', '123', '-n', 'android-candidate-bytes-6',
                                                  '-D', str(output)), downloads[0])
            finally:
                os.chdir(original_directory)

    def test_partial_draft_recovers_original_run_bytes_and_source(self): self.exercise()
    def test_changed_backup_is_rejected_before_outputs(self): self.exercise(changed=True)
    def test_missing_original_run_stops_instead_of_rebuilding(self): self.exercise(reference=False)
    def test_complete_draft_uses_assets_without_backup(self): self.exercise(complete=True, reference=False)
    def test_already_published_version_skips_even_without_latest(self): self.exercise(formal=True)


if __name__ == '__main__': unittest.main()
