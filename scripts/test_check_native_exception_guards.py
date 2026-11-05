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

    def test_a_named_thread_is_reported(self):
        write(self.root, 'src/core/a.cpp', 'std::thread worker([this] { run(); });\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_braced_thread_is_reported(self):
        write(self.root, 'src/core/a.cpp', 'auto t = std::thread{[this] { run(); }};\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_jthread_is_reported(self):
        write(self.root, 'src/core/a.cpp', 'std::jthread worker([this] { run(); });\n')
        self.assertEqual(len(self.found()), 1)

    def test_any_thread_vector_is_reported(self):
        write(self.root, 'src/core/a.cpp', 'pool.emplace_back([&] { run(); });\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_vector_of_anything_else_is_not_reported(self):
        write(self.root, 'src/core/a.cpp', 'rows.emplace_back([&] { run(); });\n')
        self.assertEqual(self.found(), [])

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


class Exports(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def found(self):
        return guards.findings(self.root)

    def test_an_unguarded_export_is_reported(self):
        write(self.root, 'src/capi/a.cpp', 'GBM_API int32_t gbm_x(void) {\n    return 0;\n}\n')
        self.assertEqual(len(self.found()), 1)

    def test_an_unguarded_one_liner_is_reported(self):
        write(self.root, 'src/capi/a.cpp', 'GBM_API void gbm_x(void) {}\n')
        self.assertEqual(len(self.found()), 1)

    def test_an_unguarded_multi_line_signature_is_reported(self):
        write(self.root, 'src/capi/a.cpp', 'GBM_API void gbm_x(int a,\n    int b) {\n}\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_guarded_export_is_not_reported(self):
        write(self.root, 'src/capi/a.cpp',
              'GBM_API void gbm_x(int a,\n    int b) try {\n} catch (...) {\n'
              '    reportCurrentException(__func__);\n}\n')
        self.assertEqual(self.found(), [])

    def test_an_unguarded_definition_in_a_header_is_reported(self):
        write(self.root, 'src/capi/a.h', 'GBM_API void gbm_x(void) {\n}\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_void_export_writing_the_staging_buffer_is_reported(self):
        write(self.root, 'src/capi/a.cpp',
              'GBM_API void gbm_x(void) try {\n} catch (...) {\n'
              '    reportNativeException(__func__);\n}\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_void_export_logging_is_not_reported(self):
        write(self.root, 'src/capi/a.cpp',
              'GBM_API void gbm_x(void) try {\n} catch (...) {\n'
              '    reportCurrentException(__func__);\n}\n')
        self.assertEqual(self.found(), [])

    def test_an_export_returning_a_value_may_write_the_staging_buffer(self):
        write(self.root, 'src/capi/a.cpp',
              'GBM_API int32_t gbm_x(void) try {\n    return 0;\n} catch (...) {\n'
              '    reportNativeException(__func__);\n    return -1;\n}\n')
        self.assertEqual(self.found(), [])

    def report_one(self, signature, catch, body=''):
        write(self.root, 'src/capi/a.cpp', f'GBM_API {signature} try {{\n{body}}} {catch}}}\n')
        self.assertEqual(len(self.found()), 1, self.found())

    def test_an_indented_unguarded_export_is_reported(self):
        write(self.root, 'src/capi/a.cpp', '    GBM_API int32_t gbm_x(void) {\n    return 0;\n}\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_narrow_catch_on_a_void_export_is_reported(self):
        self.report_one('void gbm_x(void)', 'catch (const std::exception&) {\n'
                        '    reportCurrentException(__func__);\n')

    def test_a_narrow_catch_on_a_value_export_is_reported(self):
        self.report_one('int32_t gbm_x(void)', 'catch (const std::exception&) {\n'
                        '    reportNativeException(__func__);\n    return -1;\n')

    def test_an_empty_catch_on_a_void_export_is_reported(self):
        self.report_one('void gbm_x(void)', 'catch (...) {\n')

    def test_a_void_export_reporting_natively_after_logging_is_reported(self):
        self.report_one('void gbm_x(void)', 'catch (...) {\n'
                        '    reportCurrentException(__func__);\n'
                        '    reportNativeException(__func__);\n')

    def test_a_void_export_writing_the_buffer_directly_is_reported(self):
        self.report_one('void gbm_x(void)', 'catch (...) {\n    setStagingBuffer("x");\n')

    def test_a_qualified_native_report_on_a_void_export_is_reported(self):
        self.report_one('void gbm_x(void)', 'catch (...) {\n'
                        '    gbm::capi::reportNativeException(__func__);\n')

    def test_a_void_export_writing_the_buffer_in_its_body_is_reported(self):
        self.report_one('void gbm_x(void)', 'catch (...) {\n'
                        '    reportCurrentException(__func__);\n',
                        body='    setStagingBuffer("x");\n')

    def test_a_value_export_returning_success_from_its_catch_is_reported(self):
        self.report_one('int32_t gbm_x(void)', 'catch (...) {\n'
                        '    reportNativeException(__func__);\n    return 0;\n')

    def test_a_value_export_that_does_not_report_is_reported(self):
        self.report_one('int32_t gbm_x(void)', 'catch (...) {\n    return -1;\n')

    def test_a_value_export_reporting_some_other_way_is_reported(self):
        self.report_one('int32_t gbm_x(void)', 'catch (...) {\n'
                        '    reportCurrentException(__func__);\n    return -1;\n')

    def test_a_value_export_rethrowing_is_reported(self):
        self.report_one('int32_t gbm_x(void)', 'catch (...) {\n    throw;\n')

    def test_a_listed_export_may_return_its_own_failure_value(self):
        write(self.root, 'src/capi/a.cpp',
              'GBM_API int32_t gbm_has_commit_graph(void) try {\n    return 1;\n} catch (...) {\n'
              '    reportNativeException(__func__);\n    return 0;\n}\n')
        self.assertEqual(self.found(), [])

    def test_a_listed_export_returning_the_wrong_value_is_reported(self):
        self.report_one('int32_t gbm_has_commit_graph(void)', 'catch (...) {\n'
                        '    reportNativeException(__func__);\n    return -1;\n')

    def test_a_qualified_report_is_accepted(self):
        write(self.root, 'src/capi/a.cpp',
              'GBM_API int32_t gbm_askpass_main(void) try {\n    return 0;\n} catch (...) {\n'
              '    gbm::capi::reportNativeException(__func__);\n    return 1;\n}\n'
              'GBM_API void gbm_y(void) try {\n} catch (...) {\n'
              '    gbm::reportCurrentException(__func__);\n}\n')
        self.assertEqual(self.found(), [])

    def test_an_inner_try_does_not_stand_in_for_the_function_try_block(self):
        write(self.root, 'src/capi/a.cpp',
              'GBM_API int32_t gbm_x(void) {\n    try {\n        return 0;\n'
              '    } catch (...) {\n        return -1;\n    }\n}\n')
        self.assertEqual(len(self.found()), 1)

    def test_a_declaration_in_the_header_is_not_reported(self):
        write(self.root, 'src/capi/gbm_capi.h', 'GBM_API void gbm_x(void);\n')
        self.assertEqual(self.found(), [])


if __name__ == '__main__':
    unittest.main()
