#!/usr/bin/env python3
"""開場載入的指令量（字元）不得超過 CLAUDE.md 宣告的 L0 上限。

Claude Code 在 session 開始時載入 CLAUDE.md、它遞迴的 @import（最多 4 層）、以及
.claude/rules/ 裡沒有 `paths:` 的檔案，並對總量設 150k 字元的上限 —— 那個上限連
使用者自己的 ~/.claude 也算進去，所以專案只能用其中一部分。

上限是棘輪：超過就紅；低於實際量超過 SLACK 也紅，逼每次縮減後把上限一起調低，
直到 CLAUDE.md 寫的目標值。依路徑載入的檔只回報，不擋。

從 repo 根目錄跑：python3 scripts/check-instruction-budget.py
"""
import glob, os, re, sys

SLACK = 2_000
L1_BUDGET = 6_000
_IMPORT = re.compile(r'(?<![\w`])@((?:\\ |[^\s`])+)')
_CEILING = re.compile(r'L0 ceiling\D*([\d,]+)')


def has_paths(text):
    if not text.startswith('---\n'):
        return False
    end = text.find('\n---', 4)
    return end != -1 and re.search(r'^paths\s*:', text[4:end], re.M) is not None


def imports(path, text):
    found, fenced = [], False
    for line in text.splitlines():
        if line.lstrip().startswith('```'):
            fenced = not fenced
            continue
        if fenced:
            continue
        for m in _IMPORT.finditer(re.sub(r'`[^`]*`', '', line)):
            target = os.path.expanduser(m[1].replace('\\ ', ' '))
            if not os.path.isabs(target):
                target = os.path.join(os.path.dirname(path), target)
            if os.path.isfile(target):
                found.append(os.path.normpath(target))
    return found


def _read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def rule_files(root):
    return sorted(glob.glob(os.path.join(root, '.claude', 'rules', '**', '*.md'), recursive=True))


def startup_files(root):
    """[(path, chars)]：開場載入的每個檔，依載入順序。"""
    roots = [os.path.join(root, f) for f in ('CLAUDE.md', '.claude/CLAUDE.md', 'CLAUDE.local.md')]
    roots += [p for p in rule_files(root) if not has_paths(_read(p))]
    seen, loaded = set(), []

    def visit(path, depth):
        path = os.path.normpath(path)
        if path in seen or not os.path.isfile(path):
            return
        seen.add(path)
        text = _read(path)
        loaded.append((path, len(text)))
        if depth < 4:
            for target in imports(path, text):
                visit(target, depth + 1)

    for r in roots:
        visit(r, 0)
    return loaded


def scoped_files(root):
    return [(p, len(t)) for p in rule_files(root) for t in [_read(p)] if has_paths(t)]


def read_ceiling(claude_md_text):
    m = _CEILING.search(claude_md_text)
    return int(m[1].replace(',', '')) if m else None


def verdict(total, ceiling):
    """None 表示通過；否則是要印出的失敗原因。"""
    if total > ceiling:
        return f'L0 is {total:,} chars, over the {ceiling:,} ceiling'
    if ceiling - total > SLACK:
        return f'L0 is {total:,} chars; lower the ceiling to {total:,} (slack {SLACK:,})'
    return None


def main():
    root = '.'
    ceiling = read_ceiling(_read(os.path.join(root, 'CLAUDE.md')))
    if ceiling is None:
        print('CLAUDE.md declares no "L0 ceiling"')
        return 1
    loaded = startup_files(root)
    total = sum(n for _, n in loaded)
    print(f'L0: {total:,} chars in {len(loaded)} files (ceiling {ceiling:,})')
    for path, n in sorted(loaded, key=lambda x: -x[1]):
        print(f'  {n:>7,}  {os.path.relpath(path, root)}')
    print(f'path-scoped (report only, budget {L1_BUDGET:,} each):')
    for path, n in scoped_files(root):
        print(f'  {n:>7,}  {os.path.relpath(path, root)}{"  over" if n > L1_BUDGET else ""}')
    problem = verdict(total, ceiling)
    if problem:
        print(problem)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
