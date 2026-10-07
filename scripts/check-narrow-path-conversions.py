#!/usr/bin/env python3
"""src/ 裡不得出現「拼寫得出的」narrow 路徑轉換。

Windows 上 `path::string()` / `generic_string()` 以系統代碼頁編碼、
`std::filesystem::path(std::string)` 以系統代碼頁解碼；本專案其餘部分（Dart FFI、
git 的 core.quotepath=false、ProcessRunner 的 widen(CP_UTF8)）都假設 UTF-8。
繁中 Windows（CP950）上中文會遺失，西歐代碼頁（CI 的 1252）上直接拋出例外。
一律走 fsutil::utf8FromPath / fsutil::pathFromUtf8（core/base/FsUtil.h）。

**抓不到的**：隱式轉換——把 std::string 傳給吃 path 的參數、`path / std::string`。
那些只能靠盤點，這支腳本不宣稱涵蓋。

從 repo 根目錄跑：python3 scripts/check-narrow-path-conversions.py
"""
import os, re, sys

_PATTERNS = (
    re.compile(r'\.(?:generic_)?string\(\)'),
    re.compile(r'std::filesystem::path\((?!\s*\))'),
)

# (檔案, 該行必須含的片段, 理由)。新增一筆前先問：能不能改走 FsUtil？
ALLOWED = (
    ('src/core/base/FsUtil.cpp', 'std::filesystem::path(buffer)',
     'Windows 的 buffer 是 GetModuleFileNameW 的 wstring；macOS 的是系統原生 UTF-8'),
    ('src/core/base/FsUtil.cpp', 'std::filesystem::path(L"',
     '寬字元字面值，不經代碼頁'),
    ('src/core/base/FsUtil.cpp', 'return std::filesystem::path(',
     'pathFromUtf8 本身，參數是 std::u8string'),
    ('src/core/git/GitExecutable.cpp', 'std::filesystem::path(entry)',
     'PATH 的項目來自窄 getenv，與窄建構子同一個代碼頁，往返一致'),
)


def _is_comment(line):
    return re.match(r'\s*(//|\*|/\*)', line) is not None


def findings(root):
    out = []
    for base in ('src',):
        for dirpath, _, files in os.walk(os.path.join(root, base)):
            for name in sorted(files):
                if not name.endswith(('.cpp', '.h', '.hpp')):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, root).replace(os.sep, '/')
                with open(path, encoding='utf-8') as f:
                    for number, line in enumerate(f, 1):
                        if _is_comment(line):
                            continue
                        if not any(p.search(line) for p in _PATTERNS):
                            continue
                        if any(rel == file and fragment in line for file, fragment, _ in ALLOWED):
                            continue
                        out.append(f'{rel}:{number}: {line.strip()}')
    return out


def main():
    found = findings(os.getcwd())
    for line in found:
        print(f'::error::narrow path conversion - use fsutil::utf8FromPath/pathFromUtf8: {line}')
    if found:
        return 1
    print('no narrow path conversions')
    return 0


if __name__ == '__main__':
    sys.exit(main())
