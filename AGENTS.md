# AGENTS.md

AI 向けの補足。プロジェクトのクイックリファレンスは [`CLAUDE.md`](CLAUDE.md)、アーキテクチャは [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) を参照。

## Cursor Cloud specific instructions

### 概要

KSwiftK は **SwiftPM の単一リポジトリ**で、長期稼働するアプリサーバーは不要。開発では **Swift 6.2**、**LLVM 開発パッケージ**、ビルド成果物 **`kswiftc`** を使う。Linux（Ubuntu 24.04）では CI と同様に ELF オブジェクト／リンクまで検証できるが、製品ターゲット OS は **macOS**（README / `Package.swift` の platforms）。

### 必須環境変数（Linux）

CI の [`.github/actions/setup-swift-llvm/action.yml`](.github/actions/setup-swift-llvm/action.yml) と同じ考え方:

| 変数 | 用途 |
|------|------|
| `C_INCLUDE_PATH` | `llvm-config --includedir`（例: `/usr/lib/llvm-18/include`） |
| `LIBRARY_PATH` | `llvm-config --libdir` |
| `KSWIFTK_LLVM_DYLIB` | `libLLVM*.so` の実ファイル（例: `/usr/lib/llvm-18/lib/libLLVM.so.1`） |

`llvm-dev` が入っていれば、シェル起動時に `llvm-config` から上記を組み立てるのが安全。

### Swift ツールチェーン（Linux VM）

- 公式 tarball を `/opt/swift-6.2` に展開し、`PATH` に `/opt/swift-6.2/usr/bin` を追加する（`swift-tools-version: 6.2` に合わせる）。
- 新しいシェルでは `~/.bashrc` の KSwiftK ブロックが PATH / LLVM 変数を設定する想定。

### ビルド・テスト・実行

標準コマンドは [`CLAUDE.md`](CLAUDE.md) のとおり。Linux での典型例:

```bash
swift build
bash Scripts/swift_test.sh --filter SmokeTests -Xswiftc -swift-version -Xswiftc 6
.build/debug/kswiftc Scripts/diff_cases/hello.kt -o /tmp/hello && /tmp/hello
```

- **スモーク**: `SmokeTests` はドライバ・KIR・LLVM オブジェクト生成まで（約 3 分、初回はテスト用バイナリのビルド込み）。
- **全テスト**: `bash Scripts/swift_test.sh` は長時間。並列は `SWIFT_TEST_PARALLEL` / `SWIFT_TEST_WORKERS`（[`Scripts/README.md`](Scripts/README.md)）。
- **kotlinc 差分**（任意）: JDK 21 + Kotlin 2.3.10 + `Scripts/diff_kotlinc.sh`。CI の diff ジョブ専用で、通常の `swift test` には不要。

### リント / フォーマット

このリポジトリの HEAD によっては `Scripts/swift_lint.sh` / `Scripts/swift_format.sh` が無い場合がある。存在する場合は [`Scripts/README.md`](Scripts/README.md) を参照。常に使える検証例: `bash Scripts/validate_runtime_abi_links.sh`。

### 注意点

- `kswiftc` でリンクする際、Swift リンカ（`swiftc`）が PATH に必要。
- Linux で `kswiftc` 実行時に `libswiftCore` 向けの linker warning が出ることがあるが、`hello.kt` のような最小ケースでは実行は成功する。
- ゴールデン更新は `UPDATE_GOLDEN=1` と `-Xswiftc -swift-version -Xswiftc 6` を CI に合わせて使う（[`CLAUDE.md`](CLAUDE.md)）。
