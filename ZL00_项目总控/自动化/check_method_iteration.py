#!/usr/bin/env python3
"""Read-only validation of a task's method-improvement stage record."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INDEX = Path("ZL02_研发档案/方法问题索引.json")
ISSUE_ID = re.compile(r"MI-[0-9]{8}-[0-9]{2}$")
CATEGORIES = {"method", "product", "external", "execution"}


class CheckError(Exception):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code


def nonempty(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise CheckError(2, f"{label} 必须是非空文字")
    return value.strip()


def unique_strings(value: object, label: str) -> list[str]:
    if not isinstance(value, list):
        raise CheckError(2, f"{label} 必须是数组")
    items = [nonempty(item, label) for item in value]
    if len(items) != len(set(items)):
        raise CheckError(2, f"{label} 含重复项")
    return items


def repo_path(root: Path, relative: str) -> Path:
    path = Path(nonempty(relative, "路径"))
    if path.is_absolute() or ".." in path.parts or "." in path.parts:
        raise CheckError(2, f"路径必须是仓库内相对路径：{relative}")
    resolved_root = root.resolve()
    resolved = (resolved_root / path).resolve()
    if not resolved.is_relative_to(resolved_root):
        raise CheckError(2, f"路径越出仓库：{relative}")
    return resolved


def read_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise CheckError(2, f"无法读取 JSON：{path}：{exc}") from None
    if not isinstance(data, dict) or type(data.get("schemaVersion")) is not int or data["schemaVersion"] != 1:
        raise CheckError(2, f"{path} 的 schemaVersion 必须为 1")
    return data


def validate_index(root: Path, record: str, method_issues: dict[str, str]) -> None:
    data = read_json(repo_path(root, str(INDEX)))
    entries = data.get("entries")
    if not isinstance(entries, list):
        raise CheckError(2, "方法问题索引 entries 必须是数组")
    by_id: dict[str, dict] = {}
    fingerprints: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise CheckError(2, "方法问题索引条目必须是对象")
        issue_id = nonempty(entry.get("id"), "索引 ID")
        fingerprint = nonempty(entry.get("fingerprint"), "索引指纹")
        records = unique_strings(entry.get("records"), f"索引 {issue_id} records")
        if not ISSUE_ID.fullmatch(issue_id) or not records:
            raise CheckError(2, f"索引 {issue_id} 的 ID 或 records 无效")
        if issue_id in by_id or fingerprint in fingerprints:
            raise CheckError(2, f"索引重复 ID 或指纹：{issue_id}")
        for item in records:
            repo_path(root, item)
        by_id[issue_id] = entry
        fingerprints.add(fingerprint)
    for issue_id, fingerprint in method_issues.items():
        entry = by_id.get(issue_id)
        if not entry or entry["fingerprint"] != fingerprint or record not in entry["records"]:
            raise CheckError(3, f"方法问题 {issue_id} 未在索引中指向本记录或指纹不一致")
        for item in entry["records"]:
            if not repo_path(root, item).is_file():
                raise CheckError(3, f"索引 {issue_id} 指向的记录不存在：{item}")


def validate(root: Path, record: str, required_stages: list[str], final: bool) -> tuple[int, int]:
    record_parts = Path(record).parts
    if (Path(record).name != "方法阶段记录.json" or not (
        (record_parts[:1] == ("ZL02_研发档案",) and len(record_parts) >= 3)
        or (record_parts[:2] == ("ApiRelay", "specs") and len(record_parts) >= 4)
    )):
        raise CheckError(2, "阶段记录须位于 ZL02 或 ApiRelay/specs 工作包内，文件名为 方法阶段记录.json")
    record_path = repo_path(root, record)
    data = read_json(record_path)
    nonempty(data.get("taskId"), "taskId")
    if data.get("riskLevel") not in {"standard", "high"}:
        raise CheckError(2, "riskLevel 必须为 standard 或 high；轻量任务无需建记录")
    stages = unique_strings(data.get("expectedStages"), "expectedStages")
    if not stages:
        raise CheckError(2, "expectedStages 不能为空")
    checks = data.get("checks")
    issues = data.get("issues")
    if not isinstance(checks, list) or not isinstance(issues, list):
        raise CheckError(2, "checks 和 issues 必须是数组")

    by_issue: dict[str, dict] = {}
    method_issues: dict[str, str] = {}
    for item in issues:
        if not isinstance(item, dict):
            raise CheckError(2, "问题条目必须是对象")
        issue_id = nonempty(item.get("id"), "问题 ID")
        if not ISSUE_ID.fullmatch(issue_id) or issue_id in by_issue:
            raise CheckError(2, f"问题 ID 无效或重复：{issue_id}")
        category = item.get("category")
        if category not in CATEGORIES:
            raise CheckError(2, f"{issue_id} 分类无效")
        if item.get("impact") not in {"blocking", "nonblocking"}:
            raise CheckError(2, f"{issue_id} 影响级别无效")
        if item.get("status") not in {"open", "deferred", "resolved"}:
            raise CheckError(2, f"{issue_id} 状态无效")
        nonempty(item.get("fingerprint"), f"{issue_id} 指纹")
        nonempty(item.get("evidence"), f"{issue_id} 证据")
        nonempty(item.get("action"), f"{issue_id} 已做或下一步动作")
        if category == "method":
            index_status = item.get("indexStatus")
            if index_status not in {"linked", "pending_scope"}:
                raise CheckError(2, f"{issue_id} indexStatus 必须是 linked 或 pending_scope")
            if index_status == "linked":
                method_issues[issue_id] = item["fingerprint"]
            else:
                nonempty(item.get("indexReason"), f"{issue_id} 未索引原因")
                if item["impact"] != "nonblocking" or item["status"] != "deferred":
                    raise CheckError(3, f"{issue_id} 仅非阻塞且延期的问题可待补索引")
            nonempty(item.get("regressionCase"), f"{issue_id} 回归案例")
            if item.get("regressionResult") not in {"pass", "pending"}:
                raise CheckError(2, f"{issue_id} 回归结果必须是 pass 或 pending")
            if item["status"] == "resolved" and item["regressionResult"] != "pass":
                raise CheckError(3, f"{issue_id} 标为已解决但回归尚未通过")
        by_issue[issue_id] = item

    seen: set[str] = set()
    referenced: set[str] = set()
    for check in checks:
        if not isinstance(check, dict):
            raise CheckError(2, "阶段检查条目必须是对象")
        stage = nonempty(check.get("stage"), "阶段名")
        if stage not in stages or stage in seen:
            raise CheckError(2, f"阶段未列入计划或重复：{stage}")
        if stage != stages[len(seen)]:
            raise CheckError(3, f"阶段检查必须按计划顺序记录；下一项应为 {stages[len(seen)]}，不能先填 {stage}")
        seen.add(stage)
        nonempty(check.get("evidence"), f"{stage} 检查证据")
        verdict = check.get("verdict")
        ids = unique_strings(check.get("issueIds"), f"{stage} issueIds")
        if verdict not in {"clear", "issue"} or (verdict == "clear") != (not ids):
            raise CheckError(2, f"{stage} 结论与问题 ID 不一致")
        for issue_id in ids:
            if issue_id not in by_issue:
                raise CheckError(2, f"{stage} 引用了不存在的问题：{issue_id}")
            referenced.add(issue_id)
    if set(by_issue) != referenced:
        raise CheckError(2, "存在没有被任何阶段引用的问题")

    for stage in required_stages:
        if stage not in stages:
            raise CheckError(2, f"要求核对的阶段不在计划中：{stage}")
        if stage not in seen:
            raise CheckError(3, f"阶段尚无方法检查记录：{stage}")
    if final:
        missing = [stage for stage in stages if stage not in seen]
        if missing:
            raise CheckError(3, f"计划阶段尚未逐项检查：{', '.join(missing)}")
        blockers = [issue_id for issue_id, item in by_issue.items()
                    if item["category"] == "method" and item["impact"] == "blocking"
                    and item["status"] != "resolved"]
        if blockers:
            raise CheckError(3, f"仍有未解决的阻塞方法问题：{', '.join(blockers)}")
    validate_index(root, record, method_issues)
    pending = sum(item["status"] != "resolved" for item in by_issue.values())
    return len(seen), pending


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record", required=True, help="仓库内工作包的相对 JSON 路径")
    parser.add_argument("--require-stage", action="append", default=[], help="本次必须已记录的阶段，可重复")
    parser.add_argument("--final", action="store_true", help="核对全部计划阶段和阻塞方法问题")
    args = parser.parse_args()
    try:
        count, pending = validate(ROOT, args.record, args.require_stage, args.final)
    except CheckError as exc:
        print(f"FAIL: {exc}")
        return exc.code
    print(f"阶段方法记录检查通过：已记录 {count} 阶段；仍有 {pending} 项未解决或待验证问题（须看原记录，非自动放行产品验收）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
