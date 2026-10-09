#!/usr/bin/env python3
"""Read-only checks for the repository's current governance entry points."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
METHOD = ROOT / "ZL00_项目总控/04-双AI协作与独立审计.md"
TEMPLATE = ROOT / "ZL00_项目总控/自动化/task-contract.template.json"


def source(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def main() -> int:
    problems: list[str] = []
    method = METHOD.read_text(encoding="utf-8")
    match = re.search(r"^方法版本：(MAIC-[0-9.]+)$", method, re.MULTILINE)
    contract = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    if not match or contract["methodVersion"] != match.group(1):
        problems.append("多 AI 方法正文与新契约模板版本不一致")
    if contract["repository"]["uploadTrackingRefs"]:
        problems.append("新契约模板预填了上传跟踪引用")
    if "v1.13.8" in contract["checker"]["fixedConclusions"]["phase7Pass"]:
        problems.append("新契约模板仍含旧阶段的固定通过句")
    if "除非用户已经明确调用该阶段" in method or "连续计划" not in method:
        problems.append("多 AI 方法仍把已批准的连续授权误写为每阶段重新点名")

    for relative in (
        "AGENTS.md",
        ".cursor/rules/project-governance.mdc",
        "ZL01_具体说明/08-开发流程.md",
    ):
        content = source(relative)
        if "05-单AI任务流程与持续改进.md" not in content and "ZL00/05" not in content:
            problems.append(f"{relative} 未路由单 AI 方法")
        if "04-双AI协作与独立审计.md" not in content and "ZL00/04" not in content:
            problems.append(f"{relative} 未路由多 AI 方法")

    for relative in (
        "AGENTS.md",
        ".cursor/rules/project-governance.mdc",
        ".cursor/rules/implementation-closeout.mdc",
        ".cursor/commands/closeout.md",
        "ZL00_项目总控/04-双AI协作与独立审计.md",
        "ZL00_项目总控/05-单AI任务流程与持续改进.md",
        "ZL01_具体说明/09-上传流程.md",
    ):
        content = source(relative)
        if "06-方法迭代闭环.md" not in content and "ZL00/06" not in content:
            problems.append(f"{relative} 未接入共用方法迭代闭环")
    iteration = source("ZL00_项目总控/06-方法迭代闭环.md")
    if "方法问题索引.json" not in iteration or "check_method_iteration.py" not in iteration:
        problems.append("方法迭代权威缺少跨任务索引或阶段记录检查入口")
    for relative in (
        "ZL00_项目总控/自动化/check_method_iteration.py",
        "ZL00_项目总控/自动化/method-stage-record.template.json",
        "ZL02_研发档案/方法问题索引.json",
    ):
        if not (ROOT / relative).is_file():
            problems.append(f"方法迭代入口目标不存在：{relative}")

    upload = source("ZL01_具体说明/09-上传流程.md")
    start = source("ZL01_具体说明/00-从这里开始.md")
    upload_log = source("ZL01_具体说明/13-上传记录.md")
    hotfix = source("ApiRelay/specs/playbooks/热修-save.md")
    branches = source("ApiRelay/specs/playbooks/BRANCHES.md")
    cursor_release = source(".cursor/rules/versioning-release.mdc")
    for name, content in (("09-上传流程", upload), ("热修-save", hotfix), ("versioning-release", cursor_release)):
        for obsolete in ("固定为 **两次提交**", "两次提交与记账", "只允许改并显式暂存这**四个**文件"):
            if obsolete in content:
                problems.append(f"{name} 残留过时的强制上传规则：{obsolete}")
    if "默认不移动" not in upload or "默认不移动" not in hotfix:
        problems.append("上传入口未明确大阶段引用默认不移动")
    if "check_method_iteration.py --record" not in upload:
        problems.append("上传入口未接入阶段方法检查")
    if "每次 save 还必须" in branches or "当前状态只看" not in branches:
        problems.append("分支历史台账仍强制每次改写，或未指向唯一当前状态")
    if "BRANCHES.md` 与 [`13" in start and "只在本次范围包含" not in start:
        problems.append("总入口仍强制每次上传改写分支台账和上传记录")
    if "一段对话做完或停在一半：" in start or "| 这段对话有进展 |" in upload:
        problems.append("入口仍强制每段对话改写可能不在授权范围内的 10")
    if "分支 tip / hash 权威" in upload or "冲突时信它" in upload or "当前 tip / 远端 SHA 只由实时 Git 核对" not in upload:
        problems.append("上传入口仍把历史分支台账当作实时 Git 权威")
    if "台账冲突：信" in upload_log or "实时 Git" not in upload_log:
        problems.append("上传记录仍把历史分支台账当作实时 Git 权威")

    if problems:
        for problem in problems:
            print("FAIL:", problem)
        return 1
    print("治理入口一致性检查通过：单/多 AI 路由、方法迭代入口、方法版本、授权上传边界")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as exc:
        print(f"FAIL: 治理输入无法核对：{exc}")
        raise SystemExit(2) from None
