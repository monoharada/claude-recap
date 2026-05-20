# claude-recap

> 過去の [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) セッションを **「何を達成しようとしていたか（動機）」ごとにクラスタリングして俯瞰する** ツール。タスク列でも時系列でもなく、意図で束ねる。

[English README](./README.md)

Claude Code でセッションを並列に開きまくる人（「これ考えてる間にもう一つ別の聞こう…」）ほど、後から動機が蒸発する。翌朝 `claude --resume` の picker を開くと、`おわった？` / `oi` / `/model` みたいな短文タイトルが 14 個並んでいて、自分が何をやろうとしていたのか分からない。

`claude-recap` は Claude Code がローカルに保存している JSONL を読み、期間でフィルタし、**動機ごとにクラスタリングした Markdown レポート** を生成する。使い方は 2 通り:

1. **`/recap` スラッシュコマンド** — Claude Code セッション*内*で実行。今喋っている Claude が生データを読んでその場でクラスタ要約を返す。同ターン内で完結するので速いし、追加質問もそのままできる（「FigJam クラスタもう少し詳しく」「これと連動してる別の作業ある？」）。
2. **`session-digest.sh`** — スタンドアロンのシェルスクリプト。3 モード: `--list`（箇条書き）、`--json`（1行1レコード、パイプ用）、`--synthesize`（`claude -p` を呼んで非対話的にレポート生成。遅いが cron で動く）。

## なぜ作ったか

LLM 環境では、セッションを増やすコストがほぼゼロになる。Claude の返答待ちの間に「あ、これも気になる」と新しいセッションを開く、それを繰り返す、というのは普通の知的活動になった。これは強制的な「コンテキストスイッチ」とは違う — 自発的に、興味駆動で、探索空間を滑走している感覚に近い。

ただし負荷がゼロかと言うとそうではない。それは「切り替えコスト」ではなく:
- **未完了状態の累積**
- **判断疲労**
- **「何を掘っていたか」の蒸発**

として後から効いてくる。LLM が短期記憶を外部化してくれるおかげで、本来人間の脳が持っていた「保持コスト」が見えなくなる。結果として「疲れていない気がするのに、なぜか全体の輪郭がぼやける」が起きる。

このスタイルで本当に重要なのは「切り替えを減らすこと」ではなく、

- どのスレッドが生きているか
- どれが探索でどれが収束フェーズか
- 何を捨てるか / どこで固定するか
- いつ「考えを結晶化」するか

を把握すること。**問題は多動的に動くこと自体ではなく、探索モードから収束モードへいつ降りるかのほう**にある。

しかし Claude Code 公式機能には:
- 期間指定で何をやったか一覧する
- 複数セッションを横断要約する
- 時刻ではなく動機でクラスタリングする

これらが **存在しない**。`/resume` は対話 picker のみ、JSONL を `grep` するだけだと「oi」「はい」「go」みたいな短い続き発話が文脈を失って意味不明になる。

`claude-recap` はここに刺す。Claude が自動生成する `ai-title` と、各セッションの **最初の長いプロンプト**（動機はだいたいそこに入っている）を組み合わせて、「自分が何を掘っていたか」を後から再構成できるようにする。**並列探索を捨てるためのツールではなく、並列探索を続けたまま全体を掴み直すためのツール**。

## インストール

必要環境: `bash`, `jq`, `find`, `date`, `claude` CLI が `$PATH` にあること。

```bash
git clone https://github.com/monoharada/claude-recap.git
cd claude-recap
./install.sh
```

これで以下 2 ファイルが配置される:
- `~/.claude/scripts/session-digest.sh`
- `~/.claude/commands/recap.md`（スラッシュコマンド）

## 使い方

### Claude Code セッション内（推奨）

```
/recap                        # 昨日（デフォルト）
/recap today
/recap "2 days ago"
/recap 2026-05-18 2026-05-20
```

出力は動機ごとにクラスタリングされた Markdown レポート。各クラスタに `cd … && claude --resume …` がついているので、コピペで再開できる。

