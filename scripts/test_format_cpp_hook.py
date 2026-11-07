#!/usr/bin/env python3
""".claude/hooks/format-cpp.sh 的單元測試。從 repo 根目錄跑：
python3 scripts/test_format_cpp_hook.py

hook 複製到暫存專案，`scripts/_resolve-clang-format.sh` 換成假的，所以不需要真的 clang-format。"""
import json, os, shutil, stat, subprocess, tempfile, unittest

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.claude', 'hooks', 'format-cpp.sh')

FAKE_RESOLVER = '#!/bin/sh\necho "$(dirname "$0")/fake-clang-format"\n'
# 每個引數各自加框，路徑被拆開時才看得出來。
FAKE_FORMATTER = '''#!/bin/sh
for arg in "$@"; do printf '[%s]' "$arg"; done >> "$(dirname "$0")/calls.log"
echo >> "$(dirname "$0")/calls.log"
'''


def write_executable(path, text):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


class FormatCppHook(unittest.TestCase):
    def setUp(self):
        self.root = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        os.makedirs(os.path.join(self.root, '.claude', 'hooks'))
        os.makedirs(os.path.join(self.root, 'scripts'))
        os.makedirs(os.path.join(self.root, 'src', 'core'))
        os.makedirs(os.path.join(self.root, 'tests'))
        self.hook = os.path.join(self.root, '.claude', 'hooks', 'format-cpp.sh')
        shutil.copy(HOOK, self.hook)
        self.resolver = os.path.join(self.root, 'scripts', '_resolve-clang-format.sh')
        write_executable(self.resolver, FAKE_RESOLVER)
        write_executable(os.path.join(self.root, 'scripts', 'fake-clang-format'), FAKE_FORMATTER)
        self.log = os.path.join(self.root, 'scripts', 'calls.log')

    def touch(self, rel):
        path = os.path.join(self.root, rel)
        with open(path, 'w', encoding='utf-8') as f:
            f.write('int x;\n')
        return path

    def run_hook(self, stdin):
        return subprocess.run([self.hook], input=stdin, text=True, capture_output=True, timeout=10)

    def run_on(self, path):
        return self.run_hook(json.dumps({'tool_input': {'file_path': path}}))

    def calls(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding='utf-8') as f:
            return f.read().splitlines()

    def test_formats_one_cpp_file_under_src_in_place(self):
        path = self.touch('src/core/a.cpp')
        self.assertEqual(self.run_on(path).returncode, 0)
        self.assertEqual(self.calls(), [f'[-i][--][{path}]'])

    def test_formats_a_header_under_src(self):
        path = self.touch('src/core/a.h')
        self.assertEqual(self.run_on(path).returncode, 0)
        self.assertEqual(self.calls(), [f'[-i][--][{path}]'])

    def test_path_with_spaces_stays_one_argument(self):
        path = self.touch('src/core/a b.cpp')
        self.assertEqual(self.run_on(path).returncode, 0)
        self.assertEqual(self.calls(), [f'[-i][--][{path}]'])

    def test_leaves_everything_ci_does_not_check_alone(self):
        for rel in ('tests/a.cpp', 'src/core/a.dart', 'src/core/a.cpp.orig'):
            with self.subTest(rel=rel):
                self.assertEqual(self.run_on(self.touch(rel)).returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_leaves_a_sibling_directory_with_the_src_prefix_alone(self):
        os.makedirs(os.path.join(self.root, 'src2'))
        self.assertEqual(self.run_on(self.touch('src2/a.cpp')).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_ignores_a_path_that_is_not_a_regular_file(self):
        path = os.path.join(self.root, 'src', 'core', 'gone.cpp')
        self.assertEqual(self.run_on(path).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_ignores_a_payload_without_a_path(self):
        for stdin in ('not json', '[]', '{}', '{"tool_input": null}'):
            with self.subTest(stdin=stdin):
                self.assertEqual(self.run_hook(stdin).returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_a_resolver_failure_reaches_claude_instead_of_passing_silently(self):
        write_executable(self.resolver, '#!/bin/sh\necho "no clang-format 22" >&2\nexit 1\n')
        result = self.run_on(self.touch('src/core/a.cpp'))
        self.assertEqual(result.returncode, 2)
        self.assertIn('no clang-format 22', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_a_formatter_failure_reaches_claude_instead_of_passing_silently(self):
        write_executable(os.path.join(self.root, 'scripts', 'fake-clang-format'),
                         '#!/bin/sh\necho "cannot parse" >&2\nexit 1\n')
        result = self.run_on(self.touch('src/core/a.cpp'))
        self.assertEqual(result.returncode, 2)
        self.assertIn('cannot parse', result.stderr)


if __name__ == '__main__':
    unittest.main()
