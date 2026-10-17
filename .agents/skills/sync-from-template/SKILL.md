---
name: sync-from-template
description: >
  Updates an existing kbrockhoff terraform-aws-* module repo with changes made to the
  terraform-module template since the repo was created or last synced. Covers agent
  instructions (AGENTS.md, CLAUDE.md), vendored and generated skills (.agents/skills,
  .claude/skills, skills-lock.json), MCP server config (.agents/mcp.json), editor and ignore
  settings, and everything under .github (workflows, issue and PR templates, CODEOWNERS,
  dependabot). Use when asked to sync, update, refresh or align a module repo with the
  template, when the template's agent setup, skills, MCP servers or CI changed, or when a repo
  still has the retired Ruler layout (.ruler/, GEMINI.md, .github/copilot-instructions.md).
  Does not touch Terraform code; regenerate modules/deployer and modules/cost-estimation with
  their own skills.
---

# Sync a module repo from the terraform-module template

The template owns a set of non-Terraform files that every module repo should share. This skill
brings a repo up to date with the template, and only with template changes it doesn't have
yet. Repo-specific content stays: the module description in AGENTS.md, checkov skips in CI,
extra ignore rules, and repo-only skills.

`scripts/template_sync.py` does the mechanical work. It compares three versions of every
managed path: the template commit the repo last synced to, the template version being synced
now, and the repo's working tree. That lets it tell a stale file (safe to update) apart from a
repo customization (keep or merge). The last synced commit is recorded in `.template-sync.json`
at the repo root, which is committed with every sync.

## Managed paths

| Path | Handling |
|------|----------|
| `.agents/**`, `.claude/skills/**`, `.claude/mcp.json`, `skills-lock.json` | template-owned: synced, three-way merged when both sides changed |
| `CLAUDE.md`, `.vscode/settings.json`, `.gitignore`, `.github/**` | same, but expect repo-specific edits in `.gitignore` and `.github/workflows/terraform-ci.yml` |
| `AGENTS.md` | **compose**: the repo's module section plus the template's shared guide |
| `.ruler/**`, `GEMINI.md`, `.gemini/**`, `.kiro/**`, `.mcp.json`, `.github/copilot-instructions.md`, `.claude/commands/**`, `.claude/agents/**` | retired by the template: deleted after review |
| `.claude/settings.local.json`, all Terraform code, README, CHANGELOG, release-please files | never touched |

Skills in the repo that the template doesn't have are left alone.

## Workflow

### 1. Prepare

```bash
cd <repo>
git status --short                 # note pre-existing changes; never stage or revert them
git switch -c chore/template-sync  # or the branch the user names
```

Choose the template source:
- **Local clone** (preferred when it exists, e.g. `../terraform-module`): pass
  `--template <path>`. The script fetches `origin`. Sync from a committed ref, never the
  template's working tree. The default is `--ref origin/main`. Pass a branch only when the user
  wants unreleased template changes.
- **No clone:** omit `--template`, and the script clones `github.com/kbrockhoff/terraform-module`
  into a temporary directory.

### 2. Plan

```bash
python3 -I <this-skill-dir>/scripts/template_sync.py plan --repo . --template ../terraform-module \
  --conflicts-dir "$TMPDIR/template-sync"
```

The summary line counts paths by action. `--conflicts-dir` writes every `conflict` and `review`
path's template version, its base version, and the merge with conflict markers there, for use
in step 4. Keep that directory outside the repo.

- **First sync** (no `.template-sync.json`): there is no base, so every file that differs is
  `review`, and retired Ruler files are `delete-review`. If you know the template commit the
  repo was created from, pass `--base <sha>` to get real three-way merges.
- **Later syncs:** only template changes made since the marker appear.

### 3. Apply the mechanical changes

```bash
python3 -I <this-skill-dir>/scripts/template_sync.py apply --repo . --template ../terraform-module
```

This writes `add`, `update` and `merge` paths and deletes unmodified `delete` paths. That
includes replacing skill directories copied into `.claude/skills/<name>/` with the template's
symlink to `.agents/skills/<name>`. It then writes `.template-sync.json`. It exits 1 and lists
whatever still needs you.

**Resolve every listed path before committing.** The marker now points at the new template
commit. Anything left unresolved becomes a "repo customization" on the next sync, and the
template change behind it is silently lost.

### 4. Resolve what needs judgment

