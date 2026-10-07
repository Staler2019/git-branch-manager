#!/usr/bin/env python3
"""check-narrow-path-conversions.py 的單元測試。從 repo 根目錄跑：
python3 scripts/test_check_narrow_path_conversions.py"""
import importlib.util, os, sys, tempfile, unittest

sys.dont_write_bytecode = True

_spec = importlib.util.spec_from_file_location(
    'narrow', os.path.join(os.path.dirname(__file__), 'check-narrow-path-conversions.py'))
narrow = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(narrow)


def write(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(text)


class Findings(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def found(self):
        return narrow.findings(self.root)

    def test_string_is_reported(self):
        write(self.root, 'src/core/a.cpp', 'args.push_back(dir.string());\n')
        self.assertEqual(len(self.found()), 1)

    def test_generic_string_is_reported(self):
        write(self.root, 'src/core/a.cpp', 'auto t = p.generic_string();\n')
        self.assertEqual(len(self.found()), 1)

    def test_narrow_constructor_is_reported(self):
        write(self.root, 'src/capi/a.cpp', 'auto p = std::filesystem::path(text);\n')
        self.assertEqual(len(self.found()), 1)

    def test_utf8_helpers_are_not_reported(self):
        write(self.root, 'src/core/a.cpp',
              'args.push_back(fsutil::utf8FromPath(dir));\nauto p = fsutil::pathFromUtf8(t);\n')
        self.assertEqual(self.found(), [])

    def test_a_comment_is_not_reported(self):
        write(self.root, 'src/core/a.h', '    // dir.string() is the trap\n')
        self.assertEqual(self.found(), [])

    def test_an_allowed_line_is_not_reported_but_only_in_its_file(self):
        line = 'std::filesystem::path candidate = std::filesystem::path(entry) / kExeName;\n'
        write(self.root, 'src/core/git/GitExecutable.cpp', line)
        write(self.root, 'src/core/git/Other.cpp', line)
        self.assertEqual([f.split(':')[0] for f in self.found()], ['src/core/git/Other.cpp'])

    def test_files_outside_src_are_ignored(self):
        write(self.root, 'tests/a.cpp', 'x.string();\n')
        self.assertEqual(self.found(), [])


if __name__ == '__main__':
    unittest.main()
