#!/usr/bin/env python3
"""Focused regression tests for current-governance drift detection."""

from __future__ import annotations

import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check_governance_consistency.py")
spec = importlib.util.spec_from_file_location("governance_consistency", SCRIPT)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class GovernanceConsistencyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="governance-check-")
        self.root = Path(self.temp.name)
        sources = set(module.CURRENT_ENTRYPOINTS)
        sources.update(module.FUTURE_SAVE_PROMPTS)
        sources.update(module.HISTORICAL_BOUNDARY_FILES)
        sources.update(
            str(path.relative_to(module.ROOT))
            for path in (module.METHOD, module.TEMPLATE, module.CHECKER)
        )
        for relative in sources:
            source = module.ROOT / relative
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        # Relative links point into the original repository, not this narrow fixture.
        self.original_link_re = module.LINK_RE
        module.LINK_RE = module.re.compile(r"(?!)")

    def tearDown(self) -> None:
        module.LINK_RE = self.original_link_re
        self.temp.cleanup()

    def test_current_entries_are_consistent(self) -> None:
        self.assertEqual(module.check(self.root), [])

    def test_old_forced_upload_rule_is_detected(self) -> None:
        path = self.root / "ZL01_具体说明/09-上传流程.md"
        path.write_text(path.read_text(encoding="utf-8") + "\n热修上传固定为 **两次提交**\n", encoding="utf-8")
        self.assertTrue(any("旧强制规则" in issue for issue in module.check(self.root)))

    def test_template_v1_tracking_is_detected(self) -> None:
        path = self.root / "ZL00_项目总控/自动化/task-contract.template.json"
        content = path.read_text(encoding="utf-8").replace('"uploadTrackingRefs": []', '"uploadTrackingRefs": ["v1"]')
        path.write_text(content, encoding="utf-8")
        self.assertTrue(any("不得默认追踪 v1" in issue for issue in module.check(self.root)))

    def test_future_save_prompt_branch_reset_is_detected(self) -> None:
        path = self.root / module.FUTURE_SAVE_PROMPTS[0]
        path.write_text(path.read_text(encoding="utf-8") + "\ngit checkout -B v2.1\n", encoding="utf-8")
        self.assertTrue(any("旧危险步骤" in issue for issue in module.check(self.root)))

    def test_v0_future_prompt_branch_reset_is_detected(self) -> None:
        path = self.root / module.FUTURE_SAVE_PROMPTS[0]
        path.write_text(path.read_text(encoding="utf-8") + "\ngit checkout -B plan.3\n", encoding="utf-8")
        self.assertTrue(any("旧危险步骤" in issue for issue in module.check(self.root)))


if __name__ == "__main__":
    unittest.main()
