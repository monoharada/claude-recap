#!/usr/bin/env bash
# session-digest.sh — Summarize Claude Code sessions in a time range,
# clustered by intent/motivation rather than individual tasks.
#
# Usage:
#   session-digest.sh                           # today, list mode
#   session-digest.sh yesterday
#   session-digest.sh "2 days ago"
#   session-digest.sh 2026-05-18 2026-05-20
#
# Modes:
#   --list       (default) bullet list of sessions
#   --json       one JSON object per session, oldest -> newest
#   --synthesize call `claude -p` and produce a Markdown report clustered
#                by motivation. Slow (separate API call). For interactive
#                use inside a Claude Code session, prefer the /recap slash
#                command (see commands/recap.md) instead.
#
# Reads:
#   $CLAUDE_RECAP_PROJECT_DIRS — colon-separated list of "<dir>:<label>" pairs.
#   Defaults to "$HOME/.claude/projects:claude" if unset.
#
#   Examples:
#     # default Claude Code install only
#     unset CLAUDE_RECAP_PROJECT_DIRS
#
#     # multiple installs (different CLAUDE_CONFIG_DIR setups, worktrees, etc.)
#     export CLAUDE_RECAP_PROJECT_DIRS="$HOME/.claude/projects:host:$HOME/.claude-work/projects:work"

set -euo pipefail

MODE="list"
ARGS=()
for a in "$@"; do
  case "$a" in
    --list)               MODE="list"  ;;
    --json)               MODE="json"  ;;
    --synthesize|--synth) MODE="synth" ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]:-}"

SINCE="${1:-today 00:00}"
UNTIL="${2:-}"

to_epoch() {
  local s="$1"
  date -d "$s" +%s 2>/dev/null \
    || date -j -f "%Y-%m-%d %H:%M:%S" "$s" +%s 2>/dev/null \
    || date -j -f "%Y-%m-%d" "$s" +%s 2>/dev/null \
    || {
      case "$s" in
        today|"today 00:00") date -j -v0H -v0M -v0S +%s ;;
        yesterday)           date -j -v-1d -v0H -v0M -v0S +%s ;;
        *) echo "Cannot parse date: $s" >&2; return 1 ;;
      esac
    }
}

SINCE_EPOCH=$(to_epoch "$SINCE")
UNTIL_EPOCH=$([[ -n "$UNTIL" ]] && to_epoch "$UNTIL" || date +%s)

