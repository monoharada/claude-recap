# claude-recap

> Recap your past [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) sessions, **clustered by what you were trying to accomplish** — not by tasks, not by timestamp.

[日本語版 README](./README.ja.md)

When you run multiple Claude Code sessions in parallel ("let me start another one while this one is thinking…"), the *motive* behind each one evaporates fast. The next morning you stare at `claude --resume`'s session picker and see fourteen entries titled "おわった？" / "oi" / "/model" with no idea what you were actually working on.

`claude-recap` reads the JSONL transcripts Claude Code stores locally, filters them by time range, and produces a Markdown report grouped by **intent**. There are two ways to use it:

1. **`/recap` slash command** — runs *inside* a Claude Code session. The current Claude reads the raw data and writes the cluster summary in the same turn. Fast, conversational ("now show me more about the FigJam cluster"), no extra API call.
2. **`session-digest.sh`** — standalone shell script. Three modes: `--list` (bullet list), `--json` (one record per line, for piping), `--synthesize` (calls `claude -p` to produce a report non-interactively; slower but works in cron).

## Why this exists

In an LLM-native workflow, the cost of starting a new session is effectively zero. While Claude is thinking, you start another session about something that just caught your interest, and another, and another. This isn't a forced "context switch" — it's voluntary, curiosity-driven, more like *gliding across a search space* than getting yanked between unrelated tasks.

But the cost isn't zero. It just shows up as something other than switching cost:
- **Accumulating unfinished threads**
- **Decision fatigue**
- **Evaporation of "what was I actually digging into?"**

Because the LLM externalizes your short-term memory, the *retention* cost the human brain used to bear becomes invisible. The symptom: "I don't feel tired but the whole picture has gone fuzzy."

For this style, the actual question isn't "how do I switch less?" It's:

- Which threads are still alive?
- Which are exploration vs. convergence?
- What gets dropped, what gets pinned?
- When do I crystallize a thought?

**The problem isn't moving fast — it's knowing when to come down from exploration into convergence.**

But Claude Code ships with no built-in feature to:
- Take a date range and list everything you did
- Cross-summarize multiple sessions
- Cluster by motivation rather than timestamp

`/resume` is interactive-only. Plain `grep` over JSONL works but the short follow-up prompts ("oi", "yes", "go") look meaningless without context.

`claude-recap` plugs that gap. It leans on the auto-generated `ai-title` field plus the long *first* prompt of each session — that's where the real intent lives — to reconstruct what you were trying to accomplish. **Not a tool for abandoning parallel exploration; a tool for keeping it while still being able to grasp the whole.**

## Install

Requires `bash`, `jq`, `find`, `date`, and the `claude` CLI on `$PATH`.

```bash
git clone https://github.com/<you>/claude-recap.git
cd claude-recap
./install.sh
```

This drops two files:
- `~/.claude/scripts/session-digest.sh`
- `~/.claude/commands/recap.md` (the slash command)

## Use it

### Inside a Claude Code session (recommended)

```
/recap                        # yesterday (default)
/recap today
/recap "2 days ago"
/recap 2026-05-18 2026-05-20
```

Output: a Markdown report clustered by intent, with `cd … && claude --resume …` lines you can copy and paste to dive back in.

You can keep asking follow-ups in the same turn: "expand the R7 cluster", "which of these can I drop?", "make me a handoff doc for the in-progress one".

### From the shell

```bash
~/.claude/scripts/session-digest.sh                  # today, list mode
~/.claude/scripts/session-digest.sh yesterday
~/.claude/scripts/session-digest.sh "2 days ago"
~/.claude/scripts/session-digest.sh 2026-05-18 2026-05-20

~/.claude/scripts/session-digest.sh --json yesterday | jq ...
~/.claude/scripts/session-digest.sh --synthesize yesterday   # slower, calls claude -p
```

## Sample output

```
### Migrate the billing service off the legacy queue
- Motive: The legacy queue is being decommissioned next quarter. The user
  is splitting the billing worker into two consumers and validating the
  new topology before cutting over.
- Progress:
  - 09:12 billing-svc (1a2b…) — drafted the new consumer skeleton
  - 10:30 billing-svc (3c4d…) — added integration tests against the staging broker
  - 14:05 infra (5e6f…) — wrote the Terraform diff for the new topic
- Where it stands: in progress; staging tests pass but production cutover plan unwritten.
- Next move: write the cutover runbook and dry-run it against staging once more.
- Resume:
  cd ~/code/billing-svc && claude --resume 3c4d5e6f-7890-1234-5678-90abcdef1234

## Side trips / meta
- 08:40 dotfiles (9f8e…) — one-shot question about a zsh prompt glitch
- 11:15 (7d6c…) — `/model` switch to opus
- 16:02 (5b4a…) — debugging an unrelated token-usage spike
```

## Multiple Claude installs

If you run more than one Claude Code config (e.g. `CLAUDE_CONFIG_DIR=$HOME/.claude-work claude` for work and the default for personal), point the script at both:

```bash
export CLAUDE_RECAP_PROJECT_DIRS="$HOME/.claude/projects:host:$HOME/.claude-work/projects:work"
```

Format: colon-separated `<dir>:<label>` pairs. The label appears in the list output to disambiguate.

If unset, the script reads `$HOME/.claude/projects` only.

## How it works

For each `*.jsonl` file under the configured project roots whose mtime falls in the range, the script extracts:

| field | source | why |
|---|---|---|
| `ai_title` | `type=ai-title` row | Claude's auto-generated title, the strongest single-line summary |
| `slash` | first `<command-name>` | catches `/foo` invocations even when no other prompt exists |
| `first_prompt` | first user message ≥12 chars, not a bash/command tag | where motivation usually lives — kept up to 1500 chars |
| `last_prompt` | last meaningful user message | how the session ended / where you left off |
| `prompt_count` | non-noise user messages | distinguishes "real" sessions from one-shot pings |
| `cwd`, `branch` | per-message metadata | so resume commands work |

Then either you (in `/recap`) or `claude -p` (in `--synthesize`) cluster on motive.

## Limitations

- Reads only what Claude Code persists locally. Sessions opened with `--no-session-persistence` are invisible.
- The `ai-title` is generated asynchronously; very recent sessions may not have one yet (the script falls back to `slash` then `first_prompt`).
- Subagent transcripts (`*/subagents/*.jsonl`) are deliberately skipped — they're rarely the right grain to recap on.
- mtime is used as the session timestamp. Resumed sessions move forward in time, which is usually what you want, but means a session that started yesterday and was resumed today shows up under "today".

## License

MIT.
