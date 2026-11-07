#!/usr/bin/env python3
"""_resolve-clang-format.sh 快取 venv 路徑的單元測試。從 repo 根目錄跑：
python3 scripts/test_resolve_clang_format.py

PATH 只放腳本要用的工具和假的 python3，所以機器上有沒有 clang-format、brew 都不影響結果。"""
import os, shutil, stat, subprocess, tempfile, unittest

RESOLVER = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_resolve-clang-format.sh')

# 假的 `python3 -m venv [--clear] DIR`：DIR 已存在又沒帶 --clear 就照舊留著壞掉的內容。
FAKE_PYTHON = '''#!/bin/sh
echo "$*" >> "$FAKE_LOG"
for dir in "$@"; do :; done
case "$*" in *--clear*) rm -rf "$dir" ;; esac
mkdir -p "$dir/bin"
[ -e "$dir/bin/pip" ] && exit 0
cat > "$dir/bin/pip" <<EOF
#!/bin/sh
printf '#!/bin/sh\\necho "clang-format version $FAKE_VERSION"\\n' > "$dir/bin/clang-format"
chmod +x "$dir/bin/clang-format"
EOF
chmod +x "$dir/bin/pip"
'''


def write_executable(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


class CachedVenv(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.bin = os.path.join(self.tmp, 'bin')
        os.makedirs(self.bin)
        # 包一層 exec 而不是 symlink：Windows 沒有開發人員模式時 os.symlink 會 WinError 1314。
        for tool in ('bash', 'grep', 'head', 'mkdir', 'rm', 'chmod', 'cat', 'sh'):
            real = shutil.which(tool).replace('\\', '/')
            write_executable(os.path.join(self.bin, tool), f'#!/bin/sh\nexec "{real}" "$@"\n')
        write_executable(os.path.join(self.bin, 'python3'), FAKE_PYTHON)
        self.log = os.path.join(self.tmp, 'python.log')
        self.cache = os.path.join(self.tmp, 'cache')
        self.venv_tool = os.path.join(self.cache, 'venv-18.1.8', 'bin', 'clang-format')

    def resolve(self, version='18.1.8'):
        return subprocess.run([shutil.which('bash'), RESOLVER], text=True, capture_output=True, timeout=10,
                              env={'PATH': self.bin, 'GBM_FORMAT_CACHE_DIR': self.cache,
                                   'HOME': self.tmp, 'FAKE_LOG': self.log, 'FAKE_VERSION': version})

    def python_calls(self):
        if not os.path.exists(self.log):
            return 0
        with open(self.log, encoding='utf-8') as f:
            return len(f.readlines())

    def test_builds_the_venv_when_there_is_none(self):
        result = self.resolve()
        self.assertEqual((result.returncode, os.path.normpath(result.stdout.strip())), (0, self.venv_tool), result.stderr)

    def test_a_healthy_venv_is_reused_without_rebuilding(self):
        write_executable(self.venv_tool, '#!/bin/sh\necho "clang-format version 18.1.8"\n')
        result = self.resolve()
        self.assertEqual((result.returncode, os.path.normpath(result.stdout.strip())), (0, self.venv_tool), result.stderr)
        self.assertEqual(self.python_calls(), 0)

    def test_a_venv_whose_interpreter_is_gone_is_rebuilt(self):
        # 真實案例：pyenv 移除 venv 當初用的 Python，bin/clang-format 還在但 shebang 指向不存在的檔案。
        write_executable(self.venv_tool, '#!/nonexistent/python3\n')
        write_executable(os.path.join(self.cache, 'venv-18.1.8', 'bin', 'pip'), '#!/nonexistent/python3\n')
        result = self.resolve()
        self.assertEqual((result.returncode, os.path.normpath(result.stdout.strip())), (0, self.venv_tool), result.stderr)
        self.assertEqual(self.python_calls(), 1)

    def test_a_rebuild_that_gives_the_wrong_version_is_an_error(self):
        result = self.resolve(version='23.1.5')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertIn('not major version 18', result.stderr)


if __name__ == '__main__':
    unittest.main()
