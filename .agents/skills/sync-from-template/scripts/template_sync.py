#!/usr/bin/env python3
"""Plan or apply a sync of template-managed files from terraform-module into a module repo.

Compares three versions of every managed path:
  base  - the template commit the repo was last synced to (.template-sync.json), if known
  head  - the template ref being synced now
  repo  - the repo's working tree

and classifies each path:
  unchanged     repo already matches head
  add           new in the template; repo doesn't have it
  update        template changed it and the repo still has the base version: safe overwrite
  merge         both sides changed it; git merge-file merged it cleanly
  conflict      both sides changed it and the merge conflicts: resolve by hand
  review        no base known (first sync) and repo differs from head: decide by hand
  compose       repo-specific file (AGENTS.md): never overwritten, edit by hand
  keep          repo customised it and the template didn't change it since base
  delete        template removed it (or retired it) and the repo copy is unmodified
  delete-review template removed it but the repo copy was modified, or it was retired

Usage:
  template_sync.py plan  --repo <module repo> [--template <path>] [--ref origin/main] [--base <sha>] [--json]
  template_sync.py apply --repo <module repo> [--template <path>] [--ref origin/main] [--base <sha>]

apply writes add/update/merge/delete results and the marker file. It never touches conflict,
review, compose or delete-review paths; those are listed for you to resolve. Writing the
marker means the next sync only brings template changes made after this one.

Only standard library; needs git on PATH.
"""

import argparse
import fnmatch
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

MARKER = ".template-sync.json"
DEFAULT_TEMPLATE_URL = "https://github.com/kbrockhoff/terraform-module.git"

# Paths the template owns. Globs match repo-relative paths; "**" spans directories.
MANAGED = [
    "AGENTS.md",
    "CLAUDE.md",
    "skills-lock.json",
    ".gitignore",
    ".agents/**",
    ".claude/skills/**",
    ".claude/mcp.json",
    ".vscode/settings.json",
    ".github/**",
]

# Repo-specific content around a template skeleton: never overwritten automatically.
COMPOSE = ["AGENTS.md"]

# Paths an older template generated and the current one retired. Deleted when the template
# no longer has them, even without a base (they were never repo-specific).
RETIRED = [
    ".ruler/**",
    "GEMINI.md",
    ".gemini/**",
    ".kiro/**",
    ".mcp.json",
    ".github/copilot-instructions.md",
    ".claude/commands/**",
    ".claude/agents/**",
]

# Never touched, even when under a managed glob.
IGNORED = [
    ".claude/settings.local.json",
    MARKER,
]


def matches(path, patterns):
    for pattern in patterns:
        if pattern.endswith("/**"):
            prefix = pattern[:-3]
            if path == prefix or path.startswith(prefix + "/"):
                return True
        elif fnmatch.fnmatchcase(path, pattern):
            return True
    return False


def git(cwd, *args, binary=False, check=True):
    result = subprocess.run(["git", "-C", cwd, *args], capture_output=True, check=False)
    if check and result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed in {cwd}:\n{result.stderr.decode()}")
    return result.stdout if binary else result.stdout.decode()


def tree(template, ref):
    """Map path -> (mode, content bytes) for managed and retired paths at a template commit."""
    entries = {}
    for line in git(template, "ls-tree", "-r", "-z", "--full-tree", ref, binary=True).split(b"\0"):
        if not line:
            continue
        meta, path = line.decode().split("\t", 1)
        mode, kind, sha = meta.split()
        if kind != "blob" or matches(path, IGNORED):
            continue
        if matches(path, MANAGED) or matches(path, RETIRED):
            entries[path] = (mode, sha)
    shas = {sha for _, sha in entries.values()}
    contents = {}
    if shas:
        batch = subprocess.run(["git", "-C", template, "cat-file", "--batch"], input="\n".join(shas).encode() + b"\n",
                               capture_output=True, check=True).stdout
        pos = 0
        while pos < len(batch):
            header_end = batch.index(b"\n", pos)
            sha, _, size = batch[pos:header_end].decode().split()
            start = header_end + 1
            contents[sha] = batch[start:start + int(size)]
            pos = start + int(size) + 1
    return {path: (mode, contents[sha]) for path, (mode, sha) in entries.items()}


def repo_files(repo, template_paths=()):
    """Map path -> (mode, content bytes) for managed and retired paths in the repo working tree.

    template_paths are also checked on disk, so files the repo's .gitignore hides (for example
    .vscode/settings.json before the template's negation is merged) still count as present.
    """
    listed = git(repo, "ls-files", "-z", "--cached", "--others", "--exclude-standard", binary=True).decode().split("\0")
    files = {}
    for path in sorted(set(filter(None, listed)) | set(template_paths)):
        if matches(path, IGNORED) or not (matches(path, MANAGED) or matches(path, RETIRED)):
            continue
        if through_symlink(repo, path):
            continue  # stale index entry under a directory that is now a symlink
        full = os.path.join(repo, path)
        if os.path.islink(full):
            files[path] = ("120000", os.readlink(full).encode())
        elif os.path.isfile(full) and not os.path.isdir(full):
            mode = "100755" if os.access(full, os.X_OK) else "100644"
            with open(full, "rb") as handle:
                files[path] = (mode, handle.read())
    return files