そのまま追加質問できる: 「R7 のクラスタもう少し深く」「これ捨てていい？」「進行中のやつのハンドオフ書いて」など。

### シェルから

```bash
~/.claude/scripts/session-digest.sh                  # 今日、list モード
~/.claude/scripts/session-digest.sh yesterday
~/.claude/scripts/session-digest.sh "2 days ago"
~/.claude/scripts/session-digest.sh 2026-05-18 2026-05-20

~/.claude/scripts/session-digest.sh --json yesterday | jq ...
~/.claude/scripts/session-digest.sh --synthesize yesterday   # 遅い、claude -p 経由
```

## 出力サンプル

```
### 課金サービスを旧キューから移行する
- 動機: 旧キューが来四半期で廃止予定。billing worker を 2 consumer に分割し、
  新トポロジを切替前に検証したい。
- 進行:
  - 09:12 billing-svc (1a2b…) 新 consumer の骨格をドラフト
  - 10:30 billing-svc (3c4d…) staging broker に対する結合テスト追加
  - 14:05 infra (5e6f…) 新トピックの Terraform diff
- 現在地: 進行中。staging テストは通ったが本番切替手順が未着手
- 次の一手: 切替 runbook を書いて staging で dry-run
- resume:
  cd ~/code/billing-svc && claude --resume 3c4d5e6f-7890-1234-5678-90abcdef1234

## 脱線・メタ
- 08:40 dotfiles (9f8e…) zsh プロンプトの不具合に関する 1 ターン質問
- 11:15 (7d6c…) /model を opus に切替
- 16:02 (5b4a…) 別件の token 消費スパイク調査
```

## 複数の Claude 環境を使い分けている場合

Claude Code を複数の config で使い分けている場合（例: 仕事用に `CLAUDE_CONFIG_DIR=$HOME/.claude-work claude` 、個人用にデフォルト）、両方を読ませられる:

```bash
export CLAUDE_RECAP_PROJECT_DIRS="$HOME/.claude/projects:host:$HOME/.claude-work/projects:work"
```

形式: コロン区切りの `<dir>:<label>` ペア。複数 root を指定したときだけ list 出力にラベルが付与される。

未設定の場合は `$HOME/.claude/projects` のみを読む。

## 仕組み

設定された project root 配下の `*.jsonl` のうち、mtime が指定範囲に入るものから次を抽出する:

| フィールド | 抽出元 | 用途 |
|---|---|---|
| `ai_title` | `type=ai-title` 行 | Claude が自動生成するタイトル。最強の 1 行サマリ |
| `slash` | 最初の `<command-name>` | プロンプトが他に無くても `/foo` 起動を捕捉 |
| `first_prompt` | 12 文字以上で bash/command タグでない最初のユーザー発話 | 動機が住んでいる場所。最大 1500 字保持 |
| `last_prompt` | 最後の意味あるユーザー発話 | セッションがどこで終わったか／何が残ったか |
| `prompt_count` | ノイズを除いたユーザー発話数 | 「本物のセッション」と「1ターンの問い合わせ」を区別 |
| `cwd`, `branch` | メッセージごとのメタデータ | resume コマンドを正しく組み立てるため |

その後、`/recap` ならあなたが今喋っている Claude、`--synthesize` なら `claude -p` がこれを受け取って動機でクラスタリングする。

## 制限

- Claude Code がローカルに永続化したものしか読めない。`--no-session-persistence` で開いたセッションは見えない。
- `ai-title` は非同期生成。直近セッションにはまだ付いていないことがある（その場合は `slash` → `first_prompt` の順でフォールバック）。
- サブエージェントの transcript（`*/subagents/*.jsonl`）は意図的にスキップ。recap の粒度として粗すぎることが多いため。
- mtime をセッションのタイムスタンプとして使っている。resume したセッションは時刻が更新されるので、昨日始めて今日 resume したセッションは「今日」に分類される（多くの場合これが望ましい挙動）。

## ライセンス

MIT.
