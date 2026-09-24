#!/usr/bin/env python3
"""Stdlib tests for the read-only multi-AI workflow checker."""

from __future__ import annotations

import importlib.util
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKER = Path(__file__).resolve().parent / "check_multi_ai_workflow.py"
PACKAGE = "pkg"
HEAD = "placeholder"
METHOD = "MAIC-1.0"
PASS = "验收通过，可以在用户明确授权后提交并上传 v1.13.8。"
FAIL = "验收不通过，必须进入可重复整改轮次。"
PHASE5_FAIL = "审计不通过，存在阻塞问题，不得进入阶段7或8。"
PHASE5_PASS = "审计通过，无阻塞问题，可以进入阶段7。"
ROUND_PASS = "本轮复验通过，可以在用户明确授权后进入阶段8。"
AUTHORIZATION_NOTE = "检查器只判断状态和路由，不授予下一阶段执行权限"


def run_git(repo: Path, *args: str, env: dict[str, str] | None = None) -> str:
    merged = os.environ.copy()
    merged.update(
        {
            "GIT_AUTHOR_NAME": "fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.com",
            "GIT_COMMITTER_NAME": "fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.com",
        }
    )
    if env:
        merged.update(env)
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
        env=merged,
    )
    return completed.stdout.strip()


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def identity_md(title: str, head: str, extra: str = "", version: str | None = None) -> str:
    return (
        f"# {title}\n\n"
        f"- 阶段：fixture\n"
        f"- 分支：`v1.13.8`\n"
        f"- 起始 HEAD：`{head}`\n"
        f"- 方法版本：{version or METHOD}\n\n"
        f"{extra}\n"
    )


def contract_for(repo: Path, head: str) -> dict:
    return {
        "schemaVersion": "1.0",
        "workPackageId": "fixture-pack",
        "methodVersion": METHOD,
        "sourceKind": "ZL02",
        "riskLevel": "high",
        "objective": "fixture",
        "repository": {
            "implementationWorktree": str(repo),
            "allowedReadOnlyWorktrees": [],
            "baselineBranch": "v1.13.8",
            "baselineHead": head,
            "protectedRefs": {"main": head, "origin/main": head, "release/1.0.0": head},
            "uploadTrackingRefs": ["v1", "origin/v1", "origin/v1.13.8"],
            "forbiddenBranches": ["v1.13.9"],
        },
        "roles": {
            "planningAuditor": "Codex",
            "checkExecutor": "Grok",
            "userDecides": ["finalPlan", "upload"],
            "singleWriterPerWorkspace": True,
            "phaseOwners": {
                "1": "Codex",
                "2": "Grok",
                "3": "Codex",
                "4": "Grok",
                "5": "Codex",
                "6": "Grok",
                "7": "Codex",
                "7R": "Codex",
                "7S": "Grok",
                "7T": "Codex",
                "8": "Grok",
                "9": "Codex",
            },
        },
        "paths": {
            "allowedModify": ["README.md"],
            "allowedAdd": ["ZL00_项目总控/04-双AI协作与独立审计.md"],
            "allowedPrefixes": [],
            "forbiddenPrefixes": ["secret/"],
            "knownUntracked": ["tools/"],
        },
        "writerStatus": {
            "files": ["06.md", "08.md"],
            "runningMarker": "写入状态：未停止",
            "stoppedMarker": "写入状态：已停止",
        },
        "checker": {
            "methodFile": "ZL00_项目总控/04-双AI协作与独立审计.md",
            "contractFile": "00C-任务契约.json",
            "promptDirectory": "提示词",
            "genericPrompt": "通用-只检查当前阶段.md",
            "promptsByPhase": {
                "1": "阶段1.md",
                "2": "阶段2.md",
                "3": "阶段3.md",
                "4": "阶段4.md",
                "5": "阶段5.md",
                "6": "阶段6.md",
                "7": "阶段7.md",
                "7R": "阶段7R.md",
                "7S": "阶段7S.md",
                "7T": "阶段7T.md",
                "8": "阶段8.md",
                "9": "阶段9.md",
            },
            "strictIdentityArtifacts": ["06.md", "07.md", "08.md", "09.md"],
            "fixedConclusions": {
                "phase5Pass": "审计通过，无阻塞问题，可以进入阶段7。",
                "phase5Fail": PHASE5_FAIL,
                "phase7Pass": PASS,
                "phase7Fail": FAIL,
                "roundPass": ROUND_PASS,
                "roundFail": "本轮复验不通过，必须创建下一整改轮次。",
            },
            "legacyArtifactMethodVersions": {},
            "documentInvariants": [],
            "rnn": {
                "directory": "整改轮次",
                "namePattern": "^R[0-9]{2}$",
                "files": [
                    "01-Codex整改定稿.md",
                    "02-Grok整改报告.md",
                    "03-Codex复验报告.md",
                ],
            },
        },
        "phaseArtifacts": {
            "1": ["01.md"],
            "2": ["03.md"],
            "3": ["04.md", "05.md"],
            "4": ["00C-任务契约.json", "06.md"],
            "5": ["07.md"],
            "6": ["08.md"],
            "7": ["09.md"],
        },
    }


