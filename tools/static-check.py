#!/usr/bin/env python3
"""Dependency-free structural checks; deliberately NOT an R parser or R CMD check.
Run: python tools/static-check.py .
"""
from pathlib import Path
import csv, json, re, sys, xml.etree.ElementTree as ET

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
errors = []
def require(ok, message):
    if not ok: errors.append(message)

def r_lex(text, name):
    stack, i, line = [], 0, 1
    pairs = {')': '(', ']': '[', '}': '{'}
    while i < len(text):
        c = text[i]
        if c == '\n': line += 1; i += 1; continue
        if c == '#':
            end = text.find('\n', i)
            i = len(text) if end < 0 else end
            continue
        if c in "\"'`":
            quote, start = c, line
            i += 1
            while i < len(text):
                c = text[i]
                if c == '\\':
                    if i + 1 == len(text): break
                    nxt = text[i + 1]
                    if quote != '`':
                        require(nxt in "\\\"'`nrtbafv01234567xuU\n", f'{name}:{line}: suspicious R string escape \\{nxt}')
                    if nxt == '\n': line += 1
                    i += 2; continue
                if c == quote: i += 1; break
                if c == '\n': line += 1
                i += 1
            else:
                errors.append(f'{name}:{start}: unterminated quote')
            continue
        if c in '([{': stack.append((c, line))
        elif c in pairs:
            if not stack or stack[-1][0] != pairs[c]:
                errors.append(f'{name}:{line}: unmatched {c}')
            else: stack.pop()
        i += 1
    require(not stack, f'{name}: unclosed delimiters {stack}')

def source_file(f):
    if not f.is_file(): return False
    relative = f.relative_to(root)
    if any(part in {'.git', '.qa'} for part in relative.parts): return False
    # Native builds leave object files and shared libraries next to C sources.
    # They are verified by compilation/package checks, not UTF-8 lexical scans.
    if relative.parts[0] == 'src' and (
            f.suffix in {'.o', '.so', '.dll', '.dylib', '.a'} or
            f.name in {'Makevars', 'Makevars.win'}): return False
    return True

files = [f for f in root.rglob('*') if source_file(f)]
for f in files:
    text = f.read_text(encoding='utf-8')
    require('\x00' not in text, f'{f}: NUL byte')
    require('\u2014' not in text, f'{f}: disallowed punctuation')
    require(('utm_source=' + 'chatgpt.com') not in text, f'{f}: tracking parameter')
    require(text.endswith('\n'), f'{f}: no final newline')
    if f.suffix == '.R': r_lex(text, str(f.relative_to(root)))

blocks = []
for f in [root/'README.md', *root.glob('vignettes/*.Rmd')]:
    text = f.read_text()
    found = re.findall(r'^```(?:r|\{r[^\n]*\})\s*\n(.*?)^```\s*$', text, re.M | re.S)
    for i, code in enumerate(found): r_lex(code, f'{f.name} code block {i+1}')
    blocks.extend(found)

ns = (root/'NAMESPACE').read_text()
exports = re.findall(r'^export\(([^)]+)\)', ns, re.M)
require(len(exports) == len(set(exports)) == 16, 'Expected 16 unique exports')
familiar = {'as.OECDDataList', 'browseDataList', 'compare', 'describe', 'find',
          'importData', 'importDataList', 'importDimLabel', 'importLabels', 'importMetabase'}
require(familiar <= set(exports), 'Missing familiar OECD entry point')
code = '\n'.join(f.read_text() for f in root.glob('R/*.R'))
functions = set(re.findall(r'^([.A-Za-z][.A-Za-z0-9_]*)\s*<-\s*function\s*\(', code, re.M))
require(set(exports) <= functions, 'Export without a defined function')
require('.onLoad' not in functions and '.onAttach' not in functions, 'Unexpected load hook')
methods = re.findall(r'^S3method\(([^,]+),([^,)]+)\)', ns, re.M)
require(all(a+'.'+b in functions for a,b in methods), 'S3 registration without implementation')
rd_files = list(root.glob('man/*.Rd'))
aliases = []
for f in rd_files:
    text = f.read_text()
    aliases.extend(re.findall(r'\\alias\{([^}]+)\}', text))
    level, i = 0, 0
    while i < len(text):
        if text[i] == '\\' and i+1 < len(text) and text[i+1] in '{}%\\': i += 2; continue
        if text[i] == '{': level += 1
        if text[i] == '}': level -= 1
        require(level >= 0, f'{f.name}: unmatched Rd brace')
        i += 1
    require(level == 0, f'{f.name}: unbalanced Rd braces')
    require('\\value{' in text and '\\description{' in text, f'{f.name}: missing documentation section')
require(set(exports) <= set(aliases), 'Export without a help alias')
require(len(aliases) == len(set(aliases)), 'Duplicate help alias')

