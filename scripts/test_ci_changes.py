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
