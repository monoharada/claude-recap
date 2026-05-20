---
description: Recap past Claude Code sessions in a time range, clustered by intent/motivation. Default = yesterday. Pass any value `session-digest.sh` accepts (e.g. "today", "yesterday", "2 days ago", or two YYYY-MM-DD dates).
category: meta
allowed-tools: Bash(~/.claude/scripts/session-digest.sh:*), Bash(date:*)
argument-hint: "[since] [until]   # default: yesterday"
---

# /recap — cluster past sessions by what you were trying to do

You are about to summarize the user's recent Claude Code sessions, clustered by **what they were trying to accomplish** (motivation/intent), not by individual tasks.

## Step 1 — Collect raw session data

Run the digest script in `--json` mode for the requested period. The arguments come from the user; default to `yesterday` if none given.

```
!~/.claude/scripts/session-digest.sh --json ${ARGUMENTS:-yesterday}
```

Each line of stdout is one JSON object with these fields:
`time, mtime, flavor, session, cwd, branch, ai_title, slash, first_prompt (≤1500 chars), last_prompt (≤600 chars), prompt_count`

Sessions are ordered oldest → newest by mtime.

## Step 2 — Synthesize, clustered by intent

Read the JSON lines and produce a Markdown report. Do NOT just list sessions — cluster them by the underlying motive.

For each cluster, write:

### <theme: in the user's voice, "what they were trying to accomplish">
- **Motive**: why they were doing this. Infer from the long `first_prompt` and `ai_title`, not from surface task names.
- **Progress**: which sessions, in what order, did what. Reference each as `HH:MM cwd-basename (short-session-id)` — keep it terse.
- **Where it stands**: done / in progress / blocked / handed off. Justify from `last_prompt`.
- **Next move**: if the user resumes, what should they touch first.
- **Resume**: 1–2 sessions with the highest resume value. **Copy `session_id` verbatim from the JSON** — never invent or correct UUIDs (a wrong UUID is unusable). Format:
  ```
  cd <cwd> && claude --resume <session-id>
  ```

End with a `## Side trips / meta` section: one-liners for stray short sessions (model switches, config tweaks, one-shot questions).

## Style

- Match the user's language. If their `first_prompt`s are in Japanese, write the report in Japanese; if English, write in English.
- Markdown. No preamble.
- Session IDs: copy from JSON character-for-character.
- Sessions with `prompt_count` of 1–2 usually belong in "Side trips / meta".
- Recurring filenames or IDs (FigJam keys, Linear issue numbers, output paths) across multiple sessions are strong clustering evidence.
