#!/usr/bin/env python3
"""check-native-exception-guards.py 的單元測試。從 repo 根目錄跑：
python3 scripts/test_check_native_exception_guards.py"""
import importlib.util, os, sys, tempfile, unittest

sys.dont_write_bytecode = True

_spec = importlib.util.spec_from_file_location(
    'guards', os.path.join(os.path.dirname(__file__), 'check-native-exception-guards.py'))
guards = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guards)


def write(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(text)


class ThreadEntries(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def found(self):
        return guards.findings(self.root)

    def test_an_unguarded_thread_is_reported(self):
        write(self.root, 'src/core/a.cpp', 'thread_ = std::thread([this] { run(); });\n')
        self.assertEqual(len(self.found()), 1)

    def test_an_unguarded_worker_vector_is_reported(self):
        write(self.root, 'src/core/a.cpp', 'threads.emplace_back([&] { run(); });\n')
        self.assertEqual(len(self.found()), 1)

    def test_guarded_thread_is_not_reported(self):
        write(self.root, 'src/core/a.cpp',
              'thread_ = guardedThread("name", [this] { run(); });\n'
              'threads.push_back(guardedThread("name", [&] { run(); }));\n')
        self.assertEqual(self.found(), [])

    def test_the_helper_itself_is_not_reported(self):
        write(self.root, 'src/core/base/ExceptionDiagnostic.h',
              'return std::thread([] { body(); });\n')
        self.assertEqual(self.found(), [])

    def test_a_member_declaration_is_not_reported(self):
        write(self.root, 'src/core/a.h', 'std::thread thread_;\nstd::thread::id id;\n')
        self.assertEqual(self.found(), [])

    def test_a_comment_is_not_reported(self):
        write(self.root, 'src/core/a.cpp', '// std::thread([this] { run(); }) ends the process\n')
        self.assertEqual(self.found(), [])


if __name__ == '__main__':
    unittest.main()
