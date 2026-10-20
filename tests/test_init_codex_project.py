"""Run with python3 -m unittest discover -s tests -v; requires Bash and Node.js.

npm, npx and OpenSpec are replaced with local stubs; no packages are installed.
"""

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "init-codex-project.sh"
STUB = r'''
import json
import os
from pathlib import Path
import shutil
import sys

sys.argv = sys.argv[1:]
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["INIT_TEST_CALLS"], "a") as log:
    log.write(json.dumps([tool, *args]) + "\n")

config_path = Path(os.environ["INIT_TEST_CONFIG"])
config = json.loads(config_path.read_text())
if tool == "node":
    if args == ["--version"]:
        print("v" + os.environ["INIT_TEST_NODE_VERSION"])
    elif "backup" in args and config.get("fail_backup"):
        print("injected backup failure", file=sys.stderr)
        sys.exit(1)
    else:
        actual = os.environ["INIT_TEST_REAL_NODE"]
        os.execv(actual, [actual, "--require", os.environ["INIT_TEST_NODE_PRELOAD"], *args])
elif tool == "npm":
    if args == ["--version"]:
        print("test-npm")
    elif args[:2] == ["install", "-g"]:
        if config.get("fail_install"):
            sys.exit(1)
        config["installed_version"] = config.get("installed_after", "1.14.3")
        if config.get("delivery_after"):
            config["delivery"] = config["delivery_after"]
        config_path.write_text(json.dumps(config))
        shutil.copy2(os.environ["INIT_TEST_OPEN_SPEC_LAUNCHER"], Path(sys.argv[0]).parent / "openspec")
elif tool == "npx":
    if config.get("fail_skills_preserved"):
        print("Failed to install: existing skill left unchanged", file=sys.stderr)
        sys.exit(1 if "--json" in args else 0)
    lock_path = Path("skills-lock.json")
    lock = json.loads(lock_path.read_text()) if lock_path.exists() else {"version": 1, "skills": {}}
    for i, arg in enumerate(args):
        if arg == "--skill":
            if args[i + 1] == config.get("missing_source_skill"):
                continue
            target = Path(".agents/skills") / args[i + 1]
            if target.exists():
                shutil.rmtree(target)
            target.mkdir(parents=True)
            (target / "SKILL.md").write_text("installed skill\n")
            lock["skills"][target.name] = {"source": "mattpocock/skills", "ref": "5beb35b040e3de97e54fa9e386d7e42d15c295c2"}
            lock_path.write_text(json.dumps(lock))
            if config.get("fail_skills"):
                sys.exit(1)
    if config.get("missing_source_skill") and "--json" in args:
        print("Requested skill not found in source", file=sys.stderr)
        sys.exit(1)
elif tool == "openspec":
    config = json.loads(Path(os.environ["INIT_TEST_CONFIG"]).read_text())
    if args == ["--version"]:
        if config.get("fail_version"):
            sys.exit(1)
        print(config["installed_version"])
    elif args[:2] == ["config", "get"]:
        key = args[2]
        if key == config.get("fail_read"):
            sys.exit(1)
        value = config.get(key)
        print(json.dumps(value) if isinstance(value, (list, dict)) or value is None else value)
    elif args[0] in ("init", "update"):
        Path("openspec").mkdir(exist_ok=True)
        Path("openspec/config.yaml").write_text("schema: spec-driven\n")
        workflows = ["propose", "apply", "archive"]
        if args[0] == "update" and config["profile"] == "custom":
            workflows = config["workflows"]
        names = {"propose": "openspec-propose", "apply": "openspec-apply-change",
                 "archive": "openspec-archive-change", "explore": "openspec-explore"}
        for workflow, name in names.items():
            target = Path(".agents/skills") / name
            if workflow in workflows:
                target.mkdir(parents=True, exist_ok=True)
                (target / "SKILL.md").write_text("generated OpenSpec skill\n")
            elif target.exists():
                shutil.rmtree(target)
    elif args != ["list"]:
        sys.exit(1)
'''


class InitializerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codex-init-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        self.project.mkdir()
        self.config = self.root / "config.json"
        self.calls = self.root / "calls.jsonl"
        self.configure()
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        stub = self.root / "stub.py"
        stub.write_text(STUB)
        for name in ("npm", "npx", "openspec", "node"):
            executable = bin_dir / name
            executable.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable)
                                  + " " + shlex.quote(str(stub)) + ' "$0" "$@"\n')
            executable.chmod(0o755)
        launcher = self.root / "openspec-launcher"
        shutil.copy2(bin_dir / "openspec", launcher)
        preload = self.root / "node-version.cjs"
        preload.write_text("Object.defineProperty(process.versions, 'node', "
                           "{value: process.env.INIT_TEST_NODE_VERSION});\n")
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + "/usr/bin:/bin:/usr/sbin:/sbin",
                        INIT_TEST_CONFIG=str(self.config), INIT_TEST_CALLS=str(self.calls),
                        INIT_TEST_REAL_NODE=shutil.which("node"), INIT_TEST_NODE_VERSION="22.20.0",
                        INIT_TEST_NODE_PRELOAD=str(preload), INIT_TEST_OPEN_SPEC_LAUNCHER=str(launcher))

    def configure(self, **changes):
        config = {"delivery": "both", "profile": "core", "installed_version": "1.14.3"}
        config.update(changes)
        self.config.write_text(json.dumps(config))

    def run_script(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], cwd=self.project, env=self.env,
                              capture_output=True, text=True, timeout=20)

    def initialize(self, *args):
        result = self.run_script(*args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def snapshot(self):
        return {str(p.relative_to(self.project)): p.read_bytes()
                for p in self.project.rglob("*") if p.is_file()}

    def assert_update_blocked(self, **config):
        self.initialize()
        before = self.snapshot()
        self.calls.write_text("")
        self.configure(**config)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertFalse(any(call[:2] == ["openspec", "update"] for call in calls))
        self.assertFalse(any(call[0] == "npx" for call in calls))

    def test_fresh_initialization(self):
        self.assertIn("STATUS: INITIALIZED, NOT READY FOR DEVELOPMENT", self.initialize().stdout)
        self.assertEqual(len(list(self.project.glob(".agents/skills/*/SKILL.md"))), 12)

    def test_repeat_preserves_custom_skill_and_document(self):
        self.initialize()
        skill = self.project / ".agents/skills/tdd/SKILL.md"
        document = self.project / "AGENTS.md"
        skill.write_text("custom skill\n")
        document.write_text("custom rules\n")
        self.calls.write_text("")
        self.initialize()
        self.assertEqual(skill.read_text(), "custom skill\n")
        self.assertEqual(document.read_text(), "custom rules\n")
        self.assertNotIn('"npx"', self.calls.read_text())
        self.assertNotIn('["npm", "install"', self.calls.read_text())

    def test_only_missing_skills_installed(self):
        target = self.project / ".agents/skills/tdd"
        target.mkdir(parents=True)
        (target / "SKILL.md").write_text("custom skill\n")
        self.initialize()
        self.assertEqual((target / "SKILL.md").read_text(), "custom skill\n")
        self.assertTrue((self.project / ".agents/skills/code-review/SKILL.md").is_file())

    def test_incomplete_custom_profile_blocked(self):
        self.assert_update_blocked(profile="custom", workflows=["explore"])

    def test_invalid_custom_workflows_blocked(self):
        self.assert_update_blocked(profile="custom", workflows="not-json")

    def test_unknown_profile_blocked(self):
        self.assert_update_blocked(profile="unknown")

    def test_profile_read_failure_blocked(self):
        self.assert_update_blocked(fail_read="profile")

    def test_workflows_read_failure_blocked(self):
        self.assert_update_blocked(profile="custom", fail_read="workflows")

    def test_commands_delivery_blocked(self):
        self.assert_update_blocked(delivery="commands")

    def test_complete_custom_profile_allowed(self):
        self.initialize()
        self.configure(profile="custom", workflows=["propose", "apply", "archive"])
        self.initialize()

    def test_dangling_skill_link_preserved_and_reported(self):
        target = self.project / ".agents/skills/tdd"
        target.parent.mkdir(parents=True)
        destination = self.root / "absent"
        target.symlink_to(destination, target_is_directory=True)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(target.is_symlink())
        self.assertFalse(destination.exists())
        self.assertIn("Missing Matt Pocock skill: .agents/skills/tdd/SKILL.md", result.stdout)

    def assert_no_mutations_called(self):
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        self.assertFalse(any(call[:2] in (["npm", "install"], ["openspec", "init"],
                                         ["openspec", "update"]) or call[0] == "npx" for call in calls))

    def test_node_minimum_before_any_mutation(self):
        for version in ("20.19.0", "22.17.0", "22.19.0"):
            with self.subTest(version=version):
                self.env["INIT_TEST_NODE_VERSION"] = version
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("22.20.0", result.stdout + result.stderr)
                self.assert_no_mutations_called()
                self.assertEqual(list(self.project.iterdir()), [])

    def test_higher_node_supported(self):
        self.env["INIT_TEST_NODE_VERSION"] = "24.21.0"
        self.initialize()

    def test_help_without_runtime(self):
        (self.root / "bin/node").unlink()
        result = self.run_script("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--upgrade", result.stdout)
        self.assert_no_mutations_called()
        self.assertEqual(list(self.project.iterdir()), [])

    def test_unknown_argument_before_mutation(self):
        result = self.run_script("--unknown")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_mutations_called()

    def test_old_openspec_requires_upgrade(self):
        self.configure(installed_version="1.14.1")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--upgrade", result.stdout + result.stderr)
        self.assert_no_mutations_called()

    def test_newer_openspec_is_not_downgraded(self):
        self.configure(installed_version="1.15.0")
        self.initialize("--upgrade")
        self.assertNotIn('["npm", "install"', self.calls.read_text())
        self.assertEqual(json.loads(self.config.read_text())["installed_version"], "1.15.0")

    def test_missing_openspec_installs_fixed_version(self):
        (self.root / "bin/openspec").unlink()
        self.initialize()
        self.assertIn('@fission-ai/openspec@1.14.3', self.calls.read_text())
        self.assertNotIn('@latest', self.calls.read_text())
        self.assertIn('skills@1.7.4', self.calls.read_text())
        self.assertIn('/tree/5beb35b040e3de97e54fa9e386d7e42d15c295c2', self.calls.read_text())

    def test_invalid_openspec_version_stops(self):
        for version in ("unparseable", "1.14.3-rc.1", ""):
            with self.subTest(version=version):
                self.configure(installed_version=version)
                result = self.run_script("--upgrade")
                self.assertNotEqual(result.returncode, 0)
                self.assert_no_mutations_called()

    def test_openspec_version_read_failure_stops(self):
        self.configure(fail_version=True)
        self.assertNotEqual(self.run_script("--upgrade").returncode, 0)
        self.assert_no_mutations_called()

    def test_upgrade_backs_up_and_preserves_other_skills(self):
        self.initialize()
        skill = self.project / ".agents/skills/tdd/SKILL.md"
        skill.write_text("custom TDD\n")
        other = self.project / ".agents/skills/other/SKILL.md"
        other.parent.mkdir()
        other.write_text("other source\n")
        lock = self.project / "skills-lock.json"
        data = json.loads(lock.read_text())
        data["skills"]["other"] = {"source": "someone/else"}
        lock.write_text(json.dumps(data))
        old_lock = lock.read_bytes()
        self.configure(installed_version="1.14.1")
        self.initialize("--upgrade")
        backups = list((self.project / ".init-codex-backups").iterdir())
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / ".agents/skills/tdd/SKILL.md").read_text(), "custom TDD\n")
        self.assertEqual((backups[0] / "skills-lock.json").read_bytes(), old_lock)
        self.assertTrue((backups[0] / "manifest.json").is_file())
        self.assertEqual(skill.read_text(), "installed skill\n")
        self.assertEqual(other.read_text(), "other source\n")
        self.assertEqual(json.loads(lock.read_text())["skills"]["other"], data["skills"]["other"])
        self.assertEqual(json.loads(self.config.read_text())["installed_version"], "1.14.3")
        self.initialize("--upgrade")
        self.assertEqual(len(list((self.project / ".init-codex-backups").iterdir())), 2)
        self.assertEqual((backups[0] / ".agents/skills/tdd/SKILL.md").read_text(), "custom TDD\n")

    def test_backup_failure_prevents_all_changes(self):
        self.initialize()
        before = self.snapshot()
        self.configure(installed_version="1.14.1", fail_backup=True)
        self.calls.write_text("")
        self.assertNotEqual(self.run_script("--upgrade").returncode, 0)
        self.assert_no_mutations_called()
        self.assertEqual(self.snapshot(), before)

    def test_upgrade_rejects_symlink_paths(self):
        for relative in (".agents", ".agents/skills", ".agents/skills/tdd",
                         "skills-lock.json", ".init-codex-backups"):
            with self.subTest(path=relative):
                target = self.project / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(self.root / "absent")
                self.assertNotEqual(self.run_script("--upgrade").returncode, 0)
                self.assertTrue(target.is_symlink())
                self.assert_no_mutations_called()
                target.unlink()

    def test_foreign_source_conflict_preserved(self):
        self.initialize()
        lock = self.project / "skills-lock.json"
        data = json.loads(lock.read_text())
        data["skills"]["tdd"]["source"] = "someone/else"
        lock.write_text(json.dumps(data))
        before = self.snapshot()
        self.calls.write_text("")
        self.assertNotEqual(self.run_script("--upgrade").returncode, 0)
        self.assertEqual(self.snapshot(), before)
        self.assert_no_mutations_called()

    def test_invalid_lock_blocks_upgrade(self):
        (self.project / "skills-lock.json").write_text("{broken")
        self.assertNotEqual(self.run_script("--upgrade").returncode, 0)
        self.assert_no_mutations_called()

    def test_configuration_checked_before_global_upgrade(self):
        self.initialize()
        self.configure(installed_version="1.14.1", profile="custom", workflows=["explore"])
        self.calls.write_text("")
        before = self.snapshot()
        self.assertNotEqual(self.run_script("--upgrade").returncode, 0)
        self.assertEqual(self.snapshot(), before)
        self.assert_no_mutations_called()

    def test_configuration_rechecked_after_install(self):
        self.configure(installed_version="1.14.1", delivery_after="commands")
        result = self.run_script("--upgrade")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('["openspec", "init"', self.calls.read_text())
        self.assertNotIn('"npx"', self.calls.read_text())
        self.assertIn("Global OpenSpec", result.stdout + result.stderr)

    def test_partial_skills_failure_retains_backup(self):
        self.initialize()
        skill = self.project / ".agents/skills/tdd/SKILL.md"
        skill.write_text("custom TDD\n")
        self.configure(fail_skills=True)
        result = self.run_script("--upgrade")
        self.assertNotEqual(result.returncode, 0)
        backups = list((self.project / ".init-codex-backups").iterdir())
        self.assertEqual((backups[0] / ".agents/skills/tdd/SKILL.md").read_text(), "custom TDD\n")
        self.assertIn(str(backups[0]), result.stdout + result.stderr)
        self.assertNotIn("STATUS: READY", result.stdout)

    def test_failed_install_with_old_skill_remaining_is_not_success(self):
        self.initialize()
        skill = self.project / ".agents/skills/tdd/SKILL.md"
        skill.write_text("old customized skill\n")
        self.configure(fail_skills_preserved=True)
        result = self.run_script("--upgrade")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(skill.read_text(), "old customized skill\n")
        backup = next((self.project / ".init-codex-backups").iterdir())
        self.assertEqual((backup / ".agents/skills/tdd/SKILL.md").read_text(), "old customized skill\n")
        self.assertIn("Matt Pocock skill installation", result.stderr)
        self.assertNotIn("STATUS:", result.stdout)

    def test_partial_source_selection_failure_is_not_success(self):
        self.initialize()
        skill = self.project / ".agents/skills/tdd/SKILL.md"
        skill.write_text("old customized skill\n")
        self.configure(missing_source_skill="tdd")
        result = self.run_script("--upgrade")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(skill.read_text(), "old customized skill\n")
        self.assertIn("Requested skill not found", result.stderr)
        self.assertNotIn("STATUS:", result.stdout)

    def test_installed_openspec_version_mismatch_stops(self):
        self.configure(installed_version="1.14.1", installed_after="1.14.2")
        result = self.run_script("--upgrade")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('"npx"', self.calls.read_text())

    def test_failed_global_install_reports_possible_changes(self):
        self.configure(installed_version="1.14.1", fail_install=True)
        result = self.run_script("--upgrade")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Global OpenSpec installation was attempted", result.stderr)
        self.assertNotIn('["openspec", "init"', self.calls.read_text())
        self.assertNotIn('"npx"', self.calls.read_text())

    @unittest.skipUnless(hasattr(os, "mkfifo"), "Requires POSIX FIFO support")
    def test_partial_backup_is_not_a_restore_point(self):
        target = self.project / ".agents/skills/tdd"
        target.mkdir(parents=True)
        (target / "SKILL.md").write_text("custom TDD\n")
        os.mkfifo(target / "unsupported-fifo")
        self.configure(installed_version="1.14.1")
        result = self.run_script("--upgrade")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Backup is incomplete", result.stderr)
        self.assert_no_mutations_called()
        self.assertEqual((target / "SKILL.md").read_text(), "custom TDD\n")
        backup = next((self.project / ".init-codex-backups").iterdir())
        self.assertFalse((backup / "manifest.json").exists())
        self.assertIn(str(backup), result.stderr)

    def test_nested_skill_link_backed_up_as_link(self):
        self.initialize()
        external = self.root / "external-reference"
        external.write_text("external content\n")
        link = self.project / ".agents/skills/tdd/reference"
        link.symlink_to(external)
        self.initialize("--upgrade")
        backup = next((self.project / ".init-codex-backups").iterdir())
        saved_link = backup / ".agents/skills/tdd/reference"
        self.assertTrue(saved_link.is_symlink())
        self.assertEqual(os.readlink(saved_link), str(external))
        self.assertEqual(external.read_text(), "external content\n")


if __name__ == "__main__":
    unittest.main()
