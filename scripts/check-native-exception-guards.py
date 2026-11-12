#!/usr/bin/env python3
"""原生例外不得穿出邊界：每個執行緒入口與 C API 匯出函式都要接住（#207）。

執行緒入口沒有呼叫者，例外穿出去就是 std::terminate；Windows GUI app 不會留下任何訊息。
一律用 guardedThread（core/base/ExceptionDiagnostic.h），不得直接建立 std::thread。

src/capi 匯出函式同理：例外穿進 Dart FFI 沒有 handler。一律寫成 function-try-block 加
catch (...)，catch 裡呼叫 reportNativeException（capi/Handle.h）並回傳失敗值；void 匯出沒有人
讀 staging buffer，catch 只呼叫 reportCurrentException。

從 repo 根目錄跑：python3 scripts/check-native-exception-guards.py
"""
import os, re, sys

# guardedThread 本身是唯一允許的地方。
_THREAD_HELPER = 'src/core/base/ExceptionDiagnostic.h'
_BARE_THREAD = re.compile(
    r'std::thread\s*(?:\w+\s*)?[({]|std::jthread\b|\b_beginthread|\bCreateThread\(|\bpthread_create\('
    r'|\b\w*(?i:thread|worker|pool)\w*\.emplace_back\(')

# 回傳值的匯出失敗時回 -1 或 nullptr（gbm_capi.h 的慣例）；這些的 -1 會被 Dart 當成長度或旗標。
_OWN_FAILURE_VALUE = {
    'gbm_askpass_main': '1',
    # 1 = queued, 0 = nothing queued (gbm_capi.h): Dart drops its pending entry on 0.
    'gbm_branch_checkout': '0',
    'gbm_branch_delete': '0',
    'gbm_graph_snapshot_complete': '0',
    'gbm_graph_snapshot_lane_count': '0',
    'gbm_graph_snapshot_truncated': '0',
    'gbm_has_commit_graph': '0',
    'gbm_history_refresh': '0',
    'gbm_last_result_json_len': '0',
    'gbm_remote_fetch': '0',
    'gbm_remote_prune': '0',
}
_VOID_CATCH = re.compile(r'(gbm::)?reportCurrentException\(__func__\);$')
_VALUE_CATCH = re.compile(r'(gbm::(capi::)?)?reportNativeException\(__func__\);$')


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


def _next_closing(lines, start):
    return next((i for i in range(start, len(lines)) if lines[i].startswith('}')), None)


def _export_problem(line, lines, end):
    if not lines[end].rstrip().endswith(' try {'):
        return 'export without function-try-block'
    closing = _next_closing(lines, end + 1)
    if closing is None or lines[closing].rstrip() != '} catch (...) {':
        return 'export without catch (...)'
    catch_end = _next_closing(lines, closing + 1)
    body = [text.strip() for text in lines[closing + 1:catch_end]]
    if line.startswith('GBM_API void '):
        if len(body) != 1 or not _VOID_CATCH.match(body[0]):
            return 'void export catch must only call reportCurrentException(__func__)'
        if any(re.search(r'setStagingBuffer|reportNativeException', text)
               for text in lines[end + 1:closing]):
            return 'void export writes a staging buffer nobody reads'
        return None
    if not body or not _VALUE_CATCH.match(body[0]):
        return 'export catch must call reportNativeException(__func__)'
    name = re.search(r'\bgbm_\w+', line)
    expected = _OWN_FAILURE_VALUE.get(name.group() if name else '')
    allowed = {f'return {expected};'} if expected else {'return -1;', 'return nullptr;'}
    if body[1:] and body[1] in allowed and len(body) == 2:
        return None
    return f'export catch must return one of {sorted(allowed)}'


def _export_findings(rel, lines):
    if not rel.startswith('src/capi/'):
        return []
    out = []
    for index, line in enumerate(lines):
        if not line.lstrip().startswith('GBM_API '):
            continue
        end = next(i for i in range(index, len(lines)) if lines[i].rstrip().endswith(('{', ';', '}')))
        if lines[end].rstrip().endswith(';'):
            continue
        problem = _export_problem(line.lstrip(), lines, end)
        if problem:
            out.append(f'{rel}:{index + 1}: {problem}: {line.strip()}')
    return out


def findings(root):
    out = []
    for rel, lines in _sources(root):
        out += _thread_findings(rel, lines)
        out += _export_findings(rel, lines)
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
