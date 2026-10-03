#!/usr/bin/env python3
"""check-instruction-budget.py 的單元測試。從 repo 根目錄跑：
python3 scripts/test_check_instruction_budget.py"""
import importlib.util, os, sys, tempfile, unittest

sys.dont_write_bytecode = True  # 不在 scripts/ 留下 __pycache__

_spec = importlib.util.spec_from_file_location(
    'budget', os.path.join(os.path.dirname(__file__), 'check-instruction-budget.py'))
budget = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(budget)


def write(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(text)


class StartupFiles(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def names(self):
        return sorted(os.path.relpath(p, self.root) for p, _ in budget.startup_files(self.root))

    def test_follows_imports_recursively(self):
        write(self.root, 'CLAUDE.md', '@docs/a.md\n')
        write(self.root, 'docs/a.md', '@b.md\n')
        write(self.root, 'docs/b.md', 'x')
        self.assertEqual(self.names(), ['CLAUDE.md', 'docs/a.md', 'docs/b.md'])

    def test_ignores_imports_in_code_spans_and_fences(self):
        write(self.root, 'CLAUDE.md', 'see `@docs/a.md`\n```\n@docs/b.md\n```\n')
        write(self.root, 'docs/a.md', 'x')
        write(self.root, 'docs/b.md', 'x')
        self.assertEqual(self.names(), ['CLAUDE.md'])

    def test_rule_without_paths_loads_at_start_and_scoped_one_does_not(self):
        write(self.root, 'CLAUDE.md', '')
        write(self.root, '.claude/rules/always.md', 'x')
        write(self.root, '.claude/rules/scoped.md', '---\npaths:\n  - "src/**"\n---\nx')
        self.assertEqual(self.names(), ['.claude/rules/always.md', 'CLAUDE.md'])

    def test_counts_characters_not_bytes(self):
        write(self.root, 'CLAUDE.md', '中文')
        self.assertEqual(budget.startup_files(self.root)[0][1], 2)


class Ceiling(unittest.TestCase):
    def test_reads_ceiling_with_thousands_separator(self):
        self.assertEqual(budget.read_ceiling('- **L0 ceiling**: 90,000 characters\n'), 90000)

    def test_missing_ceiling_is_none(self):
        self.assertIsNone(budget.read_ceiling('# nothing here\n'))


class Verdict(unittest.TestCase):
    def test_over_ceiling_fails(self):
        self.assertIn('over', budget.verdict(total=91000, ceiling=90000))

    def test_ceiling_far_above_total_fails_so_it_gets_lowered(self):
        self.assertIn('lower', budget.verdict(total=80000, ceiling=90000))

    def test_within_slack_passes(self):
        self.assertIsNone(budget.verdict(total=89000, ceiling=90000))


if __name__ == '__main__':
    unittest.main()
