#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 MobLog contributors
"""Fetch the exact upstream catalog inputs recorded in this release's manifests."""
from pathlib import Path
import hashlib
import json
import shutil
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fetch(url, target, expected=None):
    if target.is_file() and expected and digest(target) == expected:
        print('Verified:', target.relative_to(ROOT))
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + '.download')
    try:
        request = urllib.request.Request(url, headers={'User-Agent': 'MobLog-source-fetcher'})
        with urllib.request.urlopen(request, timeout=120) as response, temporary.open('wb') as output:
            shutil.copyfileobj(response, output)
        if expected and digest(temporary) != expected:
            raise ValueError('Source checksum mismatch: ' + str(target.relative_to(ROOT)))
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    print('Downloaded:', target.relative_to(ROOT))


def main():
    trinity = json.loads((ROOT / 'MobLog_TrinityDB/trinity-manifest.json').read_text(encoding='utf-8'))
    att = json.loads((ROOT / 'MobLog_TrinityDB/att-manifest.json').read_text(encoding='utf-8'))
    maps = json.loads((ROOT / 'MobLog/map-manifest.json').read_text(encoding='utf-8'))
    cache = ROOT / 'tools/att-review'
    commit = att['commit']
    fetch(f'https://github.com/TrinityCore/TrinityCore/releases/download/{trinity["release"]}/{trinity["archive"]}',
          ROOT / 'tools/trinity/source' / trinity['archive'], trinity['sha256'])
    fetch(f'https://api.github.com/repos/ATTWoWAddon/AllTheThings/git/trees/{commit}?recursive=1',
          cache / 'tree.json')
    tree = json.loads((cache / 'tree.json').read_text(encoding='utf-8'))
    if tree.get('sha') != commit or tree.get('truncated'):
        raise ValueError('Incomplete or unexpected upstream source tree')
    blobs = {entry['path']: entry['sha'] for entry in tree['tree'] if entry['type'] == 'blob'}
    inputs = dict(att['inputs'])
    for path, checksum in maps['inputs'].items():
        if path in inputs and inputs[path] != checksum:
            raise ValueError('Conflicting source input hashes: ' + path)
        inputs[path] = checksum
    for path, checksum in inputs.items():
        fetch(f'https://raw.githubusercontent.com/ATTWoWAddon/AllTheThings/{commit}/{urllib.parse.quote(path)}',
              cache / path, checksum)
        raw = (cache / path).read_bytes()
        blob_hash = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        if blobs.get(path) != blob_hash:
            raise ValueError('Source is not part of the pinned commit: ' + path)
    shutil.copyfile(ROOT / 'MobLog_TrinityDB/COPYING-TrinityCore', ROOT / 'tools/trinity/source/COPYING')
    print('Pinned source inputs ready. No addon data has been regenerated.')


if __name__ == '__main__':
    main()