def make_repo(complete_to: int) -> Path:
    temp = Path(tempfile.mkdtemp(prefix="maic-check-"))
    run_git(temp, "init", "-b", "v1.13.8")
    write(temp / "ZL00_项目总控/04-双AI协作与独立审计.md", f"方法版本：{METHOD}\n")
    for index in range(1, 10):
        write(temp / PACKAGE / "提示词" / f"阶段{index}.md", "prompt\n")
    for name in ("7R", "7S", "7T"):
        write(temp / PACKAGE / "提示词" / f"阶段{name}.md", "prompt\n")
    write(temp / PACKAGE / "提示词/通用-只检查当前阶段.md", "generic\n")
    write(temp / "README.md", "root\n")
    run_git(temp, "add", "README.md")
    run_git(temp, "commit", "-m", "base")
    head = run_git(temp, "rev-parse", "HEAD")
    run_git(temp, "branch", "main")
    run_git(temp, "branch", "v1")
    run_git(temp, "tag", "release/1.0.0")
    run_git(temp, "update-ref", "refs/remotes/origin/main", head)
    run_git(temp, "update-ref", "refs/remotes/origin/v1", head)
    run_git(temp, "update-ref", "refs/remotes/origin/v1.13.8", head)
    data = contract_for(temp, head)
    write(temp / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
    files = {
        1: ("01.md", identity_md("p1", head)),
        2: ("03.md", identity_md("p2", head)),
        3: ("04.md", identity_md("p3a", head)),
        30: ("05.md", identity_md("p3b", head)),
        4: ("06.md", identity_md("p4", head, "写入状态：已停止")),
        5: ("07.md", identity_md("p5", head, PHASE5_PASS)),
        7: ("09.md", identity_md("p7", head, PASS)),
    }
    mapping = {
        1: [1],
        2: [1, 2],
        3: [1, 2, 3, 30],
        4: [1, 2, 3, 30, 4],
        5: [1, 2, 3, 30, 4, 5],
        7: [1, 2, 3, 30, 4, 5, 7],
    }
    for key in mapping.get(complete_to, mapping[3]):
        relative, text = files[key]
        write(temp / PACKAGE / relative, text)
    return temp


def invoke(repo: Path, extra: list[str] | None = None, fmt: str = "json") -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    command = [
        "python3",
        "-B",
        str(CHECKER),
        "--repo-root",
        str(repo),
        "--work-package",
        PACKAGE,
        "--format",
        fmt,
    ]
    if extra:
        command.extend(extra)
    return subprocess.run(command, capture_output=True, text=True, env=env)


def load_checker_module():
    spec = importlib.util.spec_from_file_location("check_multi_ai_workflow", CHECKER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class CheckerTests(unittest.TestCase):
    def tearDown(self) -> None:
        temps = getattr(self, "_temps", [])
        for path in temps:
            shutil.rmtree(path, ignore_errors=True)

    def keep(self, path: Path) -> Path:
        self._temps = getattr(self, "_temps", [])
        self._temps.append(path)
        return path

    def assert_no_execution_authority(self, payload: dict) -> None:
        self.assertIs(payload["checkerGrantsExecutionAuthority"], False)
        self.assertEqual(payload["authorizationNote"], AUTHORIZATION_NOTE)

    def test_normal_recovery_after_final_plan(self) -> None:
        repo = self.keep(make_repo(3))
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "4")
        self.assertTrue(payload["promptPath"].endswith("阶段4.md"))
        self.assert_no_execution_authority(payload)

    def test_not_a_repo(self) -> None:
        empty = self.keep(Path(tempfile.mkdtemp(prefix="maic-empty-")))
        result = invoke(empty)
        self.assertEqual(result.returncode, 2)

    def test_missing_contract(self) -> None:
        repo = self.keep(make_repo(3))
        (repo / PACKAGE / "00C-任务契约.json").unlink()
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)

    def test_invalid_json(self) -> None:
        repo = self.keep(make_repo(3))
        write(repo / PACKAGE / "00C-任务契约.json", "{")
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)

    def test_method_version_mismatch(self) -> None:
        repo = self.keep(make_repo(3))
        write(repo / "ZL00_项目总控/04-双AI协作与独立审计.md", "方法版本：MAIC-0.9\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)

    def test_old_head_report(self) -> None:
        repo = self.keep(make_repo(3))
        write(repo / PACKAGE / "04.md", identity_md("old", "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"))
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("产物身份无效", result.stdout)

    def test_later_without_earlier(self) -> None:
        repo = self.keep(make_repo(3))
        (repo / PACKAGE / "03.md").unlink()
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)

    def test_newer_fail_overrides_old_pass(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "7R")
        self.assert_no_execution_authority(payload)

    def test_unexpected_staging(self) -> None:
        repo = self.keep(make_repo(3))
        write(repo / "staged.txt", "x\n")
        run_git(repo, "add", "staged.txt")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)

    def test_protected_path_diff(self) -> None:
        repo = self.keep(make_repo(3))
        write(repo / "secret/key.txt", "nope\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)

    def test_whitelist_rejects_unlisted_file(self) -> None:
        repo = self.keep(make_repo(3))
        write(repo / "unexpected.txt", "x\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("不在允许范围", result.stdout)

    def test_staging_after_acceptance_still_fails(self) -> None:
        repo = self.keep(make_repo(7))
        write(repo / "staged.txt", "x\n")
        run_git(repo, "add", "staged.txt")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)

    def test_staged_tools_is_not_known_untracked(self) -> None:
        repo = self.keep(make_repo(7))
        write(repo / "tools/x.txt", "x\n")
        run_git(repo, "add", "tools/x.txt")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)

    def test_head_move_after_pass_without_tracking_fails(self) -> None:
        repo = self.keep(make_repo(7))
        write(repo / "README.md", "moved\n")
        run_git(repo, "add", "README.md")
        run_git(repo, "commit", "-m", "move")
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("HEAD 已离开基线", result.stdout)

    def test_head_move_after_pass_with_tracking_is_phase_9(self) -> None:
        repo = self.keep(make_repo(7))
        write(repo / "README.md", "moved\n")
        run_git(repo, "add", "README.md")
        run_git(repo, "commit", "-m", "move")
        new_head = run_git(repo, "rev-parse", "HEAD")
        run_git(repo, "branch", "-f", "v1", new_head)
        run_git(repo, "update-ref", "refs/remotes/origin/v1", new_head)
        run_git(repo, "update-ref", "refs/remotes/origin/v1.13.8", new_head)
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "9")
        self.assert_no_execution_authority(payload)

    def test_missing_identity_on_strict_report(self) -> None:
        repo = self.keep(make_repo(4))
        write(repo / PACKAGE / "06.md", "# 无身份\n\n正文。\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("缺", result.stdout)

    def test_quoted_pass_sentence_does_not_accept(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(
            repo / PACKAGE / "09.md",
            identity_md("cite", head, f"不要写「{PASS}」当作结论。"),
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "7")

    def test_phase5_fail_routes_to_phase6(self) -> None:
        repo = self.keep(make_repo(5))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "07.md", identity_md("audit", head, f"总结论：{PHASE5_FAIL}"))
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "6")

    def test_rnn_missing_executor_report(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(repo / PACKAGE / "整改轮次/R01/03-Codex复验报告.md", identity_md("r3", head, ROUND_PASS))
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("整改链不完整", result.stdout)

    def test_missing_next_prompt(self) -> None:
        repo = self.keep(make_repo(4))
        (repo / PACKAGE / "提示词/阶段5.md").unlink()
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("阶段5.md", result.stdout)

    def test_dual_writer_declarations(self) -> None:
        repo = self.keep(make_repo(4))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "06.md", identity_md("a", head, "写入状态：未停止"))
        write(repo / PACKAGE / "08.md", identity_md("b", head, "写入状态：未停止"))
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)

    def test_unlisted_file_quoting_writer_status_is_ignored(self) -> None:
        repo = self.keep(make_repo(4))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "01.md", identity_md("quote", head, "写入状态：未停止"))
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_single_running_writer_blocks_audit(self) -> None:
        repo = self.keep(make_repo(4))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "06.md", identity_md("run", head, "写入状态：未停止"))
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("写入声明未停止", result.stdout)

    def test_missing_stopped_marker_blocks_audit(self) -> None:
        repo = self.keep(make_repo(4))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "06.md", identity_md("nostop", head))
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("缺少写入停止证据", result.stdout)

    def test_package_unlisted_file_rejected(self) -> None:
        repo = self.keep(make_repo(3))
        write(repo / PACKAGE / "arbitrary-payload.bin", "x\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("不在允许范围", result.stdout)

    def test_phase5_without_fixed_conclusion(self) -> None:
        repo = self.keep(make_repo(5))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "07.md", identity_md("empty", head, "没有固定结论。"))
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("阶段5结论不唯一", result.stdout)

    def test_nested_contract_damage_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["repository"] = {}
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("repository", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_dirty_readonly_worktree_rejected(self) -> None:
        repo = self.keep(make_repo(3))
        extra = self.keep(Path(tempfile.mkdtemp(prefix="maic-dirty-")))
        extra.rmdir()
        run_git(repo, "worktree", "add", "--detach", str(extra))
        write(extra / "README.md", "dirty\n")
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["repository"]["allowedReadOnlyWorktrees"] = [str(extra)]
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("只读 worktree 不洁净", result.stdout)

    def test_extra_worktree_rejected(self) -> None:
        repo = self.keep(make_repo(3))
        extra = self.keep(Path(tempfile.mkdtemp(prefix="maic-wt-")))
        extra.rmdir()
        run_git(repo, "worktree", "add", "--detach", str(extra))
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("worktree", result.stdout)

    def test_readonly_worktree_allowed(self) -> None:
        repo = self.keep(make_repo(3))
        extra = self.keep(Path(tempfile.mkdtemp(prefix="maic-ro-")))
        extra.rmdir()
        run_git(repo, "worktree", "add", "--detach", str(extra))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["repository"]["allowedReadOnlyWorktrees"] = [str(extra)]
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout)

    def _registered_dirty_readonly(self) -> tuple[Path, Path]:
        repo = self.keep(make_repo(3))
        extra = self.keep(Path(tempfile.mkdtemp(prefix="maic-snapshot-")).resolve())
        extra.rmdir()
        run_git(repo, "worktree", "add", "--detach", str(extra))
        write(extra / "README.md", "already dirty\n")
        write(extra / "existing evidence.txt", "existing\n")
        data_path = repo / PACKAGE / "00C-任务契约.json"
        data = json.loads(data_path.read_text(encoding="utf-8"))
        data["repository"]["allowedReadOnlyWorktrees"] = [str(extra)]
        module = load_checker_module()
        data["repository"]["readOnlyWorktreeSnapshots"] = [{
            "path": str(extra), "branch": "HEAD",
            "head": run_git(extra, "rev-parse", "HEAD"),
            "fingerprint": module.readonly_worktree_fingerprint(extra),
        }]
        write(data_path, json.dumps(data, ensure_ascii=False, indent=2))
        return repo, extra

    def test_registered_dirty_readonly_snapshot_allows_unchanged_tree(self) -> None:
        repo, _ = self._registered_dirty_readonly()
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_dirty_main_tree_and_separate_implementation_tree(self) -> None:
        main = self.keep(make_repo(3))
        run_git(main, "branch", "-m", "v1.13.9")
        linked = self.keep(Path(tempfile.mkdtemp(prefix="maic-implementation-")).resolve())
        linked.rmdir()
        run_git(main, "worktree", "add", "-b", "v1.13.8", str(linked), "HEAD")
        shutil.copytree(main / PACKAGE, linked / PACKAGE)
        write(linked / "ZL00_项目总控/04-双AI协作与独立审计.md", f"方法版本：{METHOD}\n")
        data_path = linked / PACKAGE / "00C-任务契约.json"
        data = json.loads(data_path.read_text(encoding="utf-8"))
        data["repository"]["implementationWorktree"] = str(linked)
        data["repository"]["allowedReadOnlyWorktrees"] = [str(main.resolve())]
        data["repository"]["forbiddenBranches"] = ["v1.14"]
        module = load_checker_module()
        data["repository"]["readOnlyWorktreeSnapshots"] = [{
            "path": str(main.resolve()), "branch": "v1.13.9",
            "head": run_git(main, "rev-parse", "HEAD"),
            "fingerprint": module.readonly_worktree_fingerprint(main),
        }]
        write(data_path, json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(linked)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        write(main / "README.md", "changed after snapshot\n")
        result = invoke(linked)
        self.assertEqual(result.returncode, 4)
        self.assertIn("偏离快照", result.stdout)

    def test_dirty_readonly_snapshot_rejects_content_change(self) -> None:
        repo, extra = self._registered_dirty_readonly()
        write(extra / "README.md", "changed after snapshot\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("偏离快照", result.stdout)

    def test_dirty_readonly_snapshot_rejects_new_file(self) -> None:
        repo, extra = self._registered_dirty_readonly()
        write(extra / "new evidence.txt", "new\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("偏离快照", result.stdout)

    def test_dirty_readonly_snapshot_rejects_staging(self) -> None:
        repo, extra = self._registered_dirty_readonly()
        run_git(extra, "add", "README.md")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("暂存", result.stdout)

    def test_dirty_readonly_snapshot_rejects_branch_change(self) -> None:
        repo, extra = self._registered_dirty_readonly()
        run_git(extra, "switch", "-c", "another-branch")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("分支或 HEAD", result.stdout)

    def test_dirty_readonly_snapshot_rejects_rename_status(self) -> None:
        repo, extra = self._registered_dirty_readonly()
        run_git(extra, "mv", "README.md", "renamed-readme.md")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("重命名或复制", result.stdout)

    def test_readonly_snapshot_not_on_allowlist_rejected(self) -> None:
        repo, _ = self._registered_dirty_readonly()
        data_path = repo / PACKAGE / "00C-任务契约.json"
        data = json.loads(data_path.read_text(encoding="utf-8"))
        data["repository"]["allowedReadOnlyWorktrees"] = []
        write(data_path, json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("已登记", result.stdout)

    def _frozen_external(self) -> tuple[Path, Path]:
        repo = self.keep(make_repo(3))
        external = repo / "ZL00_项目总控/自动化/isolated-fix.py"
        review = repo / "ZL02_研发档案/隔离修正/04-独立审计报告.md"
        write(external, "# externally reviewed\n")
        write(review, "隔离规则独立核验通过。\n写入状态：已停止\n")
        data_path = repo / PACKAGE / "00C-任务契约.json"
        data = json.loads(data_path.read_text(encoding="utf-8"))
        data["repository"]["frozenExternalReview"] = str(review.relative_to(repo))
        data["repository"]["frozenExternalFiles"] = [
            {"path": str(path.relative_to(repo)), "status": "??", "kind": "file",
             "mode": path.stat().st_mode & 0o777,
             "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            for path in (external, review)
        ]
        write(data_path, json.dumps(data, ensure_ascii=False, indent=2))
        return repo, external

    def test_frozen_external_files_allow_exact_reviewed_difference(self) -> None:
        repo, _ = self._frozen_external()
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_frozen_external_files_reject_changed_content(self) -> None:
        repo, external = self._frozen_external()
        write(external, "# changed\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("内容变化", result.stdout)

    def test_frozen_external_files_reject_mode_change(self) -> None:
        repo, external = self._frozen_external()
        external.chmod(0o755)
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("类型或权限变化", result.stdout)

    def test_frozen_external_files_reject_symlink_replacement(self) -> None:
        repo, external = self._frozen_external()
        external.unlink()
        external.symlink_to(repo / "README.md")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("类型或权限变化", result.stdout)

    def test_frozen_external_files_reject_new_unlisted_difference(self) -> None:
        repo, _ = self._frozen_external()
        write(repo / "ZL00_项目总控/自动化/unlisted.py", "x\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 4)
        self.assertIn("不在允许范围", result.stdout)

    def test_frozen_external_files_require_review(self) -> None:
        repo, _ = self._frozen_external()
        data_path = repo / PACKAGE / "00C-任务契约.json"
        data = json.loads(data_path.read_text(encoding="utf-8"))
        data["repository"].pop("frozenExternalReview")
        write(data_path, json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("独立审计报告", result.stdout)

    def test_rnn_gap(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(repo / PACKAGE / "整改轮次/R03/01-Codex整改定稿.md", identity_md("r3", head))
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)

    def test_duplicate_work_package_id(self) -> None:
        repo = self.keep(make_repo(3))
        shutil.copytree(repo / PACKAGE, repo / "copy")
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)

    def test_known_untracked_tools_is_allowed(self) -> None:
        repo = self.keep(make_repo(3))
        write(repo / "tools/ignore.txt", "x\n")
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_checker_rejects_write_git(self) -> None:
        repo = self.keep(make_repo(3))
        module = load_checker_module()
        with self.assertRaises(module.CheckerError) as ctx:
            module.git(repo, "add", "README.md")
        self.assertEqual(ctx.exception.code, 4)

    def test_checker_source_has_no_write_git(self) -> None:
        source = CHECKER.read_text(encoding="utf-8")
        for banned in ("commit", "checkout", "reset", "push", "add", "fetch"):
            self.assertNotIn(f'"{banned}"', source)
            self.assertNotIn(f"'{banned}'", source)

    def _upgrade(self, repo: Path, version: str, legacy: dict[str, list[str]]) -> None:
        write(repo / "ZL00_项目总控/04-双AI协作与独立审计.md", f"方法版本：{version}\n")
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["methodVersion"] = version
        data["checker"]["legacyArtifactMethodVersions"] = legacy
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))

    def test_legacy_exact_paths_remain_valid_after_upgrade(self) -> None:
        repo = self.keep(make_repo(3))
        self._upgrade(
            repo,
            "MAIC-1.1",
            {"MAIC-1.0": ["01.md", "03.md", "04.md", "05.md"]},
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["methodVersion"], "MAIC-1.1")
        self.assertEqual(payload["nextPhase"], "4")

    def test_unlisted_legacy_path_exits_chain(self) -> None:
        repo = self.keep(make_repo(3))
        self._upgrade(repo, "MAIC-1.1", {"MAIC-1.0": ["01.md", "03.md", "05.md"]})
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("方法版本不符", result.stdout)

    def test_future_round_report_cannot_reuse_legacy_version(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(
            repo / PACKAGE / "整改轮次/R01/02-Grok整改报告.md",
            identity_md("r2", head, "写入状态：已停止"),
        )
        write(
            repo / PACKAGE / "整改轮次/R01/03-Codex复验报告.md",
            identity_md("r3", head, "本轮复验不通过，必须创建下一整改轮次。"),
        )
        write(repo / PACKAGE / "整改轮次/R02/01-Codex整改定稿.md", identity_md("r02a", head))
        write(
            repo / PACKAGE / "整改轮次/R02/02-Grok整改报告.md",
            identity_md("r02b", head, "写入状态：已停止"),
        )
        self._upgrade(
            repo,
            "MAIC-1.1",
            {
                "MAIC-1.0": [
                    "01.md",
                    "03.md",
                    "04.md",
                    "05.md",
                    "06.md",
                    "07.md",
                    "09.md",
                    "整改轮次/R01/01-Codex整改定稿.md",
                    "整改轮次/R01/02-Grok整改报告.md",
                    "整改轮次/R01/03-Codex复验报告.md",
                    "整改轮次/R02/01-Codex整改定稿.md",
                ]
            },
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("整改轮次/R02/02-Grok整改报告.md", result.stdout)
        self.assertIn("方法版本不符", result.stdout)

    def test_legacy_mapping_type_error_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["checker"]["legacyArtifactMethodVersions"] = []
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("legacyArtifactMethodVersions", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_legacy_absolute_path_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["checker"]["legacyArtifactMethodVersions"] = {"MAIC-0.9": ["/tmp/01.md"]}
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("绝对路径", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_legacy_parent_path_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["checker"]["legacyArtifactMethodVersions"] = {"MAIC-0.9": ["../01.md"]}
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("路径无效", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_legacy_empty_path_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["checker"]["legacyArtifactMethodVersions"] = {"MAIC-0.9": [""]}
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("空路径", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_legacy_duplicate_path_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["checker"]["legacyArtifactMethodVersions"] = {"MAIC-0.9": ["01.md", "01.md"]}
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("重复路径", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_legacy_current_version_listed_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["checker"]["legacyArtifactMethodVersions"] = {"MAIC-1.0": ["01.md"]}
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("不得回列当前版本", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_accepted_baseline_is_phase_8_without_authority(self) -> None:
        repo = self.keep(make_repo(7))
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "8")
        self.assert_no_execution_authority(payload)

    def test_rnn_pending_executor_is_7s_without_authority(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        round_dir = repo / PACKAGE / "整改轮次/R01"
        write(round_dir / "01-Codex整改定稿.md", identity_md("r1", head))
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "7S")
        self.assert_no_execution_authority(payload)

    def test_rnn_pending_review_is_7t_without_authority(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        round_dir = repo / PACKAGE / "整改轮次/R01"
        write(round_dir / "01-Codex整改定稿.md", identity_md("r1", head))
        write(round_dir / "02-Grok整改报告.md", identity_md("r2", head, "写入状态：已停止"))
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "7T")
        self.assert_no_execution_authority(payload)

    def test_text_output_states_no_execution_authority(self) -> None:
        repo = self.keep(make_repo(3))
        result = invoke(repo, fmt="text")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("\n" + AUTHORIZATION_NOTE + "\n", "\n" + result.stdout)

    def _phase1_legacy(self) -> list[str]:
        return ["01.md", "03.md", "04.md", "05.md"]

    def test_dual_legacy_exact_paths_remain_valid(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(
            repo / PACKAGE / "整改轮次/R01/02-Grok整改报告.md",
            identity_md("r2", head, "写入状态：已停止"),
        )
        write(
            repo / PACKAGE / "整改轮次/R01/03-Codex复验报告.md",
            identity_md("r3", head, "本轮复验不通过，必须创建下一整改轮次。"),
        )
        write(repo / PACKAGE / "整改轮次/R02/01-Codex整改定稿.md", identity_md("r02a", head))
        write(
            repo / PACKAGE / "整改轮次/R02/02-Grok整改报告.md",
            identity_md("r02b", head, "写入状态：已停止", version="MAIC-1.1"),
        )
        write(
            repo / PACKAGE / "整改轮次/R02/03-Codex复验报告.md",
            identity_md("r02c", head, "本轮复验不通过，必须创建下一整改轮次。", version="MAIC-1.1"),
        )
        write(
            repo / PACKAGE / "整改轮次/R03/01-Codex整改定稿.md",
            identity_md("r03a", head, version="MAIC-1.1"),
        )
        self._upgrade(
            repo,
            "MAIC-1.2",
            {
                "MAIC-1.0": self._phase1_legacy()
                + [
                    "06.md",
                    "07.md",
                    "09.md",
                    "整改轮次/R01/01-Codex整改定稿.md",
                    "整改轮次/R01/02-Grok整改报告.md",
                    "整改轮次/R01/03-Codex复验报告.md",
                    "整改轮次/R02/01-Codex整改定稿.md",
                ],
                "MAIC-1.1": [
                    "整改轮次/R02/02-Grok整改报告.md",
                    "整改轮次/R02/03-Codex复验报告.md",
                    "整改轮次/R03/01-Codex整改定稿.md",
                ],
            },
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["methodVersion"], "MAIC-1.2")
        self.assertEqual(payload["nextPhase"], "7S")
        self.assert_no_execution_authority(payload)

    def test_unlisted_1_1_path_exits_chain(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(
            repo / PACKAGE / "整改轮次/R01/02-Grok整改报告.md",
            identity_md("r2", head, "写入状态：已停止"),
        )
        write(
            repo / PACKAGE / "整改轮次/R01/03-Codex复验报告.md",
            identity_md("r3", head, "本轮复验不通过，必须创建下一整改轮次。"),
        )
        write(
            repo / PACKAGE / "整改轮次/R02/01-Codex整改定稿.md",
            identity_md("r02a", head, version="MAIC-1.1"),
        )
        self._upgrade(
            repo,
            "MAIC-1.2",
            {
                "MAIC-1.0": self._phase1_legacy()
                + [
                    "06.md",
                    "07.md",
                    "09.md",
                    "整改轮次/R01/01-Codex整改定稿.md",
                    "整改轮次/R01/02-Grok整改报告.md",
                    "整改轮次/R01/03-Codex复验报告.md",
                ],
                "MAIC-1.1": ["整改轮次/R02/02-Grok整改报告.md"],
            },
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("整改轮次/R02/01-Codex整改定稿.md", result.stdout)
        self.assertIn("方法版本不符", result.stdout)

    def test_future_report_cannot_reuse_1_1(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(
            repo / PACKAGE / "整改轮次/R01/02-Grok整改报告.md",
            identity_md("r2", head, "写入状态：已停止"),
        )
        write(
            repo / PACKAGE / "整改轮次/R01/03-Codex复验报告.md",
            identity_md("r3", head, "本轮复验不通过，必须创建下一整改轮次。"),
        )
        write(
            repo / PACKAGE / "整改轮次/R02/01-Codex整改定稿.md",
            identity_md("r02a", head, version="MAIC-1.1"),
        )
        write(
            repo / PACKAGE / "整改轮次/R02/02-Grok整改报告.md",
            identity_md("r02b", head, "写入状态：已停止", version="MAIC-1.1"),
        )
        self._upgrade(
            repo,
            "MAIC-1.2",
            {
                "MAIC-1.0": self._phase1_legacy()
                + [
                    "06.md",
                    "07.md",
                    "09.md",
                    "整改轮次/R01/01-Codex整改定稿.md",
                    "整改轮次/R01/02-Grok整改报告.md",
                    "整改轮次/R01/03-Codex复验报告.md",
                ],
                "MAIC-1.1": ["整改轮次/R02/01-Codex整改定稿.md"],
            },
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("整改轮次/R02/02-Grok整改报告.md", result.stdout)
        self.assertIn("方法版本不符", result.stdout)

    def test_legacy_prefix_does_not_validate_children(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(
            repo / PACKAGE / "整改轮次/R01/02-Grok整改报告.md",
            identity_md("r2", head, "写入状态：已停止"),
        )
        write(
            repo / PACKAGE / "整改轮次/R01/03-Codex复验报告.md",
            identity_md("r3", head, "本轮复验不通过，必须创建下一整改轮次。"),
        )
        write(
            repo / PACKAGE / "整改轮次/R02/01-Codex整改定稿.md",
            identity_md("r02a", head, version="MAIC-1.1"),
        )
        self._upgrade(
            repo,
            "MAIC-1.2",
            {
                "MAIC-1.0": self._phase1_legacy()
                + [
                    "06.md",
                    "07.md",
                    "09.md",
                    "整改轮次/R01/01-Codex整改定稿.md",
                    "整改轮次/R01/02-Grok整改报告.md",
                    "整改轮次/R01/03-Codex复验报告.md",
                ],
                "MAIC-1.1": ["整改轮次/R02"],
            },
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("方法版本不符", result.stdout)

    def test_legacy_version_key_mash_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["methodVersion"] = "MAIC-1.2"
        write(repo / "ZL00_项目总控/04-双AI协作与独立审计.md", "方法版本：MAIC-1.2\n")
        data["checker"]["legacyArtifactMethodVersions"] = {
            "MAIC-1.0,MAIC-1.1": ["01.md"],
        }
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("键必须是 MAIC- 版本字符串", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_dual_legacy_current_version_listed_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["methodVersion"] = "MAIC-1.2"
        write(repo / "ZL00_项目总控/04-双AI协作与独立审计.md", "方法版本：MAIC-1.2\n")
        data["checker"]["legacyArtifactMethodVersions"] = {
            "MAIC-1.0": ["01.md"],
            "MAIC-1.2": ["03.md"],
        }
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("不得回列当前版本", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_dual_legacy_damaged_mapping_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["methodVersion"] = "MAIC-1.2"
        write(repo / "ZL00_项目总控/04-双AI协作与独立审计.md", "方法版本：MAIC-1.2\n")
        data["checker"]["legacyArtifactMethodVersions"] = {
            "MAIC-1.0": ["01.md"],
            "MAIC-1.1": "整改轮次/R02/02-Grok整改报告.md",
        }
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("必须是数组", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    CONTROL_HEADINGS = [
        "## 黑盒规程（不依赖本对话）",
        "## 正向命中",
        "## 不应误触发",
        "## 加载边界",
    ]
    SAMPLE_INVARIANT = {
        "path": "01.md",
        "uniqueExactLines": [
            "## 黑盒规程（不依赖本对话）",
            "## 正向命中",
            "## 不应误触发",
            "## 加载边界",
        ],
        "forbiddenSubstrings": [
            "R02 的外部重测必须由 Codex 在 7T 独立组织",
            "R02 的独立重测尚未执行",
        ],
    }

    def _wakeup_doc(self, extra: str = "", skip: str | None = None, duplicate: str | None = None) -> str:
        parts = []
        for heading in self.CONTROL_HEADINGS:
            if heading == skip:
                continue
            parts.append(f"{heading}\n\n正文\n")
            if heading == duplicate:
                parts.append(f"{heading}\n\n重复\n")
        return "\n".join(parts) + extra

    def _write_wakeup_doc(self, repo: Path, extra: str = "", skip: str | None = None, duplicate: str | None = None) -> Path:
        head = run_git(repo, "rev-parse", "HEAD")
        target = repo / PACKAGE / "01.md"
        write(target, identity_md("p1", head, self._wakeup_doc(extra, skip, duplicate)))
        return target

    def _set_invariants(self, repo: Path, rules: list) -> None:
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["checker"]["documentInvariants"] = rules
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))

    def test_empty_document_invariants_keep_phase(self) -> None:
        repo = self.keep(make_repo(3))
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "4")
        self.assertEqual(
            json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
            ["checker"]["documentInvariants"],
            [],
        )

    def test_package_like_invariants_pass(self) -> None:
        repo = self.keep(make_repo(3))
        self._write_wakeup_doc(repo)
        self._set_invariants(repo, [self.SAMPLE_INVARIANT])
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["nextPhase"], "4")

    def test_duplicate_control_heading_exits_chain(self) -> None:
        repo = self.keep(make_repo(3))
        target = self._write_wakeup_doc(repo, duplicate="## 正向命中")
        self._set_invariants(repo, [self.SAMPLE_INVARIANT])
        before = target.read_text(encoding="utf-8")
        contract_before = (repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8")
        result = invoke(repo)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("文档不变量失败", result.stdout)
        self.assertIn("uniqueExactLines:## 正向命中", result.stdout)
        self.assertEqual(target.read_text(encoding="utf-8"), before)
        self.assertEqual((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"), contract_before)

    def test_missing_control_heading_exits_chain(self) -> None:
        repo = self.keep(make_repo(3))
        self._write_wakeup_doc(repo, skip="## 加载边界")
        self._set_invariants(repo, [self.SAMPLE_INVARIANT])
        result = invoke(repo)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("uniqueExactLines:## 加载边界", result.stdout)
        self.assertIn("出现0次", result.stdout)

    def test_forbidden_substring_exits_chain(self) -> None:
        repo = self.keep(make_repo(3))
        self._write_wakeup_doc(repo, extra="\nR02 的独立重测尚未执行\n")
        self._set_invariants(repo, [self.SAMPLE_INVARIANT])
        result = invoke(repo)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("forbiddenSubstrings:R02 的独立重测尚未执行", result.stdout)

    def test_invariant_target_missing_exits_chain(self) -> None:
        repo = self.keep(make_repo(3))
        self._set_invariants(
            repo,
            [{
                "path": "00A-压力测试样本.md",
                "uniqueExactLines": ["## 黑盒规程（不依赖本对话）"],
                "forbiddenSubstrings": [],
            }],
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("文件不存在", result.stdout)

    def test_document_invariants_type_error_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        self._set_invariants(repo, {"path": "01.md"})
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("documentInvariants 必须是数组", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_document_invariants_empty_rule_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        self._set_invariants(
            repo,
            [{"path": "01.md", "uniqueExactLines": [""], "forbiddenSubstrings": []}],
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("空规则", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_document_invariants_illegal_path_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        self._set_invariants(
            repo,
            [{"path": "/tmp/01.md", "uniqueExactLines": ["# x"], "forbiddenSubstrings": []}],
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("绝对路径", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_document_invariants_duplicate_path_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        item = {"path": "01.md", "uniqueExactLines": ["# x"], "forbiddenSubstrings": []}
        self._set_invariants(repo, [item, dict(item)])
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("重复路径", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_document_invariants_duplicate_rule_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        self._set_invariants(
            repo,
            [{
                "path": "01.md",
                "uniqueExactLines": ["# x", "# x"],
                "forbiddenSubstrings": [],
            }],
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("重复规则", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_triple_legacy_1_2_exact_path_valid(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(
            repo / PACKAGE / "整改轮次/R01/02-Grok整改报告.md",
            identity_md("r2", head, "写入状态：已停止"),
        )
        write(
            repo / PACKAGE / "整改轮次/R01/03-Codex复验报告.md",
            identity_md("r3", head, "本轮复验不通过，必须创建下一整改轮次。"),
        )
        write(repo / PACKAGE / "整改轮次/R02/01-Codex整改定稿.md", identity_md("r02a", head))
        write(
            repo / PACKAGE / "整改轮次/R02/02-Grok整改报告.md",
            identity_md("r02b", head, "写入状态：已停止", version="MAIC-1.1"),
        )
        write(
            repo / PACKAGE / "整改轮次/R02/03-Codex复验报告.md",
            identity_md("r02c", head, "本轮复验不通过，必须创建下一整改轮次。", version="MAIC-1.1"),
        )
        write(
            repo / PACKAGE / "整改轮次/R03/01-Codex整改定稿.md",
            identity_md("r03a", head, version="MAIC-1.1"),
        )
        write(
            repo / PACKAGE / "整改轮次/R03/02-Grok整改报告.md",
            identity_md("r03b", head, "写入状态：已停止", version="MAIC-1.2"),
        )
        write(
            repo / PACKAGE / "整改轮次/R03/03-Codex复验报告.md",
            identity_md("r03c", head, "本轮复验不通过，必须创建下一整改轮次。", version="MAIC-1.2"),
        )
        write(
            repo / PACKAGE / "整改轮次/R04/01-Codex整改定稿.md",
            identity_md("r04a", head, version="MAIC-1.2"),
        )
        self._upgrade(
            repo,
            "MAIC-1.3",
            {
                "MAIC-1.0": self._phase1_legacy()
                + [
                    "06.md",
                    "07.md",
                    "09.md",
                    "整改轮次/R01/01-Codex整改定稿.md",
                    "整改轮次/R01/02-Grok整改报告.md",
                    "整改轮次/R01/03-Codex复验报告.md",
                    "整改轮次/R02/01-Codex整改定稿.md",
                ],
                "MAIC-1.1": [
                    "整改轮次/R02/02-Grok整改报告.md",
                    "整改轮次/R02/03-Codex复验报告.md",
                    "整改轮次/R03/01-Codex整改定稿.md",
                ],
                "MAIC-1.2": [
                    "整改轮次/R03/02-Grok整改报告.md",
                    "整改轮次/R03/03-Codex复验报告.md",
                    "整改轮次/R04/01-Codex整改定稿.md",
                ],
            },
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["methodVersion"], "MAIC-1.3")
        self.assertEqual(payload["nextPhase"], "7S")

    def test_unlisted_1_2_path_exits_chain(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(
            repo / PACKAGE / "整改轮次/R01/02-Grok整改报告.md",
            identity_md("r2", head, "写入状态：已停止"),
        )
        write(
            repo / PACKAGE / "整改轮次/R01/03-Codex复验报告.md",
            identity_md("r3", head, "本轮复验不通过，必须创建下一整改轮次。"),
        )
        write(
            repo / PACKAGE / "整改轮次/R02/01-Codex整改定稿.md",
            identity_md("r02a", head, version="MAIC-1.2"),
        )
        self._upgrade(
            repo,
            "MAIC-1.3",
            {
                "MAIC-1.0": self._phase1_legacy()
                + [
                    "06.md",
                    "07.md",
                    "09.md",
                    "整改轮次/R01/01-Codex整改定稿.md",
                    "整改轮次/R01/02-Grok整改报告.md",
                    "整改轮次/R01/03-Codex复验报告.md",
                ],
                "MAIC-1.1": [],
                "MAIC-1.2": ["整改轮次/R03/02-Grok整改报告.md"],
            },
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("整改轮次/R02/01-Codex整改定稿.md", result.stdout)
        self.assertIn("方法版本不符", result.stdout)

    def test_future_report_cannot_reuse_1_2(self) -> None:
        repo = self.keep(make_repo(7))
        head = run_git(repo, "rev-parse", "HEAD")
        write(repo / PACKAGE / "09.md", identity_md("fail", head, FAIL))
        write(repo / PACKAGE / "整改轮次/R01/01-Codex整改定稿.md", identity_md("r1", head))
        write(
            repo / PACKAGE / "整改轮次/R01/02-Grok整改报告.md",
            identity_md("r2", head, "写入状态：已停止"),
        )
        write(
            repo / PACKAGE / "整改轮次/R01/03-Codex复验报告.md",
            identity_md("r3", head, "本轮复验不通过，必须创建下一整改轮次。"),
        )
        write(
            repo / PACKAGE / "整改轮次/R02/01-Codex整改定稿.md",
            identity_md("r02a", head, version="MAIC-1.2"),
        )
        write(
            repo / PACKAGE / "整改轮次/R02/02-Grok整改报告.md",
            identity_md("r02b", head, "写入状态：已停止", version="MAIC-1.2"),
        )
        self._upgrade(
            repo,
            "MAIC-1.3",
            {
                "MAIC-1.0": self._phase1_legacy()
                + [
                    "06.md",
                    "07.md",
                    "09.md",
                    "整改轮次/R01/01-Codex整改定稿.md",
                    "整改轮次/R01/02-Grok整改报告.md",
                    "整改轮次/R01/03-Codex复验报告.md",
                ],
                "MAIC-1.2": ["整改轮次/R02/01-Codex整改定稿.md"],
            },
        )
        result = invoke(repo)
        self.assertEqual(result.returncode, 3)
        self.assertIn("整改轮次/R02/02-Grok整改报告.md", result.stdout)
        self.assertIn("方法版本不符", result.stdout)

    def test_legacy_1_3_current_listed_exits_input(self) -> None:
        repo = self.keep(make_repo(3))
        data = json.loads((repo / PACKAGE / "00C-任务契约.json").read_text(encoding="utf-8"))
        data["methodVersion"] = "MAIC-1.3"
        write(repo / "ZL00_项目总控/04-双AI协作与独立审计.md", "方法版本：MAIC-1.3\n")
        data["checker"]["legacyArtifactMethodVersions"] = {"MAIC-1.3": ["01.md"]}
        write(repo / PACKAGE / "00C-任务契约.json", json.dumps(data, ensure_ascii=False, indent=2))
        result = invoke(repo)
        self.assertEqual(result.returncode, 2)
        self.assertIn("不得回列当前版本", result.stdout)
        self.assertNotIn("Traceback", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
