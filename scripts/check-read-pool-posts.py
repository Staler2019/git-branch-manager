#!/usr/bin/env python3
"""read 只能經 postRead 送進 sharedReadPool（src/capi/Session.cpp）。

pool 自己的 catch 只寫 log（ThreadPool.cpp 的 workerLoop），read 丟例外就不會有回覆，Dart 那邊
等它的 isRefreshing、Completer 會一直等下去。postRead 接住例外後送出這個 read 原本的失敗回覆。
所以 src/ 裡除了 postRead 本身和它唯一的交出步驟 handToReadPool，不得直接 post／postFront，
也不得把 pool 拿出去（參照、指標、auto、當引數傳）再 post。採白名單：這兩個函式之外，
sharedReadPool() 只能出現在它的宣告與定義，或直接接 drain()／cancelQueuedAndDrain()——
這兩個不送工作。

從 repo 根目錄跑：python3 scripts/check-read-pool-posts.py
"""
import os, re, sys

# postRead 和它交出 run 的那一步（handToReadPool，只被 postRead 呼叫）是唯一允許的地方。
_HELPER_FILE = 'src/capi/Session.cpp'
_HELPER_START = re.compile(r'^void (?:postRead|handToReadPool)\(')
_USE = re.compile(r'sharedReadPool\(\)')
_RAW_POST = re.compile(r'\s*\.\s*post(?:Front)?\s*\(')
_DRAIN = re.compile(r'\s*\.\s*(?:drain|cancelQueuedAndDrain)\s*\(')
_DECLARATION = re.compile(r'ThreadPool\s*&\s*sharedReadPool\(\)\s*[;{]')


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
    """postRead 與 handToReadPool 定義所佔的行號（0 起算），其他檔案為空。"""
    if rel != _HELPER_FILE:
        return set()
    allowed = set()
    for start, line in enumerate(lines):
        if not _HELPER_START.match(line):
            continue
        end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('}')), len(lines))
        allowed.update(range(start, end + 1))
    return allowed


def findings(root):
    out = []
    for rel, lines in _sources(root):
        allowed = _helper_lines(rel, lines)
        code = [_strip_comment(line) for line in lines]
        text = '\n'.join(code)
        for match in _USE.finditer(text):
            index = text.count('\n', 0, match.start())
            if index in allowed or _DRAIN.match(text, match.end()) or _DECLARATION.match(code[index]):
                continue
            what = 'raw post' if _RAW_POST.match(text, match.end()) else 'pool taken out of postRead'
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
