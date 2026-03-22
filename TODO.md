# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-21

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



---

### 📦 Stdlib — File I/O

- [ ] STDLIB-320: `java.io.File` 基本操作（`readText` / `writeText` / `readLines`）を実装する
  - [x] Sema に `File(String)` コンストラクタと `readText(): String` / `writeText(String)` / `readLines(): List<String>` stub を登録する
  - [x] Runtime に `kk_file_readText` / `kk_file_writeText` / `kk_file_readLines` を追加する（PR #333, `Sources/Runtime/RuntimeFileIO.swift`）
  - [x] Codegen に `kk_file_*` extern 宣言を追加する（`RuntimeABIExterns.swift`）
  - [ ] Lowering でメンバー呼び出しを `kk_file_*` に変換する（ctor の `kk_file_new` のみ `CollectionLiteralLoweringPass+CallRewrite` 済み）
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp/test.txt").writeText("hello"); File("/tmp/test.txt").readText()` → `"hello"` が動作する

- [ ] STDLIB-321: `File.exists()` / `File.isFile` / `File.isDirectory` / `File.name` / `File.path` を実装する
  - [x] Sema に各プロパティ / メソッド stub を登録する
  - [x] Runtime に `kk_file_exists` / `kk_file_isFile` / `kk_file_isDirectory` / `kk_file_name` / `kk_file_path` を追加する（PR #333, `Sources/Runtime/RuntimeFileIO.swift`）
  - [x] Codegen extern（`RuntimeABIExterns.swift`）
  - [ ] Lowering メンバー呼び出し変換
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp").isDirectory` → `true` が動作する

- [ ] STDLIB-322: `File.forEachLine {}` / `File.useLines {}` / `File.bufferedReader()` を実装する
  - [x] Sema に各 member stub を登録する
  - [x] Runtime に `kk_file_useLines` / `kk_file_bufferedReader` を追加する（`kk_file_forEachLine` は PR #333 で実装済み。`RuntimeFileIO.swift`）
  - [x] Codegen extern
  - [ ] Lowering メンバー呼び出し変換
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("test.txt").forEachLine { println(it) }` が各行を出力する

- [ ] STDLIB-323: `File.walk()` / `File.listFiles()` / `File.delete()` / `File.mkdirs()` を実装する
  - [x] Sema に各 member stub を登録する
  - [x] Runtime に `kk_file_walk` / `kk_file_listFiles` / `kk_file_delete` / `kk_file_mkdirs` を追加する（PR #333, `Sources/Runtime/RuntimeFileIO.swift`）
  - [x] Codegen extern
  - [ ] Lowering メンバー呼び出し変換
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp/test").mkdirs()` でディレクトリが作成される

---

### 📦 Stdlib — sequence / iterator ビルダー（stdlib 版）

- [ ] STDLIB-330: `sequence {}` ビルダー（`kotlin.sequences.sequence`）を実装する (eager builder 版実装済み)
  - [x] Sema に `sequence` stub と `SequenceScope` / `yield` / `yieldAll` を登録する（`HeaderHelpers+SyntheticTODOAndIOStubs.swift`）
  - [x] Runtime に `kk_sequence_builder_create` / `kk_sequence_builder_yield` / `kk_sequence_builder_yieldAll` / `kk_sequence_builder_build` を追加する（`Sources/Runtime/RuntimeSequence.swift`）
  - [x] Lowering で `sequence {}` → `kk_sequence_builder_build`、`yield` / `yieldAll` → `kk_sequence_builder_yield` / `kk_sequence_builder_yieldAll` に変換する（`CollectionLiteralLoweringPass+CallRewrite.swift`）
  - [x] Codegen に `kk_sequence_builder_*` extern 宣言を追加する（`RuntimeABIExterns+Sequence.swift`）
  - [ ] continuation ベースの lazy sequence 生成に切り替える（現在は eager builder）
  - [x] diff/golden ケースを追加する
  - **完了条件**: `sequence { yield(1); yield(2); yield(3) }.toList()` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-331: `iterator {}` ビルダー（`kotlin.sequences.iterator`）を実装する (eager builder 版実装済み)
  - [x] Sema に `iterator` stub を登録する（receiver は `SequenceScope<T>` を流用。Kotlin の `IteratorScope` 相当）
  - [x] Lowering で `iterator {}` → `kk_iterator_builder_build`、`yield` → `kk_iterator_builder_yield`、`hasNext`/`next` → `kk_iterator_builder_*` に変換する
  - [x] Runtime に eager バッファ方式 of `kk_iterator_builder_*` を追加する（`RuntimeSequence.swift`）
  - [x] continuation ベースの遅延イテレーション（`STDLIB-564` と統合可）
  - [x] diff/golden ケースを追加する
  - **完了条件**: `val iter = iterator { yield(1); yield(2) }; println(iter.next())` → `1` が `kotlinc` と一致する

