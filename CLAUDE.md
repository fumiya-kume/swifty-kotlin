# CLAUDE.md

AI 向けクイックリファレンス。詳細なアーキテクチャ・ナビゲーション情報は [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) を参照。

## プロジェクト概要

KSwiftK は Swift で書かれた Kotlin コンパイラ。Kotlin 2.3.10 stable をターゲットとし、LLVM 経由で macOS ネイティブ実行ファイルを生成する。実行バイナリは `kswiftc`。

## ビルド & テストコマンド

```bash
swift build                              # デバッグビルド
swift build -c release                   # リリースビルド
bash Scripts/swift_test.sh                               # 全テスト（並列）
bash Scripts/swift_test.sh --filter SmokeTests           # スモークテスト
bash Scripts/swift_test.sh --filter Golden   # ゴールデン（Swift Testing: Golden.Lexer / Parser / Sema / Diagnostics）
bash Scripts/swift_test.sh --filter Golden.Sema   # Sema ゴールデンのみ
bash Scripts/swift_test.sh --filter CompilerCoreTests.LoweringPassRegressionTests  # 単一 XCTest クラス
.build/debug/kswiftc path/to/file.kt -o out  # コンパイラを直接実行
```

### ゴールデンテスト更新

```bash
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden
git diff -- Tests/CompilerCoreTests/GoldenCases
```

### テスト所要のざっくり計測（ゴールデン）

```bash
time swift test --filter Golden.Lexer
time swift test --filter Golden.Sema
```

### kotlinc 回帰差分

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt  # 単一ケース
bash Scripts/diff_kotlinc.sh Scripts/diff_cases            # 全ケース
```

CI で diff が落ちたとき: GitHub 上はジョブ **Summary** と **Artifacts**（TSV・失敗ケースディレクトリ）を優先。`gh run view RUN_ID --log-failed` だけだと、kotlinc diff ステップは `continue-on-error` のため **本体ログが含まれない**ことがある。全文ログでは `FAIL ` を grep。

## アーキテクチャ概要

```
LoadSources → Lex → Parse → BuildAST → SemaPasses → BuildKIR → Lowering → Codegen → Link
```

モジュール構成: `CompilerCore`（コンパイラ本体）/ `KSwiftKCLI`（CLIエントリ）/ `Runtime`（GC・coroutine）/ `CLLVM`（LLVM C API ブリッジ）

詳細なディレクトリマップ・フェーズ仕様・タスク別ナビゲーションは → [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

## コーディング規約

- Swift 5.9, macOS 12+, 4スペースインデント
- 型/enum/プロトコル: `UpperCamelCase`、関数/変数: `lowerCamelCase`
- フォーマッタ未設定 — 既存ファイルのスタイルに従う
- コミットメッセージ: 短く命令形（例: "Add ...", "Fix ..."）
- 診断コード: `KSWIFTK-{PHASE}-{NUMBER}` 形式（例: `KSWIFTK-SEMA-0001`）
- 分割ファイルは責務ベースで命名（`+Part2` のような番号付き名は禁止）

## 主要ドキュメント

| ファイル | 内容 |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | ディレクトリマップ・データフロー・タスク別ナビゲーション |
| [`docs/spec.md`](docs/spec.md) | フェーズ別実装仕様（Swift 型・API レベル） |
| [`docs/debugging.md`](docs/debugging.md) | DWARF / lldb デバッグガイド |
| [`TODO.md`](TODO.md) | 未完了タスク一覧 |
