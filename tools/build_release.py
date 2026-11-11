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
VERSION='1.1.4'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def packaged_bytes(path,client):
    payload=path.read_bytes()
    if path.relative_to(ROOT).as_posix()=='MobLog/MobLog.toc':
        lines=payload.decode('utf-8-sig').splitlines()
        for index,line in enumerate(lines):
            if line.startswith('## Interface:'):
                versions=[entry.strip() for entry in line.split(':',1)[1].split(',')]
                versions=['16001'] if client=='forever' else [entry for entry in versions if entry!='16001']
                lines[index]='## Interface: '+', '.join(versions)
        payload=('\n'.join(lines)+'\n').encode('utf-8')
    return payload


def build(with_source=False,client='retail',check_only=False):
    folders=('MobLog','MobLog_ForeverDB' if client=='forever' else 'MobLog_TrinityDB')
    suffix='-Forever' if client=='forever' else ''
    runtime=[]
    for folder in folders:
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
    forever=None
    if client=='forever':
        forever=json.loads((ROOT/'MobLog_ForeverDB/forever-manifest.json').read_text(encoding='utf-8'))
        for name in ('LICENSE','NOTICE.md','COPYING-TrinityCore','LICENSE-ATT'):
            if not (ROOT/'MobLog_ForeverDB'/name).is_file(): raise ValueError('Missing Forever license: '+name)
        for name,field in (('tools/forever/import_catalog.py','generator_sha256'),('tools/att/import_att.py','extractor_sha256'),('tools/forever/enrichment.json','subset_sha256')):
            if digest(ROOT/name)!=forever[field]: raise ValueError('Forever source differs: '+name)
        for name,expected in forever['base_npc_inputs'].items():
            if digest(ROOT/name)!=expected: raise ValueError('Forever base NPC source differs: '+name)
        if with_source:
            for name,expected in forever['inputs'].items():
                if digest(ROOT/'tools/forever/source/att'/name)!=expected: raise ValueError('Forever input differs: '+name)
    if check_only:
        print(f'{client}: {len(runtime)} runtime files; TOCs, source hashes and license files verified.')
        return
    source=set(runtime)
    for name in ('LICENSE','NOTICE.md','SOURCE.md','README.md','.gitignore',
                 'tools/build_release.py','tools/fetch_sources.py','tools/att/import_att.py','tools/att/import_maps.py',
                 'tools/att/enrichment.json','tools/trinity/import_catalog.py',
                 'tools/trinity/source/COPYING','tools/att-review/tree.json'):
        source.add(ROOT/name)
    source.add(archive)
    source.update(ROOT/'tools/att-review'/path for path in att['inputs'])
    source.update(ROOT/'tools/att-review'/path for path in map_data['inputs'])
    if forever:
        source.update(p for p in (ROOT/'MobLog_TrinityDB').rglob('*') if p.is_file())
        source.update(ROOT/name for name in ('tools/forever/import_catalog.py','tools/forever/enrichment.json','tools/forever/source/att/tree.json'))
        source.update(ROOT/'tools/forever/source/att'/path for path in forever['inputs'])
    source.update(ROOT/'publishing'/name for name in (f'changelog-{VERSION}.md',f'release-notes-{VERSION}.md','description.md','MobLog-logo-400.png'))
    if with_source and any(not p.is_file() for p in source): raise ValueError('Incomplete source input set')
    install_zip=ROOT/f'MobLog-{VERSION}{suffix}.zip'
    source_zip=ROOT/f'MobLog-{VERSION}{suffix}-source.zip'
    with ZipFile(install_zip,'w',ZIP_DEFLATED,compresslevel=9) as output:
        for path in sorted(runtime): output.writestr(path.relative_to(ROOT).as_posix(),packaged_bytes(path,client))
    with ZipFile(install_zip) as output:
        if output.testzip(): raise ValueError('Install ZIP CRC failed')
        if {name.split('/')[0] for name in output.namelist()}!=set(folders):
            raise ValueError('Incorrect install ZIP layout')
    if with_source:
        prefix=f'MobLog-{VERSION}{suffix}-source/'
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
    release={'source_url':source_url,'client':client,'version':VERSION,'date':'2026-11-11','previous_release':'1.1.3' if client=='forever' else '1.1.2',
             'license':'GPL-2.0-or-later','runtime_files':len(runtime),'source_files':len(source) if with_source else None,
             'archives':{path.name:{'bytes':path.stat().st_size,'sha256':digest(path)} for path in archives}}
    (ROOT/'publishing'/f'release-manifest-{VERSION}{suffix}.json').write_text(json.dumps(release,indent=2)+'\n',encoding='utf-8')
    for path in archives: print(path.name,round(path.stat().st_size/1048576,2),'MiB',flush=True)
    print('Archives CRC-checked; runtime roots and license files verified.',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--with-source',action='store_true',help='Also create an offline source ZIP with pinned upstream inputs')
    parser.add_argument('--client',choices=('retail','forever'),default='retail')
    parser.add_argument('--check-only',action='store_true',help='Verify packaging inputs without creating an archive')
    args=parser.parse_args()
    build(args.with_source,args.client,args.check_only)
