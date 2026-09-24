#!/usr/bin/env python3
"""Read-only multi-AI workflow status checker. Standard library only."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any

EXIT_OK = 0
EXIT_INPUT = 2
EXIT_CHAIN = 3
EXIT_SCOPE = 4

READ_ONLY_GIT = {
    "status",
    "rev-parse",
    "show-ref",
    "diff",
    "log",
    "ls-files",
    "worktree",
    "symbolic-ref",
    "cat-file",
    "name-rev",
}

METHOD_VERSION_RE = re.compile(r"方法版本：\s*(MAIC-[0-9.]+)")
BRANCH_RE = re.compile(r"分支：\s*`?([A-Za-z0-9._/-]+)`?")
HEAD_RE = re.compile(r"HEAD：\s*`?([0-9a-f]{7,40})`?", re.I)
REQUIRED_CONTRACT = (
    "schemaVersion",
    "workPackageId",
    "methodVersion",
    "sourceKind",
    "riskLevel",
    "objective",
    "repository",
    "roles",
    "paths",
    "checker",
)
REQUIRED_REPOSITORY = (
    "implementationWorktree",
    "baselineBranch",
    "baselineHead",
    "protectedRefs",
)
REQUIRED_PATHS = (
    "allowedModify",
    "allowedAdd",
    "forbiddenPrefixes",
    "knownUntracked",
)
REQUIRED_CHECKER = (
    "methodFile",
    "promptDirectory",
    "genericPrompt",
    "promptsByPhase",
    "fixedConclusions",
    "rnn",
    "legacyArtifactMethodVersions",
    "documentInvariants",
)
VERSION_KEY_RE = re.compile(r"^MAIC-[0-9]+(?:\.[0-9]+)*$")
FIXED_PACKAGE_FILES = (
    "00-总流程操作台.md",
    "00A-压力测试样本.md",
    "00B-自动化架构与验收口径.md",
    "00C-任务契约.json",
    "提示词/00-提示词索引与使用说明.md",
)
RNN_REL_RE = re.compile(
    r"^整改轮次/R[0-9]{2}/(?:01-Codex整改定稿|02-Grok整改报告|03-Codex复验报告)\.md$"
)
CHECKER_GRANTS_EXECUTION_AUTHORITY = False
AUTHORIZATION_NOTE = "检查器只判断状态和路由，不授予下一阶段执行权限"


class CheckerError(Exception):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def git(repo: Path, *args: str) -> str:
    if not args or args[0] not in READ_ONLY_GIT:
        raise CheckerError(EXIT_SCOPE, f"拒绝非只读 Git 命令: {args[:1]}")
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise CheckerError(
            EXIT_INPUT,
            completed.stderr.strip() or f"git {' '.join(args)} 失败",
        )
    return completed.stdout


def try_git(repo: Path, *args: str) -> str | None:
    if not args or args[0] not in READ_ONLY_GIT:
        raise CheckerError(EXIT_SCOPE, f"拒绝非只读 Git 命令: {args[:1]}")
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise CheckerError(EXIT_INPUT, f"缺少契约: {path}") from exc
    except json.JSONDecodeError as exc:
        raise CheckerError(EXIT_INPUT, f"契约不是合法 JSON: {path}") from exc
    if not isinstance(data, dict):
        raise CheckerError(EXIT_INPUT, "契约根必须是对象")
    missing = [key for key in REQUIRED_CONTRACT if key not in data]
    if missing:
        raise CheckerError(EXIT_INPUT, "契约缺字段: " + ", ".join(missing))
    validate_nested_contract(data)
    return data


def require_mapping(value: Any, name: str, keys: tuple[str, ...]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise CheckerError(EXIT_INPUT, f"契约 {name} 必须是对象")
    missing = [key for key in keys if key not in value]
    if missing:
        raise CheckerError(EXIT_INPUT, f"契约 {name} 缺字段: " + ", ".join(missing))
    return value


def validate_nested_contract(data: dict[str, Any]) -> None:
    repository = require_mapping(data.get("repository"), "repository", REQUIRED_REPOSITORY)
    if not isinstance(repository.get("protectedRefs"), dict) or not repository["protectedRefs"]:
        raise CheckerError(EXIT_INPUT, "契约 repository.protectedRefs 必须是非空对象")
    validate_readonly_snapshots(repository)
    validate_frozen_external_files(repository)
    roles = require_mapping(data.get("roles"), "roles", ("phaseOwners",))
    if not isinstance(roles.get("phaseOwners"), dict) or not roles["phaseOwners"]:
        raise CheckerError(EXIT_INPUT, "契约 roles.phaseOwners 必须是非空对象")
    paths = require_mapping(data.get("paths"), "paths", REQUIRED_PATHS)
    for key in REQUIRED_PATHS:
        if not isinstance(paths.get(key), list):
            raise CheckerError(EXIT_INPUT, f"契约 paths.{key} 必须是数组")
    checker = require_mapping(data.get("checker"), "checker", REQUIRED_CHECKER)
    for key in ("promptsByPhase", "fixedConclusions", "rnn"):
        if not isinstance(checker.get(key), dict):
            raise CheckerError(EXIT_INPUT, f"契约 checker.{key} 必须是对象")
    current_method = data.get("methodVersion")
    if not isinstance(current_method, str) or not VERSION_KEY_RE.match(current_method):
        raise CheckerError(EXIT_INPUT, "契约 methodVersion 必须是 MAIC- 版本字符串")
    validate_legacy_artifact_method_versions(
        checker.get("legacyArtifactMethodVersions"),
        current_method,
    )
    validate_document_invariants(checker.get("documentInvariants"))


def validate_package_rel_path(path: Any, field: str) -> str:
    if not isinstance(path, str) or not path:
        raise CheckerError(EXIT_INPUT, f"{field} 不得使用空路径")
    if path.strip() != path:
        raise CheckerError(EXIT_INPUT, f"{field} 不得含首尾空白")
    if path.startswith("/") or path.startswith("\\") or re.match(r"^[A-Za-z]:[/\\]", path):
        raise CheckerError(EXIT_INPUT, f"{field} 不得使用绝对路径")
    if "\\" in path:
        raise CheckerError(EXIT_INPUT, f"{field} 不得使用反斜杠")
    if path.startswith("./"):
        raise CheckerError(EXIT_INPUT, f"{field} 不得使用 ./ 前缀")
    parts = path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise CheckerError(EXIT_INPUT, f"{field} 路径无效")
    return path


def validate_legacy_artifact_method_versions(value: Any, current_method: str) -> dict[str, set[str]]:
    if not isinstance(value, dict):
        raise CheckerError(EXIT_INPUT, "契约 checker.legacyArtifactMethodVersions 必须是对象")
    mapping: dict[str, set[str]] = {}
    seen: set[str] = set()
    for key, paths in value.items():
        if not isinstance(key, str) or not VERSION_KEY_RE.match(key):
            raise CheckerError(EXIT_INPUT, "契约 checker.legacyArtifactMethodVersions 的键必须是 MAIC- 版本字符串")
        if key == current_method:
            raise CheckerError(EXIT_INPUT, "契约 checker.legacyArtifactMethodVersions 不得回列当前版本")
        if not isinstance(paths, list):
            raise CheckerError(EXIT_INPUT, f"契约 checker.legacyArtifactMethodVersions.{key} 必须是数组")
        normalized: set[str] = set()
        for item in paths:
            rel = validate_package_rel_path(
                item,
                f"契约 checker.legacyArtifactMethodVersions.{key}",
            )
            if rel in seen:
                raise CheckerError(EXIT_INPUT, f"契约 checker.legacyArtifactMethodVersions 存在重复路径: {rel}")
            seen.add(rel)
            normalized.add(rel)
        mapping[key] = normalized
    return mapping


DOCUMENT_INVARIANT_KEYS = ("path", "uniqueExactLines", "forbiddenSubstrings")


def validate_literal_string_list(value: Any, field: str, seen_rules: set[str]) -> list[str]:
    if not isinstance(value, list):
        raise CheckerError(EXIT_INPUT, f"{field} 必须是数组")
    items: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, str):
            raise CheckerError(EXIT_INPUT, f"{field}[{index}] 必须是字符串")
        if item == "":
            raise CheckerError(EXIT_INPUT, f"{field} 不得使用空规则")
        if item in seen_rules:
            raise CheckerError(EXIT_INPUT, f"{field} 存在重复规则: {item}")
        seen_rules.add(item)
        items.append(item)
    return items


def validate_document_invariants(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise CheckerError(EXIT_INPUT, "契约 checker.documentInvariants 必须是数组")
    rules: list[dict[str, Any]] = []
    seen_paths: set[str] = set()
    for index, item in enumerate(value):
        field = f"契约 checker.documentInvariants[{index}]"
        if not isinstance(item, dict):
            raise CheckerError(EXIT_INPUT, f"{field} 必须是对象")
        missing = [key for key in DOCUMENT_INVARIANT_KEYS if key not in item]
        if missing:
            raise CheckerError(EXIT_INPUT, f"{field} 缺字段: " + ", ".join(missing))
        rel = validate_package_rel_path(item.get("path"), f"{field}.path")
        if rel in seen_paths:
            raise CheckerError(EXIT_INPUT, f"{field}.path 重复路径: {rel}")
        seen_paths.add(rel)
        seen_rules: set[str] = set()
        unique_lines = validate_literal_string_list(
            item.get("uniqueExactLines"),
            f"{field}.uniqueExactLines",
            seen_rules,
        )
        forbidden = validate_literal_string_list(
            item.get("forbiddenSubstrings"),
            f"{field}.forbiddenSubstrings",
            seen_rules,
        )
        rules.append(
            {
                "path": rel,
                "uniqueExactLines": unique_lines,
                "forbiddenSubstrings": forbidden,
            }
        )
    return rules


def enforce_document_invariants(package: Path, rules: list[dict[str, Any]]) -> None:
    for rule in rules:
        rel = rule["path"]
        target = package / rel
        if not target.is_file():
            raise CheckerError(EXIT_CHAIN, f"文档不变量失败: {rel} 文件不存在")
        try:
            text = target.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            raise CheckerError(EXIT_CHAIN, f"文档不变量失败: {rel} 无法按 UTF-8 读取") from exc
        except OSError as exc:
            raise CheckerError(EXIT_CHAIN, f"文档不变量失败: {rel} 无法按 UTF-8 读取") from exc
        lines = text.splitlines()
        for expected in rule["uniqueExactLines"]:
            count = sum(1 for line in lines if line == expected)
            if count != 1:
                raise CheckerError(
                    EXIT_CHAIN,
                    f"文档不变量失败: {rel} uniqueExactLines:{expected} 出现{count}次",
                )
        for needle in rule["forbiddenSubstrings"]:
            if needle in text:
                raise CheckerError(
                    EXIT_CHAIN,
                    f"文档不变量失败: {rel} forbiddenSubstrings:{needle}",
                )


def read_method_version(method_file: Path) -> str:
    if not method_file.is_file():
        raise CheckerError(EXIT_INPUT, f"缺少方法文件: {method_file}")
    match = METHOD_VERSION_RE.search(method_file.read_text(encoding="utf-8"))
    if not match:
        raise CheckerError(EXIT_CHAIN, "方法文件没有可机读的方法版本")
    return match.group(1)


def parse_identity(text: str) -> dict[str, str]:
    identity: dict[str, str] = {}
    header = "\n".join(text.splitlines()[:80])
    branch = BRANCH_RE.search(header)
    head = HEAD_RE.search(header)
    version = METHOD_VERSION_RE.search(header)
    if branch:
        identity["branch"] = branch.group(1)
    if head:
        identity["head"] = head.group(1)
    if version:
        identity["methodVersion"] = version.group(1)
    return identity


def identity_ok(
    identity: dict[str, str],
    branch: str,
    head: str,
    method: str,
    strict: bool,
    relative: str = "",
    legacy: dict[str, set[str]] | None = None,
) -> str:
    if strict:
        if not identity.get("branch"):
            return "缺分支"
        if not identity.get("head"):
            return "缺HEAD"
        if not identity.get("methodVersion"):
            return "缺方法版本"
    if identity.get("branch") and identity["branch"] != branch:
        return f"分支不符({identity['branch']})"
    reported = identity.get("head", "")
    if reported and not head.startswith(reported) and not reported.startswith(head[:7]):
        return f"HEAD不符({reported})"
    reported_version = identity.get("methodVersion")
    if reported_version and not method_version_allowed(reported_version, method, relative, legacy or {}):
        return f"方法版本不符({reported_version})"
    return ""


def method_version_allowed(
    reported: str,
    current: str,
    relative: str,
    legacy: dict[str, set[str]],
) -> bool:
    if reported == current:
        return True
    return bool(relative) and reported in legacy and relative in legacy[reported]


def normalize_line(line: str) -> str:
    return line.strip().strip("`").replace("**", "").strip()


def standalone_conclusion(text: str, sentence: str) -> bool:
    if not sentence:
        return False
    lines = [normalize_line(item) for item in text.splitlines() if item.strip()]
    window = lines[:20] + lines[-15:]
    for item in window:
        cleaned = item.lstrip("-* ").strip()
        if cleaned == sentence:
            return True
        if cleaned.endswith(sentence):
            prefix = cleaned[: -len(sentence)].rstrip(" ：:")
            if prefix in {"", "总结论", "结论", "审计结论"}:
                return True
    return False


def list_worktrees(repo: Path) -> list[str]:
    raw = git(repo, "worktree", "list", "--porcelain")
    paths = []
    for line in raw.splitlines():
        if line.startswith("worktree "):
            paths.append(line.split(" ", 1)[1])
    return paths


def ref_sha(repo: Path, ref: str) -> str:
    return git(repo, "rev-parse", ref).strip()


def porcelain(repo: Path) -> list[tuple[str, str]]:
    raw = git(repo, "status", "--porcelain=v1", "-z", "-uall")
    entries: list[tuple[str, str]] = []
    parts = raw.split("\0")
    index = 0
    while index < len(parts):
        item = parts[index]
        if not item:
            index += 1
            continue
        code, path = item[:2], item[3:]
        if "R" in code or "C" in code:
            index += 1
            if index < len(parts) and parts[index]:
                path = parts[index]
        entries.append((code, path))
        index += 1
    return entries


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
HEAD_SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def validate_readonly_snapshots(repository: dict[str, Any]) -> dict[str, dict[str, str]]:
    raw = repository.get("readOnlyWorktreeSnapshots", [])
    allowed = repository.get("allowedReadOnlyWorktrees", [])
    if not isinstance(raw, list) or not isinstance(allowed, list):
        raise CheckerError(EXIT_INPUT, "只读 worktree 快照和名单必须是数组")
    if any(not isinstance(path, str) or not os.path.isabs(path) for path in allowed):
        raise CheckerError(EXIT_INPUT, "只读 worktree 名单必须是绝对路径字符串")
    implementation_path = repository["implementationWorktree"]
    if not isinstance(implementation_path, str) or not os.path.isabs(implementation_path):
        raise CheckerError(EXIT_INPUT, "唯一实施 worktree 必须是绝对路径字符串")
    allowed_paths = {os.path.realpath(path) for path in allowed}
    implementation = os.path.realpath(implementation_path)
    snapshots: dict[str, dict[str, str]] = {}
    for index, item in enumerate(raw):
        field = f"repository.readOnlyWorktreeSnapshots[{index}]"
        if not isinstance(item, dict) or set(item) != {"path", "branch", "head", "fingerprint"}:
            raise CheckerError(EXIT_INPUT, f"{field} 字段必须恰为 path/branch/head/fingerprint")
        path, branch, head, fingerprint = (item[key] for key in ("path", "branch", "head", "fingerprint"))
        if not isinstance(path, str) or not os.path.isabs(path) or os.path.realpath(path) != path:
            raise CheckerError(EXIT_INPUT, f"{field}.path 必须是规范绝对路径")
        if path == implementation or path not in allowed_paths or path in snapshots:
            raise CheckerError(EXIT_INPUT, f"{field}.path 不是唯一、已登记的只读 worktree")
        if not isinstance(branch, str) or not branch or branch.strip() != branch:
            raise CheckerError(EXIT_INPUT, f"{field}.branch 无效")
        if not isinstance(head, str) or not HEAD_SHA_RE.fullmatch(head):
            raise CheckerError(EXIT_INPUT, f"{field}.head 必须是完整 SHA")
        if not isinstance(fingerprint, str) or not SHA256_RE.fullmatch(fingerprint):
            raise CheckerError(EXIT_INPUT, f"{field}.fingerprint 必须是 SHA-256")
        snapshots[path] = item
    return snapshots


def validate_frozen_external_files(repository: dict[str, Any]) -> dict[str, dict[str, str]]:
    raw = repository.get("frozenExternalFiles", [])
    if not isinstance(raw, list):
        raise CheckerError(EXIT_INPUT, "repository.frozenExternalFiles 必须是数组")
    frozen: dict[str, dict[str, str]] = {}
    for index, item in enumerate(raw):
        field = f"repository.frozenExternalFiles[{index}]"
        if not isinstance(item, dict) or set(item) != {"path", "status", "kind", "mode", "sha256"}:
            raise CheckerError(EXIT_INPUT, f"{field} 字段必须恰为 path/status/kind/mode/sha256")
        path = validate_package_rel_path(item["path"], f"{field}.path")
        if path in frozen or not path.startswith(("ZL00_项目总控/", "ZL02_研发档案/")):
            raise CheckerError(EXIT_INPUT, f"{field}.path 必须是唯一的治理或独立任务文件")
        if item["status"] not in (" M", "??"):
            raise CheckerError(EXIT_INPUT, f"{field}.status 只允许未暂存的修改或新增")
        if item["kind"] != "file" or isinstance(item["mode"], bool) or not isinstance(item["mode"], int) or not 0 <= item["mode"] <= 0o777:
            raise CheckerError(EXIT_INPUT, f"{field} 只接受普通文件和三位权限值")
        if not isinstance(item["sha256"], str) or not SHA256_RE.fullmatch(item["sha256"]):
            raise CheckerError(EXIT_INPUT, f"{field}.sha256 必须是 SHA-256")
        frozen[path] = item
    review = repository.get("frozenExternalReview")
    if frozen and (not isinstance(review, str) or review not in frozen):
        raise CheckerError(EXIT_INPUT, "冻结的外部差异必须登记清单内的独立审计报告")
    if not frozen and review is not None:
        raise CheckerError(EXIT_INPUT, "没有冻结文件时不得登记外部审计报告")
    return frozen


def git_status_bytes(repo: Path) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(repo), "status", "--porcelain=v1", "-z", "-uall"],
        check=False, capture_output=True,
    )
    if completed.returncode != 0:
        raise CheckerError(EXIT_INPUT, completed.stderr.decode("utf-8", "replace").strip() or "git status 失败")
    return completed.stdout


def content_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(descriptor, "rb") as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                raise CheckerError(EXIT_SCOPE, f"快照路径不是普通文件: {path}")
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise CheckerError(EXIT_SCOPE, f"无法读取快照文件: {path}") from exc
    return digest.hexdigest()


def readonly_worktree_fingerprint(tree: Path) -> str:
    before = git_status_bytes(tree)
    records: list[tuple[str, str, str, int, str]] = []
    parts = before.split(b"\0")
    for item in parts:
        if not item:
            continue
        if len(item) < 4 or item[2:3] != b" ":
            raise CheckerError(EXIT_SCOPE, "只读快照 Git 状态格式无效")
        try:
            code = item[:2].decode("ascii", "strict")
        except UnicodeDecodeError as exc:
            raise CheckerError(EXIT_SCOPE, "只读快照 Git 状态码无效") from exc
        if "R" in code or "C" in code:
            raise CheckerError(EXIT_SCOPE, "只读快照不接受重命名或复制状态")
        if code[0] not in " ?":
            raise CheckerError(EXIT_SCOPE, "只读快照工作树存在暂存差异")
        path = os.fsdecode(item[3:])
        if path.startswith("/") or any(part in ("", ".", "..") for part in path.split("/")):
            raise CheckerError(EXIT_SCOPE, "只读快照 Git 路径无效")
        target = tree / path
        try:
            info = target.lstat()
        except FileNotFoundError:
            records.append((code, path, "missing", 0, ""))
            continue
        except OSError as exc:
            raise CheckerError(EXIT_SCOPE, f"无法读取只读快照文件状态: {path}") from exc
        mode = stat.S_IMODE(info.st_mode)
        if stat.S_ISLNK(info.st_mode):
            try:
                digest = hashlib.sha256(os.fsencode(os.readlink(target))).hexdigest()
            except OSError as exc:
                raise CheckerError(EXIT_SCOPE, f"无法读取只读快照符号链接: {path}") from exc
            kind = "symlink"
        elif stat.S_ISREG(info.st_mode):
            digest = content_sha256(target)
            kind = "file"
        else:
            raise CheckerError(EXIT_SCOPE, f"只读快照不接受特殊文件或目录: {path}")
        records.append((code, path, kind, mode, digest))
    after = git_status_bytes(tree)
    if after != before:
        raise CheckerError(EXIT_SCOPE, "只读快照计算期间 Git 状态发生变化")
    canonical = json.dumps(
        {"statusSha256": hashlib.sha256(before).hexdigest(), "files": records},
        ensure_ascii=True, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def artifact_exists(package: Path, relative: str) -> bool:
    return (package / relative).is_file()


def collect_rnn(package: Path, spec: dict[str, Any]) -> list[str]:
    directory = package / spec.get("directory", "整改轮次")
    if not directory.is_dir():
        return []
    pattern = re.compile(spec.get("namePattern", r"^R[0-9]{2}$"))
    return sorted(
        path.name
        for path in directory.iterdir()
        if path.is_dir() and pattern.match(path.name)
    )


def rnn_gap(names: list[str]) -> str:
    expected = [f"R{index:02d}" for index in range(1, len(names) + 1)]
    if names != expected:
        return f"整改轮次编号不连续: {names}"
    return ""


def package_relative(path: str, package_rel: str) -> str | None:
    prefix = package_rel.rstrip("/") + "/"
    if path == package_rel.rstrip("/"):
        return ""
    if path.startswith(prefix):
        return path[len(prefix) :]
    return None


def named_package_files(contract: dict[str, Any]) -> set[str]:
    names = set(FIXED_PACKAGE_FILES)
    for files in (contract.get("phaseArtifacts") or {}).values():
        names.update(files)
    checker = contract.get("checker") or {}
    prompt_dir = str(checker.get("promptDirectory") or "提示词").rstrip("/")
    generic = checker.get("genericPrompt")
    if generic:
        names.add(f"{prompt_dir}/{generic}")
    for name in (checker.get("promptsByPhase") or {}).values():
        names.add(f"{prompt_dir}/{name}")
    names.update((contract.get("writerStatus") or {}).get("files") or [])
    return names


def path_allowed(path: str, code: str, contract: dict[str, Any], package_rel: str) -> bool:
    spec = contract["paths"]
    known = tuple(spec.get("knownUntracked", []))
    forbidden = tuple(spec.get("forbiddenPrefixes", []))
    allowed = list(spec.get("allowedModify", [])) + list(spec.get("allowedAdd", []))
    untracked = code == "??"
    for item in known:
        if path == item.rstrip("/") or path.startswith(item):
            return untracked
    for item in forbidden:
        if path == item.rstrip("/") or path.startswith(item):
            return False
    for item in allowed:
        if path == item or path.startswith(item.rstrip("/") + "/"):
            return True
    rel = package_relative(path, package_rel)
    if rel is None:
        return False
    return rel in named_package_files(contract) or bool(RNN_REL_RE.match(rel))


def has_exact_marker(path: Path, marker: str) -> bool:
    if not path.is_file() or not marker:
        return False
    for line in path.read_text(encoding="utf-8").splitlines():
        if normalize_line(line) == marker:
            return True
    return False


def prompt_path(package: Path, contract: dict[str, Any], phase: str) -> Path:
    checker = contract["checker"]
    name = checker["genericPrompt"] if phase == "generic" else checker["promptsByPhase"].get(
        phase, checker["genericPrompt"]
    )
    return (package / checker["promptDirectory"] / name).resolve()


def owner_for(contract: dict[str, Any], phase: str) -> str:
    return str(contract.get("roles", {}).get("phaseOwners", {}).get(phase, ""))


def inspect(repo: Path, package_rel: str) -> tuple[int, dict[str, Any]]:
    package = (repo / package_rel).resolve()
    if not package.is_dir():
        raise CheckerError(EXIT_INPUT, f"工作包不存在: {package}")

    contract = load_json(package / "00C-任务契约.json")
    method_file = repo / contract["checker"]["methodFile"]
    method_version = read_method_version(method_file)
    if contract["methodVersion"] != method_version:
        raise CheckerError(
            EXIT_CHAIN,
            f"契约方法版本 {contract['methodVersion']} 与方法文件 {method_version} 不一致",
        )

    duplicates = []
    for dirpath, dirnames, filenames in os.walk(repo):
        dirnames[:] = [name for name in dirnames if name not in {".git", "tools"}]
        if "00C-任务契约.json" not in filenames:
            continue
        candidate = Path(dirpath) / "00C-任务契约.json"
        try:
            other = json.loads(candidate.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if other.get("workPackageId") == contract["workPackageId"]:
            duplicates.append(str(candidate.relative_to(repo)))
    if len(duplicates) > 1:
        raise CheckerError(EXIT_CHAIN, "同一 workPackageId 出现多份契约: " + ", ".join(duplicates))

    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD").strip()
    head = git(repo, "rev-parse", "HEAD").strip()
    baseline_branch = contract["repository"]["baselineBranch"]
    baseline_head = contract["repository"]["baselineHead"]
    if branch != baseline_branch:
        raise CheckerError(EXIT_CHAIN, f"当前分支 {branch} 不是契约基线 {baseline_branch}")

    status_entries = porcelain(repo)
    staged = [path for code, path in status_entries if code[0] not in " ?"]
    untracked = [path for code, path in status_entries if code == "??"]
    dirty = [path for code, path in status_entries if code != "??"]

    expected_worktree = os.path.realpath(contract["repository"]["implementationWorktree"])
    if os.path.realpath(repo) != expected_worktree:
        raise CheckerError(EXIT_SCOPE, "当前目录不是契约唯一实施 worktree")
    readonly_snapshots = validate_readonly_snapshots(contract["repository"])
    frozen_external = validate_frozen_external_files(contract["repository"])
    allowed_trees = {
        os.path.realpath(item)
        for item in contract["repository"].get("allowedReadOnlyWorktrees", [])
        if item
    }
    allowed_trees.add(expected_worktree)
    extra_trees = [
        path
        for path in (os.path.realpath(item) for item in list_worktrees(repo))
        if path not in allowed_trees
    ]
    if extra_trees:
        raise CheckerError(EXIT_SCOPE, "发现契约外 worktree: " + ", ".join(extra_trees))

    readonly_trees = [
        os.path.realpath(item)
        for item in contract["repository"].get("allowedReadOnlyWorktrees", [])
        if item and os.path.realpath(item) != expected_worktree
    ]
    for tree in readonly_trees:
        snapshot = readonly_snapshots.get(tree)
        if snapshot is not None:
            actual_branch = git(Path(tree), "rev-parse", "--abbrev-ref", "HEAD").strip()
            actual_head = git(Path(tree), "rev-parse", "HEAD").strip()
            if actual_branch != snapshot["branch"] or actual_head != snapshot["head"]:
                raise CheckerError(EXIT_SCOPE, "只读 worktree 分支或 HEAD 偏离快照: " + tree)
            if readonly_worktree_fingerprint(Path(tree)) != snapshot["fingerprint"]:
                raise CheckerError(EXIT_SCOPE, "只读 worktree 内容偏离快照: " + tree)
            continue
        extra_entries = porcelain(Path(tree))
        extra_staged = [path for code, path in extra_entries if code[0] not in " ?"]
        extra_dirty = [path for code, path in extra_entries if code != "??"]
        extra_untracked = [
            path
            for code, path in extra_entries
            if code == "??" and not path_allowed(path, code, contract, package_rel)
        ]
        if extra_staged or extra_dirty or extra_untracked:
            raise CheckerError(
                EXIT_SCOPE,
                "只读 worktree 不洁净: " + tree,
            )

    if staged:
        raise CheckerError(EXIT_SCOPE, "暂存区非空: " + ", ".join(staged))

    status_by_path = {path: code for code, path in status_entries}
    for path, frozen in frozen_external.items():
        if any(path == prefix.rstrip("/") or path.startswith(prefix.rstrip("/") + "/")
               for prefix in contract["paths"]["forbiddenPrefixes"]):
            raise CheckerError(EXIT_SCOPE, "冻结外部文件命中禁止范围: " + path)
        if status_by_path.get(path) != frozen["status"]:
            raise CheckerError(EXIT_SCOPE, "冻结外部文件 Git 状态变化: " + path)
        try:
            info = (repo / path).lstat()
        except OSError as exc:
            raise CheckerError(EXIT_SCOPE, "冻结外部文件状态无法读取: " + path) from exc
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != frozen["mode"]:
            raise CheckerError(EXIT_SCOPE, "冻结外部文件类型或权限变化: " + path)
        if content_sha256(repo / path) != frozen["sha256"]:
            raise CheckerError(EXIT_SCOPE, "冻结外部文件内容变化: " + path)
    if frozen_external:
        review_path = contract["repository"]["frozenExternalReview"]
        try:
            review_text = (repo / review_path).read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise CheckerError(EXIT_SCOPE, "无法读取冻结外部差异独立审计报告") from exc
        review_lines = {normalize_line(line) for line in review_text.splitlines()}
        if "隔离规则独立核验通过。" not in review_lines or "写入状态：已停止" not in review_lines:
            raise CheckerError(EXIT_SCOPE, "冻结外部差异缺少已停止的独立通过报告")

    out_of_scope = []
    for code, path in status_entries:
        if path not in frozen_external and not path_allowed(path, code, contract, package_rel):
            out_of_scope.append(path)
    if out_of_scope:
        raise CheckerError(EXIT_SCOPE, "不在允许范围的差异: " + ", ".join(out_of_scope))

    writer = contract.get("writerStatus", {})
    running_marker = writer.get("runningMarker", "写入状态：未停止")
    scan_files = list(writer.get("files", []))
    rnn_spec = contract["checker"]["rnn"]
    rnn_dir = package / rnn_spec.get("directory", "整改轮次")
    if rnn_dir.is_dir():
        scan_files.extend(
            str(path.relative_to(package))
            for path in rnn_dir.glob(f"*/{rnn_spec['files'][1]}")
        )
    running_writers = []
    for relative in scan_files:
        target = package / relative
        if not target.is_file():
            continue
        for line in target.read_text(encoding="utf-8").splitlines():
            if normalize_line(line) == running_marker:
                running_writers.append(relative)
                break
    if running_writers:
        raise CheckerError(EXIT_SCOPE, "写入声明未停止: " + ", ".join(running_writers))

    artifacts = contract.get("phaseArtifacts", {})
    strict_names = set(contract["checker"].get("strictIdentityArtifacts", []))
    legacy = validate_legacy_artifact_method_versions(
        contract["checker"].get("legacyArtifactMethodVersions"),
        method_version,
    )
    valid: list[str] = []
    invalid: dict[str, str] = {}
    present: dict[str, bool] = {}
    for phase, files in artifacts.items():
        for relative in files:
            present[relative] = artifact_exists(package, relative)
            if not present[relative]:
                continue
            if relative.endswith(".json"):
                valid.append(relative)
                continue
            identity = parse_identity((package / relative).read_text(encoding="utf-8"))
            reason = identity_ok(
                identity,
                baseline_branch,
                baseline_head,
                method_version,
                relative in strict_names,
                relative,
                legacy,
            )
            if reason:
                invalid[relative] = reason
            else:
                valid.append(relative)

    if invalid:
        details = "; ".join(f"{name}: {reason}" for name, reason in invalid.items())
        raise CheckerError(EXIT_CHAIN, "产物身份无效: " + details)

    conclusions = contract["checker"]["fixedConclusions"]
    phase7_rel = (artifacts.get("7") or [None])[0]
    phase7_text = (package / phase7_rel).read_text(encoding="utf-8") if phase7_rel and phase7_rel in valid else ""

    rnn_names = collect_rnn(package, rnn_spec)
    gap = rnn_gap(rnn_names)
    if gap:
        raise CheckerError(EXIT_CHAIN, gap)

    latest_round_fail = False
    latest_round_pass = False
    latest_round = rnn_names[-1] if rnn_names else ""
    if latest_round:
        round_dir = package / rnn_spec["directory"] / latest_round
        files = rnn_spec["files"]
        first, second, third = (round_dir / files[0], round_dir / files[1], round_dir / files[2])
        if third.is_file() and (not first.is_file() or not second.is_file()):
            raise CheckerError(EXIT_CHAIN, f"{latest_round} 复验存在但整改链不完整")
        for report in (first, second, third):
            if not report.is_file():
                continue
            text = report.read_text(encoding="utf-8")
            relative = str(report.relative_to(package))
            reason = identity_ok(
                parse_identity(text),
                baseline_branch,
                baseline_head,
                method_version,
                True,
                relative,
                legacy,
            )
            if reason:
                raise CheckerError(EXIT_CHAIN, f"{relative} 身份无效: {reason}")
        if third.is_file():
            text = third.read_text(encoding="utf-8")
            latest_round_fail = standalone_conclusion(text, conclusions["roundFail"])
            latest_round_pass = standalone_conclusion(text, conclusions["roundPass"])
            if latest_round_fail and latest_round_pass:
                raise CheckerError(EXIT_CHAIN, f"{latest_round} 同时出现通过与失败结论")

    phase7_fail = standalone_conclusion(phase7_text, conclusions["phase7Fail"])
    phase7_pass = standalone_conclusion(phase7_text, conclusions["phase7Pass"])
    if phase7_fail and phase7_pass:
        raise CheckerError(EXIT_CHAIN, "阶段7同时出现通过与失败结论")
    latest_effective_fail = latest_round_fail or (phase7_fail and not latest_round_pass)
    latest_effective_pass = latest_round_pass or (phase7_pass and not latest_round_fail)
    if latest_round_fail and phase7_pass:
        latest_effective_pass = False

    def missing(phase: str) -> bool:
        files = artifacts.get(phase, [])
        return not files or any(not present.get(name, False) or name in invalid for name in files)

    for later, earlier in (("2", "1"), ("3", "2"), ("5", "4"), ("7", "5")):
        later_files = artifacts.get(later, [])
        if any(present.get(name, False) for name in later_files) and missing(earlier):
            raise CheckerError(EXIT_CHAIN, f"缺少阶段{earlier}有效产物却已有阶段{later}文件")

    head_moved = head != baseline_head
    if head_moved and not latest_effective_pass:
        raise CheckerError(EXIT_CHAIN, f"HEAD {head} 不是基线 {baseline_head}")

    protected = {}
    for name, expected in contract["repository"]["protectedRefs"].items():
        actual = ref_sha(repo, name)
        protected[name] = actual
        if actual != expected:
            raise CheckerError(EXIT_CHAIN, f"保护引用 {name}={actual} 不是 {expected}")

    for name in contract["repository"].get("forbiddenBranches", []):
        if try_git(repo, "show-ref", "--verify", "--quiet", f"refs/heads/{name}") is not None:
            raise CheckerError(EXIT_CHAIN, f"禁止分支已存在: {name}")
        if try_git(repo, "show-ref", "--verify", "--quiet", f"refs/remotes/origin/{name}") is not None:
            raise CheckerError(EXIT_CHAIN, f"禁止远程分支已存在: {name}")

    if head_moved and latest_effective_pass:
        tracking = contract["repository"].get("uploadTrackingRefs", [])
        for name in tracking:
            actual = try_git(repo, "rev-parse", name)
            if actual != head:
                raise CheckerError(
                    EXIT_CHAIN,
                    f"HEAD 已离开基线，但 {name} 不是当前 HEAD，不能视为已完成 A/B",
                )

    enforce_document_invariants(
        package,
        validate_document_invariants(contract["checker"].get("documentInvariants")),
    )

    next_phase = "generic"
    approval = "无"
    blockers: list[str] = []

    if missing("1"):
        next_phase = "1"
    elif missing("2"):
        next_phase = "2"
    elif missing("3"):
        next_phase = "3"
    elif missing("4"):
        next_phase = "4"
        approval = "最终计划（若尚未确认）"
    elif missing("5"):
        next_phase = "5"
    else:
        audit_rel = (artifacts.get("5") or [None])[0]
        audit_text = (package / audit_rel).read_text(encoding="utf-8") if audit_rel and audit_rel in valid else ""
        phase5_fail = standalone_conclusion(
            audit_text,
            conclusions.get("phase5Fail", "审计不通过，存在阻塞问题，不得进入阶段7或8。"),
        )
        phase5_pass = standalone_conclusion(
            audit_text,
            conclusions.get("phase5Pass", "审计通过，无阻塞问题，可以进入阶段7。"),
        )
        if audit_rel and audit_rel in valid and phase5_fail == phase5_pass:
            raise CheckerError(EXIT_CHAIN, "阶段5结论不唯一")
        has_blockers = phase5_fail
        if has_blockers and missing("6"):
            next_phase = "6"
        elif missing("7") and not latest_round:
            next_phase = "7"
        elif latest_effective_fail:
            round_dir = package / rnn_spec["directory"] / latest_round if latest_round else None
            files = rnn_spec["files"]
            if not latest_round or (round_dir and (round_dir / files[2]).is_file()):
                next_phase = "7R"
            elif round_dir and not (round_dir / files[1]).is_file():
                next_phase = "7S"
                approval = f"批准 {latest_round}/01"
            elif round_dir and not (round_dir / files[2]).is_file():
                next_phase = "7T"
            else:
                next_phase = "7R"
        elif latest_effective_pass:
            next_phase = "9" if head_moved else "8"
            if next_phase == "8":
                approval = "单独批准提交和上传"
        else:
            next_phase = "7"

    stopped_marker = writer.get("stoppedMarker", "写入状态：已停止")
    if next_phase in {"5", "7", "7T", "9"}:
        executor: Path | None = None
        if next_phase == "5":
            names = artifacts.get("4") or []
            executor = package / names[-1] if names else None
        elif next_phase == "7":
            names = artifacts.get("6") or []
            if names and (package / names[0]).is_file():
                executor = package / names[0]
            else:
                names = artifacts.get("4") or []
                executor = package / names[-1] if names else None
        elif next_phase == "7T" and latest_round:
            executor = package / rnn_spec["directory"] / latest_round / rnn_spec["files"][1]
        elif next_phase == "9":
            names = artifacts.get("6") or []
            executor = package / names[0] if names else None
        if executor is not None and executor.is_file() and not has_exact_marker(executor, stopped_marker):
            raise CheckerError(EXIT_CHAIN, "缺少写入停止证据: " + str(executor.relative_to(package)))

    prompt = prompt_path(package, contract, next_phase)
    if not prompt.is_file():
        generic = prompt_path(package, contract, "generic")
        if not generic.is_file():
            raise CheckerError(EXIT_INPUT, f"提示词不存在: {prompt}；通用提示词也不存在: {generic}")
        raise CheckerError(EXIT_INPUT, f"下一阶段提示词不存在: {prompt}；改用 {generic}")

    if next_phase == "generic":
        blockers.append("无法唯一确定下一阶段")

    payload = {
        "contractValid": True,
        "methodVersion": method_version,
        "methodVersionMatch": True,
        "branch": branch,
        "head": head,
        "stagingEmpty": not staged,
        "protectedRefs": protected,
        "validArtifacts": valid,
        "invalidArtifacts": invalid,
        "untracked": untracked,
        "dirty": dirty,
        "writerConflict": False,
        "nextPhase": next_phase,
        "owner": owner_for(contract, next_phase),
        "promptPath": str(prompt),
        "requiredUserApproval": approval,
        "checkerGrantsExecutionAuthority": CHECKER_GRANTS_EXECUTION_AUTHORITY,
        "authorizationNote": AUTHORIZATION_NOTE,
        "blockers": blockers,
        "workPackageId": contract["workPackageId"],
    }
    return (EXIT_OK if not blockers else EXIT_CHAIN), payload


def render_text(payload: dict[str, Any]) -> str:
    lines = [
        f"契约: {'有效' if payload.get('contractValid') else '无效'}  workPackageId={payload.get('workPackageId', '')}",
        f"方法版本: {payload.get('methodVersion', '')}  匹配={payload.get('methodVersionMatch')}",
        f"分支: {payload.get('branch', '')}  HEAD: {payload.get('head', '')}",
        f"暂存区空: {payload.get('stagingEmpty')}",
        f"有效产物: {', '.join(payload.get('validArtifacts') or []) or '无'}",
        f"失效产物: {payload.get('invalidArtifacts') or '{}'}",
        f"写入冲突: {payload.get('writerConflict')}",
        f"下一阶段: {payload.get('nextPhase')}  负责人: {payload.get('owner')}",
        f"需要用户批准: {payload.get('requiredUserApproval')}",
        f"提示词: {payload.get('promptPath')}",
        str(payload.get("authorizationNote") or AUTHORIZATION_NOTE),
    ]
    if payload.get("blockers"):
        lines.append("阻塞: " + "; ".join(payload["blockers"]))
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="只读多 AI 工作流检查器")
    parser.add_argument("--work-package", required=True)
    parser.add_argument("--repo-root")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)
    try:
        repo = Path(args.repo_root).resolve() if args.repo_root else Path.cwd().resolve()
        if not (repo / ".git").exists():
            raise CheckerError(EXIT_INPUT, f"不是 Git 仓库根: {repo}")
        code, payload = inspect(repo, args.work_package)
    except CheckerError as exc:
        message = {"ok": False, "error": exc.message, "code": exc.code}
        if args.format == "json":
            sys.stdout.write(json.dumps(message, ensure_ascii=False, indent=2) + "\n")
        else:
            sys.stdout.write(f"停止: {exc.message}\n")
        return exc.code
    except (KeyError, TypeError, AttributeError, ValueError) as exc:
        message = {"ok": False, "error": f"契约结构无效: {exc}", "code": EXIT_INPUT}
        if args.format == "json":
            sys.stdout.write(json.dumps(message, ensure_ascii=False, indent=2) + "\n")
        else:
            sys.stdout.write(f"停止: 契约结构无效: {exc}\n")
        return EXIT_INPUT
    if args.format == "json":
        sys.stdout.write(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    else:
        sys.stdout.write(render_text(payload))
    return code


if __name__ == "__main__":
    sys.exit(main())
