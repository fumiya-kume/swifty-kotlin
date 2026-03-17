# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-17

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


- [x] STDLIB-257: Precondition lazy message fallback の失敗経路を明確化する
  - 背景: `require {}` / `check {}` の lazy message 評価失敗が default message fallback に見える余地がある
  - [x] [Sources/Runtime/RuntimePreconditions.swift](Sources/Runtime/RuntimePreconditions.swift) の `preconditionWithLazyMessage` / `runtimeEvaluateLazyMessage` を棚卸しする
  - [x] lazy message closure 自体の失敗と、通常の precondition failure を区別できるよう契約を整理する
  - [x] lazy message throw の回帰ケースを追加する
  - **完了条件**: lazy message 評価失敗が通常の `require/check` 失敗に紛れず観測できる

- [ ] STDLIB-258: `assert()` 関数を `kotlin.Preconditions` に追加する
  - [ ] `HeaderHelpers+SyntheticPreconditionStubs.swift` に `assert` stub を登録する
  - [ ] Runtime に `kk_precondition_assert` を追加し、`-ea` (enable assertions) フラグ相当の制御を検討する
  - **完了条件**: `assert(x > 0)` がビルド・実行可能であること

---

### 📦 Stdlib — File I/O

- [ ] STDLIB-320: `java.io.File` 基本操作（`readText` / `writeText` / `readLines`）を実装する
  - [x] Sema に `File(String)` コンストラクタと `readText(): String` / `writeText(String)` / `readLines(): List<String>` stub を登録する
  - [x] Runtime に `kk_file_readText` / `kk_file_writeText` / `kk_file_readLines` を追加する（PR #333, `Sources/Runtime/RuntimeFileIO.swift`）
  - [ ] Codegen/Lowering に `kk_file_*` extern 宣言とメンバー呼び出し変換を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp/test.txt").writeText("hello"); File("/tmp/test.txt").readText()` → `"hello"` が動作する

- [ ] STDLIB-321: `File.exists()` / `File.isFile` / `File.isDirectory` / `File.name` / `File.path` を実装する
  - [x] Sema に各プロパティ / メソッド stub を登録する
  - [x] Runtime に `kk_file_exists` / `kk_file_isFile` / `kk_file_isDirectory` / `kk_file_name` / `kk_file_path` を追加する（PR #333, `Sources/Runtime/RuntimeFileIO.swift`）
  - [ ] Codegen/Lowering に `kk_file_*` extern 宣言とメンバー呼び出し変換を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp").isDirectory` → `true` が動作する

- [ ] STDLIB-322: `File.forEachLine {}` / `File.useLines {}` / `File.bufferedReader()` を実装する
  - [x] Sema に各 member stub を登録する
  - [ ] Runtime に `kk_file_useLines` / `kk_file_bufferedReader` を追加する（`kk_file_forEachLine` は PR #333 で実装済み）
  - [ ] Codegen/Lowering に `kk_file_*` extern 宣言とメンバー呼び出し変換を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("test.txt").forEachLine { println(it) }` が各行を出力する

- [ ] STDLIB-323: `File.walk()` / `File.listFiles()` / `File.delete()` / `File.mkdirs()` を実装する
  - [x] Sema に各 member stub を登録する
  - [x] Runtime に `kk_file_walk` / `kk_file_listFiles` / `kk_file_delete` / `kk_file_mkdirs` を追加する（PR #333, `Sources/Runtime/RuntimeFileIO.swift`）
  - [ ] Codegen/Lowering に `kk_file_*` extern 宣言とメンバー呼び出し変換を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp/test").mkdirs()` でディレクトリが作成される

---

### 📦 Stdlib — sequence / iterator ビルダー（stdlib 版）

