#!/usr/bin/env python3
"""Read-only checks for current governance entrypoints; historical archives are excluded."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
METHOD = ROOT / "ZL00_项目总控/04-双AI协作与独立审计.md"
TEMPLATE = ROOT / "ZL00_项目总控/自动化/task-contract.template.json"
CHECKER = ROOT / "ZL00_项目总控/自动化/check_multi_ai_workflow.py"

CURRENT_ENTRYPOINTS = (
    "AGENTS.md",
    "ZL01_具体说明/00-从这里开始.md",
    "ZL00_项目总控/00-项目治理总纲.md",
    "ZL00_项目总控/01-权威职责与边界.md",
    "ZL00_项目总控/03-关账与发布闸门.md",
    "ZL00_项目总控/04-双AI协作与独立审计.md",
    "ZL01_具体说明/07-计划流程.md",
    "ZL01_具体说明/08-开发流程.md",
    "ZL01_具体说明/09-上传流程.md",
    "ZL01_具体说明/13-上传记录.md",
    "ZL01_具体说明/14-项目当前状态.md",
    ".cursor/rules/versioning-release.mdc",
    "ApiRelay/specs/playbooks/README.md",
    "ApiRelay/specs/playbooks/BRANCHES.md",
    "ApiRelay/specs/playbooks/热修-save.md",
    "ApiRelay/specs/playbooks/v0-planning/00-README.md",
    "ApiRelay/specs/playbooks/v0-planning/15-phase-push.md",
    "ApiRelay/specs/playbooks/v1-key-vault/00-README.md",
    "ApiRelay/specs/playbooks/v1-key-vault/20-push.md",
    "ApiRelay/specs/playbooks/v1-key-vault/30-create-next-branch.md",
    "ApiRelay/specs/playbooks/v1-key-vault/12-release-T062.md",
    "ApiRelay/specs/playbooks/v1-key-vault/40-checkout-next-branch.md",
    "ApiRelay/specs/playbooks/v2-usage-insights/00-README.md",
    "ApiRelay/specs/playbooks/v2-usage-insights/20-push.md",
    "ApiRelay/specs/playbooks/v2-usage-insights/30-create-next-branch.md",
    "ApiRelay/specs/playbooks/v2-usage-insights/40-checkout-next-branch.md",
    "ApiRelay/specs/playbooks/v3-relay-service/00-README.md",
    "ApiRelay/specs/playbooks/v3-relay-service/20-push.md",
    "ApiRelay/specs/playbooks/v3-relay-service/30-create-next-branch.md",
    "ApiRelay/specs/playbooks/v3-relay-service/40-checkout-next-branch.md",
    "ApiRelay/specs/playbooks/重要说明/索引.md",
    "ApiRelay/specs/playbooks/重要说明/分支与版本.md",
    "ZL02_研发档案/第一阶段-密钥库/00-阶段总览.md",
    ".cursor/commands/closeout.md",
)

FUTURE_SAVE_PROMPTS = ("ApiRelay/specs/playbooks/v0-planning/phases/P03-save.md",) + tuple(
    f"ApiRelay/specs/playbooks/{stage}/phases/P{phase:02d}-save.md"
    for stage, count in (("v2-usage-insights", 8), ("v3-relay-service", 7))
    for phase in range(1, count + 1)
)

HISTORICAL_BOUNDARY_FILES = {
    "ZL01_具体说明/10-AI对话相关记录.md": "历史待办快照，不是现行任务清单或执行授权",
    "ApiRelay/specs/playbooks/v1-key-vault/12-release-T062.md": "历史发布档案，禁止再次按本页执行",
    "ApiRelay/specs/playbooks/v1-key-vault/40-checkout-next-branch.md": "历史导航，不可直接执行旧切换命令",
}

FORBIDDEN_CURRENT_PHRASES = (
    "热修上传固定为 **两次提交**",
    "两次提交与记账只执行",
    "提交 B 才写上传记录",
    "每个小阶段写完 → 必须",
    "每一个小阶段写完，都必须",
    "只建立阶段1所需入口",
    "每次 save 还必须",
    "**当前：T062 已执行**",
)
LINK_RE = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def check(root: Path = ROOT) -> list[str]:
    issues: list[str] = []
    try:
        method = (root / METHOD.relative_to(ROOT)).read_text(encoding="utf-8")
        template = json.loads((root / TEMPLATE.relative_to(ROOT)).read_text(encoding="utf-8"))
        checker = (root / CHECKER.relative_to(ROOT)).read_text(encoding="utf-8")
    except (OSError, ValueError) as exc:
        return [f"无法读取治理文件: {exc}"]

    matches = re.findall(r"^方法版本：(MAIC-\d+(?:\.\d+)+)$", method, re.MULTILINE)
    if len(matches) != 1:
        issues.append("ZL00/04 必须恰有一个机读方法版本")
    else:
        version = matches[0]
        if template.get("methodVersion") != version:
            issues.append(f"契约模板版本 {template.get('methodVersion')} 与方法 {version} 不一致")
        if f'CURRENT_METHOD_VERSION = "{version}"' not in checker:
            issues.append("只读检查器的当前方法版本与 ZL00/04 不一致")

    repository = template.get("repository", {})
    if repository.get("worktreeIsolation") != "scoped":
        issues.append("新契约必须默认 scoped 工作树隔离")
    if repository.get("uploadTrackingRefs") != []:
        issues.append("新契约不得默认追踪 v1 或其他未获授权的上传引用")
    if "v1.13.8" in template.get("checker", {}).get("fixedConclusions", {}).get("phase7Pass", ""):
        issues.append("契约模板的验收结论不得固定旧产品分支")

    for relative in CURRENT_ENTRYPOINTS:
        path = root / relative
        try:
            content = path.read_text(encoding="utf-8")
        except OSError:
            issues.append(f"现行入口缺失: {relative}")
            continue
        for phrase in FORBIDDEN_CURRENT_PHRASES:
            if phrase in content:
                issues.append(f"现行入口含旧强制规则: {relative}: {phrase}")
        if path.suffix == ".md":
            for target in LINK_RE.findall(content):
                target = target.strip().strip("<>").split("#", 1)[0]
                if not target or "://" in target or target.startswith("mailto:"):
                    continue
                if not (path.parent / target).exists():
                    issues.append(f"现行入口链接目标不存在: {relative} -> {target}")
    for relative in FUTURE_SAVE_PROMPTS:
        try:
            content = (root / relative).read_text(encoding="utf-8")
        except OSError:
            issues.append(f"未来阶段提示词缺失: {relative}")
            continue
        if "不使用 `checkout -B` 重置分支" not in content or "本次授权已包含本地提交才 commit" not in content:
            issues.append(f"未来阶段提示词缺安全授权闸门: {relative}")
        for phrase in ("git checkout -B", "**等我同意后再 commit**", "push 后的 hash"):
            if phrase in content:
                issues.append(f"未来阶段提示词含旧危险步骤: {relative}: {phrase}")
    for relative, marker in HISTORICAL_BOUNDARY_FILES.items():
        try:
            content = (root / relative).read_text(encoding="utf-8")
        except OSError:
            issues.append(f"历史边界文件缺失: {relative}")
            continue
        if marker not in content:
            issues.append(f"历史边界标记缺失: {relative}")
    return issues


def main() -> int:
    issues = check()
    if issues:
        for issue in issues:
            print("FAIL:", issue)
        return 1
    print("PASS: current governance entrypoints and tool defaults are consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
