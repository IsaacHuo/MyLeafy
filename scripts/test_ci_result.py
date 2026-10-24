import copy
import unittest
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

spec = spec_from_file_location('ci_result', Path(__file__).with_name('ci-result.py'))
gate = module_from_spec(spec)
spec.loader.exec_module(gate)


class ResultTests(unittest.TestCase):
    def jobs(self):
        return {
            'changes': {'result': 'success', 'outputs': {name: 'false' for name in gate.PLATFORMS}},
            'safety': {'result': 'success'},
            **{name: {'result': 'skipped'} for name in gate.PLATFORMS},
        }

    def test_docs_only_and_selected_success(self):
        jobs = self.jobs()
        gate.validate(jobs)
        for name in gate.PLATFORMS:
            jobs['changes']['outputs'][name] = 'true'
            jobs[name]['result'] = 'success'
        gate.validate(jobs)

    def test_selected_failure_cancellation_or_skip_cannot_pass(self):
        for name in gate.PLATFORMS:
            for result in ('failure', 'cancelled', 'skipped'):
                with self.subTest(platform=name, result=result):
                    jobs = self.jobs()
                    jobs['changes']['outputs'][name] = 'true'
                    jobs[name]['result'] = result
                    with self.assertRaises(ValueError):
                        gate.validate(jobs)

    def test_safety_selection_and_missing_outputs_cannot_pass(self):
        for name in ('changes', 'safety'):
            jobs = self.jobs()
            jobs[name]['result'] = 'failure'
            with self.assertRaises(ValueError):
                gate.validate(jobs)
        for value in ('', 'unknown'):
            jobs = copy.deepcopy(self.jobs())
            jobs['changes']['outputs']['ios'] = value
            with self.assertRaises(ValueError):
                gate.validate(jobs)
        jobs = self.jobs()
        del jobs['ios']
        with self.assertRaises(KeyError):
            gate.validate(jobs)