---

### 🛡️ Type Safety — Sema / Runtime 境界


- [ ] TYPE-103: `arrayOf()` 系の「型を `Any` に erase してヒューリスティックで補う」処理を廃止する
  - [ ] `CallTypeChecker+MemberCallFallbacks.swift` の array-like 判定で `Any` を特別扱いしている分岐を調査する
  - [ ] `arrayOf` / primitive array constructor の戻り型を header / body 解析の両方で正しく保持する
  - [ ] receiver が collection 扱いであることを別フラグに頼らず、型そのものから判断できるようにする
  - [ ] `Any` receiver に array 専用メンバーが誤って解決されない negative ケースを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `arrayOf(1, 2).get(0)` などは引き続き通り、`Any` に erase された receiver への配列専用メンバー解決は発生しない

---

### Kotlin Stdlib 互換性（独立タスク）

各タスクは他タスクに依存せず、並列実施可能。1 タスク = 1 API または 1 検証項目。

#### A. kotlin.random

- [ ] STDLIB-514: `Random.nextLong()` の stub と Runtime
- [ ] STDLIB-515: `Random.nextFloat()` の stub と Runtime
- [ ] STDLIB-516: `Random(seed)` コンストラクタの再現性検証（diff テスト）
- [ ] STDLIB-653: `Random.nextBytes(ByteArray)` の stub と Runtime（`HeaderHelpers+SyntheticRandomStubs.swift`, `RuntimeRandom.swift`）
- [ ] STDLIB-654: `Random.nextDouble(until: Double)` の stub と Runtime
- [ ] STDLIB-655: `Random.nextFloat(until: Float)` の stub と Runtime

#### B. kotlin.ranges / 型強制

- [x] STDLIB-637: `UIntRange` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/uint_range.kt`）— STDLIB-607 棚卸しで PASS 確認
- [x] STDLIB-638: `ULongRange` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/uint_range.kt`）— STDLIB-607 棚卸しで PASS 確認

#### C. kotlin.collections — 単一 API 単位

- [ ] STDLIB-526: `reduceOrNull` の Iterable 拡張
- [ ] STDLIB-527: `scan` の Iterable 拡張
- [ ] STDLIB-528: `scanReduce` の Iterable 拡張
- [ ] STDLIB-529: `runningFold` の Iterable 拡張
- [ ] STDLIB-530: `runningReduce` の Iterable 拡張
- [ ] STDLIB-531: `shuffled(random: Random)` オーバーロード
- [ ] STDLIB-532: `Map?.orEmpty()` 拡張
- [ ] STDLIB-533: `List?.orEmpty()` 拡張
- [ ] STDLIB-534: `String?.orEmpty()` 拡張
- [ ] STDLIB-538: `ListIterator.hasPrevious()` / `previous()`
- [ ] STDLIB-539: `ArrayList` 型エイリアスの golden テスト（型スタブは `HeaderHelpers+SyntheticComparableAndCollectionStubs` で登録済み）
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
- [ ] STDLIB-550: `zip` の Pair 型 diff 検証
- [ ] STDLIB-551: `unzip` の Pair 型 diff 検証
- [ ] STDLIB-552: `flatten()` の kotlinc 互換 diff 検証
- [x] STDLIB-627: `partition()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/list_partition.kt`）— PASS
- [x] STDLIB-628: `associate()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/list_associate.kt`）— PASS
- [x] STDLIB-629: `associateBy()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/list_associate.kt`）— PASS
- [x] STDLIB-630: `associateWith()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/list_associate.kt`）— PASS
- [x] STDLIB-631: `groupBy()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/stdlib_collection_hof.kt`）— PASS
- [x] STDLIB-632: `mapNotNull()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/list_map_not_null.kt`）— PASS
- [x] STDLIB-633: `filterNotNull()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/list_map_not_null.kt`）— PASS
- [x] STDLIB-634: `List.subList()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/list_sublist.kt`）— PASS
- [x] STDLIB-635: `Array.copyOf()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/array_copy.kt`）— PASS
- [x] STDLIB-636: `Array.copyOfRange()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/array_copy.kt`）— PASS
- [x] STDLIB-641: `Map.maxByOrNull()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/map_flatmap_maxby_minby.kt`）— PASS
- [x] STDLIB-642: `Map.minByOrNull()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/map_flatmap_maxby_minby.kt`）— PASS
- [x] STDLIB-643: `List.shuffled()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/list_shuffled_random.kt`）— PASS
- [x] STDLIB-644: `Map.plus()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/map_plus_minus.kt`）— PASS
- [x] STDLIB-645: `Map.minus()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/map_plus_minus.kt`）— PASS
- [x] STDLIB-646: `Set.intersect()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/set_intersect_union_subtract.kt`）— PASS
- [x] STDLIB-647: `Set.union()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/set_intersect_union_subtract.kt`）— PASS
- [x] STDLIB-648: `Set.subtract()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/set_intersect_union_subtract.kt`）— PASS
- [x] STDLIB-649: `List.sortedWith()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/list_sorted_variants.kt`）— PASS
- [x] STDLIB-650: `Collection.toMutableList()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/collection_copies.kt`）— PASS
- [x] STDLIB-651: `Iterable.toSet()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/collection_copies.kt`）— PASS
- [x] STDLIB-652: `Map.toMutableMap()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/collection_copies.kt`）— PASS