- [ ] STDLIB-330: `sequence {}` ビルダー（`kotlin.sequences.sequence`）を実装する
  - [ ] Sema に `sequence(block: suspend SequenceScope<T>.() -> Unit): Sequence<T>` stub を登録する（`SequenceScope` 未登録）
  - [ ] `SequenceScope.yield(value)` / `yieldAll(iterable)` を解決可能にする（`yieldAll` 未実装）
  - [x] Runtime に `kk_sequence_builder_create` / `kk_sequence_builder_yield` / `kk_sequence_builder_build` を追加する（`Sources/Runtime/RuntimeSequence.swift`）
  - [x] Lowering で `sequence {}` → `kk_sequence_builder_build`、`yield()` → `kk_sequence_builder_yield` に変換する（`CollectionLiteralLoweringPass+CallRewrite.swift`）
  - [x] Codegen に `kk_sequence_builder_*` extern 宣言を追加する（`RuntimeABIExterns+Sequence.swift`）
  - [ ] continuation ベースの lazy sequence 生成に切り替える（現在は eager builder）
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequence { yield(1); yield(2); yield(3) }.toList()` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-331: `iterator {}` ビルダー（`kotlin.sequences.iterator`）を実装する
  - [ ] Sema に `iterator(block: suspend IteratorScope<T>.() -> Unit): Iterator<T>` stub を登録する
  - [x] Lowering で `iterator {}` -> `kk_iterator_builder_build` に変換する
  - [ ] Runtime で continuation ベースのイテレータ生成を実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val iter = iterator { yield(1); yield(2) }; println(iter.next())` → `1` が `kotlinc` と一致する

---

### 🛡️ Type Safety — Sema / Runtime 境界

- [ ] TYPE-101: Collection HOF 推論で `Any` に潰れている戻り型を generic 保持に置き換える
  - [x] `CallTypeChecker+MemberCallInference.swift` の `flatMap` / `associateBy` / `associateWith` / `associate` / `mapIndexed` / `groupBy` の戻り型推論を棚卸しする
  - [ ] ラムダ戻り型 `R`、key 型 `K`、value 型 `V` を `Any` にフォールバックせず `TypeID` として保持する共通ヘルパーを導入する
  - [ ] `flatMap` を `List<R>`、`associateBy` を `Map<K, T>`、`associateWith` を `Map<T, V>`、`associate` を `Map<K, V>` として推論できるようにする
  - [x] `mapIndexed` を `List<R>`、`groupBy` を `Map<K, List<T>>` として推論できるようにする
  - [ ] `Any` に落ちたことで通ってしまっていた不正プログラムの negative golden を追加する
  - [ ] 正常系の diff/golden ケースを追加する
  - **完了条件**: `listOf(1).mapIndexed { _, x -> "$x" }` の型が `List<String>` になり、`associateBy` / `flatMap` / `groupBy` でも `kotlinc` と同等の型推論結果になる

- [ ] TYPE-102: synthetic collection stub の暫定 `Any` 戻り型を実型ベースに置き換える
  - [ ] `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift` の `partition` など、コメントで「use Any for now」としている箇所を対応する（`mapIndexed` stub は `List<R>` で定義済み）
  - [ ] synthetic stub 側で関数型 type parameter `R`、`Pair<List<T>, List<T>>`、`Map<K, V>` を表現するための builder を追加する
  - [x] `mapIndexed` の stub 定義（`List<R>`）を推論コード（`CallTypeChecker+MemberCallInference.swift`）が利用するよう連携する（現在は stub を無視して `List<Any>` を返している）
  - [ ] fallback 推論に依存せず、stub 定義だけで Kotlin 標準ライブラリ署名を再現できるようにする
  - [ ] `lookupByShortName(...).first!` に依存する箇所を、診断可能な lookup helper に寄せる
  - [ ] 対応した stub の golden 署名を更新し、既存ケースとの差分を固定する
  - **完了条件**: synthetic stub のダンプで `partition` が `Pair<List<T>, List<T>>`、`mapIndexed` が `List<R>` として表現され、後段の推論特例が不要になる

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

#### A. kotlin.math — 各関数を個別タスク化

