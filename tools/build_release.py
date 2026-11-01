#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 MobLog contributors
"""Package the installable release and complete corresponding development source."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZIP_STORED
import argparse
import hashlib
import json
import subprocess

ROOT=Path(__file__).resolve().parents[1]
VERSION='1.1.2'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def build(with_source=False):
    runtime=[]
    for folder in ('MobLog','MobLog_TrinityDB'):
        runtime.extend(p for p in (ROOT/folder).rglob('*') if p.is_file())
        toc=ROOT/folder/(folder+'.toc')
        text=toc.read_text(encoding='utf-8-sig')
        if f'## Version: {VERSION}' not in text: raise ValueError('Incorrect version: '+str(toc))
        for line in text.splitlines():
            if line and not line.startswith('#') and not (toc.parent/line).is_file():
                raise ValueError('Missing TOC file: '+line)
    for name in ('MobLog/LICENSE','MobLog/NOTICE.md','MobLog/SOURCE.md',
                 'MobLog_TrinityDB/LICENSE','MobLog_TrinityDB/COPYING-TrinityCore',
                 'MobLog_TrinityDB/LICENSE-ATT','MobLog_TrinityDB/ATT-NOTICE.md'):
        if not (ROOT/name).is_file(): raise ValueError('Missing license/source notice: '+name)
    manifest=json.loads((ROOT/'MobLog_TrinityDB/trinity-manifest.json').read_text(encoding='utf-8'))
    archive=ROOT/'tools/trinity/source'/manifest['archive']
    if with_source and digest(archive)!=manifest['sha256']: raise ValueError('Source archive checksum mismatch')
    att=json.loads((ROOT/'MobLog_TrinityDB/att-manifest.json').read_text(encoding='utf-8'))
    if digest(ROOT/'tools/att/enrichment.json')!=att['subset_sha256']: raise ValueError('ATT subset differs')
    if digest(ROOT/'tools/att/import_att.py')!=att['extractor_sha256']: raise ValueError('ATT extractor differs')
    for path,expected in (att['inputs'].items() if with_source else []):
        if digest(ROOT/'tools/att-review'/path)!=expected: raise ValueError('ATT input differs: '+path)
    map_data=json.loads((ROOT/'MobLog/map-manifest.json').read_text(encoding='utf-8'))
    if digest(ROOT/'tools/att/import_maps.py')!=map_data['generator_sha256']: raise ValueError('Map generator differs')
    if digest(ROOT/'MobLog/InstanceMaps.lua')!=map_data['output_sha256']: raise ValueError('Map output differs')
    for path,expected in (map_data['inputs'].items() if with_source else []):
        if digest(ROOT/'tools/att-review'/path)!=expected: raise ValueError('Map input differs: '+path)
    source=set(runtime)
    for name in ('LICENSE','NOTICE.md','SOURCE.md','README.md','.gitignore',
                 'tools/build_release.py','tools/fetch_sources.py','tools/att/import_att.py','tools/att/import_maps.py',
                 'tools/att/enrichment.json','tools/trinity/import_catalog.py',
                 'tools/trinity/source/COPYING','tools/att-review/tree.json'):
        source.add(ROOT/name)
    source.add(archive)
    source.update(ROOT/'tools/att-review'/path for path in att['inputs'])
    source.update(ROOT/'tools/att-review'/path for path in map_data['inputs'])
    source.update(ROOT/'publishing'/name for name in (f'changelog-{VERSION}.md',f'release-notes-{VERSION}.md','description.md','MobLog-logo-400.png'))
    if with_source and any(not p.is_file() for p in source): raise ValueError('Incomplete source input set')
    install_zip=ROOT/f'MobLog-{VERSION}.zip'
    source_zip=ROOT/f'MobLog-{VERSION}-source.zip'
    with ZipFile(install_zip,'w',ZIP_DEFLATED,compresslevel=9) as output:
        for path in sorted(runtime): output.write(path,path.relative_to(ROOT).as_posix())
    with ZipFile(install_zip) as output:
        if output.testzip(): raise ValueError('Install ZIP CRC failed')
        if {name.split('/')[0] for name in output.namelist()}!={'MobLog','MobLog_TrinityDB'}:
            raise ValueError('Incorrect install ZIP layout')
    if with_source:
        prefix=f'MobLog-{VERSION}-source/'
        checksums=[]
        with ZipFile(source_zip,'w',ZIP_DEFLATED,compresslevel=9) as output:
            for path in sorted(source):
                name=path.relative_to(ROOT).as_posix()
                output.write(path,prefix+name,compress_type=ZIP_STORED if path==archive else ZIP_DEFLATED)
                checksums.append(digest(path)+'  '+name)
            output.writestr(prefix+'SHA256SUMS.txt','\n'.join(checksums)+'\n')
        with ZipFile(source_zip) as output:
            if output.testzip(): raise ValueError('Source ZIP CRC failed')
    archives=(install_zip,source_zip) if with_source else (install_zip,)
    commit=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,capture_output=True,text=True)
    source_url='https://github.com/Eychkay/MobLog'
    if commit.returncode==0: source_url+='/tree/'+commit.stdout.strip()
    release={'source_url':source_url,'version':VERSION,'date':'2026-11-01','previous_release':'1.1.1',
             'license':'GPL-2.0-or-later','runtime_files':len(runtime),'source_files':len(source) if with_source else None,
             'archives':{path.name:{'bytes':path.stat().st_size,'sha256':digest(path)} for path in archives}}
    (ROOT/'publishing'/f'release-manifest-{VERSION}.json').write_text(json.dumps(release,indent=2)+'\n',encoding='utf-8')
    for path in archives: print(path.name,round(path.stat().st_size/1048576,2),'MiB',flush=True)
    print('Archives CRC-checked; runtime roots and license files verified.',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--with-source',action='store_true',help='Also create an offline source ZIP with pinned upstream inputs')
    build(parser.parse_args().with_source)
