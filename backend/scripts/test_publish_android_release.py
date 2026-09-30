"""Release coordinator tests: no network, real temporary artifact bytes."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('publish-android-release.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class ReleaseCoordinatorTest(unittest.TestCase):
    def exercise(self, failure=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / 'MyLeafy-Android-1.2.0.apk'
            apk.write_bytes(b'isolated coordinator fixture')
            info = dict(versionName='1.2.0',versionCode=4,packageName='com.myleafy.android',commit='a'*40,
                sizeBytes=apk.stat().st_size,sha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
                artifactKey='android/official/4/'+apk.name,releaseNotes='Test release')
            manifest = root / (apk.name+'-build-info.txt')
            manifest.write_text(json.dumps(info))
            release = dict(id=7,draft=True,tag_name='android-v1.2.0',target_commitish='a'*40,
                body='Test release',assets=[],upload_url='https://uploads.github.com/releases/7/assets{?name}')
            uploaded = {}
            cloud = {}
            transitions = []

            def gh(*arguments):
                if arguments[1] == 'graphql': return json.dumps({'data':{'repository':{'release':None}}})
                if '-X' in arguments and 'POST' in arguments: return json.dumps(release)
                if '-X' in arguments and 'PATCH' in arguments:
                    release['draft'] = arguments[-1] == 'draft=true'
                    transitions.append(release['draft'])
                return json.dumps(release)

            def request(url, method='GET', data=None, token=None, headers=None):
                if url.startswith('https://uploads.github.com/'):
                    identifier = len(uploaded)+1
                    uploaded[identifier] = data
                    return json.dumps({'id':identifier}).encode()
                if method == 'PUT': cloud[url.split('/artifacts/')[1].split('?')[0]] = data; return b'{}'
                if url.startswith('https://downloads.myleafy.space/'): return cloud[url.split('space/')[1]]
                if method == 'POST' and failure: raise RuntimeError('Lost registration response')
                if url.endswith('/com.myleafy.android-4') and failure == 'uncommitted': raise RuntimeError('Not published')
                if '/latest?' in url: return json.dumps({'release':info}).encode()
                return json.dumps(info).encode()

            def download(arguments, stdout, check):
                stdout.write(uploaded[int(arguments[2].split('/')[-1])])

            with patch.dict(os.environ, {'GH_TOKEN':'test-only','MYLEAFY_RELEASE_PUBLISH_TOKEN':'test-only',
                'RELEASE_SOURCE_SHA':'a'*40,'GITHUB_REPOSITORY':'IsaacHuo/MyLeafy'}), \
                patch.object(publisher,'gh',gh), patch.object(publisher,'request',request), \
                patch.object(publisher.subprocess,'run',download), \
                patch.object(publisher,'digest',lambda path:hashlib.sha256(path.read_bytes()).hexdigest()):
                if failure == 'uncommitted':
                    with self.assertRaises(RuntimeError): publisher.publish(apk,manifest,'https://api.myleafy.space','approved-test-operation')
                    self.assertEqual([False,True],transitions)
                else:
                    publisher.publish(apk,manifest,'https://api.myleafy.space','approved-test-operation')
                    self.assertEqual([False],transitions)
                self.assertEqual(3,len(uploaded))
                self.assertEqual(3,len(cloud))

    def test_created_draft_uses_returned_id_and_verifies_both_catalogues(self): self.exercise()
    def test_failed_registration_returns_new_github_release_to_draft(self): self.exercise('uncommitted')
    def test_lost_response_preserves_verified_public_pair(self): self.exercise('committed')


if __name__ == '__main__': unittest.main()
