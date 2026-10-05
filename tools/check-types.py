"""Check every Rojo-mapped runtime source under both Luau solver flag profiles."""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
LSP_VERSION = "1.68.1"
DEFINITIONS_SHA256 = "a0027362f872d231c1c4bbea6b2d5d561b0a4ea7e82458ea8a5f862cef8938aa"


def definitions(path: Path | None) -> Path:
    destination = path or ROOT / ".tools" / f"globalTypes-{LSP_VERSION}.d.luau"
    if not destination.is_file() and path is None:
        url = (
            "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/"
            f"{LSP_VERSION}/scripts/globalTypes.d.luau"
        )
        with urllib.request.urlopen(url, timeout=30) as response:
            content = response.read()
        if hashlib.sha256(content).hexdigest() != DEFINITIONS_SHA256:
            raise RuntimeError("Roblox definitions failed SHA-256 verification")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)
    if hashlib.sha256(destination.read_bytes()).hexdigest() != DEFINITIONS_SHA256:
        raise RuntimeError("Roblox definitions do not match the pinned release")
    return destination.resolve()


def tool(name: str, override: str | None) -> str:
    result = override or shutil.which(name)
    if not result:
        raise RuntimeError(f"{name} is missing; install the tools from rokit.toml")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lsp", help="Override the luau-lsp executable path")
    parser.add_argument("--rojo", help="Override the Rojo executable path")
    parser.add_argument("--defs", type=Path, help="Reuse pinned Roblox definitions")
    args = parser.parse_args()
    lsp = tool("luau-lsp", args.lsp)
    rojo = tool("rojo", args.rojo)
    version = subprocess.check_output([lsp, "--version"], cwd=ROOT, text=True).strip()
    if version != LSP_VERSION:
        raise RuntimeError(f"Expected luau-lsp {LSP_VERSION}, got {version}")
    defs = definitions(args.defs)
    failed = False
    with tempfile.TemporaryDirectory(prefix="animblend-typecheck-") as directory:
        sourcemap = Path(directory) / "sourcemap.json"
        subprocess.run(
            [rojo, "sourcemap", "AnimBlend.project.json", "--include-non-scripts", "-o", str(sourcemap)],
            cwd=ROOT,
            check=True,
        )
        for all_flags in (False, True):
            for solver_v2 in (True, False):
                profile = "all flags" if all_flags else "default flags"
                print(f"Luau Solver {'V2' if solver_v2 else 'V1'} ({profile})", flush=True)
                flags = [] if all_flags else ["--no-flags-enabled"]
                result = subprocess.run(
                    [
                        lsp, "analyze", *flags,
                        f"--flag:LuauSolverV2={str(solver_v2).lower()}",
                        "--sourcemap", str(sourcemap),
                        "--defs", str(defs),
                        "--base-luaurc", str(ROOT / ".luaurc"),
                        "--platform", "roblox", str(ROOT / "src"),
                    ],
                    cwd=ROOT,
                )
                failed |= result.returncode != 0
    print("Type analysis FAILED" if failed else "All runtime type checks passed")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