- [ ] STDLIB-500: `kotlin.math.sin` の Float オーバーロード
- [ ] STDLIB-501: `kotlin.math.cos` の Float オーバーロード
- [ ] STDLIB-502: `kotlin.math.tan` の Float オーバーロード
- [ ] STDLIB-503: `kotlin.math.asin` の Float オーバーロード
- [ ] STDLIB-504: `kotlin.math.acos` の Float オーバーロード
- [ ] STDLIB-505: `kotlin.math.atan` の Float オーバーロード
- [ ] STDLIB-506: `kotlin.math.atan2` の Float オーバーロード
- [ ] STDLIB-507: `kotlin.math.sqrt` の Float オーバーロード
- [ ] STDLIB-508: `kotlin.math.round` の Float オーバーロード
- [ ] STDLIB-509: `kotlin.math.ceil` / `floor` の Float オーバーロード
- [ ] STDLIB-510: `roundToInt()` の Float/Double 拡張
- [ ] STDLIB-511: `roundToLong()` の Float/Double 拡張
- [ ] STDLIB-512: `ulp` / `nextUp` / `nextDown` の Double 拡張
- [ ] STDLIB-513: `ulp` / `nextUp` / `nextDown` の Float 拡張

#### B. kotlin.random

- [ ] STDLIB-514: `Random.nextLong()` の stub と Runtime
- [ ] STDLIB-515: `Random.nextFloat()` の stub と Runtime
- [ ] STDLIB-516: `Random(seed)` コンストラクタの再現性検証（diff テスト）

#### C. kotlin.ranges / 型強制

- [ ] STDLIB-517: `Int.coerceIn(Int, Int)` の golden テスト
- [ ] STDLIB-518: `Long.coerceIn(Long, Long)` の golden テスト
- [ ] STDLIB-519: `Double.coerceIn(Double, Double)` の golden テスト
- [ ] STDLIB-520: `Float.coerceIn(Float, Float)` の golden テスト
- [ ] STDLIB-521: `coerceAtLeast` / `coerceAtMost` の Long 版 golden テスト
- [x] STDLIB-522: `LongRange` の完全サポート（stub + Runtime）
- [ ] STDLIB-523: `UIntRange` の完全サポート
- [ ] STDLIB-524: `ULongRange` の完全サポート
- [x] STDLIB-525: `Int/Long.coerceIn(range)` の実装（レシーバがInt/Longの場合のClosedRange引数オーバーロード）

#### D. kotlin.collections — 単一 API 単位

- [ ] STDLIB-526: `reduceOrNull` の Iterable 拡張
- [ ] STDLIB-527: `scan` の Iterable 拡張
- [ ] STDLIB-528: `scanReduce` の Iterable 拡張
- [ ] STDLIB-529: `runningFold` の Iterable 拡張
- [ ] STDLIB-530: `runningReduce` の Iterable 拡張
- [ ] STDLIB-531: `shuffled(random: Random)` オーバーロード
- [ ] STDLIB-532: `Map?.orEmpty()` 拡張
- [ ] STDLIB-533: `List?.orEmpty()` 拡張
- [ ] STDLIB-534: `String?.orEmpty()` 拡張
- [ ] STDLIB-535: `associateByTo` の stub と Runtime
- [ ] STDLIB-536: `associateWithTo` の stub と Runtime
- [ ] STDLIB-537: `groupByTo` の stub と Runtime
- [ ] STDLIB-538: `ListIterator.hasPrevious()` / `previous()`
- [ ] STDLIB-539: `ArrayList` 型エイリアスの golden テスト
- [ ] STDLIB-540: `LinkedList` 型エイリアスの golden テスト
- [ ] STDLIB-541: `HashMap` 型エイリアスの golden テスト
- [ ] STDLIB-542: `LinkedHashMap` 型エイリアスの golden テスト
- [ ] STDLIB-543: `firstOrNull` の kotlinc 挙動 diff 検証
- [ ] STDLIB-544: `lastOrNull` の kotlinc 挙動 diff 検証
- [ ] STDLIB-545: `singleOrNull` の kotlinc 挙動 diff 検証
- [ ] STDLIB-546: `asReversed()` と `reversed()` の区別 diff 検証
- [x] STDLIB-547: `binarySearch(compare)` オーバーロード
- [ ] STDLIB-548: `chunked(step)` オプション
- [ ] STDLIB-549: `windowed(step, partialWindows)` オプション
- [ ] STDLIB-550: `zip` の Pair 型 diff 検証
- [ ] STDLIB-551: `unzip` の Pair 型 diff 検証
- [ ] STDLIB-552: `flatten()` の kotlinc 互換 diff 検証

#### E. kotlin.sequences — 単一 API 単位

