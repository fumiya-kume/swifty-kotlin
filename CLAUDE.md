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
bash Scripts/swift_test.sh --filter Golden               # ゴールデン全部（Swift Testing: Lexer / Parser / Sema / Diagnostics）。`Golden` はシンボル名の部分一致
bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden  # Sema ゴールデンのみ（`Golden.Sema` は @Suite 表示名のため --filter に効かない）
bash Scripts/swift_test.sh --filter CompilerCoreTests.LoweringPassRegressionTests  # 単一 XCTest クラス
.build/debug/kswiftc path/to/file.kt -o out  # コンパイラを直接実行
```

### ゴールデンテスト更新

CI（Full Swift Tests）と Swift の言語モードを揃えるなら `-Xswiftc -swift-version -Xswiftc 6` を付ける。

```bash
# 全ゴールデン（Lexer / Parser / Sema / Diagnostics）を一括更新
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6

# Sema のみ更新する例
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6

git diff -- Tests/CompilerCoreTests/GoldenCases
```

### テスト所要のざっくり計測（ゴールデン）

`Golden.Lexer` / `Golden.Sema` のような @Suite ラベルはログ用で、`swift test --filter` にはそのままではマッチしない。型名で指定する。

```bash
time swift test --filter CompilerCoreTests.GoldenLexerGoldenTests/matchesGolden
time swift test --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden
# 四スイートまとめて計測するなら
time swift test --filter Golden
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
