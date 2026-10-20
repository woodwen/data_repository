"""Run with python3 -m unittest discover -s tests -v; requires Bash and Node.js.

npm, npx and OpenSpec are replaced with local stubs; no packages are installed.
"""

import json
import os
from pathlib import Path
import shlex
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

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["INIT_TEST_CALLS"], "a") as log:
    log.write(json.dumps([tool, *args]) + "\n")

if tool == "npm":
    if args == ["--version"]:
        print("test-npm")
elif tool == "npx":
    for i, arg in enumerate(args):
        if arg == "--skill":
            target = Path(".agents/skills") / args[i + 1]
            if target.exists():
                shutil.rmtree(target)
            target.mkdir(parents=True)
            (target / "SKILL.md").write_text("installed skill\n")
elif tool == "openspec":
    config = json.loads(Path(os.environ["INIT_TEST_CONFIG"]).read_text())
    if args == ["--version"]:
        print("test-openspec")
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
        for name in ("npm", "npx", "openspec"):
            executable = bin_dir / name
            executable.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable)
                                  + ' - "$0" "$@" <<\'PY\'\n'
                                  + 'import sys\nsys.argv = sys.argv[1:]\n' + STUB + "\nPY\n")
            executable.chmod(0o755)
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ["PATH"],
                        INIT_TEST_CONFIG=str(self.config), INIT_TEST_CALLS=str(self.calls))

    def configure(self, **changes):
        config = {"delivery": "both", "profile": "core"}
        config.update(changes)
        self.config.write_text(json.dumps(config))

    def run_script(self):
        return subprocess.run(["bash", str(SCRIPT)], cwd=self.project, env=self.env,
                              capture_output=True, text=True, timeout=20)

    def initialize(self):
        result = self.run_script()
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


if __name__ == "__main__":
    unittest.main()
