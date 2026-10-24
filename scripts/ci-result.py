"""Reject failed, missing, or unexpectedly skipped selected checks."""
import json
import os

PLATFORMS = ('ios', 'android', 'backend', 'site', 'supabase')


def validate(jobs):
    if jobs['changes']['result'] != 'success' or jobs['safety']['result'] != 'success':
        raise ValueError('Selection and repository safety must pass')
    for name in PLATFORMS:
        selection = jobs['changes']['outputs'][name]
        if selection not in ('true', 'false'):
            raise ValueError(f'Invalid selection for {name}: {selection}')
        expected = 'success' if selection == 'true' else 'skipped'
        if jobs[name]['result'] != expected:
            raise ValueError(f'{name}: expected {expected}, got {jobs[name]["result"]}')


if __name__ == '__main__':
    validate(json.loads(os.environ['RESULTS']))
