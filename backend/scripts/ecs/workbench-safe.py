"""Run Workbench with bounded transport retries and redacted session URLs."""
import json
import re
import subprocess
import sys
import time

_TOKEN = re.compile(r"(?i)((?:securityToken|security_token|x-oss-security-token|signature|x-oss-signature|x-amz-signature)(?:=|%3d))([a-z0-9._~%+/-]+)")


def redact(text):
    return _TOKEN.sub(r"\1REDACTED", text)


def transport_failure(result, arguments):
    for output in (result.stdout, result.stderr):
        try:
            error = json.loads(output.strip())
        except (ValueError, TypeError):
            continue
        if isinstance(error, dict) and error.get("code") == 5:
            return True
    combined = (result.stdout + result.stderr).lower()
    return (
        arguments[:1] == ["upload"]
        and "upload to oss" in combined
        and any(word in combined for word in ("i/o timeout", "connection reset", "tls handshake timeout", "context deadline exceeded"))
    )


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    for attempt in range(3):
        result = subprocess.run(
            ["workbench", *arguments], stdin=subprocess.DEVNULL,
            capture_output=True, text=True,
        )
        sys.stdout.write(redact(result.stdout))
        sys.stderr.write(redact(result.stderr))
        if result.returncode == 0 or not transport_failure(result, arguments) or attempt == 2:
            return result.returncode
        print(f"Workbench transport failed; retry {attempt + 1}/2.", file=sys.stderr, flush=True)
        time.sleep(attempt + 1)
    raise AssertionError("unreachable")


if __name__ == "__main__":
    sys.exit(main())