- [x] STDLIB-553: `yieldAll(iterable)` の Runtime 実装
- [ ] STDLIB-554: `List.asSequence()` の stub と Lowering
- [ ] STDLIB-555: `Iterable.asSequence()` の stub と Lowering
- [ ] STDLIB-556: `reduceIndexed` の Sequence 拡張
- [ ] STDLIB-557: `foldIndexed` の Sequence 拡張
- [x] STDLIB-558: `runningFold` の Sequence 拡張
- [x] STDLIB-559: `runningReduce` の Sequence 拡張
- [x] STDLIB-560: `scan` の Sequence 拡張
- [ ] STDLIB-561: `Sequence.plus(other)` の実装
- [ ] STDLIB-562: `Sequence.minus(element)` の実装
- [ ] STDLIB-563: `sequence {}` の lazy 評価（continuation ベース）
- [ ] STDLIB-564: `iterator {}` の continuation ベース Runtime

#### F. kotlin.io / java.io.File — 単一 API 単位

- [ ] STDLIB-565: File メンバー呼び出しの VirtualCallRewrite 統合（readText, writeText, readLines, exists, isFile, isDirectory, name, path, forEachLine, delete, mkdirs, listFiles, walk）
- [ ] STDLIB-566: `File.useLines {}` の Runtime 実装
- [ ] STDLIB-567: `File.bufferedReader()` の Runtime 実装
- [ ] STDLIB-568: diff_cases に `file_readtext.kt` を追加
- [ ] STDLIB-569: diff_cases に `file_exists.kt` を追加
- [ ] STDLIB-570: diff_cases に `file_mkdirs.kt` を追加
- [ ] STDLIB-571: `readlnOrNull` の stub と Runtime
- [ ] STDLIB-572: `print` の 0 引数オーバーロード

#### G. kotlin.text / String — 単一 API 単位

- [x] STDLIB-573: `String.encodeToByteArray()` の実装（デフォルト UTF-8、charset 引数なし）
- [x] STDLIB-574: `ByteArray.decodeToString()` の実装（デフォルト UTF-8、charset 引数なし）
- [ ] STDLIB-575: `commonPrefixWith(other, ignoreCase)` オーバーロード
- [ ] STDLIB-576: `commonSuffixWith(other, ignoreCase)` オーバーロード
- [ ] STDLIB-577: `padStart(length, padChar: Char)` オーバーロード
- [ ] STDLIB-578: `padEnd(length, padChar: Char)` オーバーロード
- [ ] STDLIB-579: `buildString.appendLine` の完全性確認
- [ ] STDLIB-580: `buildString.appendRange` の完全性確認
- [x] STDLIB-581: `String.toByteArray()` の charset オーバーロード（既存 toByteArray の拡張）

#### H. kotlin.time / kotlin.system

- [ ] STDLIB-582: `Duration.inWholeMilliseconds` の Runtime 確認
- [ ] STDLIB-583: `Duration.inWholeSeconds` の Runtime 確認
- [ ] STDLIB-584: `Duration.inWholeMinutes` の Runtime 確認
- [x] STDLIB-585: `measureTime { }` の戻り型を `Duration` に統一
- [ ] STDLIB-586: `RuntimeDuration` の RuntimeTests 追加
- [ ] STDLIB-587: `measureTimeMillis` の diff テスト追加
- [ ] STDLIB-588: `measureNanoTime` の diff テスト追加

#### I. kotlin.Result / kotlin.contracts

- [ ] STDLIB-589: `Result.recover` の stub と Runtime
- [ ] STDLIB-590: `Result.onFailure` の kotlinc 挙動 diff 検証
- [ ] STDLIB-591: `contract { returns() }` の意味ある実装検討
- [ ] STDLIB-592: `contract { callsInPlace }` の意味ある実装検討
- [ ] STDLIB-593: `contract { returnsNotNull }` の意味ある実装検討

#### J. kotlin.io.Closeable / その他

- [x] STDLIB-594: `Closeable.use { }` の Runtime 実装（try-finally 相当）
- [ ] STDLIB-595: `UInt.toInt` / `toLong` / `toUInt` の diff 検証
- [ ] STDLIB-596: `ULong.toLong` / `toULong` の diff 検証
- [ ] STDLIB-597: `RegexOption.MULTILINE` の互換性確認
- [ ] STDLIB-598: `RegexOption.IGNORE_CASE` の互換性確認
- [ ] STDLIB-599: `RegexOption.DOT_MATCHES_ALL` の互換性確認
- [ ] STDLIB-600: `assert()` の stub と Runtime（既存 STDLIB-258 と統合可）

