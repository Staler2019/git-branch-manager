#!/usr/bin/env python3
"""scripts/_find-python.sh 的單元測試。從 repo 根目錄跑：
python3 scripts/test_find_python.py

PATH 只放假的 python3／python，所以機器上裝了什麼 Python 都不影響結果。"""
import os, shutil, stat, subprocess, tempfile, unittest

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_find-python.sh')


def write_executable(path, text):
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


def interpreter(exe, crlf=False):
    """A fake that answers the helper's probe with `exe`, as a real Python 3 would."""
    end = '\\r\\n' if crlf else '\\n'
    return f'#!/bin/sh\nprintf \'%s{end}\' \'{exe}\'\n'


# Microsoft Store 的 python3.exe：在 PATH 上找得到，但執行只會叫你去 Store 裝。
STORE_STUB = '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store" >&2\nexit 9009\n'
# Python 2 的 sys.version_info[0] 是 2，探測程式會 exit 1。
PYTHON2 = '#!/bin/sh\nexit 1\n'


class FindPython(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.bin = os.path.join(self.tmp, 'bin')
        os.makedirs(self.bin)

    def fake(self, name, text):
        write_executable(os.path.join(self.bin, name), text)

    def find(self):
        return subprocess.run([shutil.which('sh'), '-c', '. "$1" && find_python', 'sh', HELPER],
                              text=True, capture_output=True, timeout=10, env={'PATH': self.bin})

    def test_prefers_python3_and_prints_its_real_executable(self):
        self.fake('python3', interpreter('/opt/py3/bin/python3.12'))
        self.fake('python', interpreter('/opt/other/bin/python'))
        result = self.find()
        self.assertEqual((result.returncode, result.stdout), (0, '/opt/py3/bin/python3.12\n'), result.stderr)

    def test_falls_back_to_python_when_there_is_no_python3(self):
        self.fake('python', interpreter('/opt/py/bin/python'))
        result = self.find()
        self.assertEqual((result.returncode, result.stdout), (0, '/opt/py/bin/python\n'), result.stderr)

    def test_skips_a_python3_that_cannot_run(self):
        self.fake('python3', STORE_STUB)
        self.fake('python', interpreter('/opt/py/bin/python'))
        result = self.find()
        self.assertEqual((result.returncode, result.stdout), (0, '/opt/py/bin/python\n'), result.stderr)

    def test_skips_a_python_2(self):
        self.fake('python3', STORE_STUB)
        self.fake('python', PYTHON2)
        result = self.find()
        self.assertEqual((result.returncode, result.stdout), (1, ''))

    def test_strips_the_carriage_return_a_windows_python_prints(self):
        self.fake('python3', interpreter('C:\\Python312\\python.exe', crlf=True))
        result = self.find()
        self.assertEqual((result.returncode, result.stdout), (0, 'C:\\Python312\\python.exe\n'), result.stderr)

    def test_probing_leaves_the_callers_stdin_alone(self):
        # pyenv-win 的 shim 會把 stdin 讀光；hook 的 payload 就在 stdin 上。
        self.fake('python3', '#!/bin/sh\ncat >/dev/null\nprintf \'%s\\n\' /opt/py3/bin/python3\n')
        result = subprocess.run([shutil.which('sh'), '-c', '. "$1" && find_python && cat', 'sh', HELPER],
                                input='payload', text=True, capture_output=True, timeout=10,
                                env={'PATH': self.bin + os.pathsep + os.path.dirname(shutil.which('cat'))})
        self.assertEqual((result.returncode, result.stdout), (0, '/opt/py3/bin/python3\npayload'), result.stderr)

    def test_fails_when_there_is_no_python_at_all(self):
        result = self.find()
        self.assertEqual((result.returncode, result.stdout), (1, ''))


if __name__ == '__main__':
    unittest.main()
