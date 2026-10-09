#!/usr/bin/env python3
"""Stdlib tests for the read-only method-iteration checker."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

CHECKER = Path(__file__).with_name("check_method_iteration.py")
SPEC = importlib.util.spec_from_file_location("method_checker", CHECKER)
assert SPEC and SPEC.loader
method_checker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(method_checker)

RECORD = "ZL02_研发档案/task/方法阶段记录.json"
INDEX = "ZL02_研发档案/方法问题索引.json"
ISSUE_ID = "MI-20261009-01"


def fixture() -> tuple[dict, dict]:
    record = {
        "schemaVersion": 1,
        "taskId": "fixture",
        "riskLevel": "standard",
        "expectedStages": ["摸底", "整改", "复验"],
        "checks": [
            {"stage": "摸底", "verdict": "issue", "evidence": "发现旧入口误导", "issueIds": [ISSUE_ID]},
            {"stage": "整改", "verdict": "clear", "evidence": "入口已对齐", "issueIds": []},
            {"stage": "复验", "verdict": "clear", "evidence": "旧案例重跑通过", "issueIds": []},
        ],
        "issues": [{
            "id": ISSUE_ID,
            "category": "method",
            "indexStatus": "linked",
            "fingerprint": "route|single-ai|wrong-trigger|nine-stage",
            "impact": "blocking",
            "status": "resolved",
            "evidence": "单 AI 被旧入口导向九阶段",
            "action": "修正入口并加回归测试",
            "regressionCase": "单 AI 跨目录任务仍走单 AI 流程",
            "regressionResult": "pass",
        }],
    }
    index = {"schemaVersion": 1, "entries": [{
        "id": ISSUE_ID,
        "fingerprint": "route|single-ai|wrong-trigger|nine-stage",
        "records": [RECORD],
    }]}
    return record, index


class MethodIterationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.record, self.index = fixture()

    def write(self) -> None:
        for relative, data in ((RECORD, self.record), (INDEX, self.index)):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

    def check(self, *, final: bool = False, required: list[str] | None = None) -> tuple[int, int]:
        self.write()
        return method_checker.validate(self.root, RECORD, required or [], final)

    def assert_error(self, code: int, phrase: str, *, final: bool = False,
                     required: list[str] | None = None) -> None:
        with self.assertRaises(method_checker.CheckError) as caught:
            self.check(final=final, required=required)
        self.assertEqual(caught.exception.code, code)
        self.assertIn(phrase, str(caught.exception))

    def test_complete_record_passes(self) -> None:
        self.assertEqual(self.check(final=True), (3, 0))

    def test_missing_stage_fails_final_but_partial_check_passes(self) -> None:
        self.record["checks"].pop()
        self.assertEqual(self.check(required=["整改"]), (2, 0))
        self.assert_error(3, "复验", final=True)

    def test_requested_stage_must_exist(self) -> None:
        self.record["checks"].pop()
        self.assert_error(3, "复验", required=["复验"])

    def test_stage_cannot_skip_previous_stage(self) -> None:
        self.record["checks"].pop(1)
        self.assert_error(3, "下一项应为 整改")

    def test_clear_cannot_hide_issue(self) -> None:
        self.record["checks"][0]["verdict"] = "clear"
        self.assert_error(2, "结论与问题 ID")

    def test_resolved_method_issue_needs_passed_regression(self) -> None:
        self.record["issues"][0]["regressionResult"] = "pending"
        self.assert_error(3, "回归尚未通过", final=True)

    def test_unresolved_method_blocker_prevents_final(self) -> None:
        self.record["issues"][0]["status"] = "open"
        self.record["issues"][0]["regressionResult"] = "pending"
        self.assert_error(3, "阻塞方法问题", final=True)

    def test_external_pending_is_visible_but_not_method_blocker(self) -> None:
        self.record["issues"][0]["category"] = "external"
        self.record["issues"][0]["status"] = "deferred"
        self.record["issues"][0]["regressionResult"] = "pending"
        self.assertEqual(self.check(final=True), (3, 1))

    def test_method_issue_requires_index_pointer(self) -> None:
        self.index["entries"][0]["records"] = ["ZL02_研发档案/other.json"]
        other = self.root / "ZL02_研发档案/other.json"
        other.parent.mkdir(parents=True, exist_ok=True)
        other.write_text("{}", encoding="utf-8")
        self.assert_error(3, "未在索引中指向本记录")

    def test_nonblocking_issue_can_wait_for_index_scope(self) -> None:
        item = self.record["issues"][0]
        item.update({"indexStatus": "pending_scope", "indexReason": "封闭文件清单不含索引",
                     "impact": "nonblocking", "status": "deferred", "regressionResult": "pending"})
        self.index["entries"] = []
        self.assertEqual(self.check(final=True), (3, 1))

    def test_blocking_issue_cannot_skip_index_or_closure(self) -> None:
        item = self.record["issues"][0]
        item.update({"indexStatus": "pending_scope", "indexReason": "封闭文件清单不含索引",
                     "status": "deferred", "regressionResult": "pending"})
        self.index["entries"] = []
        self.assert_error(3, "仅非阻塞且延期")

    def test_index_duplicate_fingerprint_fails(self) -> None:
        self.index["entries"].append({
            "id": "MI-20261009-02",
            "fingerprint": self.index["entries"][0]["fingerprint"],
            "records": [RECORD],
        })
        self.assert_error(2, "重复 ID 或指纹")

    def test_index_target_must_exist(self) -> None:
        self.index["entries"][0]["records"].append("ZL02_研发档案/missing.json")
        self.assert_error(3, "记录不存在")

    def test_unrelated_missing_index_target_does_not_block_task(self) -> None:
        self.index["entries"].append({
            "id": "MI-20261009-02",
            "fingerprint": "other|trigger|gate|effect",
            "records": ["ZL02_研发档案/other/missing.json"],
        })
        self.assertEqual(self.check(final=True), (3, 0))

    def test_record_cannot_escape_repository(self) -> None:
        with self.assertRaises(method_checker.CheckError) as caught:
            method_checker.validate(self.root, "../outside.json", [], True)
        self.assertEqual(caught.exception.code, 2)

    def test_record_must_be_in_task_work_package(self) -> None:
        with self.assertRaises(method_checker.CheckError) as caught:
            method_checker.validate(self.root, "ZL00_项目总控/方法阶段记录.json", [], True)
        self.assertEqual(caught.exception.code, 2)
        with self.assertRaises(method_checker.CheckError) as caught:
            method_checker.validate(self.root, "ZL02_研发档案/方法阶段记录.json", [], True)
        self.assertEqual(caught.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