#### K. テスト・検証（各 1 タスク）

- [ ] STDLIB-601: Coercion の Long golden テスト
- [ ] STDLIB-602: Coercion の Double golden テスト
- [ ] STDLIB-603: Coercion の Float golden テスト
- [ ] STDLIB-604: `countOneBits` のエッジケーステスト
- [ ] STDLIB-605: `countLeadingZeroBits` のエッジケーステスト
- [ ] STDLIB-606: `countTrailingZeroBits` のエッジケーステスト
- [x] STDLIB-607: diff_cases 全 197 .kt ファイルの stdlib サポート状況棚卸し (195 PASS, 2 SKIP, 0 FAIL)
- [x] STDLIB-608: `list_of.kt` の diff 通過確認
- [x] STDLIB-609: `sequence_lazy.kt` の diff 通過確認
- [x] STDLIB-610: `string_stdlib.kt` の diff 通過確認

#### L. 既存・補足

- [ ] STDLIB-611: `Comparator.thenBy` の kotlinc 挙動 diff 検証
- [ ] STDLIB-612: `Comparator.thenByDescending` の kotlinc 挙動 diff 検証
- [ ] STDLIB-613: `compareBy` の複数セレクタオーバーロード
- [x] STDLIB-614: `minOf` / `maxOf` の 3 引数以上オーバーロード
- [ ] STDLIB-615: `repeat(times) { }` の kotlinc 挙動 diff 検証
- [ ] STDLIB-616: `takeIf` / `takeUnless` の kotlinc 挙動 diff 検証
- [ ] STDLIB-617: `scope functions` (let, run, with, apply, also) の diff 検証
- [x] STDLIB-618: `builder_dsl.kt` の diff 通過確認
- [ ] STDLIB-619: `require_check_error.kt` の diff 通過確認
- [ ] STDLIB-620: `regex_basic.kt` の diff 通過確認

---

## バックログ: Incomplete/Half-baked Implementations
 
監査で見つかった「簡易実装（Stub）」や「中途半端なパス」を将来の改善項目として追跡する。
 
- [x] STDLIB-317: `String.asIterable()` を lazy `Iterable<Char>` ビューに変更する
  - `RuntimeStringIterableBox` で文字列ハンドルのみ保持、消費時に遅延展開
- [ ] STDLIB-250: `kk_with_context` を非同期実行に対応させる
  - 現状: 実行コンテキストを取得するのみで、実際の実行は同期的なまま（`RuntimeCoroutine.swift`）
- [ ] STDLIB-088: `Flow` の lazy/cold stream セマンティクスを完全に実装する
  - 現状: `map`/`filter` 等が非常に最小限の stub 実装（`RuntimeCoroutine.swift`）
- [ ] STDLIB-133: Coroutine Dispatcher のスケジューラ実体を実装する
  - 現状: `KKD\x01` などのタグを返すのみで、スレッド制御は未実装（`RuntimeCoroutine.swift`）
- [x] STDLIB-480: `Regex` の `CANON_EQ` オプションに対応する
  - NFC 正規化によるマッチングで実装済み（`RuntimeRegex.swift`）
- [ ] STDLIB-331: `yieldAll` を `RuntimeSequence.swift` に実装し、Lowering と連携する
- [ ] STDLIB-324: File I/O のメンバー呼び出し（`readText` / `readLines` / `exists` 等）を `VirtualCallRewrite.swift` に統合する
  - 現状: Runtime は実装済みだが、Lowering が未対応のため標準ライブラリ呼び出しがリンクされない
- [ ] KIR-001: KIR の `Set` などのシンボル名を完全修飾名 (`kotlin.collections.Set`) に統一する
  - 現状: `CallSupportLowerer+DefaultArgsAndVarargs.swift:132` に TODO コメントあり
