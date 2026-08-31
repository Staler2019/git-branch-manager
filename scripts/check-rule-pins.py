#!/usr/bin/env python3
"""每個 [PIN] 引用都必須對到一個真的 ## [PIN] 標題；pin 不可重複定義。"""
import re, glob, sys, collections
defined, refs = {}, collections.defaultdict(list)
for f in sorted(glob.glob('docs/rules/*.md')):
    fenced = False
    for i, l in enumerate(open(f, encoding='utf-8'), 1):
        if l.startswith('```'):
            fenced = not fenced          # README 的格式範例是示範，不是真的規則
            continue
        if fenced:
            continue
        m = re.match(r'^## \[([A-Z]+-[a-z0-9-]+)\]', l)
        if m:
            if m[1] in defined:
                print(f"DUPLICATE pin {m[1]}: {defined[m[1]]} and {f}:{i}")
            defined[m[1]] = f"{f}:{i}"
        # `[FLU-036]` 之類寫在反引號裡的是「不要這樣做」的示例，不是引用
        for r in re.findall(r'\[([A-Z]+-[a-z0-9-]+)\]', re.sub(r'`[^`]*`', '', l)):
            if not m or r != m[1]:
                refs[r].append(f"{f}:{i}")
dangling = {r: v for r, v in refs.items() if r not in defined}
print(f"{len(defined)} 條規則、{sum(len(v) for v in refs.values())} 個交叉引用，懸空 {len(dangling)}")
for r, v in sorted(dangling.items()):
    print(f"  DANGLING [{r}] cited at {', '.join(v)}")
sys.exit(1 if dangling else 0)
