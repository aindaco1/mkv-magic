#!/usr/bin/env python3
"""Default local development gate: existing validation plus calibrated Jev review."""

import argparse
import datetime as dt
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from testing import jev


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--offline", action="store_true", help="Explicit local-only subset; skips Jev")
    mode.add_argument("--dry-run", action="store_true", help="Run local gates and preview Jev requests without authentication")
    parser.add_argument("--output-dir", type=Path, default=jev.ROOT / ".build/jev" /
                        dt.datetime.now(dt.timezone.utc).strftime("development-%Y%m%dT%H%M%S%fZ"))
    args = parser.parse_args()
    output = args.output_dir.absolute()
    report = {"schema": "mkv-magic.development.v1", "passed": False, "full_suite_passed": False, "release_accepted": False,
              "mode": "offline" if args.offline else "preview" if args.dry_run else "full",
              "skipped": ["Jev calibration and workflow review"] if args.offline else [], "gates": []}
    try:
        output.mkdir(parents=True, exist_ok=False)
    except OSError:
        print("Choose a new writable output directory; existing evidence is never overwritten.")
        return 2

    def save():
        jev.write_json(output / "report.json", report)

    try:
        save()
        env = os.environ.copy()
        # Keep generated signed bundles out of cloud-synced source directories.
        env.setdefault("MKV_MAGIC_SWIFT_SCRATCH_PATH", str(Path(tempfile.gettempdir()) /
                       ("mkv-magic-swift-" + jev.digest(str(jev.ROOT).encode())[:12])))
        # Never inherit another run's export location into this run or offline tests.
        env.pop("MKV_MAGIC_WORKFLOW_EVIDENCE", None)
        config = jev.local_config()
        runtime = env.get("MKV_MAGIC_TOOL_ROOT") or config.get("tool_root")
        if runtime:
            if not isinstance(runtime, str) or not Path(runtime).is_absolute():
                raise ValueError("Configure an absolute MKV_MAGIC_TOOL_ROOT")
            env["MKV_MAGIC_TOOL_ROOT"] = runtime
        if not args.offline:
            if not runtime:
                raise ValueError("Full workflow evidence needs the verified bundled MKV_MAGIC_TOOL_ROOT")
            evidence = output / "workflow-evidence"
            evidence.mkdir()
            env["MKV_MAGIC_WORKFLOW_EVIDENCE"] = str(evidence)
        before = jev.source_hashes()
        print("Running existing source, Swift, and Universal-build validation", flush=True)
        code = subprocess.run([str(jev.ROOT / "scripts/ci/validate.sh")], cwd=jev.ROOT, env=env).returncode
        report["gates"].append({"name": "local validation", "exit_code": code})
        save()
        if code:
            return 1
        if not args.offline:
            rows = jev.seal_evidence(evidence, before)
            # Validate all evidence before authentication, including calibration checks.
            rows = jev.calibration_rows() + rows
            policy = jev.load_policy()
            reviewed = jev.review(rows, output / "jev", live=not args.dry_run, policy=policy)
            report["gates"].append({"name": "Jev request preview" if args.dry_run else "Jev calibration and workflows",
                                    "exit_code": 0 if args.dry_run or reviewed["passed"] else 1})
        report["passed"] = all(gate["exit_code"] == 0 for gate in report["gates"])
        report["full_suite_passed"] = report["passed"] and not args.offline and not args.dry_run
        save()
        print(f"Development report: {output / 'report.json'}")
        return 0 if report["passed"] else 1
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Only local validation errors reach here; transport failures were sanitized by jev.
        report["error"] = str(error)
        save()
        print(f"Development check incomplete: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