# Build ROOTS from CLAUDE_RECAP_PROJECT_DIRS or fall back to default.
declare -a ROOTS
if [[ -n "${CLAUDE_RECAP_PROJECT_DIRS:-}" ]]; then
  IFS=':' read -ra raw <<<"$CLAUDE_RECAP_PROJECT_DIRS"
  # raw is alternating <dir> <label> entries
  i=0
  while (( i < ${#raw[@]} )); do
    dir="${raw[i]}"
    label="${raw[i+1]:-claude}"
    ROOTS+=("$dir:$label")
    i=$((i + 2))
  done
else
  ROOTS=("$HOME/.claude/projects:claude")
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/session-digest.XXXXXX")
trap 'rm -f "$tmp"' EXIT

for entry in "${ROOTS[@]}"; do
  root="${entry%:*}"
  flavor="${entry##*:}"
  [[ -d "$root" ]] || continue
  while IFS= read -r f; do
    if stat -f '%m' "$f" >/dev/null 2>&1; then
      mt=$(stat -f '%m' "$f")
    else
      mt=$(stat -c '%Y' "$f")
    fi
    if (( mt >= SINCE_EPOCH && mt <= UNTIL_EPOCH )); then
      printf '%s\t%s\t%s\n' "$mt" "$flavor" "$f" >> "$tmp"
    fi
  done < <(find "$root" -maxdepth 3 -name '*.jsonl' -not -path '*/subagents/*' 2>/dev/null)
done

if [[ ! -s "$tmp" ]]; then
  echo "No sessions in range." >&2
  exit 0
fi

since_human=$(date -r "$SINCE_EPOCH" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$SINCE_EPOCH" '+%Y-%m-%d %H:%M')
until_human=$(date -r "$UNTIL_EPOCH" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$UNTIL_EPOCH" '+%Y-%m-%d %H:%M')

# JQ: collect a rich session record. We keep first_prompt long (1500 chars)
# so the *motivation* behind a session survives. last_prompt is shorter — it
# is mostly used to infer "how did this end / where did we leave off".
JQ_FILTER='
def clean(s; n): (s // "") | gsub("\\s+"; " ") | sub("^\\s+"; "") | .[0:n];
def isnoise(s): (s // "") | (test("^<(command-|local-command-|bash-)") or test("^This session is being continued"));
[inputs]
| reduce .[] as $r (
    {ai_title:"", slash:"", first_real:"", last_user:"", cwd:"", branch:"", session:"", count:0};
    if $r.type == "ai-title" then
      .ai_title = ($r.aiTitle // .ai_title)
    elif $r.type == "user" and ($r.message.content | type) == "string" then
      .cwd = ($r.cwd // .cwd)
      | .branch = ($r.gitBranch // .branch)
      | .session = ($r.sessionId // .session)
      | ($r.message.content) as $c
      | .count = (.count + (if isnoise($c) then 0 else 1 end))
      | (if ($c | test("^<command-name>")) and .slash == "" then
           .slash = ($c | capture("<command-name>(?<n>[^<]+)").n)
         else . end)
      | (if (isnoise($c) | not) and ($c | length) > 12 and .first_real == "" then
           .first_real = $c
         else . end)
      | (if (isnoise($c) | not) and ($c | length) > 0 then
           .last_user = $c
         else . end)
    else . end
  )
| {
    session: .session,
    cwd: .cwd,
    branch: .branch,
    ai_title: clean(.ai_title; 200),
    slash: clean(.slash; 80),
    first_prompt: clean(.first_real; 1500),
    last_prompt: clean(.last_user; 600),
    prompt_count: .count
  }
'

emit_json() {
  sort -n "$tmp" | while IFS=$'\t' read -r mt flavor f; do
    iso=$(date -r "$mt" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d "@$mt" '+%Y-%m-%dT%H:%M:%S%z')
    rec=$(jq -c "$JQ_FILTER" "$f" 2>/dev/null || true)
    [[ -z "$rec" || "$rec" == "null" ]] && continue
    jq -c --arg t "$iso" --arg flavor "$flavor" --arg mt "$mt" \
      '. + {time:$t, flavor:$flavor, mtime:($mt|tonumber)}' <<<"$rec"
  done
}

emit_list() {
  echo "# Sessions  $since_human  →  $until_human"
  echo
  emit_json | while IFS= read -r rec; do
    sid=$(jq -r '.session' <<<"$rec")
    cwd=$(jq -r '.cwd' <<<"$rec")
    branch=$(jq -r '.branch' <<<"$rec")
    title=$(jq -r '.ai_title' <<<"$rec")
    slash=$(jq -r '.slash' <<<"$rec")
    first=$(jq -r '.first_prompt' <<<"$rec")
    last=$(jq -r '.last_prompt' <<<"$rec")
    flavor=$(jq -r '.flavor' <<<"$rec")
    mt=$(jq -r '.mtime' <<<"$rec")
    count=$(jq -r '.prompt_count' <<<"$rec")

    [[ -z "$sid" ]] && continue
    base=$(basename "${cwd:-?}")
    hhmm=$(date -r "$mt" '+%m-%d %H:%M' 2>/dev/null || date -d "@$mt" '+%m-%d %H:%M')

    show_title=""
    if   [[ -n "$title" ]];  then show_title="$title"
    elif [[ -n "$slash" ]];  then show_title="/$slash"
    elif [[ -n "$first" ]];  then show_title="${first:0:80}"
    else                          show_title="(no readable prompt)"
    fi
    branch_str=""; [[ -n "$branch" && "$branch" != "HEAD" ]] && branch_str=" ($branch)"
    flavor_str=""; [[ "${#ROOTS[@]}" -gt 1 ]] && flavor_str=" [$flavor]"

    printf '• %s%s %s%s  (%s prompts)\n' "$hhmm" "$flavor_str" "$base" "$branch_str" "$count"
    printf '    title : %s\n' "$show_title"
    [[ -n "$first" ]] && printf '    intent: %s\n' "${first:0:140}"
    if [[ -n "$last" && "$last" != "$first" ]]; then
      printf '    last  : %s\n' "${last:0:140}"
    fi
    printf '    resume: cd %q && claude --resume %s\n\n' "${cwd:-?}" "$sid"
  done
}

emit_synth() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "claude CLI not found; falling back to --list" >&2
    emit_list
    return
  fi

  prompt='以下は私 (ユーザー) が指定期間に Claude Code 上で開いたセッション群の生データです。
時系列順に並んでおり、各ブロックは1セッション分です。

あなたの仕事は、これらのセッションを **「私が何を成し遂げようとしていたか（動機・目的）」のテーマごとにクラスタリングして要約する** こと。
個別の作業内容ではなく、その背後にある狙いで束ねること。
脱線・メタ作業（モデル切替、token 確認、設定変更、ログ記録など）は最後にまとめてよい。

各クラスタについて以下を書いてください:

### <テーマ: 私の言葉で「何を達成しようとしていたか」>
- **動機**: なぜこれをやろうとしていたのか（first_prompt の長文や ai_title から推測）。表層のタスクではなくその背後にある狙い
- **進行**: どのセッションがどの順で何を進めたか。HH:MM cwd-basename (session-id短縮) で最小限に
- **現在地**: 完了 / 進行中 / ブロック / ハンドオフ済 のどれか、根拠は last_prompt
- **次の一手**: 私が再開するなら何から触るべきか
- **resume**: 再開価値が高い 1〜2 件。session_id は **生データのものを 1 文字も変えずに** コピーすること。形式: `cd <cwd> && claude --resume <session-id>`

最後に「## 脱線・メタ」セクションを置き、本筋から外れた短いセッションを 1 行ずつ並べる。

出力は日本語、Markdown、冗長な前置きなし。

--- 以下が生データ ---
'
  {
    printf '%s\n\n' "$prompt"
    emit_json | jq -r '
      "## " + .time + "  " + (.cwd // "?") + (if .branch != "" and .branch != "HEAD" then " (" + .branch + ")" else "" end),
      "session_id: " + .session,
      "ai_title: " + (.ai_title // ""),
      "slash: " + (.slash // ""),
      "prompt_count: " + (.prompt_count|tostring),
      "first_prompt: " + (.first_prompt // ""),
      "last_prompt: " + (.last_prompt // ""),
      ""
    '
  } | claude -p --permission-mode bypassPermissions
}

case "$MODE" in
  list)  emit_list  ;;
  json)  emit_json  ;;
  synth) emit_synth ;;
esac