# Extract balanced public formal lists and compare with documented usage.
# This is a lexical comparison, not an R parser or evaluator.
def balanced_formals(text, opening):
    depth, quote, i = 1, None, opening + 1
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == '\\': i += 2; continue
            if ch == quote: quote = None
        elif ch in "\"'`": quote = ch
        elif ch == '(': depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0: return re.sub(r'\s+', '', text[opening + 1:i])
        i += 1
    return None

signatures_checked = 0
all_help = '\n'.join(section for f in rd_files for section in re.findall(r'\\usage\{(.*?)\n\}', f.read_text(), re.S))
for name in exports:
    source_match = re.search(r'^' + re.escape(name) + r'\s*<-\s*function\s*\(', code, re.M)
    usage_match = re.search(r'^' + re.escape(name) + r'\s*\(', all_help, re.M)
    if source_match and usage_match:
        got = balanced_formals(code, source_match.end() - 1)
        documented = balanced_formals(all_help, usage_match.end() - 1)
        require(got is not None and got == documented, f'{name}: public formals / help usage mismatch')
        signatures_checked += 1
    else:
        require(False, f'{name}: missing source or documented usage')


desc = {}
key = None
for line in (root/'DESCRIPTION').read_text().splitlines():
    if line.startswith((' ', '\t')):
        require(key is not None, 'Invalid DCF continuation')
        if key: desc[key] += '\n'+line.strip()
    else:
        require(':' in line, 'Invalid DESCRIPTION line')
        if ':' in line:
            key,value = line.split(':',1)
            value = value.lstrip()
            require(key not in desc, 'Duplicate DESCRIPTION field')
            desc[key] = value
require(desc.get('Package') == 'OECDdata', 'Wrong package name')
require(bool(re.fullmatch(r'\d+\.\d+\.\d+', desc.get('Version', ''))), 'Invalid package version')
require(desc.get('License') == 'MIT + file LICENSE', 'Wrong license declaration')
require('Alek' in desc.get('Authors@R','') and 'alek.rutkowski@gmail.com' in desc.get('Authors@R',''), 'Wrong maintainer metadata')
declared = set(re.findall(r'([A-Za-z][A-Za-z0-9.]*)\s*(?:\([^)]*\))?(?:,|$)',
                        desc.get('Imports','').replace('\n','')+','+desc.get('Suggests','').replace('\n','')))
used = set(re.findall(r'\b([A-Za-z][A-Za-z0-9.]*)::(?!:)(?:[.A-Za-z][.A-Za-z0-9_]*|`[^`]+`)\s*\(', code))
require(used <= declared | {'base'}, f'Undeclared runtime namespaces: {used-declared}')

# Check fixture shape and labels using Python's XML and CSV readers, not R.
doc = ET.parse(root/'inst/extdata/structure.xml')
local = lambda x: x.tag.rsplit('}',1)[-1]
flows = [x for x in doc.iter() if local(x)=='Dataflow' and x.get('agencyID')]
require(len(flows)==2 and all(x.get('agencyID')=='TEST' for x in flows), 'Unexpected fixture flow')
components = [x for x in doc.iter() if local(x) in ('Dimension','TimeDimension')]
dims = [x.get('id') for x in sorted(components,key=lambda x:int(x.get('position')))]
require(dims == ['FREQ','REF_AREA','MEASURE','GROUP','TIME_PERIOD'], 'Wrong fixture dimension order')
with (root/'inst/extdata/example.csv').open(newline='') as f: rows = list(csv.DictReader(f))
require(len(rows)==12, 'Wrong fixture observation count')
require(len({tuple(r[d] for d in dims) for r in rows}) == len(rows), 'Duplicate fixture key')
require(all(r['GROUP']=='00' for r in rows), 'Leading-zero fixture lost')
require(all(r['STRUCTURE_ID']=='TEST:DEMO(1.0)' for r in rows), 'Fixture identity mismatch')
require(all(float(r['OBS_VALUE'])>0 for r in rows), 'Invalid synthetic values')
# Confirm the reserved dictionary code really is absent from the actual constraint.
constraints=[x for x in doc.iter() if local(x)=='ContentConstraint']
actual_values=[x.text for c in constraints for x in c.iter() if local(x)=='Value']
require('ZZZ' not in actual_values, 'Fixture no longer separates allowed and observed codes')
require(any(local(x)=='Code' and x.get('id')=='ZZZ' for x in doc.iter()), 'Missing allowed-only fixture code')

cases = sum(f.read_text().count('test_that(') for f in root.glob('tests/testthat/test-*.R'))
report = dict(status='PASS' if not errors else 'FAIL', package=desc.get('Package'),
 version=desc.get('Version'), r_files=len(list(root.rglob('*.R'))), exports=len(exports),
 familiar_exports=len(familiar), manual_pages=len(rd_files), documented_exports=len(set(exports)&set(aliases)),
 public_signatures_compared=signatures_checked, test_cases_authored=cases, live_test_cases=1, documentation_r_blocks_checked=len(blocks),
 synthetic_rows=len(rows), errors=errors,
 scope='Static lexical/structural checks only. Not R parsing, package execution, R CMD check, or live API validation.')
print(json.dumps(report, indent=2))
sys.exit(bool(errors))
