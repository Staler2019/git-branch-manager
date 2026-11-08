#!/usr/bin/env python3
"""read 只能經 postRead 送進 sharedReadPool（src/capi/Session.cpp）。

pool 自己的 catch 只寫 log（ThreadPool.cpp 的 workerLoop），read 丟例外就不會有回覆，Dart 那邊
等它的 isRefreshing、Completer 會一直等下去。postRead 接住例外後送出這個 read 原本的失敗回覆。
所以 src/ 裡除了 postRead 本身，不得直接 post／postFront，也不得把 pool 取成參照再 post。
drain、cancelQueuedAndDrain 不送工作，不受限。

從 repo 根目錄跑：python3 scripts/check-read-pool-posts.py
"""
import os, re, sys

# postRead 的定義是唯一允許的地方。
_HELPER_FILE = 'src/capi/Session.cpp'
_HELPER_START = re.compile(r'^void postRead\(')
_RAW_POST = re.compile(r'sharedReadPool\(\)\s*\.\s*post(?:Front)?\s*\(')
_POOL_REFERENCE = re.compile(r'ThreadPool\s*&\s*\w+\s*=\s*sharedReadPool\(\)')


def _strip_comment(line):
    if re.match(r'\s*(\*|/\*)', line):
        return ''
    return line.split('//', 1)[0]


def _sources(root):
    for dirpath, _, files in os.walk(os.path.join(root, 'src')):
        for name in sorted(files):
            if name.endswith(('.cpp', '.h', '.hpp')):
                path = os.path.join(dirpath, name)
                with open(path, encoding='utf-8') as f:
                    yield os.path.relpath(path, root).replace(os.sep, '/'), f.read().split('\n')


def _helper_lines(rel, lines):
    """postRead 定義所佔的行號（0 起算），其他檔案為空。"""
    if rel != _HELPER_FILE:
        return range(0)
    start = next((i for i, line in enumerate(lines) if _HELPER_START.match(line)), None)
    if start is None:
        return range(0)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('}')), len(lines))
    return range(start, end + 1)


def findings(root):
    out = []
    for rel, lines in _sources(root):
        allowed = _helper_lines(rel, lines)
        code = [_strip_comment(line) for line in lines]
        text = '\n'.join(code)
        for pattern, what in ((_RAW_POST, 'raw post'), (_POOL_REFERENCE, 'pool taken by reference')):
            for match in pattern.finditer(text):
                index = text.count('\n', 0, match.start())
                if index in allowed:
                    continue
                out.append(f'{rel}:{index + 1}: {what}, use postRead: {lines[index].strip()}')
    return out


def main():
    found = findings(os.getcwd())
    for line in found:
        print(f'::error::read posted around postRead: {line}')
    if found:
        return 1
    print('every read goes through postRead')
    return 0


if __name__ == '__main__':
    sys.exit(main())