def merge3(repo_content, base_content, head_content):
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for name, content in (("repo", repo_content), ("base", base_content), ("head", head_content)):
            path = os.path.join(tmp, name)
            with open(path, "wb") as handle:
                handle.write(content)
            paths.append(path)
        result = subprocess.run(["git", "merge-file", "-p", "-L", "repo", "-L", "base", "-L", "template", *paths],
                                capture_output=True, check=False)
        return result.returncode == 0, result.stdout


def symlinked_dirs(entries):
    """Directories that are symlinks in an entry map, e.g. .claude/skills/<name>."""
    return {path for path, (mode, _) in entries.items() if mode == "120000"}


def classify(base, head, repo):
    plan = {}
    head_links = symlinked_dirs(head)
    # A repo directory where the template has a symlink (e.g. a skill copied into .claude/skills/
    # that the template keeps in .agents/skills/): its files are covered by the symlink.
    covered = {p for p in repo if any(p.startswith(link + "/") for link in head_links)}

    for path in sorted(set(base) | set(head) | set(repo)):
        b, h, r = base.get(path), head.get(path), repo.get(path)
        if path in covered:
            link = next(link for link in head_links if path.startswith(link + "/"))
            # Compare with the file the symlink will point at, e.g. .agents/skills/<name>/<file>
            target = os.path.normpath(os.path.join(os.path.dirname(link), head[link][1].decode(), path[len(link) + 1:]))
            same = head.get(target) is not None and head[target][1] == r[1]
            plan[path] = {"action": "delete" if same else "delete-review",
                          "reason": f"replaced by template symlink {link}" + ("" if same else "; repo copy differs from template")}
            continue
        if h is not None:
            if r == h:
                action, reason = "unchanged", ""
            elif matches(path, COMPOSE):
                action, reason = "compose", "repo-specific sections around the template skeleton"
            elif r is None:
                action, reason = "add", "new in template"
            elif b is None:
                action, reason = "review", "no sync base; repo differs from template"
            elif r == b:
                action, reason = "update", "template changed; repo unmodified since base"
            elif b == h:
                action, reason = "keep", "repo customisation; template unchanged since base"
            elif r[0] == "120000" or h[0] == "120000" or b[0] == "120000":
                action, reason = "conflict", "symlink changed on both sides"
            else:
                clean, merged = merge3(r[1], b[1], h[1])
                action = "merge" if clean else "conflict"
                reason = "merged repo and template changes" if clean else "overlapping repo and template changes"
                plan[path] = {"action": action, "reason": reason, "merged": merged}
                continue
        elif r is not None:
            if matches(path, RETIRED):
                action, reason = ("delete", "retired by template") if (b is None or r == b) else (
                    "delete-review", "retired by template but modified in repo")
                if b is None:
                    action, reason = "delete-review", "retired by template; check for repo-specific content first"
            elif b is not None:
                action, reason = ("delete", "removed from template") if r == b else (
                    "delete-review", "removed from template but modified in repo")
            else:
                action, reason = "repo-only", "not in template; left alone"
        else:
            continue
        plan[path] = {"action": action, "reason": reason}
    # Retired files that hold repo-specific content are review items only when nothing else
    # covers them; .ruler/instructions.md always feeds AGENTS.md, so flag it explicitly.
    for path in plan:
        if path == ".ruler/instructions.md" and plan[path]["action"].startswith("delete"):
            plan[path] = {"action": "delete-review", "reason": "move its module description into AGENTS.md first"}
    return plan


def write(repo, path, mode, content):
    full = os.path.join(repo, path)
    if through_symlink(repo, path):
        raise SystemExit(f"refusing to write {path}: a parent directory is a symlink")
    if os.path.lexists(full) and (os.path.isdir(full) and not os.path.islink(full)):
        shutil.rmtree(full)
    elif os.path.lexists(full):
        os.remove(full)
    os.makedirs(os.path.dirname(full) or repo, exist_ok=True)
    if mode == "120000":
        os.symlink(content.decode(), full)
    else:
        with open(full, "wb") as handle:
            handle.write(content)
        os.chmod(full, 0o755 if mode == "100755" else 0o644)


def through_symlink(repo, path):
    """True if any parent directory of path inside repo is a symlink."""
    parent = os.path.dirname(path)
    while parent:
        if os.path.islink(os.path.join(repo, parent)):
            return True
        parent = os.path.dirname(parent)
    return False


