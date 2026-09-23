import copy
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from testing import jev


def response(choice="pass", model="jev-test"):
    return {"success": True, "result": {"state": "Completed", "result": {
        "model": model, "answers": {"contract": {"type": "choice", "choice": choice,
            "probabilities": {key: 0.98 if key == choice else 0.01 for key in jev.CRITERIA}}},
        "usage": {"input_tokens": 100, "output_tokens": 1}}}}


class JevTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.policy = {"minimum_margin": 0.10, "resolved_models": ["jev-test"]}
        self.rows = [{"id": "sample", "deterministic_passed": True,
                      "request": jev.request_for({"source_preserved": True}, "Cancelled", "Identify cancellation.")}]

    def evidence(self):
        directory = self.root / "evidence"
        directory.mkdir()
        for key, spec in jev.read_json(jev.CASES).items():
            jev.write_json(directory / (key + ".json"), {
                "schema": "mkv-magic.workflow-evidence.v1", "id": key,
                "facts": {key: True for key in spec["facts"]}, "explanation": "Synthetic explanation"})
        jev.seal_evidence(directory, jev.source_hashes())
        return directory

    def reseal(self, directory):
        (directory / "manifest.json").unlink()
        return jev.seal_evidence(directory, jev.source_hashes())

    def mock_review(self, rows=None, choice="pass"):
        with patch.object(jev, "credentials", return_value=("a" * 32, "SECRET")), \
                patch.object(jev, "call_jev", return_value=response(choice)):
            return jev.review(rows or self.rows, self.root / "review", policy=self.policy)

    def test_live_pass_fail_and_deterministic_failure(self):
        self.rows[0]["deterministic_passed"] = False
        report = self.mock_review()
        self.assertEqual(report["cases"][0]["decision"], "pass")
        self.assertFalse(report["passed"])
        self.assertFalse(report["release_accepted"])
        self.assertNotIn("SECRET", (self.root / "review/report.json").read_text())

    def test_jevs_failure_is_not_a_pass(self):
        self.assertFalse(self.mock_review(choice="fail")["passed"])

    def test_dry_run_never_authenticates_and_is_not_a_full_pass(self):
        with patch.object(jev, "credentials", side_effect=AssertionError("authentication")):
            report = jev.review(self.rows, self.root / "preview", live=False)
        self.assertFalse(report["passed"])
        self.assertFalse(report["complete"])
        self.assertEqual(report["network_attempts"], 0)

    def test_missing_changed_and_unknown_model_policies_need_review(self):
        answer = response()["result"]["result"]["answers"]["contract"]
        self.assertEqual(jev.decision(answer, "jev-test", None), "review")
        self.assertEqual(jev.decision(answer, "unknown", self.policy), "review")
        answer["probabilities"] = {"pass": 0.51, "fail": 0.48, "uncertain": 0.01}
        self.assertEqual(jev.decision(answer, "jev-test", self.policy), "review")

    def test_malformed_responses_fail_closed(self):
        good = response()
        malformed = [None, {}, {"success": False}, {"result": {"state": "Running"}}]
        for update in ({"answers": {}}, {"usage": {}}, {"model": ""}):
            value = copy.deepcopy(good)
            value["result"]["result"].update(update)
            malformed.append(value)
        for probability in (float("nan"), -0.1, True, 1.1):
            value = copy.deepcopy(good)
            value["result"]["result"]["answers"]["contract"]["probabilities"]["pass"] = probability
            malformed.append(value)
        value = copy.deepcopy(good)
        value["result"]["result"]["answers"]["contract"]["choice"] = "fail"
        malformed.append(value)
        for value in malformed:
            with self.subTest(value=value), self.assertRaises(ValueError):
                jev.parse_response(value)

    def test_service_error_has_no_retry_and_does_not_log_response_details(self):
        error = urllib.error.HTTPError("https://invalid.example/SECRET", 429, "SECRET", {}, None)
        with patch.object(jev, "credentials", return_value=("account", "SECRET")), \
                patch.object(jev, "call_jev", side_effect=error) as call, self.assertRaises(ValueError):
            jev.review(self.rows, self.root / "error", policy=self.policy)
        call.assert_called_once()
        report = (self.root / "error/report.json").read_text()
        self.assertNotIn("SECRET", report)
        self.assertFalse(json.loads(report)["complete"])

    def test_budget_checked_before_credentials(self):
        for budget in (0, float("nan"), 2, 0.000001):
            with self.subTest(budget=budget), patch.object(jev, "credentials", side_effect=AssertionError()), \
                    self.assertRaises(ValueError):
                jev.review(self.rows, self.root / "budget", max_estimated_usd=budget)

    def test_public_registration_covers_actual_exporters(self):
        import re
        exporters = "\n".join(p.read_text() for p in (jev.ROOT / "Tests/MKVMagicAppTests").glob("*.swift"))
        registered = re.findall(r'WorkflowEvidence.record\(\s*"([a-z-]+)"', exporters)
        self.assertEqual(set(registered), set(jev.read_json(jev.CASES)))
        self.assertEqual(len(registered), len(set(registered)))
        calibration = jev.read_json(jev.CALIBRATION)
        self.assertEqual({c["case"] for c in calibration if c["split"] == "calibration"}, set(registered))

    def test_complete_evidence_projects_only_public_fields(self):
        rows = jev.evidence_rows(self.evidence())
        for row in rows:
            self.assertEqual(set(row["request"]["input"]["state"]), {"observed_facts", "candidate_explanation"})
        self.assertNotIn(str(jev.ROOT), json.dumps(rows))

    def test_missing_extra_and_tampered_evidence_are_rejected(self):
        directory = self.evidence()
        sample = directory / "metadata-plan.json"
        sample.write_text(sample.read_text() + " ")
        with self.assertRaisesRegex(ValueError, "changed"):
            jev.evidence_rows(directory)
        sample.unlink()
        with self.assertRaisesRegex(ValueError, "Missing"):
            jev.evidence_rows(directory)
        (directory / "private.json").write_text("{}")
        with self.assertRaises(ValueError):
            jev.evidence_rows(directory)

    def test_private_text_unknown_fields_and_nonbool_facts_are_rejected(self):
        directory = self.evidence()
        sample = directory / "metadata-plan.json"
        original = jev.read_json(sample)
        bad_values = []
        for text in ("/Users/person/Private.mkv", "contact@example.com", "file:///secret", "", "x" * 8001):
            bad = copy.deepcopy(original); bad["explanation"] = text; bad_values.append(bad)
        bad = copy.deepcopy(original); bad["private_path"] = "secret"; bad_values.append(bad)
        bad = copy.deepcopy(original); bad["facts"][next(iter(bad["facts"]))] = "true"; bad_values.append(bad)
        for value in bad_values:
            jev.write_json(sample, value)
            manifest = jev.read_json(directory / "manifest.json")
            manifest["files"][sample.name] = jev.digest(sample.read_bytes())
            jev.write_json(directory / "manifest.json", manifest)
            with self.subTest(value=value), self.assertRaises(ValueError):
                jev.evidence_rows(directory)

    def test_failed_or_stale_provenance_never_becomes_accepted(self):
        directory = self.evidence()
        manifest = jev.read_json(directory / "manifest.json")
        for field, value in (("local_passed", False), ("sources", {}), ("files", None)):
            bad = copy.deepcopy(manifest); bad[field] = value
            jev.write_json(directory / "manifest.json", bad)
            with self.assertRaises(ValueError):
                jev.evidence_rows(directory)

    def test_symlinks_nonregular_files_duplicate_keys_and_nonfinite_json_rejected(self):
        target = self.root / "target.json"; target.write_text("{}")
        link = self.root / "linked.json"; link.symlink_to(target)
        with self.assertRaises(OSError):
            jev.read_json(link)
        with self.assertRaises((OSError, ValueError)):
            jev.read_json(self.root)
        for data in ('{"a": 1, "a": 2}', '{"a": NaN}'):
            target.write_text(data)
            with self.assertRaises(ValueError):
                jev.read_json(target)

    def test_outputs_never_overwrite_prior_review(self):
        existing = self.root / "prior"; existing.mkdir()
        with self.assertRaises(FileExistsError):
            jev.review(self.rows, existing, live=False)

    def test_policy_bootstrap_never_uses_validation_labels(self):
        answer = response()["result"]["result"]["answers"]["contract"]
        row = {**answer, "model": "jev-test", "expected": "pass", "split": "validation"}
        report = {"complete": True, "cases": [row], "resolved_models": ["jev-test"]}
        with self.assertRaises(ValueError):
            jev.proposed_policy(report)
        row["split"] = "calibration"
        self.assertEqual(jev.proposed_policy(report)["minimum_margin"], 0.1)
        row["expected"] = "fail"
        with self.assertRaises(ValueError):
            jev.proposed_policy(report)

    def test_redirects_are_refused(self):
        self.assertIsNone(jev.NoRedirect().redirect_request(None, None, 302, "", {}, "https://other.example"))

    def test_invalid_or_changed_policy_is_rejected(self):
        path = self.root / "policy.json"
        for value in (None, [], {}, {"protocol_sha256": "stale"}):
            jev.write_json(path, value)
            with self.subTest(value=value), self.assertRaises(ValueError):
                jev.load_policy(path)

    def test_validate_forwards_scratch_to_all_swift_calls_and_rejects_relative_paths(self):
        ci = self.root / "scripts/ci"; ci.mkdir(parents=True)
        for name in ("validate.sh", "architecture.sh"):
            shutil.copy2(jev.ROOT / "scripts/ci" / name, ci / name)
        (ci / "source-contract-gate.sh").write_text("#!/bin/bash\nexit 0\n")
        (ci / "source-contract-gate.sh").chmod(0o755)
        binaries = self.root / "bin"; binaries.mkdir()
        log = self.root / "commands"
        programs = {
            "swift": '#!/bin/bash\nprintf "%s\\n" "$*" >> "$TEST_COMMAND_LOG"\nif [[ "$*" == *--show-bin-path* ]]; then echo /synthetic-build; fi\n',
            "lipo": '#!/bin/bash\necho "arm64 x86_64"\n',
            "git": '#!/bin/bash\nexit 0\n',
        }
        for name, text in programs.items():
            path = binaries / name; path.write_text(text); path.chmod(0o755)
        env = {**os.environ, "PATH": str(binaries) + ":/usr/bin:/bin", "TEST_COMMAND_LOG": str(log)}
        for scratch in (None, str(self.root / "scratch with spaces")):
            env.pop("MKV_MAGIC_SWIFT_SCRATCH_PATH", None)
            if scratch: env["MKV_MAGIC_SWIFT_SCRATCH_PATH"] = scratch
            result = subprocess.run([str(ci / "validate.sh")], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            commands = log.read_text().splitlines(); log.unlink()
            self.assertEqual(len(commands), 3)
            self.assertTrue(all("--disable-automatic-resolution" in c for c in commands))
            self.assertTrue(all(("--scratch-path" in c) == bool(scratch) for c in commands))
        env["MKV_MAGIC_SWIFT_SCRATCH_PATH"] = "relative"
        self.assertNotEqual(subprocess.run([str(ci / "validate.sh")], env=env, capture_output=True).returncode, 0)
        self.assertFalse(log.exists())

    def test_default_runner_is_live_and_offline_is_explicit(self):
        spec = importlib.util.spec_from_file_location("development_tests", jev.ROOT / "scripts/test.py")
        runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
        for index, flags in enumerate(([], ["--dry-run"], ["--offline"])):
            with self.subTest(flags=flags), patch.object(sys, "argv", ["test.py", "--output-dir", str(self.root / str(index)), *flags]), \
                    patch.object(jev, "local_config", return_value={"tool_root": "/synthetic-runtime"}), \
                    patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)), \
                    patch.object(jev, "seal_evidence", return_value=self.rows), \
                    patch.object(jev, "load_policy", return_value=self.policy), \
                    patch.object(jev, "review", return_value={"passed": True}) as review:
                self.assertEqual(runner.main(), 0)
                if "--offline" in flags:
                    review.assert_not_called()
                else:
                    self.assertEqual(review.call_args.kwargs["live"], "--dry-run" not in flags)
                result = jev.read_json(self.root / str(index) / "report.json")
                self.assertEqual(result["full_suite_passed"], not flags)


if __name__ == "__main__":
    unittest.main()