#### D. kotlin.sequences — 単一 API 単位

- [ ] STDLIB-563: `sequence {}` の lazy 評価（continuation ベース。現状 eager builder）
- [x] STDLIB-564: `iterator {}` の continuation ベース Runtime（現状 eager `kk_iterator_builder_*`）
- [x] STDLIB-624: `Iterable.asSequence()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/iterable_as_sequence.kt`）— PASS
- [x] STDLIB-625: `sequenceOf()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/sequence_of_generate.kt`）— PASS
- [x] STDLIB-626: `generateSequence()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/sequence_of_generate.kt`）— PASS

#### E. kotlin.io / java.io.File — 単一 API 単位

- [ ] STDLIB-565: File メンバー呼び出しの VirtualCallRewrite 統合（readText, writeText, readLines, exists, isFile, isDirectory, name, path, forEachLine, delete, mkdirs, listFiles, walk）。`File(String)` → `kk_file_new` の ctor rewrite のみ `CollectionLiteralLoweringPass+CallRewrite` に実装済み
- [ ] STDLIB-572: `print` の 0 引数オーバーロード
- [x] STDLIB-621: `readLine()` の stdin / EOF kotlinc 挙動 diff 検証（`Scripts/diff_cases/readline_basic.kt`）— PASS
- [ ] STDLIB-658: `readln()` の stub / Lowering / Runtime と kotlinc 一致（`HeaderHelpers+SyntheticTODOAndIOStubs.swift`, `RuntimeStringArray.swift`）
- [ ] STDLIB-659: `readlnOrNull()` の stub / Lowering / Runtime と kotlinc 一致（同上）
- [ ] STDLIB-664: `java.io.File.appendText(String)` の Sema stub / Runtime / Lowering / diff（`Scripts/diff_cases/file_readtext.kt` 周辺）
- [ ] STDLIB-665: `java.io.File.readBytes(): ByteArray` の Sema stub / Runtime / Lowering / diff

#### F. kotlin.text / String — 単一 API 単位

- [ ] STDLIB-573: `String.encodeToByteArray(charset)` の実装
- [ ] STDLIB-574: `ByteArray.decodeToString(charset)` の実装
- [ ] STDLIB-575: `commonPrefixWith(other, ignoreCase)` オーバーロード
- [ ] STDLIB-576: `commonSuffixWith(other, ignoreCase)` オーバーロード
- [ ] STDLIB-581: `String.toByteArray(Charset)` / charset 付き `encodeToByteArray` の完全互換（無印版は `kk_string_encodeToByteArray` 等で対応）
- [x] STDLIB-639: `String.lines()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/string_lines.kt`）— PASS
- [x] STDLIB-640: `CharArray.concatToString()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/string_concat.kt`）— PASS
- [ ] STDLIB-666: `String.lineSequence()` の stub / Runtime / Lowering と `lines()` との差分検証
- [x] STDLIB-667: `String.encodeToByteArray()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/string_tobytearray.kt`）— PASS
- [x] STDLIB-668: `String.removePrefix()` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/string_remove_prefix_suffix_surrounding.kt`）— PASS
- [x] STDLIB-669: `String.removeSuffix()` の kotlinc 挙動 diff 検証（同上）— PASS
- [x] STDLIB-670: `String.removeSurrounding()` の kotlinc 挙動 diff 検証（同上）— PASS
- [x] STDLIB-671: `String.chunked(Int)` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/string_chunked_windowed.kt`）— PASS
- [x] STDLIB-672: `String.windowed(Int, ...)` の kotlinc 挙動 diff 検証（同上）— PASS

