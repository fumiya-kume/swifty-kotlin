# KSwiftK

**KSwiftK** は Swift で書かれた Kotlin コンパイラです。Kotlin 2.3.10 stable の機能をターゲットとし、LLVM 経由で macOS ネイティブ実行ファイルを生成します。

| 属性 | 値 |
|---|---|
| 実装言語 | Swift 5.9 / macOS 12+ |
| ビルドシステム | SwiftPM |
| 出力バイナリ | `kswiftc` |
| ターゲット | Kotlin 2.3.10 stable, macOS arm64/x86_64 |

---

## クイックスタート

```bash
# ビルド
swift build

# コンパイル & 実行
.build/debug/kswiftc hello.kt -o hello
./hello
```

---

## ビルド & テスト

```bash
swift build                    # デバッグビルド
swift build -c release         # リリースビルド

bash Scripts/swift_test.sh                             # 全テスト（並列）
bash Scripts/swift_test.sh --filter SmokeTests         # スモークテストのみ
bash Scripts/swift_test.sh --filter Golden # ゴールデンテストのみ（Swift Testing）

UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden  # ゴールデン更新
bash Scripts/diff_kotlinc.sh Scripts/diff_cases        # kotlinc との差分回帰テスト
```

---

## コンパイルパイプライン

```
LoadSources → Lex → Parse → BuildAST → SemaPasses → BuildKIR → Lowering → Codegen → Link
```

詳細は [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) を参照してください。

---

## ドキュメント

| ファイル | 内容 |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | アーキテクチャ詳細・ディレクトリマップ・タスク別ナビゲーション |
| [`docs/spec.md`](docs/spec.md) | フェーズ別実装仕様（Swift 型・API レベル） |
| [`docs/debugging.md`](docs/debugging.md) | DWARF デバッグ情報の使い方（lldb セッション例） |
| [`TODO.md`](TODO.md) | 未完了タスク一覧 |
| [`CLAUDE.md`](CLAUDE.md) | AI 向けクイックリファレンス |