def remove(repo, path):
    full = os.path.join(repo, path)
    if through_symlink(repo, path):
        raise SystemExit(f"refusing to delete {path}: a parent directory is a symlink")
    if os.path.lexists(full):
        os.remove(full)
    parent = os.path.dirname(full)
    while parent and parent != repo and os.path.isdir(parent) and not os.listdir(parent):
        os.rmdir(parent)
        parent = os.path.dirname(parent)


def resolve_template(args):
    if args.template:
        template = os.path.abspath(args.template)
        git(template, "fetch", "--quiet", "origin", check=False)
        return template, None
    tmp = tempfile.mkdtemp(prefix="terraform-module-")
    subprocess.run(["git", "clone", "--quiet", "--filter=blob:none", DEFAULT_TEMPLATE_URL, tmp], check=True)
    return tmp, tmp


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["plan", "apply"])
    parser.add_argument("--repo", required=True, help="module repo to update")
    parser.add_argument("--template", help="local terraform-module clone (default: fresh clone of GitHub)")
    parser.add_argument("--ref", default="origin/main", help="template ref to sync to (default origin/main)")
    parser.add_argument("--base", help="template commit last synced; overrides the marker file")
    parser.add_argument("--json", action="store_true", help="print the plan as JSON")
    parser.add_argument("--conflicts-dir", help="write conflict paths with merge markers, plus each path's "
                        "base and template versions, under this directory (outside the repo)")
    args = parser.parse_args()

    repo = os.path.abspath(args.repo)
    template, cleanup = resolve_template(args)
    try:
        head_sha = git(template, "rev-parse", "--verify", args.ref + "^{commit}").strip()
        marker_path = os.path.join(repo, MARKER)
        base_sha = args.base
        if not base_sha and os.path.exists(marker_path):
            with open(marker_path) as handle:
                base_sha = json.load(handle).get("commit")
        if base_sha:
            base_sha = git(template, "rev-parse", "--verify", base_sha + "^{commit}").strip()

        base = tree(template, base_sha) if base_sha else {}
        head = tree(template, head_sha)
        plan = classify(base, head, repo_files(repo, set(base) | set(head)))

        if args.conflicts_dir:
            for path, item in plan.items():
                if item["action"] not in ("conflict", "review"):
                    continue
                for suffix, content in (("merged", item.get("merged")), ("template", head.get(path, (0, None))[1]),
                                        ("base", base.get(path, (0, None))[1])):
                    if content is None:
                        continue
                    out = os.path.join(args.conflicts_dir, path + "." + suffix)
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    with open(out, "wb") as handle:
                        handle.write(content)

        summary = {}
        for item in plan.values():
            summary[item["action"]] = summary.get(item["action"], 0) + 1

        if args.json:
            print(json.dumps({
                "template_ref": args.ref, "head": head_sha, "base": base_sha, "summary": summary,
                "paths": {p: {k: v for k, v in i.items() if k != "merged"} for p, i in plan.items()
                          if i["action"] != "unchanged"},
            }, indent=2))
        else:
            print(f"template {args.ref} = {head_sha[:12]}   base = {base_sha[:12] if base_sha else 'none (first sync)'}")
            print("summary: " + ", ".join(f"{k}={v}" for k, v in sorted(summary.items())))
            order = ["conflict", "review", "compose", "delete-review", "merge", "update", "add", "delete", "keep", "repo-only"]
            for action in order:
                paths = [p for p, i in plan.items() if i["action"] == action]
                # Collapse whole directories (vendored skills) to keep the listing readable
                shown = {}
                for p in paths:
                    collapse = p.startswith((".agents/skills/", ".claude/skills/")) and p.count("/") > 2
                    key = "/".join(p.split("/")[:3]) + "/..." if collapse else p
                    shown.setdefault(key, plan[p]["reason"])
                for p, reason in shown.items():
                    print(f"  {action:13s} {p}  ({reason})")

        if args.command == "apply":
            # Deletes first, so replacing a copied directory with a template symlink never
            # deletes through the new symlink
            for path in sorted((p for p, i in plan.items() if i["action"] == "delete"), reverse=True):
                remove(repo, path)
            for path, item in sorted(plan.items()):
                if through_symlink(repo, path):
                    continue
                if item["action"] in ("add", "update"):
                    write(repo, path, *head[path])
                elif item["action"] == "merge":
                    write(repo, path, head[path][0], item["merged"])
            with open(marker_path, "w") as handle:
                json.dump({"template": DEFAULT_TEMPLATE_URL, "ref": args.ref, "commit": head_sha,
                           "synced_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}, handle, indent=2)
                handle.write("\n")
            pending = [p for p, i in plan.items() if i["action"] in ("conflict", "review", "compose", "delete-review")]
            print(f"\napplied; marker set to {head_sha[:12]}; {len(pending)} path(s) need manual resolution")
            return 1 if pending else 0
    finally:
        if cleanup:
            shutil.rmtree(cleanup, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