#### G. kotlin.time / kotlin.system

- [x] STDLIB-656: `System.nanoTime(): Long` の Sema stub と `kk_system_nanoTime` 呼び出し下げ（`HeaderHelpers+SyntheticTODOAndIOStubs.swift`, `RuntimeSystem.swift`）
- [ ] STDLIB-657: `exitProcess(Int)` の `Nothing` 終了セマンティクスと下げ（`RuntimeSystem.swift`）
- [ ] STDLIB-660: `measureTimedValue { }` の stub / Lowering / Runtime（`RuntimeDuration.swift` の STDLIB-231 相当コメント参照）
- [ ] STDLIB-661: `Duration.inWholeMicroseconds` の Sema / `kk_duration_*` / ABI
- [ ] STDLIB-662: `Duration.inWholeHours` の Sema / `kk_duration_*` / ABI
- [ ] STDLIB-663: `Long` 受け Duration 工場（例 `5L.seconds`）の Sema stub（`HeaderHelpers+SyntheticDurationStubs.swift` は Int のみ）

#### H. kotlin.Result / kotlin.contracts

- [ ] STDLIB-590: `Result.onFailure` の kotlinc 挙動 diff 検証
- [ ] STDLIB-591: `contract { returns() }` の意味ある実装検討

#### I. kotlin.io.Closeable / その他

- [x] STDLIB-622: `println()` の 0 引数オーバーロードの kotlinc 挙動 diff 検証（`Scripts/diff_cases/println_no_arg.kt`）— PASS
- [x] STDLIB-623: `Closeable.use { }` の kotlinc 挙動 diff 検証（`Scripts/diff_cases/closeable_use.kt`）— PASS
- [ ] STDLIB-597: `RegexOption.MULTILINE` の互換性確認
- [ ] STDLIB-598: `RegexOption.IGNORE_CASE` の互換性確認
- [ ] STDLIB-599: `RegexOption.DOT_MATCHES_ALL` の互換性確認

#### J. テスト・検証（各 1 タスク）

- [ ] STDLIB-604: `countOneBits` のエッジケーステスト
- [ ] STDLIB-605: `countLeadingZeroBits` のエッジケーステスト
- [ ] STDLIB-606: `countTrailingZeroBits` のエッジケーステスト
- [x] STDLIB-607: diff_cases 全 `.kt` ファイル（現状 233 件）の stdlib サポート状況棚卸し
  - 結果: 224 PASS / 0 FAIL / 8 SKIP（`data_object`, `iterator_builder`, `list_indexed`, `list_maxby_minby`, `measure_time`, `random_seed`, `result_onfailure`, `sequence_fold_reduce_indexed`）
  - `file_exists.kt` の String+Long 結合バグを修正（`kk_any_to_string` 経由で RHS を toString）
  - 既知の制限: `String ==` は構造比較ではなくポインタ比較（pre-existing）
- [x] STDLIB-608: `list_of.kt` の diff 通過確認
- [x] STDLIB-609: `sequence_lazy.kt` の diff 通過確認
- [x] STDLIB-610: `string_stdlib.kt` の diff 通過確認

#### K. 既存・補足

- [x] STDLIB-611: `Comparator.thenBy` の kotlinc 挙動 diff 検証 — PASS (`comparator_thenby.kt`)
- [x] STDLIB-612: `Comparator.thenByDescending` の kotlinc 挙動 diff 検証 — PASS (`comparator_thenby.kt`)
- [x] STDLIB-615: `repeat(times) { }` の kotlinc 挙動 diff 検証 — PASS (`repeat.kt`)
- [x] STDLIB-616: `takeIf` / `takeUnless` の kotlinc 挙動 diff 検証 — PASS (`take_if_take_unless.kt`, `takeif_takeunless.kt`)
- [x] STDLIB-617: `scope functions` (let, run, with, apply, also) の diff 検証 — PASS (`scope_functions.kt`)
- [x] STDLIB-618: `builder_dsl.kt` の diff 通過確認 — PASS
- [x] STDLIB-619: `require_check_error.kt` の diff 通過確認 — PASS
- [x] STDLIB-620: `regex_basic.kt` の diff 通過確認 — PASS

