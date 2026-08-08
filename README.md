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
| [`ci-delta-reports`](skills/ci-delta-reports/) | Sets up GitHub Actions CI that reports what *changed* between base and PR — new vs resolved type errors, lint issues, formatter drift, bundle size, test failures — in one PR comment that updates in place. |

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
