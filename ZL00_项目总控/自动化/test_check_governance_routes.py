#!/usr/bin/env python3
"""Fixture tests for current governance routing and upload boundary checks."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

CHECKER = Path(__file__).with_name("check_governance_routes.py")
SPEC = importlib.util.spec_from_file_location("governance_routes", CHECKER)
assert SPEC and SPEC.loader
routes = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(routes)

METHOD = "ZL00_项目总控/04-双AI协作与独立审计.md"
TEMPLATE = "ZL00_项目总控/自动化/task-contract.template.json"


class GovernanceRouteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.files = {
            METHOD: "方法版本：MAIC-1.5.0\n06-方法迭代闭环.md 连续计划\n",
            "AGENTS.md": "04-双AI协作与独立审计.md 05-单AI任务流程与持续改进.md 06-方法迭代闭环.md\n",
            ".cursor/rules/project-governance.mdc": "ZL00/04 ZL00/05 ZL00/06\n",
            ".cursor/rules/implementation-closeout.mdc": "ZL00/06\n",
            ".cursor/commands/closeout.md": "ZL00/06\n",
            "ZL00_项目总控/05-单AI任务流程与持续改进.md": "06-方法迭代闭环.md\n",
            "ZL00_项目总控/06-方法迭代闭环.md": "方法问题索引.json check_method_iteration.py\n",
            "ZL00_项目总控/自动化/check_method_iteration.py": "# fixture\n",
            "ZL00_项目总控/自动化/method-stage-record.template.json": "{}\n",
            "ZL02_研发档案/方法问题索引.json": "{}\n",
            "ZL01_具体说明/08-开发流程.md": "ZL00/04 ZL00/05\n",
            "ZL01_具体说明/00-从这里开始.md": "BRANCHES.md` 与 [`13 只在本次范围包含\n",
            "ZL01_具体说明/09-上传流程.md": "ZL00/06 默认不移动 check_method_iteration.py --record 当前 tip / 远端 SHA 只由实时 Git 核对\n",
            "ZL01_具体说明/13-上传记录.md": "实时 Git 核对；BRANCHES 是历史分支台账\n",
            "ApiRelay/specs/playbooks/热修-save.md": "默认不移动\n",
            "ApiRelay/specs/playbooks/BRANCHES.md": "当前状态只看 ZL01/14\n",
            ".cursor/rules/versioning-release.mdc": "上传前核对\n",
        }
        self.contract = {
            "methodVersion": "MAIC-1.5.0",
            "repository": {"uploadTrackingRefs": []},
            "checker": {"fixedConclusions": {"phase7Pass": "验收通过"}},
        }

    def run_checker(self) -> tuple[int, str]:
        for relative, content in self.files.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        template = self.root / TEMPLATE
        template.parent.mkdir(parents=True, exist_ok=True)
        template.write_text(json.dumps(self.contract), encoding="utf-8")
        output = io.StringIO()
        with patch.object(routes, "ROOT", self.root), patch.object(routes, "METHOD", self.root / METHOD), \
             patch.object(routes, "TEMPLATE", template), contextlib.redirect_stdout(output):
            result = routes.main()
        return result, output.getvalue()

    def test_complete_routes_pass(self) -> None:
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)
        self.assertIn("方法迭代入口", output)

    def test_missing_stage_trigger_fails(self) -> None:
        self.files[".cursor/commands/closeout.md"] = "旧收尾命令\n"
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("未接入共用方法迭代闭环", output)

    def test_upload_must_call_iteration_checker(self) -> None:
        self.files["ZL01_具体说明/09-上传流程.md"] = "ZL00/06 默认不移动\n"
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("上传入口未接入阶段方法检查", output)

    def test_method_and_template_version_must_match(self) -> None:
        self.contract["methodVersion"] = "MAIC-1.4.0"
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("版本不一致", output)

    def test_missing_iteration_target_fails(self) -> None:
        self.files.pop("ZL02_研发档案/方法问题索引.json")
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("方法迭代入口目标不存在", output)

    def test_old_per_stage_reapproval_clause_fails(self) -> None:
        self.files[METHOD] += "除非用户已经明确调用该阶段\n"
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("每阶段重新点名", output)

    def test_old_branch_ledger_mandate_fails(self) -> None:
        self.files["ApiRelay/specs/playbooks/BRANCHES.md"] = "每次 save 还必须更新本文件\n"
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("分支历史台账仍强制", output)

    def test_old_upload_navigation_mandate_fails(self) -> None:
        self.files["ZL01_具体说明/00-从这里开始.md"] = "BRANCHES.md` 与 [`13 是第三步的一部分\n"
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("总入口仍强制", output)

    def test_old_branch_tip_authority_fails(self) -> None:
        self.files["ZL01_具体说明/09-上传流程.md"] += "分支 tip / hash 权威：BRANCHES.md。冲突时信它。\n"
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("历史分支台账当作实时 Git 权威", output)

    def test_old_dialog_ledger_mandate_fails(self) -> None:
        self.files["ZL01_具体说明/00-从这里开始.md"] += "一段对话做完或停在一半：更新 10\n"
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("强制每段对话改写", output)

    def test_old_upload_log_branch_authority_fails(self) -> None:
        self.files["ZL01_具体说明/13-上传记录.md"] = "台账冲突：信 BRANCHES.md\n"
        code, output = self.run_checker()
        self.assertEqual(code, 1)
        self.assertIn("上传记录仍把历史分支台账", output)


if __name__ == "__main__":
    unittest.main()
