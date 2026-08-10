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
| [`comment-review-a`](skills/comment-review-a/) [`-b`](skills/comment-review-b/) [`-c`](skills/comment-review-c/) | Three variants of the same PR-time job — review the comments in one change. Being compared in real use; see below. |
| [`ci-delta-reports`](skills/ci-delta-reports/) | Sets up GitHub Actions CI that reports what *changed* between base and PR — new vs resolved type errors, lint issues, formatter drift, bundle size, test failures — in one PR comment that updates in place. |

`spec-debt` came from `mhsnook/journo-harness@707bc1e`, branch
`skill/spec-debt-audit`. Its worked examples cite that project's paths; the
method is what transfers.

### The comment-review trial

Three variants of one skill, installed together and invoked by name, to find out
which actually works before one of them ships as `comment-review`.

| | What it is | Length |
|---|---|---|
| **A** | The original copy-paste prompt, unchanged. The control — it ran in real sessions before any of this was a skill. | 55 lines |
| **B** | The structured rewrite. A's judgment reorganised around drift, over-specification and invisible specs, with the extent, the report shape and the apply step spelled out. | 251 lines |
| **C** | The hybrid. A's checklist, still short and imperative, with drift promoted to the first check, the signpost exemption given a test, and the closing rebalanced so deletion stops being scored as a win. | 94 lines |

The open question is whether B's structure earns its 4.5× length, or whether an
imperative checklist just drives behaviour better than an essay does. C exists
because the answer is plausibly "neither" — that A was mostly right and needed
three grafts.

Each variant's description tells the model not to auto-select, so asking for "a
comment review" without naming one gets you a question rather than an arbitrary
pick. Name the variant: `/comment-review-a`.

A is verbatim apart from two typo fixes (`referance`, and `documents` for
`document`). Notably it still says "this batch of work" rather than resolving a
diff, which is a real difference from B and C and is being tested rather than
patched.

When one wins, the other two go and the survivor is renamed.

`spec-debt` and the comment-review variants share doctrine and are edited
together. They cannot share a file: `upload.sh` sends each `skills/<name>/` as
an isolated tree, so a cross-directory reference resolves locally and breaks
everywhere else. The overlap is the cut list, the signpost rule, and the
absolutes table. Change one, look at the others. The procedure around that
doctrine is genuinely different in each and should not be reconciled.

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
