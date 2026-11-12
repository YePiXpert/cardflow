#!/usr/bin/env python3
"""Reject private runtime files in the public repository; print paths only."""
from pathlib import Path, PurePosixPath
import argparse
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {"tools/pii_samples/clean.log", "tools/pii_samples/dirty.log"}

def private_path(value):
    p = PurePosixPath(value.lower())
    name = p.name
    if value in ALLOWED or value in {"evidence/README.md", "docs/80-delivery/README.md"}:
        return False
    if p.parts and p.parts[0] in {"private-local", "private", "local", "reports", "backups", "evidence"}:
        return True
    if str(p).startswith("docs/80-delivery/"):
        return True
    if name == '.env' or (name.startswith('.env.') and not name.endswith(('.example', '.sample', '.template'))):
        return True
    if name in {"id_rsa", "id_ed25519", "credentials.json", "accounts.json", "session.json", "cookies.txt", "nodes.json", "subscriptions.txt"}:
        return True
    if p.suffix in {'.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.mobileprovision', '.db', '.sqlite', '.sqlite3', '.har', '.log'}:
        return True
    if len(p.parts) == 1 and name.startswith(('report-', 'splitcheck-report', 'diagnostics-')):
        return True
    return False

def self_test():
    for path in ['.env', 'deploy/.env.production', 'private-local/nodes.json', 'reports/out.svg',
                 'backups/family.json', 'device.har', 'data.sqlite', 'key.PEM', 'credentials.json',
                 'evidence/device/output.txt', 'report-2026.md']:
        assert private_path(path), path
    for path in ['.env.example', 'deploy/.env.production.example', 'README.md', 'package.json',
                 'docs/report-split.svg', 'tests/test_backup.py', 'evidence/README.md']:
        assert not private_path(path), path

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print('Privacy path checks: self-test passed.')
        return 0
    cmd = ['git', '-C', str(ROOT)]
    cmd += ['diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z'] if args.staged else ['ls-files', '-z']
    paths = subprocess.check_output(cmd).decode('utf-8').split('\0')
    bad = [p for p in paths if p and (args.staged or (ROOT / p).exists()) and private_path(p)]
    if bad:
        print('Private files must stay outside the public repository:', file=sys.stderr)
        for path in bad:
            print('  ' + path, file=sys.stderr)
        return 1
    print('Privacy path checks passed.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
