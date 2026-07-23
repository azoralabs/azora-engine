#!/usr/bin/env python3
"""azpm — the Azora Engine package manager / resolver.

Reads the workspace and every package.azon manifest, then resolves what a
project needs from its `import engine[.x]` statements: the transitive package
closure, the source directories to stage, and the native frameworks/libs to
link. This replaces the hard-coded dependency graph and framework list that
used to live in tools/build.sh.

Usage:
  azpm.py resolve <project_dir>   # staging + native link plan (machine readable)
  azpm.py frameworks <project_dir>
  azpm.py libs <project_dir>
  azpm.py graph                   # print the whole package dependency graph
"""

from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import azon  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMPORT_RE = re.compile(r"^\s*(?:export\s+)?import\s+(engine(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\b")


class Package:
    def __init__(self, path: str, manifest: dict):
        pkg = manifest.get("package", {})
        self.dir = path
        self.name = pkg.get("name") or os.path.basename(path)
        self.module = pkg.get("module", "")
        self.kind = pkg.get("kind", "core")
        self.deps = list((manifest.get("dependencies") or {}).keys())
        native = manifest.get("native") or {}
        self.frameworks = list(native.get("frameworks") or [])
        self.libs = list(native.get("libs") or [])

    @property
    def src_dir(self) -> str:
        return os.path.join(self.dir, "src")

    @property
    def stage_dir(self) -> str:
        # engine.render -> engine/render ; engine -> engine ; engine.app -> engine/app
        return self.module.replace(".", "/") if self.module else ""


class Workspace:
    def __init__(self, root: str = ROOT):
        self.root = root
        ws = azon.load(os.path.join(root, "workspace.azon"))
        self.packages: dict[str, Package] = {}
        self.by_module: dict[str, Package] = {}
        for member in ws.get("members", []):
            manifest_path = os.path.join(root, member, "package.azon")
            if not os.path.exists(manifest_path):
                continue
            pkg = Package(os.path.join(root, member), azon.load(manifest_path))
            self.packages[pkg.name] = pkg
            if pkg.module:
                self.by_module[pkg.module] = pkg

    def package_for_module(self, module: str) -> Package | None:
        # exact match, then walk up (engine.render.webgl -> engine.render)
        parts = module.split(".")
        while parts:
            pkg = self.by_module.get(".".join(parts))
            if pkg is not None:
                return pkg
            parts.pop()
        return None

    def closure(self, roots: list[str]) -> list[Package]:
        """Transitive dependency closure of the given package names, in
        dependency-first (topological) order."""
        ordered: list[Package] = []
        seen: set[str] = set()

        def visit(name: str) -> None:
            if name in seen:
                return
            seen.add(name)
            pkg = self.packages.get(name)
            if pkg is None:
                raise SystemExit(f"azpm: unknown package '{name}'")
            for dep in pkg.deps:
                visit(dep)
            ordered.append(pkg)

        for r in roots:
            visit(r)
        return ordered

    def project_roots(self, project_dir: str) -> list[str]:
        src = os.path.join(project_dir, "src")
        modules: list[str] = []
        if os.path.isdir(src):
            for fn in sorted(os.listdir(src)):
                if not fn.endswith(".az"):
                    continue
                with open(os.path.join(src, fn), encoding="utf-8") as fh:
                    for line in fh:
                        m = IMPORT_RE.match(line)
                        if m:
                            modules.append(m.group(1))
        roots: list[str] = []
        for mod in modules:
            pkg = self.package_for_module(mod)
            if pkg and pkg.name not in roots:
                roots.append(pkg.name)
        # A project that imports nothing engine-specific still gets the facade,
        # matching the old `import engine` == everything default.
        if not roots:
            facade = self.by_module.get("engine")
            if facade:
                roots.append(facade.name)
        return roots

    def resolve(self, project_dir: str) -> list[Package]:
        return self.closure(self.project_roots(project_dir))


def _cmd_resolve(ws: Workspace, project_dir: str) -> None:
    pkgs = ws.resolve(project_dir)
    frameworks: list[str] = []
    libs: list[str] = []
    for pkg in pkgs:
        print(f"STAGE\t{pkg.src_dir}\t{pkg.stage_dir}")
        for f in pkg.frameworks:
            if f not in frameworks:
                frameworks.append(f)
        for l in pkg.libs:
            if l not in libs:
                libs.append(l)
    for f in frameworks:
        print(f"FRAMEWORK\t{f}")
    for l in libs:
        print(f"LIB\t{l}")


def _cmd_frameworks(ws: Workspace, project_dir: str) -> None:
    fs: list[str] = []
    for pkg in ws.resolve(project_dir):
        for f in pkg.frameworks:
            if f not in fs:
                fs.append(f)
    print(" ".join(fs))


def _cmd_libs(ws: Workspace, project_dir: str) -> None:
    ls: list[str] = []
    for pkg in ws.resolve(project_dir):
        for l in pkg.libs:
            if l not in ls:
                ls.append(l)
    print(" ".join(ls))


def _cmd_graph(ws: Workspace) -> None:
    for name in sorted(ws.packages):
        pkg = ws.packages[name]
        deps = ", ".join(pkg.deps) if pkg.deps else "(none)"
        print(f"{name}  [{pkg.module}]  ->  {deps}")


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    ws = Workspace()
    cmd = argv[0]
    if cmd == "graph":
        _cmd_graph(ws)
        return 0
    if cmd in ("resolve", "frameworks", "libs"):
        if len(argv) != 2:
            print(f"usage: azpm.py {cmd} <project_dir>", file=sys.stderr)
            return 2
        project = os.path.abspath(argv[1])
        {"resolve": _cmd_resolve, "frameworks": _cmd_frameworks, "libs": _cmd_libs}[cmd](ws, project)
        return 0
    print(f"azpm: unknown command '{cmd}'", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
