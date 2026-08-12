# mhsnook/skills

Personal Claude skills, in one place, installable four ways.

One `skills/` tree serves every consumer — there is no duplicated content and no
build step.

## Install

**As a Claude Code plugin** (the main path — carries hooks, agents, and MCP
servers if a skill ever needs them):

```bash
claude plugin marketplace add mhsnook/skills
claude plugin install ci-delta-reports@mhsnook --scope user
```

Or from inside a session: `/plugin marketplace add mhsnook/skills`, then
`/plugin install ci-delta-reports@mhsnook`.

**With `npx skills`** (works for Cursor, Codex, and ~70 other agents):

```bash
npx skills add mhsnook/skills -s ci-delta-reports -g
```

**Locally, for authoring** — symlinks each skill into `~/.claude/skills`, so
edits here take effect in a running session without a restart:

```bash
./scripts/link-local.sh
```

**For cloud sessions, Cowork, and routines** — those read the skills enabled on
your claude.ai account, never `~/.claude/skills` on your machine:

```bash
ANTHROPIC_API_KEY=sk-... ./scripts/upload.sh
```

Then enable them at claude.ai → Settings → Capabilities → Skills. IDs land in
`.skill-ids.json`, so a later run publishes a new version rather than a
duplicate.

## Skills

| Skill | What it does |
|---|---|
| [`spec-debt`](skills/spec-debt/) | Read-only audit for specification debt: claims living at the wrong altitude, and claims stated more strongly than they are known. Produces a ledger and a report; edits nothing. |
| [`ci-delta-reports`](skills/ci-delta-reports/) | Sets up GitHub Actions CI that reports what *changed* between base and PR — new vs resolved type errors, lint issues, formatter drift, bundle size, test failures — in one PR comment that updates in place. |

`spec-debt` came from `mhsnook/journo-harness@707bc1e`, branch
`skill/spec-debt-audit`. Its worked examples cite that project's paths; the
method is what transfers.

## Hooks

| Hook | What it does |
|---|---|
| [`naming-pass`](hooks/naming-pass.md) | Ends every code-editing turn with one short pass: names too short to carry their meaning, and comments covering for names that should have said it themselves. Fires only when the turn touched code, and only once per turn. |

This one is a plugin with no skill in it — the payload is
[`hooks/naming-pass.json`](hooks/naming-pass.json), which wires two events:
`PostToolUse` on `Edit|Write|NotebookEdit` notes any code file that was
touched, and `Stop` hands Claude the checklist in
[`hooks/naming-pass.md`](hooks/naming-pass.md) and lets the turn continue.

```bash
claude plugin install naming-pass@mhsnook --scope user
```

Edit `hooks/naming-pass.md` to change what the pass asks — it is plain prose
handed straight to Claude, not a template. Two environment variables tune the
rest: `NAMING_PASS_EXTENSIONS` replaces the list of extensions that count as
code, and `NAMING_PASS_DISABLE=1` turns the whole thing off without
uninstalling it.

The pass never fires twice in a row. Claude Code sets `stop_hook_active` on a
`Stop` that a stop hook itself caused, and the script allows that stop rather
than asking for a pass on the pass.

## Adding a skill

```bash
mkdir -p skills/my-skill && $EDITOR skills/my-skill/SKILL.md
```

Then add a plugin entry to `.claude-plugin/marketplace.json`, pointing `skills`
at the new directory:

```json
{
  "name": "my-skill",
  "source": "./",
  "skills": ["./skills/my-skill"],
  "description": "…"
}
```

One plugin per skill keeps the install command specific
(`/plugin install my-skill@mhsnook`) and mirrors how `npx skills add -s` works.

A plugin that ships hooks instead of a skill swaps the `skills` key for
`hooks`, pointing at a config file rather than a directory:

```json
{
	"name": "my-hook",
	"source": "./",
	"hooks": "./hooks/my-hook.json",
	"description": "…"
}
```

The path has to be explicit. Every plugin here sets `"source": "./"`, so the
repo root is the plugin root for all of them, and a hook config at the default
`hooks/hooks.json` would attach itself to every plugin in the marketplace.

### Frontmatter must stay spec-clean

Claude Code accepts around twenty frontmatter fields. The Skills API, claude.ai
upload, and `npx skills` accept **six**:

```
name  description  license  compatibility  metadata  allowed-tools
```

Anything else — `argument-hint`, `disable-model-invocation`, `paths`, `model` —
makes `upload.sh` fail with a hard error rather than ignoring the field. Staying
inside the six keeps one file working everywhere. `upload.sh` checks this before
it sends anything.

## Where each install path actually reaches

| | Local sessions | Cloud sessions | Cowork / routines |
|---|---|---|---|
| Plugin, user scope | ✅ | ❌ | ❌ |
| Plugin declared in a repo's `.claude/settings.json` | ✅ that repo | ✅ that repo | ❌ |
| `npx skills add -g` | ✅ | ❌ | ❌ |
| `link-local.sh` | ✅ | ❌ | ❌ |
| `upload.sh` | ❌ | ✅ | ✅ |

Nothing reaches all three, so the working setup is `link-local.sh` plus
`upload.sh`. The plugin and `npx skills` paths are for other machines and other
people.

That table is about skills. Hooks are narrower: only the two plugin rows carry
them. `npx skills`, `link-local.sh`, and `upload.sh` all move `SKILL.md` files
and nothing else, so `naming-pass` reaches a local session by
`claude plugin install`, and a cloud session only by being named in that
repo's `.claude/settings.json`.