- [ ] TYPE-110: `toHashSet()` 等の戻り型を `MutableSet<T>` に修正する（型システムに可変コレクション型を追加する）
  - 現状: `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift:1223-1225` で `Set<T>` として返している（KL: mutable collection types are not yet supported in the type system）
- [ ] TYPE-111: HOF セレクタの Nullable キー（`K?`）をサポートする
  - 現状: `distinctBy` 等のセレクタ戻り型が `Any` に固定されており Nullable キーが利用不可（`HeaderHelpers+SyntheticComparableAndCollectionStubs.swift:1490`）
- [ ] STDLIB-088: Data Class の `copy()` メソッドを正しく実装する
  - 現状: `DataEnumSealedSynthesisPass.swift` で `$self` を返すだけの stub になっている
- [ ] STDLIB-089: Data Class (non-object) の `toString`, `equals`, `hashCode` を自動生成する
  - 現状: `DataEnumSealedSynthesisPass.swift` で `object` の場合にしか生成されていない
- [ ] STDLIB-090: Data Class の `componentN()` 関数を自動生成する
  - 現状: `DataEnumSealedSynthesisPass.swift` に全く実装されていない
- [ ] LOWER-005: `TailrecLoweringPass` で `$default` stub 呼び出しを最適化対象に含める
  - 現状: default 引数を含む再帰呼び出しは `foo$default` という別シンボルを呼ぶため、symbol identity チェック (`isSelfRecursiveCall`) で不一致となりループ最適化されない
- [ ] RUNTIME-001: Collection HOF のキー重複排除で `equals`/`hashCode` ベースの構造等価性を使用する
  - 現状: `distinctBy` 等は raw Int（identity）で比較。String は interning で動作するが、data class 等のカスタム型で誤結果になる（`RuntimeCollectionHOF.swift:1002-1014`）
- [ ] LOWERING-001: Lowering の virtual call rewrite を tracked receiver 以外の collection receiver にも適用する
  - 現状: `listExprIDs`/`setExprIDs` 等に含まれない receiver（関数引数や戻り値として受け取った List 等）は rewrite されない（`VirtualCallRewrite.swift:112`, `CallRewrite.swift:980`）
- [ ] CORO-001: Channel の suspend セマンティクスを実装する（send の一時停止とバックプレッシャー）
  - 現状: buffered channel は満杯時に drop、rendezvous は基本的に動作するが Kotlin の suspend 型セマンティクスとは異なる（`RuntimeCoroutine.swift:890-976`）
- [ ] TEST-001: `RuntimeDuration.swift` のテストを追加する
  - 現状: Duration ファクトリ、`inWhole*` アクセサ、`toString()` フォーマット、`measureTime` のテストが未追加（`RuntimeDuration.swift:17-19`）
- [ ] TEST-002: Long/Double/Float 型強制変換の golden/smoke テストを追加する
  - 現状: `HeaderHelpers+SyntheticCoercionStubs.swift:4` に TODO コメントあり
- [ ] TEST-003: Numeric bit-count 関数のエッジケーステストを追加する
  - 現状: `RuntimeNumericCompat.swift:481` に TODO コメントあり
- [ ] STDLIB-431: `Random.nextLong()` / `nextFloat()` を実装する
  - [ ] `HeaderHelpers+SyntheticRandomStubs.swift` に `nextLong` / `nextFloat` stub を登録する
  - [ ] Runtime に `kk_random_nextLong` / `kk_random_nextFloat` を追加する
  - **完了条件**: `Random.nextLong()` が 64-bit 乱数を返すこと
- [ ] STDLIB-430: `kotlin.math` の `Float` オーバーロード（`sin`, `cos` 等）を完備する
  - 現状: `HeaderHelpers+SyntheticMathStubs.swift` に TODO あり。現状は `Double` にキャストして計算している可能性がある
  - **完了条件**: `sin(1.0f)` が `Float` 型の戻り値を返し、`Double` への暗黙キャストが発生しないこと
- [ ] REFL-001: `KClass` / `KType` を型システムでモデル化する (TYPE-111)
  - 現状: `anyType` をプレースホルダーとして使用しており、型安全性が欠如している
- [ ] REFL-002: スタンドアロンの `T::class` 参照を `Unit` ではなく、正しいメタデータ参照として下げる
  - 現状: `simpleName` 呼び出しがない限り `Unit` にフォールバックされる
