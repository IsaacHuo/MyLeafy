import unittest
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

spec = spec_from_file_location('changes', Path(__file__).with_name('ci-changes.py'))
changes = module_from_spec(spec)
spec.loader.exec_module(changes)


class SelectionTests(unittest.TestCase):
    def test_docs_do_not_build_clients(self):
        self.assertFalse(any(changes.affected(['docs/operations/delivery.md']).values()))

    def test_cross_directory_contracts(self):
        self.assertTrue(changes.affected(['site/src/admin/registry.ts'])['backend'])
        self.assertTrue(changes.affected(['leafy/Core/Client.swift'])['backend'])
        self.assertTrue(changes.affected(['backend/src/admin-router.ts'])['site'])
        self.assertTrue(changes.affected(['contracts/api.json'])['android'])

    def test_workflow_changes_validate_all_jobs(self):
        self.assertTrue(all(changes.affected(['.github/workflows/ci.yml']).values()))

    def test_swift_formatting_configuration_selects_ios(self):
        for path in ('.swiftformat', 'scripts/format-swift.sh'):
            with self.subTest(path=path):
                self.assertEqual(changes.affected([path]), dict(
                    ios=True, android=False, backend=False, site=False, supabase=False))

    def test_shared_editor_settings_select_both_clients(self):
        self.assertEqual(changes.affected(['.editorconfig']), dict(
            ios=True, android=True, backend=False, site=False, supabase=False))

    def test_new_sources_and_gradle_configuration_select_their_platform(self):
        for path, platform in (
            ('LeafyExternalImportShared/NewImport.swift', 'ios'),
            ('leafyTests/NewTests.swift', 'ios'),
            ('android/app/src/androidTest/java/NewTest.kt', 'android'),
            ('android/build.gradle.kts', 'android'),
            ('android/gradle/libs.versions.toml', 'android'),
        ):
            with self.subTest(path=path):
                self.assertTrue(changes.affected([path])[platform])

    def test_status_and_contribution_docs_do_not_build_clients(self):
        self.assertFalse(any(changes.affected([
            'state/PLATFORMS.md', 'AGENTS.md', 'CONTRIBUTING.md',
            '.github/ISSUE_TEMPLATE/bug_report.yml', '.github/pull_request_template.md',
        ]).values()))
