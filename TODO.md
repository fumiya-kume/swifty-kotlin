# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-25

## 運用ルール

- `TODO.md` は未完了タスクのみを管理する。完了タスクは Git 履歴を参照する。
- タスクIDはカテゴリ接頭辞 (`LEX/TYPE/EXPR/CTRL/DECL/CLASS/PROP/FUNC/GEN/NULL/CORO/STDLIB/ANNO/TOOL/MPP`) + 3桁連番を使用する。
- 完了済みタスクを参照する場合は `既存実装済み` と記載する。
- 共通完了条件（全タスク共通）:
  1. `Scripts/diff_kotlinc.sh` が exit 0 かつ stdout 完全一致
  2. golden テストが byte 一致
  3. エラーケースで `KSWIFTK-*` 診断コード出力
  4. 各項目末尾エッジケース golden が通過

---

## 未完了バックログ

監査で見つかった「簡易実装（Stub）」や「中途半端なパス」を将来の改善項目として追跡する。

- [ ] CORO-001: Channel の send / バックプレッシャーを Kotlin suspend セマンティクスに揃える
  - 現状: 満杯時の扱い・Flow 側の eager ソースなど、Kotlin との差が残る（`RuntimeCoroutine.swift` の `RuntimeChannelHandle.send` 等）
- [ ] TEST-001: `kk_measureTime` およびシステム計測の Runtime XCTest 強化
  - 現状: `RuntimeDurationTests` で Duration 工場・`inWhole*`・`toString` はカバー。`kk_measureTime` 本体のテストは薄い
- [ ] TEST-002: Long/Double/Float 型強制の golden/smoke テスト追加
  - 現状: `HeaderHelpers+SyntheticCoercionStubs.swift` 先頭にテスト参照コメント。ケース拡充は未了
- [ ] TEST-003: Numeric bit-count 系のエッジケーステスト追加
  - 現状: `RuntimeNumericCompat.swift` にビット数まわりの TODO コメント（行は実装変更で前後しうる）
- [ ] STDLIB-431: `Random.nextLong()` / `nextFloat()` の実装追跡（互換性セクションの `STDLIB-514` / `STDLIB-515` と重複。片方に統合可）
- [x] STDLIB-430: `kotlin.math` Float オーバーロードの **kotlinc 完全一致検証**（スタブは `HeaderHelpers+SyntheticMathStubs.swift` の `kk_math_*_float` 等で登録済み）
  - **完了条件**: `sin(1.0f)` が `Float` のみで完結し `kotlinc` と stdout 一致
- [x] REFL-001: `KClass` / `KType` を型システムで端到端にモデル化する
  - **既存実装済み**: 基本的な `KClass` / `KType` 機能は実装済み。`String::class` / `Int::class` / `typeOf<T>()` などが動作
- [x] CODE-001: **例外経路**でインラインした `finally` のスロー先を Kotlin に合わせる
  - **既存実装済み**: `return` / `break` / `continue` 前の enclosing `finally` インラインは実装済み（`ExprLowerer+ControlFlowAndBlocks.swift` の `TODO(CODE-001)` は例外ルーティング）
- [ ] CORO-004: サスペンドを continuation モデルに移行（Channel > withContext > await/join > sequence builders）
  - 進捗: `runSuspendEntryLoopWithContinuation` の内部サスペンド（delay等）は `installResumeContinuation` ベースのノンブロッキングモデルに移行済み。`completionGate` は最外の同期待ちポイントのみでブロック（許容範囲）
  - 残り: `awaitResult` / `join` / `withContext` / Channel send&receive / sequence builder の semaphore 待ちを continuation モデルに移行（優先順: Channel > withContext > await/join > sequence builders）
  - 詳細: `RuntimeCoroutine.swift` 先頭の CORO-004 Migration Plan コメントブロック参照
- [ ] REFL-004: 実行時 `KClass` から読めるバイナリメタデータ（`MetadataSerializer` 等の活用）
  - 現状: リンク用メタデータはあるが実行時参照は限定
- [x] ENUM-001: Enum **静的初期化順・エッジ**と `entries` / 合成の Kotlin 完全一致
  - **既存実装済み**: `valueOf` / `kk_enum_make_values_array` 等の合成・Runtime は存在（`DataEnumSealedSynthesisPass.swift`, `RuntimeEnum.swift`）。基本的な初期化順やエッジケースは動作
- [x] STDLIB-664: `File.appendText(String)` の実装（Sema/Runtime/Lowering/Codegen）
- [x] STDLIB-665: `File.readBytes()` の実装確認（既存実装）
- [x] REFL-005: `KClass.isInstance` / `members` / `constructors` と `KType` / `typeOf<T>()` の実装
  - **既存実装済み**: `KClass.isInstance` / `members` / `constructors` と `KType` / `typeOf<T>()` は実装済み
  - [x] Runtime に `kk_kclass_isInstance` / `kk_kclass_members` / `kk_kclass_constructors` を実装
  - [x] `KType` / `KTypeProjection` / `kk_typeof` を実装
  - [x] KIR lowering でメンバ呼び出しと `typeOf<T>()` をサポート
  - **完了条件**: `String::class.members.size` や `typeOf<String>()` が `kotlinc` と一致する

---

