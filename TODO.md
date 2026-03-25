# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-25

## 運用ルール

- `TODO.md` は未完了タスクを主に管理しつつ、直近で完了した大きめの項目は `[x]` で残してよい。
- タスクIDはカテゴリ接頭辞 (`LEX/TYPE/EXPR/CTRL/DECL/CLASS/PROP/FUNC/GEN/NULL/CORO/STDLIB/ANNO/TOOL/MPP`) + 3桁連番を使用する。
- 完了済みタスクを参照する場合は `[x]` または `既存実装済み` のどちらかで明示する。
- 共通完了条件（全タスク共通）:
  1. `Scripts/diff_kotlinc.sh` が exit 0 かつ stdout 完全一致
  2. golden テストが byte 一致
  3. エラーケースで `KSWIFTK-*` 診断コード出力
  4. 各項目末尾エッジケース golden が通過

---

## 未完了バックログ

監査で見つかった「簡易実装（Stub）」や「中途半端なパス」を将来の改善項目として追跡する。

- [x] CORO-001: Channel の send / バックプレッシャーを Kotlin suspend セマンティクスに揃える
  - 現状: 満杯時の扱い・Flow 側の eager ソースなど、Kotlin との差が残る（`RuntimeCoroutine.swift` の `RuntimeChannelHandle.send` 等）
  - **完了**: ✅ Prompt cancellation guaranteeを実装、✅ BufferOverflow戦略を追加、✅ continuationモデルへ移行、✅ テスト追加
- [ ] TEST-001: `kk_measureTime` およびシステム計測の Runtime XCTest 強化
  - 現状: `RuntimeDurationTests` で Duration 工場・`inWhole*`・`toString` はカバー。`kk_measureTime` 本体のテストは薄い
- [ ] TEST-002: Long/Double/Float 型強制の golden/smoke テスト追加
  - 現状: `HeaderHelpers+SyntheticCoercionStubs.swift` 先頭にテスト参照コメント。ケース拡充は未了
- [ ] TEST-003: Numeric bit-count 系のエッジケーステスト追加
  - 現状: `RuntimeNumericCompat.swift` にビット数まわりの TODO コメント（行は実装変更で前後しうる）
- [ ] STDLIB-431: `Random.nextLong()` / `nextFloat()` の実装追跡（互換性セクションの `STDLIB-514` / `STDLIB-515` と重複。片方に統合可）
- [ ] CORO-004: サスペンドを continuation モデルに移行（Channel > withContext > await/join > sequence builders）
  - 進捗: `runSuspendEntryLoopWithContinuation` の内部サスペンド（delay等）は `installResumeContinuation` ベースのノンブロッキングモデルに移行済み。`completionGate` は最外の同期待ちポイントのみでブロック（許容範囲）
  - 残り: `awaitResult` / `join` / `withContext` / Channel send&receive / sequence builder の semaphore 待ちを continuation モデルに移行（優先順: Channel > withContext > await/join > sequence builders）
  - 詳細: `RuntimeCoroutine.swift` 先頭の CORO-004 Migration Plan コメントブロック参照
- [ ] REFL-004: 実行時 `KClass` から読めるバイナリメタデータ（`MetadataSerializer` 等の活用）
  - 現状: リンク用メタデータはあるが実行時参照は限定

---

### Kotlin Stdlib 互換性（独立タスク）

各タスクは他タスクに依存せず、並列実施可能。1 タスク = 1 API または 1 検証項目。

#### C. kotlin.collections — 単一 API 単位

- [ ] STDLIB-532: `Map?.orEmpty()` 拡張
- [ ] STDLIB-533: `List?.orEmpty()` 拡張
- [ ] STDLIB-540: `LinkedList` 型エイリアスの golden テスト（`ArrayList` / `HashMap` / `LinkedHashMap` も同ファイルでスタブ登録済み）
- [ ] STDLIB-541: `HashMap` 型エイリアスの golden テスト
- [ ] STDLIB-542: `LinkedHashMap` 型エイリアスの golden テスト
- [ ] STDLIB-543: `firstOrNull` の kotlinc 挙動 diff 検証
- [ ] STDLIB-544: `lastOrNull` の kotlinc 挙動 diff 検証
- [ ] STDLIB-545: `singleOrNull` の kotlinc 挙動 diff 検証
- [ ] STDLIB-546: `asReversed()` と `reversed()` の区別 diff 検証
- [ ] STDLIB-547: `binarySearch(compare)` オーバーロード
- [ ] STDLIB-548: `chunked(step)` オプション
- [ ] STDLIB-549: `windowed(step, partialWindows)` オプション
- [ ] STDLIB-552: `flatten()` の kotlinc 互換 diff 検証

#### F. kotlin.text / String — 単一 API 単位


#### G. kotlin.time / kotlin.system

- [ ] STDLIB-657: `exitProcess(Int)` の `Nothing` 終了セマンティクスと下げ（`RuntimeSystem.swift`）
- [ ] STDLIB-660: `measureTimedValue { }` の stub / Lowering / Runtime（`RuntimeDuration.swift` の STDLIB-231 相当コメント参照）
- [ ] STDLIB-661: `Duration.inWholeMicroseconds` の Sema / `kk_duration_*` / ABI

#### H. kotlin.Result / kotlin.contracts

- [ ] STDLIB-590: `Result.onFailure` の kotlinc 挙動 diff 検証

#### I. kotlin.io.Closeable / その他

- [ ] STDLIB-597: `RegexOption.MULTILINE` の互換性確認
- [ ] STDLIB-598: `RegexOption.IGNORE_CASE` の互換性確認
- [ ] STDLIB-599: `RegexOption.DOT_MATCHES_ALL` の互換性確認

#### J. テスト・検証（各 1 タスク）