**`compose` AGENTS.md.** AGENTS.md has two parts:
1. **Module section** (repo-specific): the `# <Name> Terraform Module Guide for AI Agents`
   title, a one-paragraph purpose, and `## Components` with requirements per component. This
   runs up to the line before `## Terraform Module Guide`.
2. **Shared guide** (template-owned): everything from `## Terraform Module Guide` to the end.

Keep the repo's module section and replace the shared guide with the template's, verbatim. On
the first sync from Ruler, build the module section from `.ruler/instructions.md` (title,
purpose, components). Then compare each other `.ruler/*.md` with the template's shared guide.
Content the template has already absorbed or deliberately dropped goes away. Genuinely
repo-specific rules go into the module section under a `## Module-specific Rules` heading.
Don't re-add generic guidance the template removed.

**`review`** (first sync only) and **`conflict`.** Start from the template version, then carry
over repo-specific values:
- `.github/workflows/terraform-ci.yml`: keep the repo's checkov `--skip-check` list and its
  justification comments, extra test or example steps, and environment the module needs. Take
  the template's action versions, Terraform and Go versions, matrix and step structure.
- `.gitignore`: keep the template's file, and append the repo's extra entries. The template's
  `!.vscode/settings.json` and `.claude/settings.local.json` lines must stay.
- `.github/CODEOWNERS`, `.github/dependabot.yml`, `.github/CONTRIBUTING.md`, issue and PR
  templates: take the template's version unless the repo has a real difference, such as other
  owners or extra package ecosystems.
- `CLAUDE.md`: take the template's version (it imports AGENTS.md).

For a `conflict`, edit the `.merged` file from the conflicts directory and copy it over the
repo file. Never leave `<<<<<<<` markers.

**`delete-review`.** Confirm the content survives elsewhere: `.ruler/instructions.md` in the
AGENTS.md module section, and repo-specific rules in `## Module-specific Rules`. Then
`git rm -r` the paths. Generated files (`GEMINI.md`, `.github/copilot-instructions.md`,
`.gemini/settings.json`, `.ruler/ruler.toml`, `.ruler/mcp.json`) can go once you've checked
that `.agents/mcp.json` covers their MCP servers. If a repo-only MCP server exists, tell the
user rather than dropping it.

**Files the template now ignores.** If `git ls-files .claude/settings.local.json` lists it,
run `git rm --cached .claude/settings.local.json`. It holds per-developer permissions, and
the template's `.gitignore` excludes it.

### 5. Verify

```bash
python3 -I <this-skill-dir>/scripts/template_sync.py plan --repo . --template ../terraform-module
```
The plan must now show only `unchanged`, `keep` (the customizations you chose) and
`repo-only`.

Also check:
- **Symlinks:** every `.claude/skills/*` and `.claude/mcp.json` link resolves:
  `for l in .claude/skills/* .claude/mcp.json .agents/agents.md; do [ -e "$l" ] || echo "broken: $l"; done`
- **Skills lock:** every skill in `skills-lock.json` exists under `.agents/skills/`.
- **No leftovers:** `grep -rn '\.ruler\|copilot-instructions\|GEMINI' --exclude-dir=.git --exclude=CHANGELOG.md .`
  finds nothing outside history files.
- **Repo checks:** `make check` and `make lint`. If workflows changed and `actionlint` is
  installed, run it on `.github/workflows`.
- **Staged set:** `git status --short`. Only managed paths and `.template-sync.json` should
  change, plus any pre-existing edits you noted, which stay unstaged.

### 6. Report and commit

Report the template range synced (`base..head`), counts by action, every manual decision (what
was kept from the repo and why), and anything the user should look at, such as repo-only MCP
servers or dropped rules. Commit only if the user asks, as
`chore(template): sync agent config and CI from terraform-module <short-sha>`, including
`.template-sync.json`.

## Common mistakes

- Committing with unresolved `conflict` or `review` paths. The marker already moved, so the
  template change is lost on the next sync.
- Overwriting `terraform-ci.yml` wholesale and dropping the repo's checkov skips, or the
  reverse: keeping the repo's file and missing the template's action and version bumps.
- Syncing from the template's working tree or an unpushed branch without the user asking.
- Editing files under `.agents/skills/` in the module repo. They are vendored, so change them
  in the template and sync.
- Deleting `.ruler/instructions.md` before its module description is in AGENTS.md.