### 📦 Stdlib — sequence / iterator ビルダー（stdlib 版）

- [x] STDLIB-330: `sequence {}` ビルダー（`kotlin.sequences.sequence`）を実装する (lazy evaluation 版実装済み)
  - [x] Sema に `sequence` stub と `SequenceScope` / `yield` / `yieldAll` を登録する（`HeaderHelpers+SyntheticTODOAndIOStubs.swift`）
  - [x] Runtime に `kk_sequence_builder_create` / `kk_sequence_builder_yield` / `kk_sequence_builder_yieldAll` / `kk_sequence_builder_build` を追加する（`Sources/Runtime/RuntimeSequence.swift`）
  - [x] Lowering で `sequence {}` → `kk_sequence_builder_build`、`yield` / `yieldAll` → `kk_sequence_builder_yield` / `kk_sequence_builder_yieldAll` に変換する（`CollectionLiteralLoweringPass+CallRewrite.swift`）
  - [x] Codegen に `kk_sequence_builder_*` extern 宣言を追加する（`RuntimeABIExterns+Sequence.swift`）
  - [x] continuation ベースの lazy sequence 生成に切り替える（現在は eager builder）
  - [x] diff/golden ケースを追加する
  - **完了条件**: `sequence { yield(1); yield(2); yield(3) }.toList()` → `[1, 2, 3]` が `kotlinc` と一致する

- [x] STDLIB-331: `iterator {}` ビルダー（`kotlin.sequences.iterator`）を実装する (eager builder 版実装済み)
  - [x] Sema に `iterator` stub を登録する（receiver は `SequenceScope<T>` を流用。Kotlin の `IteratorScope` 相当）
  - [x] Lowering で `iterator {}` → `kk_iterator_builder_build`、`yield` → `kk_iterator_builder_yield`、`hasNext`/`next` → `kk_iterator_builder_*` に変換する
  - [x] Runtime に eager バッファ方式 of `kk_iterator_builder_*` を追加する（`RuntimeSequence.swift`）
  - [x] continuation ベースの遅延イテレーション（`STDLIB-564` と統合可）
  - [x] diff/golden ケースを追加する
  - **完了条件**: `val iter = iterator { yield(1); yield(2) }; println(iter.next())` → `1` が `kotlinc` と一致する

---

### Kotlin Stdlib 互換性（独立タスク）

各タスクは他タスクに依存せず、並列実施可能。1 タスク = 1 API または 1 検証項目。

#### C. kotlin.collections — 単一 API 単位

- [ ] STDLIB-532: `Map?.orEmpty()` 拡張
- [ ] STDLIB-533: `List?.orEmpty()` 拡張
- [x] STDLIB-534: `String?.orEmpty()` 拡張
- [x] STDLIB-538: `ListIterator.hasPrevious()` / `previous()`
- [x] STDLIB-539: `ArrayList` 型エイリアスの golden テスト（型スタブは `HeaderHelpers+SyntheticComparableAndCollectionStubs` で登録済み）
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

- [x] STDLIB-573: `String.encodeToByteArray(charset)` の実装
- [x] STDLIB-574: `ByteArray.decodeToString(charset)` の実装
- [x] STDLIB-575: `commonPrefixWith(other, ignoreCase)` オーバーロード
- [x] STDLIB-576: `commonSuffixWith(other, ignoreCase)` オーバーロード
- [x] STDLIB-581: `String.toByteArray(Charset)` / charset 付き `encodeToByteArray` の完全互換（無印版は `kk_string_encodeToByteArray` 等で対応）
- [x] STDLIB-666: `String.lineSequence()` の stub / Runtime / Lowering と `lines()` との差分検証

#### G. kotlin.time / kotlin.system

- [ ] STDLIB-657: `exitProcess(Int)` の `Nothing` 終了セマンティクスと下げ（`RuntimeSystem.swift`）
- [ ] STDLIB-660: `measureTimedValue { }` の stub / Lowering / Runtime（`RuntimeDuration.swift` の STDLIB-231 相当コメント参照）
- [ ] STDLIB-661: `Duration.inWholeMicroseconds` の Sema / `kk_duration_*` / ABI
- [x] STDLIB-662: `Duration.inWholeHours` の Sema / `kk_duration_*` / ABI (既存実装済み)
- [x] STDLIB-663: `Long` 受け Duration 工場（例 `5L.seconds`）の Sema stub（`HeaderHelpers+SyntheticDurationStubs.swift` は Int のみ）

#### H. kotlin.Result / kotlin.contracts

- [ ] STDLIB-590: `Result.onFailure` の kotlinc 挙動 diff 検証

#### I. kotlin.io.Closeable / その他

- [ ] STDLIB-597: `RegexOption.MULTILINE` の互換性確認
- [ ] STDLIB-598: `RegexOption.IGNORE_CASE` の互換性確認
- [ ] STDLIB-599: `RegexOption.DOT_MATCHES_ALL` の互換性確認

#### J. テスト・検証（各 1 タスク）

- [x] STDLIB-604: `countOneBits` のエッジケーステスト
- [x] STDLIB-605: `countLeadingZeroBits` のエッジケーステスト
- [x] STDLIB-606: `countTrailingZeroBits` のエッジケーステスト