---

## バックログ: Incomplete/Half-baked Implementations
 
監査で見つかった「簡易実装（Stub）」や「中途半端なパス」を将来の改善項目として追跡する。

- [x] STDLIB-317: `String.asIterable()` を lazy `Iterable<Char>` ビューに変更する
  - 現状: `kk_string_asIterable` (lazy view) は実装済み。KIR 下げも対応。
- [x] STDLIB-250: `kk_with_context` の非同期セマンティクスを Kotlin に近づける
  - 現状: `RuntimeCoroutine.swift` で dispatch とスコープ伝播、デッドロック回避が実装済み。
- [x] STDLIB-088: `Flow` の cold / op-chain とソース収集の Kotlin 完全一致
  - 現状: `RuntimeCoroutine.swift` で lazy 経路が実装済み。
- [/] STDLIB-324: File メンバー呼び出しを `kk_file_*` に繋ぐ Lowering 統合
  - 現状: `File(String)` コンストラクタは対応済み。`readText` 等の virtual rewrite は未対応（`STDLIB-565`）。
- [x] KIR-001: KIR の `Set` などのシンボル名を完全修飾名 (`kotlin.collections.Set`) に統一する
  - 現状: `CompilerKnownNames.swift` の `isSetLikeSymbol` 等で FQN 対応済み。
- [x] TYPE-110: `toHashSet()` 等の戻り型を `MutableSet<T>` に修正する
  - 現状: `HeaderHelpers` で `MutableSet<T>` を返すように修正済み。
- [x] TYPE-111: HOF セレクタの Nullable キー（`K?`）をサポートする
  - 現状: `distinctBy` 等のセレクタ戻り型が `Any?` に変更され、Nullable キーに対応済み。
- [x] STDLIB-089: Data Class (non-object) の `toString`, `equals`, `hashCode` を自動生成する
  - 現状: `DataEnumSealedSynthesisPass.swift` で実装済み。
- [x] STDLIB-090: Data Class の `componentN()` 関数を自動生成する
  - 現状: `DataEnumSealedSynthesisPass.swift` で実装済み。
- [x] LOWER-005: `TailrecLoweringPass` で `$default` stub 呼び出しを最適化対象に含める
  - 現状: `TailrecLoweringPass.swift` で `$default` チェックが実装済み。
- [x] RUNTIME-001: Collection HOF のキー重複排除で `equals`/`hashCode` ベースの構造等価性を使用する
  - 現状: `RuntimeElementKey` を使用して構造等価性が導入済み。
- [/] LOWERING-001: virtual call rewrite を **tracked 外**の collection receiver にも適用する
  - 現状: `CollectionLiteralLoweringPass+VirtualCallRewrite.swift` で tracked 制限あり。既知の制限として残存。
- [ ] CORO-001: Channel の send / バックプレッシャーを Kotlin suspend セマンティクスに揃える
  - 現状: 満杯時の扱い・Flow 側の eager ソースなど、Kotlin との差が残る（`RuntimeCoroutine.swift` の `RuntimeChannelHandle.send` 等）
- [ ] TEST-001: `kk_measureTime` およびシステム計測の Runtime XCTest 強化
  - 現状: `RuntimeDurationTests` で Duration 工場・`inWhole*`・`toString` はカバー。`kk_measureTime` 本体のテストは薄い
- [ ] TEST-002: Long/Double/Float 型強制の golden/smoke テスト追加
  - 現状: `HeaderHelpers+SyntheticCoercionStubs.swift` 先頭にテスト参照コメント。ケース拡充は未了
- [ ] TEST-003: Numeric bit-count 系のエッジケーステスト追加
  - 現状: `RuntimeNumericCompat.swift` にビット数まわりの TODO コメント（行は実装変更で前後しうる）
- [ ] STDLIB-431: `Random.nextLong()` / `nextFloat()` の実装追跡（互換性セクションの `STDLIB-514` / `STDLIB-515` と重複。片方に統合可）
- [ ] STDLIB-430: `kotlin.math` Float オーバーロードの **kotlinc 完全一致検証**（スタブは `HeaderHelpers+SyntheticMathStubs.swift` の `kk_math_*_float` 等で登録済み）
  - **完了条件**: `sin(1.0f)` が `Float` のみで完結し `kotlinc` と stdout 一致