- [ ] REFL-003: 呼び出し可能参照 (`::foo`) に `KFunction` / `KProperty` の型アイデンティティを付与する
  - 現状: 単なるラムダとして生成されており、リフレクション API での利用が不可
- [ ] CODE-001: `return`, `break`, `continue` の際、囲んでいる `finally` ブロックを確実に実行するようにする
  - 現状: `ExprLowerer+ControlFlowAndBlocks.swift` で直接 `returnValue` / `jump` を発行しており、`finally` がスキップされる
- [ ] CODE-002: 例外型チェックの精度を向上させる (UNKNOWN token 0 の対応)
  - 現状: トークンが 0 の場合に全 catch 節にマッチしてしまう可能性がある。`kk_throwable_is_instance` による実行時チェックを導入する
- [ ] CORO-001: コルーチンのサスペンドを真に非ブロッキングにする
  - 現状: `waitForResumeSignal` で `DispatchSemaphore` を使用してスレッドをブロックしている。本来は継続（Continuation）を保存してスレッドを解放すべき
- [ ] CORO-002: `Flow` の評価を遅延（Lazy）にする
  - 現状: `runtimeFlowEvaluateSource` で全要素を即座に配列に収集している。無限ストリームに対応できない
- [ ] CORO-003: `currentScope` の管理に TLS (Thread Local Storage) を使用しないようにする
  - 現状: サスペンド・レジュームが別スレッドで行われた場合にスコープが消失する。コルーチンコンテキストに含めるべき
- [ ] REFL-004: 実行時リフレクション用メタデータの生成 (MetadataSerializer の活用)
  - 現状: コンパイル時のリンク用メタデータはあるが、実行時に `KClass` からアクセス可能なバイナリメタデータが存在しない
- [x] ENUM-001: Enum エントリの静的初期化と `valueOf` / `values` の KIR 合成
  - 完了: `DataEnumSealedSynthesisPass` が `__enum_static_init_<ClassName>` 関数を合成し、各エントリの KIRGlobal と ordinal 初期化を生成
- [ ] VAL-001: Value Class のアンボックス化（Unboxing）とマングリングの実装
  - 現状: 単なる class として扱われており、最適化（インライン化）が行われていない
- [ ] DATA-001: Data Class の `copy()` 生成を完備する
  - 現状: キャリアレシーバ（`this`）を即座に返す stub になっている。引数によるプロパティ上書きロジックが必要（`DataEnumSealedSynthesisPass.swift:227`）
- [ ] DATA-002: Data Class の `componentN()` シンボルの合成
  - 現状: `DataEnumSealedSynthesisPass.swift` に実装が皆無
- [ ] DATA-003: Data Class の `hashCode()` シンボルの合成
  - 現状: `DataEnumSealedSynthesisPass.swift` に実装が皆無
- [ ] DATA-004: 複数プロパティを持つ Data Class の `equals()` / `toString()` 修正
  - 現状: `object`（シングルトン）以外ではプロパティを考慮した比較・文字列表現が生成されない
- [x] INLINE-001: Inline 関数における非局所 return (Non-local return) の実装
  - KIRInstruction に `nonLocalReturn` 命令を追加し、InlineLoweringPass でインライン展開時に caller の `returnValue`/`returnUnit` へ変換する仕組みを実装済み
- [ ] INLINE-002: Inline 関数に渡されたラムダ引数のインライン展開
  - 現状: ラムダはインライン化されず、単なる間接呼び出しとして残るため overhead が削減されない
- [x] CLSR-001: 安定したクロージャオブジェクトの合成と LambdaClosureConversionPass の実装
  - 完了: キャプチャ変数を `kk_closure_obj_*` オブジェクトに格納し、`kk_closure_invoke_*` ラッパー経由で呼び出す closure conversion を実装
- [ ] ENUM-002: `enumValues()` が正しい Array オブジェクトを返すようにする
  - 現状: 現在は `count` (Int) のみを返しており、Kotlin の Array<T> セマンティクスを満たしていない（`DataEnumSealedSynthesisPass.swift:494`）
- [x] STDLIB-317: `String.asIterable()` を lazy `Iterable<Char>` ビューに変更する


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
