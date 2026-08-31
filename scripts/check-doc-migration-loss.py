#!/usr/bin/env python3
"""剪短一段散文時，檢查有沒有把得來不易的證據弄丟。

每個具體事實（code span、檔名、版本號、issue 號）都必須在新寫的檔案或
docs/ledger.md 裡找得到。找不到 = 這次剪短弄丟了東西，先回填再刪。

    scripts/check-doc-migration-loss.py <ref:path> '<section 標題>' <新檔案>...

例（2026-08-31 那輪實際跑的）：

    scripts/check-doc-migration-loss.py f8cdfb9:CLAUDE.md '### C++ core' \
        docs/rules/fn-cpp-core.md

寫成腳本而不是靠肉眼，是因為它真的抓到過東西：搬 refs/git 那一段時，
它報 `RepoSessionController.refreshRepoStatus()` 不見了 —— 標題被我少寫了
類別前綴。ledger: 2026-08-31-docs-split-rules-for-parallel-rounds
"""
import re, subprocess, sys

if len(sys.argv) < 4:
    sys.exit(__doc__)
oldref, section, newfiles = sys.argv[1], sys.argv[2], sys.argv[3:]
old = subprocess.run(['git','show',oldref],capture_output=True,text=True).stdout.split('\n')

try:
    start = next(i for i,l in enumerate(old) if l.strip()==section)
except StopIteration:
    sys.exit(f"{oldref} 裡找不到標題 {section!r}")
end   = next(i for i,l in enumerate(old[start+1:],start+1) if re.match(r'^#{2,4} ',l))
oldtext = '\n'.join(old[start:end])

hay = open('docs/ledger.md',encoding='utf-8').read()
for f in newfiles:
    hay += open(f,encoding='utf-8').read()
# 原文是硬斷行的，code span 常被折成兩行；比對前把空白正規化，
# 否則折行會被誤報成「弄丟了」。
norm = lambda s: re.sub(r'\s+', ' ', s)
hay = norm(hay)

facts = set()
facts |= set(re.findall(r'`([^`]+)`', oldtext))          # code spans
facts |= set(re.findall(r'\*\*(#\d+)\*\*', oldtext))     # issue numbers
facts |= set(re.findall(r'\b\d+(?:\.\d+)+\b', oldtext))  # versions
facts |= set(re.findall(r'[A-Za-z_][\w/.-]*\.(?:dart|cpp|h|yml|yaml|md|ps1|sh|xib|plist)\b', oldtext))

missing = sorted(f for f in facts if f.strip() and norm(f) not in hay)
print(f"{section}: {len(facts)} 個具體事實，缺 {len(missing)}")
for m in missing:
    print("  MISSING:", repr(m))
sys.exit(1 if missing else 0)