- [ ] REFL-001: `KClass` / `KType` を型システムで端到端にモデル化する
  - 現状: 一部 `KClassType` 等はあるが、`anyType` フォールバックやエッジが残る
- [ ] REFL-002: `T::class` のメタデータ下げとスタンドアロン参照の型精度
  - 現状: `ExprLowerer+ControlFlowAndBlocks.swift` 等で `kk_kclass_create` 経路あり。全経路・診断は未固定
- [ ] REFL-003: 呼び出し可能参照 (`::foo`) の `KFunction` / `KProperty` 同一性と下げ
  - 現状: `ExprTypeChecker+NameLambdaAndCallableRefInference.swift` 等で kind 束縛あり。KIR/実行時・リフレクション API まで含め差分あり
- [ ] CODE-001: **例外経路**でインラインした `finally` のスロー先を Kotlin に合わせる
  - 現状: `return` / `break` / `continue` 前の enclosing `finally` インラインは実装済み（`ExprLowerer+ControlFlowAndBlocks.swift` の `TODO(CODE-001)` は例外ルーティング）
- [ ] CORO-004: サスペンドを `DispatchSemaphore` 待ちではない継続モデルにする
  - 現状: `waitForResumeSignal` 等（`RuntimeCoroutine.swift`）
- [x] CORO-003: スコープを TLS / `threadDictionary` 依存から減らす
  - 完了: 全 `threadDictionary` 使用を `pthread_key_t` ベースの軽量 TLS に移行（タスクキー / Flow collect スタック / ディスパッチャー）
- [ ] REFL-004: 実行時 `KClass` から読めるバイナリメタデータ（`MetadataSerializer` 等の活用）
  - 現状: リンク用メタデータはあるが実行時参照は限定
- [ ] ENUM-001: Enum **静的初期化順・エッジ**と `entries` / 合成の Kotlin 完全一致
  - 現状: `valueOf` / `kk_enum_make_values_array` 等の合成・Runtime は存在（`DataEnumSealedSynthesisPass.swift`, `RuntimeEnum.swift`）。初期化順や未カバーケースは要 diff
- [ ] ENUM-002: `enumValues` / `entries` の **Array vs List** など ABI 上の Kotlin 差分の整理
  - 現状: `kk_enum_make_values_array` が `List` を返す（`RuntimeEnum.swift`）。Kotlin JVM の `Array` との差を diff で固定するか方針決定
- [ ] VAL-001: Value class のアンボックス化とマングリング
  - 現状: `ValueClassUnboxingPass` disabled 等（`LoweringPhase.swift`）
- [ ] DATA-001: Data class `copy()` の **primary ctor 不在・シグネチャ異常**時のフォールバックとエッジ
  - 現状: 通常 ctor がある data class は引数付き `copy` を合成（`DataEnumSealedSynthesisPass.swift` `appendSyntheticDataCopyIfNeeded`）。ctor 解決失敗時のみ self-return
- [x] INLINE-001: 非局所 return の残差（`InlineLoweringPass.swift`）
- [x] INLINE-002: ラムダ引数インライン展開の網羅と最適化品質
- [ ] CLSR-001: クロージャキャプチャ・`kk_lambda_invoke` まわりの Kotlin 完全一致（`LambdaClosureConversionPass.swift` は実装拡大済み、差分は diff で固定）

 
---
 
## 🧪 テストケース一括管理

テストケース生成は `Scripts/test_case_registry.json` をソースオブジェクトとして運用する。

### ワークフロー

```bash
# 特定タスクのテストケースを一括生成
bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-005

# 単体テストの手動生成
bash Scripts/generate_test_case.sh --type golden-sema --name my_test --from-file path/to/template.kt

# golden ファイルの自動更新
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter GoldenHarnessTests
```

### ファイル構成

| パス | 説明 |
|---|---|
| `Scripts/test_case_registry.json` | 全タスクのテストケース定義（タスク ID・カテゴリ・テンプレートパス） |
| `Scripts/generate_test_case.sh` | テストケース scaffold ジェネレータ |
| `Scripts/test_templates/{lexer,parser,sema,diff}/` | カテゴリ別 Kotlin テンプレート |
| `Tests/CompilerCoreTests/GoldenCases/{Lexer,Parser,Sema}/` | golden テスト（`.kt` + `.golden`） |
