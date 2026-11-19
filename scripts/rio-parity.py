"""Regenerate Fixtures/parity/*.rio.json: rio's TR-03183-2 results for each parity fixture.

Run from the repository root with `make parity-refresh`. Needs `rio` on PATH (rio 0.10 or later);
`make test` does not, it compares with the committed files.
"""
import glob
import json
import os
import shutil
import subprocess
import sys

INPUTS = sorted(glob.glob("Fixtures/public/*.json")) + sorted(glob.glob("Fixtures/rio/*.json")) + [
    "Fixtures/synthetic/tr-edge-1.6.cdx.json"
] + sorted(glob.glob("Fixtures/tools/*.cdx.json"))  # SBOMs as Syft, Trivy, cdxgen and Maven write them
MANIFEST = """version: 1
artifacts:
  - id: parity
    sbom: "input.json"
gate:
  mode: warn
  require: [name, version]
  profile: bsi-tr-03183-2@2.1.0
"""


def main():
    rio = shutil.which("rio")
    if rio is None:
        sys.exit("rio not found on PATH")
    version = subprocess.run([rio, "--version"], capture_output=True, text=True, check=True).stdout.strip()
    os.makedirs("Fixtures/parity", exist_ok=True)
    for path in INPUTS:
        work = os.path.join("build", "parity", os.path.basename(path))
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(work)
        shutil.copyfile(path, os.path.join(work, "input.json"))
        with open(os.path.join(work, "rio.yaml"), "w") as f:
            f.write(MANIFEST)
        run = subprocess.run([rio, "normalize", "--manifest", "rio.yaml", "--out", "out", "--quiet"],
                             cwd=work, capture_output=True, text=True)
        if run.returncode != 0:
            sys.exit(f"rio failed on {path}:\n{run.stdout}{run.stderr}")
        (index,) = glob.glob(os.path.join(work, "out", "runs", "*", "index.json"))
        with open(index) as f:
            artifact = json.load(f)["artifacts"][0]
        checks = artifact["checks"]
        findings = []
        for g in artifact.get("gateFindings", []):
            scope = "sbom" if g.get("sbom") else "subject" if g.get("subject") else "components"
            findings.append({"scope": scope, "component": g.get("component"), "missing": g["missing"]})
        out = {
            "rio": version,
            "input": path,
            "specVersionInput": artifact["specVersion"]["input"],
            "evaluations": [
                {k: e[k] for k in ("scope", "requirement", "evaluated", "failed")} for e in checks["evaluations"]
            ],
            "profileLevels": checks["profileLevels"],
            "findings": findings,
        }
        target = os.path.join("Fixtures", "parity", os.path.basename(path) + ".rio.json")
        with open(target, "w") as f:
            json.dump(out, f, indent=1)
            f.write("\n")
        print(f"{target}: {sum(e['failed'] for e in out['evaluations'])} failures")


main()
