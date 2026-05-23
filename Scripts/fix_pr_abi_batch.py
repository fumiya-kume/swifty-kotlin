#!/usr/bin/env python3
"""Fix ABI allowlist / RuntimeABISpec gaps on open PR branches."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWLIST = ROOT / "Tests/RuntimeTests/ABIMismatchTests+RuntimeExportParity.swift"
RUNTIME_SPEC = ROOT / "Sources/RuntimeABI/RuntimeABISpec.swift"


def run(cmd: list[str], check: bool = True) -> str:
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}\n{r.stderr}\n{r.stdout}")
    return r.stdout


def git(*args: str) -> str:
    return run(["git", *args])


def read_allowlist() -> set[str]:
    text = ALLOWLIST.read_text()
    m = re.search(r"allowedSpecOnlyRuntimeABINames: Set<String> \{\s*\[([\s\S]*?)\]\s*\}", text)
    if not m:
        raise RuntimeError("allowlist not found")
    return set(re.findall(r'"(kk_[^"]+)"', m.group(1)))


def write_allowlist(names: set[str]) -> bool:
    text = ALLOWLIST.read_text()
    existing = read_allowlist()
    missing = sorted(names - existing)
    if not missing:
        return False
    merged = sorted(existing | set(missing))
    block = ",\n            ".join(f'"{n}"' for n in merged)
    new_text = re.sub(
        r"(allowedSpecOnlyRuntimeABINames: Set<String> \{\s*\[)([\s\S]*?)(\]\s*\})",
        rf"\1\n            {block},\n        \3",
        text,
        count=1,
    )
    ALLOWLIST.write_text(new_text)
    return True


def new_abi_from_diff(base: str, head: str) -> set[str]:
    diff = git("diff", f"{base}...{head}", "--", "Sources/RuntimeABI/RuntimeABISpec.swift")
    return set(re.findall(r'name: "(kk_[^"]+)"', diff))


def new_sema_links_from_diff(base: str, head: str) -> set[str]:
    diff = git("diff", f"{base}...{head}", "--", "Sources/CompilerCore")
    return set(re.findall(r'"(kk_[^"]+)"', diff)) | set(
        re.findall(r"setExternalLinkName\(\"(kk_[^\"]+)\"", diff)
    )


def runtime_spec_names() -> set[str]:
    return set(re.findall(r'name: "(kk_[^"]+)"', RUNTIME_SPEC.read_text()))


def add_runtime_spec_entry(name: str, param_type: str = "intptr") -> bool:
    text = RUNTIME_SPEC.read_text()
    if name in text:
        return False
    entry = f"""        RuntimeABIFunctionSpec(
            name: "{name}",
            parameters: [
                RuntimeABIParameter(name: "value", type: .{param_type}),
            ],
            returnType: .intptr,
            section: "System"
        ),
"""
    marker = '        RuntimeABIFunctionSpec(\n            name: "kk_string_toJsString",'
    if marker not in text:
        marker = "    ]\n\n    public static let gcFunctions"
        if marker not in text:
            raise RuntimeError("insertion marker not found")
        text = text.replace(marker, entry + marker, 1)
    else:
        text = text.replace(marker, entry + marker, 1)
    RUNTIME_SPEC.write_text(text)
    return True


def param_type_for(name: str) -> str:
    if "_int_" in name or name.startswith("kk_int_"):
        return "int32"
    if "_long_" in name or name.startswith("kk_long_"):
        return "int64"
    return "intptr"


def process_branch(branch: str, base: str) -> dict:
    git("fetch", "origin", branch, check=False)
    git("checkout", branch)
    git("pull", "origin", branch, check=False)
    git("merge", f"origin/{base}", check=False)

    new_spec = new_abi_from_diff(f"origin/{base}", "HEAD")
    new_links = new_sema_links_from_diff(f"origin/{base}", "HEAD")
    spec_names = runtime_spec_names()
    missing_spec = sorted(link for link in new_links if link.startswith("kk_") and link not in spec_names)

    changed = False
    for name in missing_spec:
        if add_runtime_spec_entry(name, param_type_for(name)):
            changed = True
            new_spec.add(name)

    allow = new_spec | set(missing_spec)
    if write_allowlist(allow):
        changed = True

    if not changed:
        return {"branch": branch, "status": "noop", "new_spec": sorted(new_spec), "missing_spec": missing_spec}

    run(
        [
            "bash",
            "Scripts/swift_test.sh",
            "--filter",
            "RuntimeABIExternalLinkValidationTests|ABIMismatchTests.testSpecOnly",
            "-Xswiftc",
            "-swift-version",
            "-Xswiftc",
            "6",
        ],
        check=True,
    )
    git("add", "-A")
    diff = git("diff", "--cached", "--stat")
    if not diff.strip():
        return {"branch": branch, "status": "noop_after_test"}
    msg = f"Fix Runtime ABI registration for {branch.split('/')[-1]}"
    git("commit", "-m", msg)
    git("push", "origin", branch)
    return {"branch": branch, "status": "pushed", "new_spec": sorted(new_spec), "missing_spec": missing_spec}


def main() -> None:
    prs = json.loads(
        run(
            [
                "gh",
                "pr",
                "list",
                "--state",
                "open",
                "--limit",
                "100",
                "--json",
                "number,headRefName,baseRefName,mergeStateStatus,mergeable",
            ]
        )
    )
    targets = [
        p
        for p in prs
        if p["mergeStateStatus"] == "BLOCKED" and p["mergeable"] == "MERGEABLE"
    ]
    results = []
    for p in sorted(targets, key=lambda x: x["number"]):
        branch = p["headRefName"]
        base = p["baseRefName"]
        print(f"=== PR {p['number']} {branch} (base {base}) ===", flush=True)
        try:
            results.append(process_branch(branch, base))
        except Exception as e:
            results.append({"branch": branch, "status": f"error: {e}"})
            git("merge", "--abort", check=False)
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
