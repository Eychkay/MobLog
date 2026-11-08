# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 MobLog contributors
"""Extract a conservative NPC-loot subset without executing ATT Lua.

Run --fetch to obtain the pinned public inputs; otherwise use the review cache.
The generated subset derives from MIT-licensed ATT data. Keep its license/notice.
"""
from pathlib import Path
from dataclasses import dataclass
import argparse
import collections
import hashlib
import json
import re
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / 'tools/att-review'
COMMIT = '5ee014cf4cf4c9e4d4c8f3c0d2333e3ac695ad07'
CATEGORIES = ('Instances', 'Zones', 'WorldDrops', 'Delves',
              'ExpansionFeatures', 'WorldEvents', 'Holidays', 'Secrets')
TOKEN = re.compile(r'''\s+|--\[\[.*?\]\]|--[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|0[xX][0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[A-Za-z_][A-Za-z_0-9]*|\.\.|==|~=|<=|>=|.''', re.S)


@dataclass
class Table:
    fields: dict
    values: list


@dataclass
class Call:
    name: str
    args: list


@dataclass
class Symbol:
    name: str


OPAQUE = Symbol('!dynamic')


class Parser:
    """Small data-expression reader. Functions are skipped, never evaluated."""
    def __init__(self, text):
        self.tokens = (m[0] for m in TOKEN.finditer(text)
                       if not m[0].isspace() and not m[0].startswith('--'))
        self.current = next(self.tokens, '')

    def pop(self, expected=None):
        value = self.current
        if expected is not None and value != expected:
            raise ValueError(f'Expected {expected!r}, got {value!r}')
        self.current = next(self.tokens, '')
        return value

    def expr(self):
        token = self.pop()
        if token == '{':
            fields, values = {}, []
            while self.current != '}':
                if not self.current:
                    raise ValueError('Unterminated table')
                if self.current == '[':
                    self.pop('['); key = self.expr(); self.pop(']'); self.pop('=')
                    if isinstance(key, (str, int, float)): fields[key] = self.expr()
                    else: self.expr()
                else:
                    value = self.expr()
                    if self.current == '=':
                        self.pop('=')
                        if not isinstance(value, Symbol): raise ValueError('Invalid field key')
                        fields[value.name] = self.expr()
                    else: values.append(value)
                if self.current in (',', ';'): self.pop()
                elif self.current != '}': raise ValueError('Expected table separator: '+self.current)
            self.pop('}'); value = Table(fields, values)
        elif token == '(':
            value = self.expr(); self.pop(')')
        elif token == 'function':
            depth = 1
            while depth:
                word = self.pop()
                if not word: raise ValueError('Unterminated function')
                if word in ('function', 'if', 'do', 'repeat'): depth += 1
                elif word in ('end', 'until'): depth -= 1
            value = OPAQUE
        elif token in ('-', '#', 'not'):
            other = self.expr()
            value = -other if token == '-' and type(other) in (int, float) else OPAQUE
        elif token.startswith(('"', "'")):
            # Only keys/string flags are needed. Preserve unsupported escapes.
            value = re.sub(r'\\([\\\'"nrt])', lambda m: {'n':'\n','r':'\r','t':'\t'}.get(m[1],m[1]), token[1:-1])
        elif re.fullmatch(r'0[xX][0-9a-fA-F]+', token): value = int(token, 16)
        elif re.fullmatch(r'\d+(?:\.\d+)?(?:[eE][+-]?\d+)?', token):
            value = float(token) if any(c in token for c in '.eE') else int(token)
        elif token in ('true', 'false', 'nil'): value = {'true':True,'false':False,'nil':None}[token]
        elif re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', token): value = Symbol(token)
        else: raise ValueError('Unsupported expression token: '+token)
        while self.current in ('.', '[', '(', ':'):
            if self.current in ('.', ':'):
                self.pop(); name = self.pop()
                value = Symbol(value.name+'.'+name) if isinstance(value, Symbol) else OPAQUE
            elif self.current == '[':
                self.pop('['); self.expr(); self.pop(']'); value = OPAQUE
            else:
                self.pop('('); args = []
                while self.current != ')':
                    args.append(self.expr())
                    if self.current == ',': self.pop(',')
                    elif self.current != ')': raise ValueError('Expected argument separator: '+self.current)
                self.pop(')'); value = Call(value.name,args) if isinstance(value, Symbol) and value != OPAQUE else OPAQUE
        # Nonliteral arithmetic/conditional expressions are deliberately opaque.
        if self.current in ('..', '+', '-', '*', '/', '%', '^', 'and', 'or', '==', '~=', '<', '>', '<=', '>='):
            self.pop(); self.expr(); value = OPAQUE
        return value


def integer(value):
    return value if type(value) is int and value > 0 else None


def numbers(value):
    if isinstance(value, Table): return sorted({v for v in value.values if integer(v)})
    return [value] if integer(value) else []


def dynamic(value):
    if value == OPAQUE: return True
    if isinstance(value, Table): return any(dynamic(v) for v in value.fields.values())
    return False


