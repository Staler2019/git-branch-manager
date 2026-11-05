#!/usr/bin/env python3
"""原生例外不得穿出邊界：每個執行緒入口都要接住（#207）。

執行緒入口沒有呼叫者，例外穿出去就是 std::terminate；Windows GUI app 不會留下任何訊息。
一律用 guardedThread（core/base/ExceptionDiagnostic.h），不得直接建立 std::thread。

從 repo 根目錄跑：python3 scripts/check-native-exception-guards.py
"""
import os, re, sys

# guardedThread 本身是唯一允許的地方。
_THREAD_HELPER = 'src/core/base/ExceptionDiagnostic.h'
_BARE_THREAD = re.compile(r'std::thread\(|\b(?:threads|workers_)\.emplace_back\(')


def _is_comment(line):
    return re.match(r'\s*(//|\*|/\*)', line) is not None


def _sources(root):
    for dirpath, _, files in os.walk(os.path.join(root, 'src')):
        for name in sorted(files):
            if name.endswith(('.cpp', '.h', '.hpp')):
                path = os.path.join(dirpath, name)
                with open(path, encoding='utf-8') as f:
                    yield os.path.relpath(path, root).replace(os.sep, '/'), f.read().split('\n')


def _thread_findings(rel, lines):
    if rel == _THREAD_HELPER:
        return []
    return [f'{rel}:{index + 1}: bare thread, use guardedThread: {line.strip()}'
            for index, line in enumerate(lines)
            if not _is_comment(line) and _BARE_THREAD.search(line)]


def findings(root):
    out = []
    for rel, lines in _sources(root):
        out += _thread_findings(rel, lines)
    return out


def main():
    found = findings(os.getcwd())
    for line in found:
        print(f'::error::native exception guard missing: {line}')
    if found:
        return 1
    print('every native boundary catches exceptions')
    return 0


if __name__ == '__main__':
    sys.exit(main())
