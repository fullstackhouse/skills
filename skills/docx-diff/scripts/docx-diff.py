#!/usr/bin/env python3
"""Reconstruct a diff of two .docx files when the counterparty didn't use tracked changes.

    docx-diff.py ours.docx theirs.docx > redline.diff

Each file is converted to markdown with pandoc, paragraphs are broken into sentences
(semantic linefeeds) so `diff -u` marks the changed *sentence* instead of the whole
paragraph, and Word comment anchors are stripped. Inputs that are already .md are used
as-is (the pandoc step is skipped).

Sentence splitting has to know which periods do not end a sentence. The default
abbreviation list is Polish-legal ("ust.", "art.", "m.in."); pass --abbr for another
language, e.g.

    docx-diff.py --abbr 'No,Sec,Art,cf,e.g,i.e,etc,vs,Inc,Ltd' ours.docx theirs.docx
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile

ABBR_PL = ('ust,art,pkt,nr,lit,poz,tj,np,zob,ok,str,ww,dot,proc,godz,m.in,itp,itd,'
           'ul,al,im,tel,dr,prof,mln,tys,zł,pn,r,w,z,s,ds,tzn,min,maks')

# A sentence may start with an opening quote/bracket or an uppercase letter.
SENTENCE_START = r'[„"“(\[]|[A-ZÀ-ÖØ-ÞĄĆĘŁŃŚŹŻ]'


def to_markdown(path, workdir):
    """Path to a markdown rendering of `path` — pandoc it unless it is already .md."""
    if path.lower().endswith('.md'):
        return path
    out = os.path.join(workdir, os.path.basename(path) + '.md')
    subprocess.run(['pandoc', '-f', 'docx', '-t', 'markdown', '--wrap=none', path, '-o', out],
                   check=True)
    return out


def clean(path, abbr):
    """Markdown → one sentence per line, Word comment anchors and images removed."""
    t = open(path, encoding='utf-8').read()
    t = re.sub(r'\[([^\]]*)\]\{\.comment-start id="\d+" author="[^"]*" date="[^"]*"\}', '', t)
    prev = None
    while prev != t:                       # comment anchors can nest
        prev = t
        t = re.sub(r'\[*\]\{\.comment-end id="\d+"\}', '', t)
    out = []
    for raw in t.split('\n'):
        s = raw.strip()
        if not s or set(s) <= {'-'} or s.startswith('![') or s == '<!-- -->':
            out.append('')
            continue
        s = s.replace('\\...', '...')
        s = re.sub(r'\.{4,}', '……', s)
        s = re.sub(r'\s+', ' ', s)

        def brk(m):
            last = re.search(r'([\w.]+)[.!?]$', s[:m.start()])
            if last and (re.fullmatch(abbr + r'\.?', last.group(1), re.I)
                         or len(last.group(1)) <= 1):
                return m.group(0)          # abbreviation or initial — keep the line
            return '\n'

        out.extend(re.sub(r'(?<=[.!?])\s+(?=' + SENTENCE_START + r')', brk, s).split('\n'))
    res = []
    for line in out:                       # collapse runs of blank lines
        if line == '' and (not res or res[-1] == ''):
            continue
        res.append(line)
    return '\n'.join(res) + '\n'


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('old', help='our version (.docx or .md)')
    ap.add_argument('new', help='their version (.docx or .md)')
    ap.add_argument('--abbr', default=ABBR_PL, metavar='LIST',
                    help='comma-separated abbreviations that must not end a sentence')
    ap.add_argument('--label-old', metavar='LABEL', help='diff header for the old file')
    ap.add_argument('--label-new', metavar='LABEL', help='diff header for the new file')
    args = ap.parse_args()

    abbr = '(?:%s)' % '|'.join(re.escape(a.strip()) for a in args.abbr.split(',') if a.strip())
    stem = lambda p: os.path.splitext(os.path.basename(p))[0] + '.md'
    label_old = args.label_old or 'a/' + stem(args.old)
    label_new = args.label_new or 'b/' + stem(args.new)

    with tempfile.TemporaryDirectory() as d:
        paths = []
        for src, sub in ((args.old, 'a'), (args.new, 'b')):
            os.makedirs(os.path.join(d, sub))
            target = os.path.join(d, sub, 'doc.md')
            open(target, 'w', encoding='utf-8').write(clean(to_markdown(src, d), abbr))
            paths.append(target)
        r = subprocess.run(['diff', '-u', paths[0], paths[1],
                            '--label', label_old, '--label', label_new],
                           capture_output=True, text=True)
        sys.stdout.write(r.stdout)
        # diff: 0 = identical, 1 = differences, >1 = trouble
        return 0 if r.returncode in (0, 1) else r.returncode


if __name__ == '__main__':
    sys.exit(main())
