#!/usr/bin/env python3
"""check-read-pool-posts.py 的單元測試。從 repo 根目錄跑：
python3 scripts/test_check_read_pool_posts.py"""
import importlib.util, os, sys, tempfile, unittest

sys.dont_write_bytecode = True

_spec = importlib.util.spec_from_file_location(
    'posts', os.path.join(os.path.dirname(__file__), 'check-read-pool-posts.py'))
posts = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(posts)

_POST_READ = (
    'void postRead(ReadLane lane, std::string where) {\n'
    '    if (lane == ReadLane::Front) {\n'
    '        sharedReadPool().postFront(std::move(run));\n'
    '    } else {\n'
    '        sharedReadPool().post(std::move(run));\n'
    '    }\n'
    '}\n')


def write(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(text)


class ReadPoolPosts(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def found(self):
        return posts.findings(self.root)

    def test_post_read_itself_is_not_reported(self):
        write(self.root, 'src/capi/Session.cpp', _POST_READ)
        self.assertEqual(self.found(), [])

    def test_post_reads_hand_off_step_is_not_reported(self):
        write(self.root, 'src/capi/Session.cpp',
              'void handToReadPool(ReadLane lane, std::function<void()> job) {\n'
              '    sharedReadPool().postFront(std::move(job));\n'
              '}\n' + _POST_READ)
        self.assertEqual(self.found(), [])

    def test_a_raw_post_after_the_hand_off_step_is_still_reported(self):
        write(self.root, 'src/capi/Session.cpp',
              'void handToReadPool(ReadLane lane, std::function<void()> job) {\n'
              '    sharedReadPool().post(std::move(job));\n'
              '}\n'
              'void Session::requestX() {\n'
              '    sharedReadPool().post([this]() { run(); });\n'
              '}\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_raw_post_in_a_session_method_is_reported(self):
        write(self.root, 'src/capi/Session.cpp',
              _POST_READ + 'void Session::requestX() {\n'
              '    sharedReadPool().post([this]() { run(); });\n'
              '}\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_raw_post_front_anywhere_in_src_is_reported(self):
        write(self.root, 'src/capi/Other.cpp', 'sharedReadPool().postFront([] {});\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_post_split_across_lines_is_reported(self):
        write(self.root, 'src/capi/Other.cpp', 'sharedReadPool()\n    .post([] {});\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_pool_taken_by_reference_is_reported(self):
        write(self.root, 'src/capi/Other.cpp', 'ThreadPool& pool = sharedReadPool();\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_pool_taken_by_auto_reference_is_reported(self):
        write(self.root, 'src/capi/Other.cpp', 'auto& pool = sharedReadPool();\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_pool_taken_by_pointer_is_reported(self):
        write(self.root, 'src/capi/Other.cpp',
              'ThreadPool* a = &sharedReadPool();\n'
              'auto* b = &sharedReadPool();\n')
        self.assertEqual(len(self.found()), 2)

    def test_a_pool_handed_to_another_function_is_reported(self):
        write(self.root, 'src/capi/Other.cpp', 'schedule(sharedReadPool(), [] {});\n')
        self.assertEqual(len(self.found()), 1)

    def test_the_declaration_and_definition_are_not_reported(self):
        write(self.root, 'src/capi/Session.h', 'ThreadPool& sharedReadPool();\n')
        write(self.root, 'src/capi/Session.cpp',
              _POST_READ + 'ThreadPool& sharedReadPool() {\n'
              '    static ThreadPool pool;\n'
              '    return pool;\n'
              '}\n')
        self.assertEqual(self.found(), [])

    def test_draining_the_pool_is_not_reported(self):
        write(self.root, 'src/capi/Session.cpp',
              _POST_READ + 'Session::~Session() {\n'
              '    sharedReadPool().cancelQueuedAndDrain();\n'
              '}\n')
        self.assertEqual(self.found(), [])

    def test_a_comment_is_not_reported(self):
        write(self.root, 'src/core/a.h',
              '/// a background read post to sharedReadPool().post(), not serialised\n'
              '// sharedReadPool().postFront(x) used to be here\n')
        self.assertEqual(self.found(), [])

    def test_the_real_tree_is_clean(self):
        root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
        self.assertEqual(posts.findings(root), [])


if __name__ == '__main__':
    unittest.main()
