import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("workbench_safe", Path(__file__).parents[1] / "scripts/ecs/workbench-safe.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WorkbenchTests(unittest.TestCase):
    def run_wrapper(self, arguments, results):
        out, err = io.StringIO(), io.StringIO()
        with patch.object(module.subprocess, "run", side_effect=results) as run, patch.object(module.time, "sleep"), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = module.main(arguments)
        return code, out.getvalue() + err.getvalue(), run.call_count

    def test_redacts_session_token_before_retrying_connection(self):
        failure = subprocess.CompletedProcess([], 5, json.dumps({"code": 5, "message": "websocket: https://example.test/?sessionId=s-test&securityToken=FAKE_WB_SESSION_TOKEN"}), "")
        success = subprocess.CompletedProcess([], 0, '{"exit_code":0}', "")
        code, output, count = self.run_wrapper(["exec", "-c", "true"], [failure, success])
        self.assertEqual((code, count), (0, 2))
        self.assertNotIn("FAKE_WB_SESSION_TOKEN", output)
        self.assertIn("REDACTED", output)
        self.assertIn("retry", output)

    def test_redacts_object_storage_signed_urls(self):
        value = module.redact("https://example.test/file?x-oss-signature=FAKE_WB_SIGNATURE&security_token=FAKE_WB_STS")
        self.assertNotIn("FAKE_WB_SIGNATURE", value)
        self.assertNotIn("FAKE_WB_STS", value)
        self.assertEqual(value.count("REDACTED"), 2)

    def test_does_not_retry_remote_program_exit_code_five(self):
        result = subprocess.CompletedProcess([], 5, '{"exit_code":5,"stdout":"application failure"}', "")
        code, _, count = self.run_wrapper(["exec", "-c", "false"], [result])
        self.assertEqual((code, count), (5, 1))

    def test_retries_only_recognized_upload_transport_errors(self):
        failed = subprocess.CompletedProcess([], 1, "", "upload failed: upload: upload to OSS: i/o timeout")
        success = subprocess.CompletedProcess([], 0, "uploaded", "")
        code, _, count = self.run_wrapper(["upload", "artifact", "/var/tmp/artifact"], [failed, success])
        self.assertEqual((code, count), (0, 2))

    def test_retry_is_bounded_and_escaped_urls_stay_redacted(self):
        failed = subprocess.CompletedProcess([], 5, '{"code":5,"message":"securityToken=FAKE_WB_SESSION_TOKEN\\u0026other=value"}', "")
        code, output, count = self.run_wrapper(["exec"], [failed] * 3)
        self.assertEqual((code, count), (5, 3))
        self.assertNotIn("FAKE_WB_SESSION_TOKEN", output)


if __name__ == "__main__":
    unittest.main()