def literal(value):
    if isinstance(value,Table):
        if not value.fields: return [literal(v) for v in value.values]
        return {str(k):literal(v) for k,v in value.fields.items()}
    if isinstance(value,Symbol): return {'symbol':value.name}
    if isinstance(value,Call): return {'call':value.name,'args':[literal(v) for v in value.args]}
    return value


def fetch(flavor='Standard'):
    CACHE.mkdir(parents=True,exist_ok=True)
    tree = json.load(urllib.request.urlopen(f'https://api.github.com/repos/ATTWoWAddon/AllTheThings/git/trees/{COMMIT}?recursive=1', timeout=45))
    (CACHE/'tree.json').write_text(json.dumps(tree), encoding='utf-8')
    paths = ['LICENSE',f'db/{flavor}/LocalizationDB.lua'] + [f'db/{flavor}/Categories/{name}.lua' for name in CATEGORIES]
    for path in paths:
        url=f'https://raw.githubusercontent.com/ATTWoWAddon/AllTheThings/{COMMIT}/{urllib.parse.quote(path)}'
        target=CACHE/path; target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(urllib.request.urlopen(url,timeout=45).read())


def build(flavor='Standard', destination=None):
    tree = json.loads((CACHE/'tree.json').read_text(encoding='utf-8'))
    if tree['sha'] != COMMIT or tree.get('truncated'): raise ValueError('Unexpected ATT snapshot')
    blobs = {x['path']: x['sha'] for x in tree['tree'] if x['type']=='blob'}
    inputs = {}
    def read(path):
        raw=(CACHE/path).read_bytes()
        if hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()!=blobs[path]:
            raise ValueError('Modified ATT input: '+path)
        inputs[path]=hashlib.sha256(raw).hexdigest()
        return raw.decode('utf-8-sig')
    read('LICENSE')
    localization=read(f'db/{flavor}/LocalizationDB.lua')
    start=localization.index('localize(L.HEADER_NAMES, {')
    names=dict((int(k),v) for k,v in re.findall(r'^\s*\[(-?\d+)\]\s*=\s*(.*),$',localization[start:localization.find('\n})',start)],re.M))
    blocked_headers={key for key,label in names.items() if any(word in label.upper() for word in
                     ('VENDOR','QUEST','REWARD','TREASURE','CRAFT','PROFESSION','FISHING','ACHIEVEMENT','BATTLE_PET'))}
    drop_headers={-16,-21,-27,-46,-61,-63,-698}
    blocked_headers |= {-20,-22,-23,-24,-29,-43,-44,-45,-47,-49,-56,-58,-64}
    blocked_headers -= drop_headers
    edges=collections.defaultdict(set); contexts=collections.Counter(); skipped=collections.Counter()
    difficulty_names={1:'Normal',2:'Heroic',3:'10-player Normal',4:'25-player Normal',5:'10-player Heroic',6:'25-player Heroic',7:'Raid Finder',8:'Mythic+',9:'40-player',14:'Normal',15:'Heroic',16:'Mythic',17:'Raid Finder',23:'Mythic',24:'Timewalking',33:'Timewalking'}
    def visit(node, state, aliases, category):
        if isinstance(node, Table):
            for child in node.values: visit(child,state,aliases,category)
            return
        if not isinstance(node, Call): return
        kind=aliases.get(node.name,node.name).removeprefix('_.Create')
        if kind in ('Quest','HQT','HQTBonusRep','Achievement','AchievementCriteria','GuildAchievement','Object','Profession','RecipeSkill','Reputation','Faction','Ensemble','EnsembleSpell'):
            return
        info=next((a for a in reversed(node.args) if isinstance(a,Table)),Table({},[])); f=info.fields
        if dynamic(info) or 'u' in f or 'rwp' in f or 'cost' in f or 'provider' in f or 'providers' in f:
            skipped['dynamic_unavailable_or_purchase_branch']+=1; return
        state=dict(state)
        for field in ('difficulties','r','c','races','awp'):
            value=f.get(field)
            if value is not None:
                if field=='awp':
                    if not integer(value): return
                    state[field]=max(state.get(field,0),value)
                elif field in ('c','races','difficulties'):
                    if isinstance(value,Table) and (value.fields or any(not integer(v) for v in value.values)): return
                    if not isinstance(value,Table) and not integer(value): return
                    values=numbers(value)
                    if values:
                        if field in state:
                            values=sorted(set(state[field])&set(values))
                            if not values: return
                        state[field]=values
                elif value in (1,2):
                    if field in state and state[field]!=value: return
                    state[field]=value
                else: return
        if any(key in f for key in ('sourceQuests','customCollect','minReputation','requireSkill','OnUpdate','OnTooltip')):
            state['conditional']=True
        requirements={key:literal(f[key]) for key in ('sourceQuests','customCollect','minReputation','requireSkill','isDaily','isWeekly','lockCriteria') if key in f}
        if requirements: state['requirements']=state.get('requirements',[])+[requirements]
        first=node.args[0] if node.args else None
        if kind in ('CustomHeader','Header'):
            if first in blocked_headers: return
            if first in drop_headers: state['drop_context']=True
            elif not (type(first) is int and -107 <= first <= -88):
                # A nested unrelated header must not inherit a rare/boss owner.
                state['drop_context']=False
                state.pop('owners',None); state.pop('encounter',None)
        if kind=='Difficulty' and 'difficulties' not in f:
            if integer(first):
                if 'difficulties' in state and first not in state['difficulties']: return
                state['difficulties']=[first]
        if kind=='Encounter':
            state['owners']=numbers(f.get('crs')) or numbers(f.get('npcID'))
            state['encounter']=integer(first)
            state['drop_context']=True
        elif kind=='NPC':
            if not integer(first): return
            # Positive NPCs in other contexts can be vendors/quest-givers.
            if not state.get('drop_context'): return
            state['owners']=[first]; state.pop('encounter',None)
        item=integer(f.get('itemID'))
        if kind in ('Item','Toy','MountMod') and integer(first): item=first
        elif kind=='ItemSource' and len(node.args)>1: item=integer(node.args[1])
        item_kind=kind in ('Item','ItemSource','Toy','Mount','MountMod','Species','Recipe','Decor','Illusion','Heirloom')
        if item_kind:
            owners=numbers(f['crs']) if 'crs' in f else state.get('owners',[])
            if not item or not state.get('drop_context') or not owners: return
            restrictions={key:state[key] for key in ('difficulties','r','c','races','awp','conditional','encounter','requirements') if state.get(key)}
            if len(owners)>1: restrictions['sharedEncounter']=True
            # Keep individual variants, rather than merging faction/difficulty constraints.
            signature=json.dumps({'category':category,**restrictions},sort_keys=True,separators=(',',':'))
            for npc in owners: edges[(npc,item)].add(signature)
            contexts[category]+=1
            return  # Contents of a dropped container are not direct NPC drops.
        allowed=('CustomHeader','Header','NPC','Encounter','Difficulty','Filter','Expansion','Map','Instance','Category','Exploration')
        if kind not in allowed: return
        # Generated constructors also accept a bare children array when there
        # are no metadata fields: h(-46,{n(...),n(...)}).
        children=f.get('g') or (info if info.values else None)
        if isinstance(children,Table):
            for child in children.values: visit(child,state,aliases,category)
    for category in CATEGORIES:
        text=read(f'db/{flavor}/Categories/{category}.lua')
        aliases={}
        for match in re.finditer(r'local ([A-Za-z_,]+)=([^;\n]+)',text):
            keys,values=match[1].split(','),match[2].split(',')
            if len(keys)==len(values): aliases.update(zip(keys,values))
        marker=re.search(r'categories\.\w+\s*=\s*',text)
        if not marker: raise ValueError('Missing category root: '+category)
        parser=Parser(text[marker.end():]); root=parser.expr()
        if parser.current not in ('end',';'): raise ValueError('Unexpected category tail: '+category+' '+parser.current)
        visit(root,{'drop_context':category=='WorldDrops'},aliases,category)
        print(category,'parsed; total pairs',len(edges),flush=True)
    def note(variant):
        parts=[]
        if variant.get('sharedEncounter'): parts.append('Shared encounter loot')
        if variant.get('difficulties'):
            parts.append('Difficulty: '+', '.join(dict.fromkeys(difficulty_names.get(v,'specific difficulty') for v in variant['difficulties'])))
        if variant.get('r'): parts.append({1:'Alliance',2:'Horde'}.get(variant['r'],'Faction restricted'))
        if variant.get('c'): parts.append('Class restricted')
        if variant.get('races'): parts.append('Race restricted')
        if variant.get('awp'):
            patch=variant['awp']; parts.append(f'Introduced in {patch//10000}.{patch//100%100}.{patch%100}')
        if variant.get('conditional'): parts.append('Additional character, quest or event requirements')
        elif variant.get('requirements'): parts.append('Additional availability conditions')
        return '; '.join(parts) or 'Encounter or creature drop'
    records=[]
    for (npc,item),variants in sorted(edges.items()):
        variants=[json.loads(v) for v in sorted(variants)]
        records.append({'npc':npc,'item':item,'variants':variants,'note':' / '.join(sorted({note(v) for v in variants}))})
    output={'commit':COMMIT,'url':f'https://github.com/ATTWoWAddon/AllTheThings/tree/{COMMIT}',
            'inputs':inputs,'policy':'Explicit encounter/NPC drops in allowlisted drop contexts only. No unavailable, purchase, quest-reward, container-content or dynamic branches.',
            'pairs':records,'contexts':dict(contexts),'skipped':dict(skipped)}
    if flavor!='Standard': output['flavor']=flavor
    destination=Path(destination) if destination else Path(__file__).with_name('enrichment.json')
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(output,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8',newline='\n')
    print('Wrote',len(records),'NPC-item pairs;',len({r['item'] for r in records}),'items;',len({r['npc'] for r in records}),'NPCs.',flush=True)
    return output


if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--fetch',action='store_true'); args=parser.parse_args()
    if args.fetch: fetch()
    build()
