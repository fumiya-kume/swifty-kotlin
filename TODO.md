# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-12

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

### 📦 Stdlib — Enum ユーティリティ

- [x] STDLIB-171: `enumValues<T>()` / `enumValueOf<T>(name)` を実装する（基本実装完了）
  - [x] Sema に reified type parameter 付き `enumValues<T>(): List<T>` / `enumValueOf<T>(String): T` stub を登録する
  - [x] CallTypeChecker で enumValues/enumValueOf の特殊処理を追加
  - [x] CallLowerer で enumValues → kk_enum_make_values_array、enumValueOf → Companion.valueOf へ書き換え
  - [x] Runtime に `kk_enum_make_values_array(count)` を追加
  - [x] diff ケース `Scripts/diff_cases/enum_values.kt` を追加
  - [ ] `enumValues<Color>().map { it.name }` → `[RED, GREEN, BLUE]` の完全一致（map HOF のリンク要確認）

- [ ] STDLIB-172: `Enum.entries` プロパティ（Kotlin 1.9+）を実装する
  - [ ] Sema に `Enum<T>` companion の `entries: EnumEntries<T>` プロパティ stub を登録する
  - [ ] Lowering で companion property アクセスとして展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Color.entries.map { it.name }` → `[RED, GREEN]` が `kotlinc` と一致する

---

### 📦 Stdlib — Map 高度操作

- [x] STDLIB-195: `Map.getOrDefault(key, defaultValue)` / `Map.getOrElse(key) { defaultValue }` を実装する
  - [x] Sema に `Map<K,V>.getOrDefault(K, V): V` / `Map<K,V>.getOrElse(K, () -> V): V` stub を登録する
  - [x] Runtime に `kk_map_getOrDefault` / `kk_map_getOrElse` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1).getOrDefault("b", 0)` → `0` が `kotlinc` と一致する

- [x] STDLIB-196: `MutableMap.getOrPut(key) { defaultValue }` を実装する
  - [x] Sema に `MutableMap<K,V>.getOrPut(K, () -> V): V` stub を登録する
  - [x] Runtime でキーが存在しない場合に default を挿入する処理を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `mutableMapOf("a" to 1).getOrPut("b") { 2 }` → `2` が `kotlinc` と一致する

- [x] STDLIB-197: `Map.plus(pair)` / `Map.minus(key)` operator を実装する
  - [x] Sema に `Map<K,V>.plus(Pair<K,V>): Map<K,V>` / `Map<K,V>.minus(K): Map<K,V>` operator stub を登録する
  - [x] Runtime に新しい Map を生成する `kk_map_plus` / `kk_map_minus` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1) + ("b" to 2)` → `{a=1, b=2}` が `kotlinc` と一致する

- [x] STDLIB-198: `Map.count {}` / `Map.any {}` / `Map.all {}` / `Map.none {}` を実装する
  - [x] Sema に `Map<K,V>` の述語 HOF stub を登録する
  - [x] Runtime に `kk_map_count` / `kk_map_any` / `kk_map_all` / `kk_map_none` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1, "b" to 2).count { it.value > 1 }` → `1` が `kotlinc` と一致する

- [x] STDLIB-199: `Map.flatMap {}` / `Map.maxByOrNull {}` / `Map.minByOrNull {}` を実装する
  - [x] Sema に `Map<K,V>` の `flatMap` / `maxByOrNull` / `minByOrNull` stub を登録する
  - [x] Runtime に対応ランタイム関数を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1, "b" to 2).maxByOrNull { it.value }?.key` → `"b"` が `kotlinc` と一致する

- [x] STDLIB-200: `List<Pair<K,V>>.toMap()` / `Iterable<Pair<K,V>>.toMap()` を実装する
  - [x] Sema に `Iterable<Pair<K,V>>.toMap(): Map<K,V>` stub を登録する
  - [x] Runtime に `kk_list_toMap` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `listOf("a" to 1, "b" to 2).toMap()` → `{a=1, b=2}` が `kotlinc` と一致する

---

### 📦 Stdlib — MutableList 高度操作

- [x] STDLIB-205: `MutableList.sort()` / `MutableList.sortBy {}` / `MutableList.sortByDescending {}` を実装する
  - [x] Sema に `MutableList<T>.sort()` / `sortBy` / `sortByDescending` stub を登録する（in-place sort）
  - [x] Runtime に `kk_mutable_list_sort` / `kk_mutable_list_sortBy` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `val l = mutableListOf(3,1,2); l.sort(); println(l)` → `[1, 2, 3]` が `kotlinc` と一致する

- [x] STDLIB-206: `MutableList.shuffle()` / `MutableList.reverse()` を実装する
  - [x] Sema に `MutableList<T>.shuffle()` / `reverse()` stub を登録する（in-place 操作）
  - [x] Runtime に `kk_mutable_list_shuffle` / `kk_mutable_list_reverse` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `val l = mutableListOf(1,2,3); l.reverse(); println(l)` → `[3, 2, 1]` が `kotlinc` と一致する

- [x] STDLIB-207: `MutableList.addAll(collection)` / `MutableList.removeAll(collection)` / `MutableList.retainAll(collection)` を実装する
  - [x] Sema に `addAll(Collection<E>): Boolean` / `removeAll(Collection<E>): Boolean` / `retainAll(Collection<E>): Boolean` stub を登録する
  - [x] Runtime に対応ヘルパーを追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `val l = mutableListOf(1,2); l.addAll(listOf(3,4)); println(l)` → `[1, 2, 3, 4]` が `kotlinc` と一致する

- [x] STDLIB-208: `MutableList.add(index, element)` / `MutableList.set(index, element)` / `MutableList[index] = value` を実装する
  - [x] Sema に `add(Int, E)` / `set(Int, E): E` / `operator set(Int, E)` stub を登録する
  - [x] Runtime に `kk_mutable_list_add_at` / `kk_mutable_list_set` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `val l = mutableListOf(1,3); l.add(1, 2); println(l)` → `[1, 2, 3]` が `kotlinc` と一致する

---

### 📦 Stdlib — Collection ユーティリティ

- [x] STDLIB-210: `List.firstOrNull()` / `List.lastOrNull()` 引数なし版を実装する
  - [x] Sema に `List<T>.firstOrNull(): T?` / `List<T>.lastOrNull(): T?` stub を登録する（predicate なし）
  - [x] Runtime に `kk_list_firstOrNull` / `kk_list_lastOrNull` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `emptyList<Int>().firstOrNull()` → `null` が `kotlinc` と一致する

- [ ] STDLIB-211: `List.single()` / `List.singleOrNull()` を実装する
  - [ ] Sema に `single(): T` / `singleOrNull(): T?` stub を登録する
  - [ ] Runtime で要素数が 1 でない場合に `IllegalArgumentException` を throw する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(42).single()` → `42` が `kotlinc` と一致する

- [x] STDLIB-212: `List.getOrNull(index)` / `List.getOrElse(index) { default }` / `List.elementAtOrNull(index)` を実装する
  - [x] Sema に `getOrNull(Int): T?` / `getOrElse(Int, (Int) -> T): T` / `elementAtOrNull(Int): T?` stub を登録する
  - [x] Runtime に対応ヘルパーを追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3).getOrNull(5)` → `null` が `kotlinc` と一致する

- [ ] STDLIB-213: `List.subList(fromIndex, toIndex)` を実装する
  - [ ] Sema に `List<T>.subList(Int, Int): List<T>` stub を登録する
  - [ ] Runtime に `kk_list_subList` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3,4,5).subList(1, 3)` → `[2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-214: `List.binarySearch(element)` を実装する
  - [ ] Sema に `List<T>.binarySearch(T): Int` stub を登録する
  - [ ] Runtime に `kk_list_binarySearch` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3,4,5).binarySearch(3)` → `2` が `kotlinc` と一致する

- [ ] STDLIB-215: `List.asReversed()` / `List.asSequence()` 拡張を実装する
  - [ ] Sema に `asReversed(): List<T>` / `asSequence(): Sequence<T>` stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3).asReversed()` → `[3, 2, 1]` が `kotlinc` と一致する

---

### 📦 Stdlib — Iterable / Iterator インターフェース

- [ ] STDLIB-220: `Iterable<T>` インターフェースと `iterator()` メソッドを実装する
  - [ ] Sema に `Iterable<T>` インターフェースと `operator fun iterator(): Iterator<T>` を登録する
  - [ ] for-in ループで `Iterable` 実装型を利用可能にする
  - [ ] diff/golden ケースを追加する
  - **完了条件**: カスタム `Iterable` 実装クラスを for ループで使えるようになる

- [ ] STDLIB-221: `Iterator<T>` / `MutableIterator<T>` インターフェースを実装する
  - [ ] Sema に `Iterator<T>` (`hasNext(): Boolean`, `next(): T`) と `MutableIterator<T>` (`remove()`) を登録する
  - [ ] Runtime でイテレータプロトコルを正しくサポートする
  - [ ] diff/golden ケースを追加する
  - **完了条件**: カスタム `Iterator` 実装が for ループで動作する

---

### 📦 Stdlib — kotlin.reflect 基本

- [ ] STDLIB-225: `KClass<T>` 型と `::class` 構文を実装する
  - [ ] Sema に `KClass<T>` nominal type と `T::class` / `obj::class` 式を解決する
  - [ ] Runtime に `kk_get_class` を追加し、実行時型情報を返す
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `println(42::class.simpleName)` → `"Int"` が `kotlinc` と一致する

- [ ] STDLIB-226: `KClass.simpleName` / `KClass.qualifiedName` プロパティを実装する
  - [ ] Sema に `KClass<T>.simpleName: String?` / `KClass<T>.qualifiedName: String?` を登録する
  - [ ] Runtime で RTTI からクラス名を取得するヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `String::class.simpleName` → `"String"` が `kotlinc` と一致する

- [ ] STDLIB-227: `KClass.isInstance(value)` を実装する
  - [ ] Sema に `KClass<T>.isInstance(Any?): Boolean` stub を登録する
  - [ ] Runtime で RTTI を用いた型チェックを行う
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Int::class.isInstance(42)` → `true` が `kotlinc` と一致する

---

### 📦 Stdlib — kotlin.time

- [ ] STDLIB-230: `kotlin.time.Duration` 型と `Duration.seconds` / `Duration.milliseconds` 等を実装する
  - [ ] Sema に `Duration` value class と companion 拡張 `Int.seconds` / `Int.milliseconds` / `Long.seconds` を登録する
  - [ ] Runtime に `RuntimeDurationBox` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `5.seconds.inWholeMilliseconds` → `5000` が `kotlinc` と一致する

- [ ] STDLIB-231: `measureTime {}` / `measureTimedValue {}` を実装する
  - [ ] Sema に `kotlin.time.measureTime(block: () -> Unit): Duration` / `measureTimedValue(block: () -> T): TimedValue<T>` stub を登録する
  - [ ] Runtime に `kk_measure_time` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `measureTime { Thread.sleep(100) }` が正の Duration を返す

---

### 📦 Stdlib — Annotation 処理

- [ ] STDLIB-236: `@JvmOverloads` / `@JvmField` annotation を実装する
  - `@JvmStatic` は既存実装済み
  - [ ] Sema に `@JvmOverloads` / `@JvmField` annotation class を登録する
  - [ ] default parameter / field に対する lowering を調整する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `@JvmField val x = 1` と `@JvmOverloads fun f(x: Int = 0)` が `kotlinc` と一致する

- [ ] STDLIB-237: `@Throws(ExceptionClass::class)` annotation を実装する
  - [ ] Sema に `@Throws` annotation class を登録し、metadata に伝搬する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `@Throws(IOException::class)` が metadata に反映される

---

### 📦 Runtime Hardening — Silent Fallback 排除

- [ ] STDLIB-238: `Sequence` runtime の invalid handle fallback を fail-fast に置き換える
  - 背景: `kk_sequence_of` と同系統で、壊れた handle が空 sequence として観測される余地がまだ残っている
  - [ ] [Sources/Runtime/RuntimeSequence.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeSequence.swift) の `kk_sequence_from_list` / `kk_sequence_map` / `kk_sequence_filter` / `kk_sequence_take` / `kk_sequence_drop` / `kk_sequence_distinct` / `kk_sequence_zip` / `kk_sequence_forEach` / `kk_sequence_flatMap` / `kk_sequence_to_list` で `?? []` / 空 source fallback を棚卸しする
  - [ ] invalid handle を Kotlin 仕様の空 sequence と区別し、`fatalError("KSwiftK panic [...]")` か throwable 返却のどちらかに統一する
  - [ ] `runtimeSequenceSourceElements(from:)` の利用規約を整理し、「本当に許容される入力型」だけを受けるように制約する
  - [ ] `sequenceOf` / `asSequence` / `generateSequence` / chained HOF の diff/golden ケースを追加する
  - **完了条件**: 壊れた sequence handle は空結果にならず診断付きで停止し、正常系は `kotlinc` と一致する

- [ ] STDLIB-239: `Sequence` runtime の lambda throw 握りつぶしを解消する
  - 背景: `applyMapStep` / `applyFilterStep` / `kk_sequence_flatMap` が throw を空結果や部分結果に潰している
  - [ ] [Sources/Runtime/RuntimeSequence.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeSequence.swift) の throw 経路を洗い出し、`outThrown` 相当の伝搬戦略を決める
  - [ ] `applyMapStep` / `applyFilterStep` を result と thrown を分離して返せる形にリファクタする
  - [ ] `kk_sequence_forEach` / `kk_sequence_flatMap` を含め、例外発生時に silent success を返さないよう修正する
  - [ ] sequence HOF の throw ケース golden を追加する
  - **完了条件**: Sequence HOF 内の例外は空 list / 部分結果に化けず、呼び出し元まで観測可能になる

- [ ] STDLIB-240: Collection HOF の invalid container fallback を fail-fast へ統一する
  - 背景: list/map/array HOF が invalid handle を空 list/map/false に潰し、ABI 破綻や pointer 汚染の検知を遅らせている
  - [ ] [Sources/Runtime/RuntimeCollectionHOF.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeCollectionHOF.swift) の `kk_list_*` / `kk_map_*` / `kk_array_*` で invalid handle 時の返り値を一覧化する
  - [ ] Kotlin 仕様上 nullable/empty が正しいケースと runtime corruption を分離し、invalid handle は fail-fast か throwable に統一する
  - [ ] `map` / `filter` / `flatMap` / `groupBy` / `sortedBy` / `associate*` / `array_map` / `array_filter` を優先して修正する
  - [ ] `zip` / `unzip` / `take` / `drop` / `reversed` / `sorted` / `distinct` / `flatten` / `chunked` / `windowed` の `?.elements ?? []` 系 fallback も hardening 対象に含める
  - [ ] invalid handle の回帰ケースを追加する
  - **完了条件**: 壊れた collection handle が空コレクション成功扱いにならない

- [ ] STDLIB-241: Collection HOF の lambda throw fallback を厳格化する
  - 背景: `kk_list_map` などが `outThrown` を立てつつ空結果を返すため、呼び出し側の取りこぼしで silent corruption になる
  - [ ] [Sources/Runtime/RuntimeCollectionHOF.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeCollectionHOF.swift) の throw 処理を類型化する
  - [ ] `outThrown` を持つ runtime helper で「throw 時の返り値は未使用である」ことを ABI/コード生成側まで含めて確認する
  - [ ] 必要なら sentinel return を専用 panic path に切り替える
  - [ ] list/map/array HOF の throw regression を追加する
  - **完了条件**: HOF 内例外が空結果や `false` に見えず、すべて一貫した失敗経路に乗る

- [ ] STDLIB-242: Collection conversion API の silent empty fallback を除去する
  - 背景: `toList` / `toMutableList` / `toSet` / `copyOf` 系が invalid handle を空コレクションとして返す
  - [ ] [Sources/Runtime/RuntimeCollections.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeCollections.swift) の conversion/utility API を棚卸しする
  - [ ] `kk_list_to_mutable_list` / `kk_list_to_set` / `kk_map_keys` / `kk_map_values` / `kk_map_entries` / `kk_map_to_mutable_map` / `kk_array_toList` / `kk_array_toMutableList` / `kk_list_toTypedArray` / `kk_array_copyOf` / `kk_array_copyOfRange` を優先して修正する
  - [ ] Kotlin 仕様として empty が正当なケースは、入力が valid handle の場合にのみ成立することをテストで固定する
  - [ ] diff/golden とランタイム単体テストを追加する
  - **完了条件**: conversion 系 API で invalid handle が空結果として観測されない

- [ ] STDLIB-243: Range runtime の invalid handle fallback を厳格化する
  - 背景: range API が invalid handle を `0` や空 list に潰しており、空 range と区別できない
  - [ ] [Sources/Runtime/RuntimeRangeAndDispatch.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeRangeAndDispatch.swift) の `kk_range_first` / `last` / `count` / `toList` / `forEach` / `map` を見直す
  - [ ] property access と terminal/HOF で、invalid handle 時の失敗方針を統一する
  - [ ] `IntRange` / `downTo` / `step` / empty range / invalid handle の回帰ケースを追加する
  - **完了条件**: invalid range handle が空 range 相当の成功値にならない

- [ ] STDLIB-244: Regex runtime で no-match と invalid handle を分離する
  - 背景: regex API は invalid regex/string を false・空文字・元文字列・空 list に潰しており、仕様上の no-match と混同している
  - [ ] [Sources/Runtime/RuntimeRegex.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeRegex.swift) の `matches` / `contains` / `find` / `findAll` / `replace` / `split` / `pattern` / `match_result_*` を棚卸しする
  - [ ] 「入力 regex が invalid」ケースと「正しい regex だが match しない」ケースを分けて返すよう修正する
  - [ ] 既存 API 契約上 nullable を返すものは nullable を維持しつつ、invalid handle は fail-fast か throwable に統一する
  - [ ] regex diff/golden に invalid handle 回帰ケースを追加する
  - **完了条件**: Regex API で invalid handle が no-match と同じ返り値に潰れない

- [ ] STDLIB-245: String runtime の invalid handle fallback を fail-fast 方針へ整理する
  - 背景: `runtimeStringFromRaw(...) ?? ""` が広範囲に使われており、壊れた string handle が空文字として観測される
  - [ ] [Sources/Runtime/RuntimeStringStdlib.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeStringStdlib.swift) と [Sources/Runtime/RuntimeStringArray.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeStringArray.swift) の `?? ""` / `?? []` / `return 0` を棚卸しする
  - [ ] `trim` / `lowercase` / `uppercase` / `split` / `replace` / `startsWith` / `endsWith` / `contains` / `substringBefore*` / `substringAfter*` / `format` を優先して、invalid handle と正当な空文字入力を分離する
  - [ ] `String.iterator()` / `iterator.hasNext()` / `iterator.next()` の invalid iterator を通常終端と区別できるようにする
  - [ ] string invalid handle の diff/golden と runtime 単体テストを追加する
  - **完了条件**: invalid string / string-iterator handle が空文字や通常終端に潰れない

- [ ] STDLIB-246: String HOF の throw fallback を厳格化する
  - 背景: `kk_string_filter` / `kk_string_map` などが throw 時に空文字を返し、呼び出し側の取りこぼしで silent corruption になる
  - [ ] [Sources/Runtime/RuntimeStringStdlib.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeStringStdlib.swift) の `filter` / `map` / `count` / `any` / `all` / `none` の throw 経路を棚卸しする
  - [ ] `outThrown` を使う API の返り値契約を明文化し、throw 時に成功値風の文字列を返さないよう統一する
  - [ ] string HOF の throw regression を追加する
  - **完了条件**: String HOF 内例外が `""` や `false` に見えず、一貫した失敗経路に乗る

- [ ] STDLIB-247: Comparator trampoline の invalid closure fallback を fail-fast 化する
  - 背景: comparator trampoline が closure decode 失敗時に `0` を返し、比較結果の「同値」と区別できない
  - [ ] [Sources/Runtime/RuntimeComparator.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeComparator.swift) の `kk_comparator_from_selector_trampoline` / `kk_comparator_then_by_trampoline` / `kk_comparator_reversed_trampoline` の guard failure を棚卸しする
  - [ ] invalid comparator closure を fail-fast か throwable に統一し、`0` を返さないよう修正する
  - [ ] `sortedBy` / `sortedWith` / `compareBy` / `thenBy` / `reversed` 経由の回帰ケースを追加する
  - **完了条件**: invalid comparator closure が「要素が等しい」比較結果に潰れない

- [ ] STDLIB-248: Pair / Triple runtime の silent fallback を整理する
  - 背景: `Pair` / `Triple` accessor / conversion / toString が invalid handle を null sentinel・空 list・`(null, null)` に潰している
  - [ ] [Sources/Runtime/RuntimeCollections.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeCollections.swift) の `kk_pair_first` / `kk_pair_second` / `kk_pair_to_string` / `kk_pair_toList` / `kk_triple_*` を棚卸しする
  - [ ] API ごとに「Kotlin 仕様上 nullable を返す」のか「runtime corruption を fail-fast すべきか」を決める
  - [ ] pair/triple invalid handle の回帰ケースを追加する
  - **完了条件**: invalid `Pair` / `Triple` handle が成功値風の null sentinel / 空 list / 文字列表現に潰れない

- [ ] STDLIB-249: Delegate runtime の invalid handle fallback を fail-fast 化する
  - 背景: property delegate / lazy / observable / vetoable / custom delegate の各 helper が invalid handle を `0` や `newValue` に潰している
  - [ ] [Sources/Runtime/RuntimeDelegates.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeDelegates.swift) の `kk_kproperty_stub_*` / `kk_lazy_*` / `kk_observable_*` / `kk_vetoable_*` / `kk_custom_delegate_*` / `kk_delegate_*` を棚卸しする
  - [ ] invalid handle と「正当な false/0/null/新値返却」を区別し、fail-fast か throwable に統一する
  - [ ] custom delegate getter/setter 未設定時の契約を明文化し、silent success を返さないよう整理する
  - [ ] delegated property invalid handle の回帰ケースを追加する
  - **完了条件**: invalid delegate handle が通常の property 値や setter 成功値に潰れない

- [ ] STDLIB-250: Coroutine / Flow / Channel runtime の invalid handle fallback を整理する
  - 背景: flow collect / emit / channel / scope / await helper が invalid handle を `0` や no-op に潰している
  - [ ] [Sources/Runtime/RuntimeCoroutine.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeCoroutine.swift) の `kk_flow_*` / `kk_channel_*` / `kk_coroutine_scope_*` / `kk_job_join` / `kk_await_all` と補助 helper を棚卸しする
  - [ ] invalid handle・解放済み handle・型違い handle を fail-fast か throwable に統一する
  - [ ] `runtimeReadArrayElement` の `0` fallback を見直し、array decode failure と実際の `0` 要素を区別できるようにする
  - [ ] coroutine/flow invalid handle の回帰ケースを追加する
  - **完了条件**: invalid coroutine/flow/channel handle が通常終了や `0` 結果に潰れない

- [ ] STDLIB-251: Dispatch lookup の lookup failure と runtime corruption を分離する
  - 背景: `vtable` / `itable` lookup が `0` を返し、未登録メソッドと invalid receiver の区別が曖昧
  - [ ] [Sources/Runtime/RuntimeRangeAndDispatch.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeRangeAndDispatch.swift) の `kk_vtable_lookup` / `kk_itable_lookup` / `kk_dispatch_error` の契約を整理する
  - [ ] invalid receiver / slot 範囲外 / method 未登録を区別できる診断経路を導入する
  - [ ] dispatch failure の回帰ケースを追加する
  - **完了条件**: dispatch 失敗時に「本当にメソッドがない」のか「receiver/itable が壊れている」のか区別できる

- [ ] STDLIB-252: 低レベル String ABI の silent fallback を整理する
  - 背景: low-level string ABI が invalid pointer を `""` や null sentinel に潰しており、高レベル string API の hardeningを迂回してしまう
  - [ ] [Sources/Runtime/RuntimeStringArray.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeStringArray.swift) の `kk_string_concat` / `kk_string_compareTo` / `kk_string_length` と関連 helper を棚卸しする
  - [ ] invalid string pointer と正当な空文字/nullable を分離する
  - [ ] low-level string ABI の invalid handle 回帰ケースを追加する
  - **完了条件**: invalid string pointer が空文字や通常比較結果に潰れない

- [ ] STDLIB-253: Boxing / unboxing の契約違反を検出できるようにする
  - 背景: `kk_unbox_long` / `kk_unbox_float` / `kk_unbox_double` / `kk_unbox_char` は decode 不能時に入力値をそのまま返し、box/unbox の契約違反を隠す余地がある
  - [ ] [Sources/Runtime/RuntimeBoxing.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeBoxing.swift) の unbox helper の設計意図を整理する
  - [ ] 「未 box 値の passthrough」と「壊れた object pointer」の区別方法を設計する
  - [ ] 必要なら debug/runtime check を追加し、契約違反時に診断を出す
  - [ ] boxing/unboxing mismatch の回帰ケースを追加する
  - **完了条件**: box/unbox 契約違反が無言で passthrough されず、少なくとも診断可能になる

- [ ] STDLIB-254: Builder DSL runtime の silent fallback を fail-fast 化する
  - 背景: `buildString` / `buildList` / `buildMap` が frame push 失敗や invalid input を空結果に潰している
  - [ ] [Sources/Runtime/RuntimeBuilderDSL.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeBuilderDSL.swift) の `kk_string_builder_append` / `kk_build_string` / `kk_builder_list_add` / `kk_build_list` / `kk_builder_map_put` / `kk_build_map` を棚卸しする
  - [ ] frame 未作成・nesting 超過・invalid string pointer を fail-fast か throwable に統一する
  - [ ] builder lambda の throw 時に空文字/空 list/空 map を返さないよう契約を整理する
  - [ ] builder DSL invalid state の回帰ケースを追加する
  - **完了条件**: builder runtime の内部状態破綻が空結果成功に潰れない

- [ ] STDLIB-255: Random runtime の invalid range fallback を Kotlin 互換に修正する
  - 背景: `nextInt(until)` / `nextInt(from, until)` が不正範囲で `0` や `from` を返し、例外条件を成功値に潰している
  - [ ] [Sources/Runtime/RuntimeRandom.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeRandom.swift) の `kk_random_nextInt_until` / `kk_random_nextInt_range` を Kotlin 仕様と照合する
  - [ ] invalid range 時は `IllegalArgumentException` 系の失敗経路へ統一する
  - [ ] random range error の diff/golden ケースを追加する
  - **完了条件**: invalid random range が `0` や `from` に潰れず、`kotlinc` と同じ失敗になる

- [ ] STDLIB-256: low-level enum/string equality helper の invalid pointer fallback を整理する
  - 背景: enum 系で使う `kk_string_equals` が invalid pointer を `""` として比較し、名前比較の corruption を隠す
  - [ ] [Sources/Runtime/RuntimeEnum.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeEnum.swift) の `kk_string_equals` / `kk_enum_valueOf_throw` を見直す
  - [ ] invalid string pointer と正当な空文字比較を区別する
  - [ ] enum name comparison の invalid handle 回帰ケースを追加する
  - **完了条件**: enum/string name 比較で invalid pointer が空文字比較に潰れない

- [ ] STDLIB-257: Precondition lazy message fallback の失敗経路を明確化する
  - 背景: `require {}` / `check {}` の lazy message 評価失敗が default message fallback に見える余地がある
  - [ ] [Sources/Runtime/RuntimePreconditions.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimePreconditions.swift) の `preconditionWithLazyMessage` / `runtimeEvaluateLazyMessage` を棚卸しする
  - [ ] lazy message closure 自体の失敗と、通常の precondition failure を区別できるよう契約を整理する
  - [ ] lazy message throw の回帰ケースを追加する
  - **完了条件**: lazy message 評価失敗が通常の `require/check` 失敗に紛れず観測できる

- [ ] TOOL-046: synthetic stdlib stub と runtime ABI の整合性検査を自動化する
  - 背景: `sequenceOf` では `registerSyntheticVarargFunction(... externalLinkName: "kk_sequence_of")` と runtime ABI の引数数ズレが CI まで漏れた
  - [ ] `registerSyntheticVarargFunction` / `setExternalLinkName` で紐づく symbol を抽出し、[Sources/Runtime/RuntimeABISpec.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimeABISpec.swift) 系の spec と照合する仕組みを作る
  - [ ] vararg function は「runtime 側が受け取る形が packed array 1 引数である」ことを明示チェックする
  - [ ] CI に ABI 整合性検査を追加する
  - [ ] 不整合時は具体的な symbol 名・宣言箇所・期待/実際の引数数を出す
  - **完了条件**: synthetic stub と runtime ABI の引数数/vararg 形状ズレが CI で即座に検出される

---

### 📦 Stdlib — ArrayDeque

- [ ] STDLIB-240: `ArrayDeque<T>` 型を実装する
  - [ ] Sema に `ArrayDeque<T>()` コンストラクタと `addFirst` / `addLast` / `removeFirst` / `removeLast` / `first` / `last` / `size` member を登録する
  - [ ] Runtime に `RuntimeArrayDequeBox` と対応操作を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val dq = ArrayDeque<Int>(); dq.addLast(1); dq.addFirst(0); println(dq)` → `[0, 1]` が `kotlinc` と一致する

---

### 📦 Stdlib — Type Alias

- [ ] STDLIB-245: `ArrayList` / `HashMap` / `HashSet` / `LinkedHashMap` / `LinkedHashSet` 型エイリアスを実装する
  - [ ] Sema に `kotlin.collections.ArrayList<T>` → `MutableList<T>` 等の typealias を登録する
  - [ ] `ArrayList()` コンストラクタや `HashMap()` コンストラクタが MutableList / MutableMap として動作するようにする
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val list = ArrayList<Int>(); list.add(1); println(list)` → `[1]` が `kotlinc` と一致する

---

### 📦 Stdlib — Closeable / use

- [ ] STDLIB-250: `Closeable` / `AutoCloseable` インターフェースと `.use {}` 拡張を実装する
  - [ ] Sema に `Closeable` / `AutoCloseable` インターフェースと `T.use(block: (T) -> R): R` inline extension を登録する
  - [ ] Lowering で try-finally 展開し、finally ブロックで `close()` を呼び出す
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `resource.use { it.read() }` がブロック終了後に `close()` を呼び出す

---

### 📦 Stdlib — StringBuilder

- [ ] STDLIB-255: `StringBuilder` 型と基本操作（`append` / `toString` / `length`）を実装する
  - [ ] Sema に `StringBuilder()` コンストラクタと `append(Any?): StringBuilder` / `toString(): String` / `length: Int` を登録する
  - [ ] Runtime に `RuntimeStringBuilderBox` と対応操作を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `StringBuilder().append("hello").append(" ").append("world").toString()` → `"hello world"` が `kotlinc` と一致する

- [ ] STDLIB-256: `StringBuilder.appendLine()` / `StringBuilder.insert(index, value)` / `StringBuilder.delete(start, end)` を実装する
  - [ ] Sema に `appendLine(Any?): StringBuilder` / `insert(Int, Any?): StringBuilder` / `delete(Int, Int): StringBuilder` stub を登録する
  - [ ] Runtime に対応操作を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `StringBuilder().appendLine("hello").append("world").toString()` が `"hello\nworld"` を返す

- [ ] STDLIB-257: `StringBuilder.clear()` / `StringBuilder.deleteCharAt(index)` / `StringBuilder.reverse()` / `StringBuilder[index]` を実装する
  - [ ] Sema に各 member stub を登録する
  - [ ] Runtime に対応操作を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `StringBuilder("abc").reverse().toString()` → `"cba"` が `kotlinc` と一致する

---

### 📦 Stdlib — MutableMap 操作

- [ ] STDLIB-260: `MutableMap.clear()` を実装する
  - `MutableMap.put(K, V): V?` / `remove(K): V?` は既存実装済み
  - [ ] Sema に `MutableMap<K,V>.clear()` stub を登録する
  - [ ] Runtime に `kk_mutable_map_clear` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val m = mutableMapOf("a" to 1); m.clear(); println(m)` → `{}` が `kotlinc` と一致する

- [x] STDLIB-261: `MutableMap.putAll(map)` を実装する
  - `MutableMap[key] = value` operator set は既存実装済み
  - [x] Sema に `MutableMap<K,V>.putAll(Map<K,V>)` stub を登録する
  - [x] Runtime に対応ヘルパーを追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `val m = mutableMapOf("a" to 1); m.putAll(mapOf("b" to 2)); println(m)` → `{a=1, b=2}` が `kotlinc` と一致する

- [ ] STDLIB-262: `Map.getValue(key)` を実装する
  - [ ] Sema に `Map<K,V>.getValue(K): V` stub を登録する（キー不在時 `NoSuchElementException` throw）
  - [ ] Runtime に `kk_map_getValue` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1).getValue("a")` → `1`, `getValue("b")` が例外を投げ `kotlinc` と一致する

---

### 📦 Stdlib — MutableSet / Set 操作

- [x] STDLIB-265: `MutableSet.clear()` / `MutableSet.addAll(collection)` を実装する
  - `MutableSet.add(element)` / `MutableSet.remove(element)` は既存実装済み
  - [x] Sema に `MutableSet<E>.clear()` / `addAll(Collection<E>): Boolean` stub を登録する
  - [x] Runtime に `kk_mutable_set_clear` / `kk_mutable_set_addAll` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `val s = mutableSetOf(1, 2); s.clear(); s.addAll(setOf(2, 3)); println(s)` → `[2, 3]` が `kotlinc` と一致する

- [x] STDLIB-266: `Set.intersect(other)` / `Set.union(other)` / `Set.subtract(other)` を実装する
  - [x] Sema に `Set<T>.intersect(Iterable<T>): Set<T>` / `union` / `subtract` stub を登録する
  - [x] Runtime に `kk_set_intersect` / `kk_set_union` / `kk_set_subtract` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `setOf(1,2,3).intersect(setOf(2,3,4))` → `[2, 3]` が `kotlinc` と一致する

- [x] STDLIB-267: `Set.contains(element)` / `Set.containsAll(elements)` / `Set.isEmpty()` / `Set.size` を実装する
  - [x] Sema に `Set<E>` の基本プロパティ / メソッド stub を登録する
  - [x] Runtime に対応ヘルパーを追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `setOf(1, 2, 3).contains(2)` → `true` が `kotlinc` と一致する

- [ ] STDLIB-268: `Set.map {}` / `Set.filter {}` / `Set.forEach {}` / `Set.toList()` を実装する
  - [ ] Sema に `Set<T>` の HOF stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `setOf(1, 2, 3).map { it * 2 }` → `[2, 4, 6]` が `kotlinc` と一致する

---

### 📦 Stdlib — Sequence 高度操作

- [x] STDLIB-270: `Sequence.takeWhile {}` / `Sequence.dropWhile {}` を実装する
  - [x] Sema に `Sequence<T>.takeWhile((T) -> Boolean): Sequence<T>` / `dropWhile` stub を登録する
  - [x] Runtime に lazy ステップとして `kk_sequence_takeWhile` / `kk_sequence_dropWhile` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1,2,3,4,5).takeWhile { it < 4 }.toList()` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-271: `Sequence.mapNotNull {}` / `Sequence.filterNotNull()` / `Sequence.mapIndexed {}` / `Sequence.withIndex()` を実装する
  - [ ] Sema に各 stub を登録する
  - [ ] Runtime に対応する lazy ステップを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1, null, 3).filterNotNull().toList()` → `[1, 3]` が `kotlinc` と一致する

- [x] STDLIB-272: `Sequence.sorted()` / `Sequence.sortedBy {}` / `Sequence.sortedDescending()` を実装する
  - [x] Sema に各 stub を登録する（terminal 化して list 経由でソート）
  - [x] Runtime に対応ランタイム関数を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(3,1,2).sorted().toList()` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-273: `Sequence.first()` / `Sequence.firstOrNull()` / `Sequence.last()` / `Sequence.count()` を実装する
  - [ ] Sema に各 terminal operation stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1,2,3).first()` → `1` が `kotlinc` と一致する

- [ ] STDLIB-274: `Sequence.any {}` / `Sequence.all {}` / `Sequence.none {}` / `Sequence.fold {}` / `Sequence.reduce {}` を実装する
  - [ ] Sema に各 terminal operation stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1,2,3).any { it > 2 }` → `true` が `kotlinc` と一致する

- [ ] STDLIB-275: `Sequence.joinToString()` / `Sequence.sumOf {}` / `Sequence.associate {}` を実装する
  - [ ] Sema に `joinToString` / `sumOf` / `associate` / `associateBy` stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1,2,3).joinToString(", ")` → `"1, 2, 3"` が `kotlinc` と一致する

- [ ] STDLIB-276: `Sequence.chunked(size)` / `Sequence.windowed(size, step)` / `Sequence.onEach {}` を実装する
  - [ ] Sema に各 stub を登録する
  - [ ] Runtime に対応する lazy ステップを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1,2,3,4,5).chunked(2).toList()` → `[[1, 2], [3, 4], [5]]` が `kotlinc` と一致する

- [ ] STDLIB-277: `emptySequence<T>()` / `Sequence.ifEmpty { alternative }` を実装する
  - [ ] Sema に `emptySequence<T>(): Sequence<T>` / `Sequence<T>.ifEmpty(() -> Sequence<T>): Sequence<T>` stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `emptySequence<Int>().toList()` → `[]` が `kotlinc` と一致する

---

### 📦 Stdlib — Result / runCatching

- [ ] STDLIB-280: `Result<T>` 型と `runCatching {}` を実装する
  - [ ] Sema に `Result<T>` value class と `runCatching(block: () -> T): Result<T>` stub を登録する
  - [ ] Runtime に `RuntimeResultBox` を追加し、成功/失敗を保持する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `runCatching { 42 }.isSuccess` → `true` が `kotlinc` と一致する

- [ ] STDLIB-281: `Result.getOrNull()` / `Result.getOrDefault(default)` / `Result.getOrElse {}` / `Result.getOrThrow()` を実装する
  - [ ] Sema に各 member stub を登録する
  - [ ] Runtime で Result の値取得を実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `runCatching { error("fail") }.getOrDefault(0)` → `0` が `kotlinc` と一致する

- [ ] STDLIB-282: `Result.map {}` / `Result.mapCatching {}` / `Result.fold(onSuccess, onFailure)` を実装する
  - [ ] Sema に各 HOF stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `runCatching { 42 }.map { it * 2 }.getOrNull()` → `84` が `kotlinc` と一致する

- [ ] STDLIB-283: `Result.isSuccess` / `Result.isFailure` / `Result.exceptionOrNull()` / `Result.onSuccess {}` / `Result.onFailure {}` を実装する
  - [ ] Sema に各 member stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `runCatching { error("x") }.onFailure { println(it.message) }` → `"x"` が `kotlinc` と一致する

---

### 📦 Stdlib — Grouping

- [ ] STDLIB-285: `Iterable.groupingBy {}` / `Grouping.eachCount()` を実装する
  - [ ] Sema に `Iterable<T>.groupingBy((T) -> K): Grouping<T, K>` / `Grouping<T, K>.eachCount(): Map<K, Int>` stub を登録する
  - [ ] Runtime に `kk_grouping_eachCount` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf("a","bb","a","ccc").groupingBy { it.length }.eachCount()` → `{1=2, 2=1, 3=1}` が `kotlinc` と一致する

- [ ] STDLIB-286: `Grouping.fold {}` / `Grouping.reduce {}` / `Grouping.aggregate {}` を実装する
  - [ ] Sema に `Grouping` の `fold` / `reduce` / `aggregate` stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3,4).groupingBy { it % 2 }.fold(0) { acc, e -> acc + e }` → `{0=6, 1=4}` が `kotlinc` と一致する

---

### 📦 Stdlib — CharRange / LongRange

- [ ] STDLIB-290: `CharRange` (`'a'..'z'`) と `CharRange.toList()` / `CharRange.forEach {}` を実装する
  - [ ] Sema に `CharRange` の nominal type と `Char.rangeTo(Char): CharRange` を登録する
  - [ ] Runtime に `kk_char_range_iterator` / `kk_char_range_toList` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `('a'..'e').toList()` → `[a, b, c, d, e]` が `kotlinc` と一致する

- [ ] STDLIB-291: `LongRange` と `Long.rangeTo(Long)` / `LongRange.toList()` を実装する
  - [ ] Sema に `LongRange` の nominal type と `Long.rangeTo(Long): LongRange` を登録する
  - [ ] Runtime に `kk_long_range_iterator` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `(1L..5L).toList()` → `[1, 2, 3, 4, 5]` が `kotlinc` と一致する

---

### 📦 Stdlib — Collection / MutableCollection インターフェース

- [ ] STDLIB-295: `Collection<T>` インターフェース共通メソッド（`size`, `isEmpty`, `contains`, `containsAll`, `iterator`）を実装する
  - [ ] Sema に `Collection<T>` 共通 member を登録し、`List` / `Set` の共通 supertype として利用可能にする
  - [ ] 既存の `List` / `Set` 実装を `Collection` で受け取れるようにする
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `fun <T> printSize(c: Collection<T>) = println(c.size)` が `List` / `Set` どちらでも動作する

- [ ] STDLIB-296: `MutableCollection<T>` インターフェースを実装する
  - [ ] Sema に `MutableCollection<T>` を `Collection<T>` のサブタイプとして登録し、`add` / `remove` / `clear` メンバーを定義する
  - [ ] `MutableList` / `MutableSet` を `MutableCollection` のサブタイプとして扱えるようにする
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `fun addToCollection(c: MutableCollection<Int>) { c.add(42) }` が動作する

---

### 📦 Stdlib — onEach / maxByOrNull / minByOrNull

- [ ] STDLIB-300: `Iterable.onEach {}` / `Iterable.onEachIndexed {}` を実装する
  - [ ] Sema に `Iterable<T>.onEach((T) -> Unit): Iterable<T>` / `onEachIndexed((Int, T) -> Unit): Iterable<T>` stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3).onEach { print(it) }` → `123` を出力しリストを返す

- [ ] STDLIB-301: `Iterable.maxByOrNull {}` / `Iterable.minByOrNull {}` / `Iterable.maxOfOrNull {}` / `Iterable.minOfOrNull {}` を実装する
  - [ ] Sema に `maxByOrNull` / `minByOrNull` / `maxOfOrNull` / `minOfOrNull` stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf("a","bbb","cc").maxByOrNull { it.length }` → `"bbb"` が `kotlinc` と一致する

---

### 📦 Stdlib — Char / Int / Any 変換

- [ ] STDLIB-305: `Char.toInt()` / `Int.toChar()` を実装する
  - [ ] Sema に `Char.code: Int` (既出) に加え `Char.toInt(): Int` / `Int.toChar(): Char` stub を登録する
  - [ ] Lowering で直接の整数変換命令に展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `'A'.toInt()` → `65`, `65.toChar()` → `'A'` が `kotlinc` と一致する

- [ ] STDLIB-306: `Any.hashCode()` / `Any.toString()` / `Any.equals(other)` を実装する
  - [ ] Sema に `Any` の member method stub (`hashCode(): Int`, `toString(): String`, `equals(Any?): Boolean`) を登録する
  - [ ] Runtime に `kk_any_hashCode` / `kk_any_equals` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `42.hashCode()` / `42.toString()` が `kotlinc` と同一出力になる

- [ ] STDLIB-307: `Any?.toString()` safe call 版を実装する
  - [ ] Sema で nullable receiver の `toString()` 呼び出しを `"null"` 返却にフォールバックする
  - [ ] Runtime でnull sentinel を `"null"` に変換する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val x: Int? = null; println(x.toString())` → `"null"` が `kotlinc` と一致する

- [ ] STDLIB-308: `Boolean.not()` / `Boolean.and(other)` / `Boolean.or(other)` / `Boolean.xor(other)` を実装する
  - [ ] Sema に `Boolean` の member method stub を登録する
  - [ ] Lowering でビット演算命令に展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `true.and(false)` → `false` が `kotlinc` と一致する

---

### 📦 Stdlib — buildSet / buildString 拡張

- [ ] STDLIB-310: `buildSet {}` を実装する
  - [ ] Sema に `buildSet(builderAction: MutableSet<E>.() -> Unit): Set<E>` stub を登録する
  - [ ] Lowering で MutableSet 生成 + builder lambda 実行 + immutable 化に展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `buildSet { add(1); add(2); add(1) }.size` → `2` が `kotlinc` と一致する

- [ ] STDLIB-311: `buildString {}` の機能拡充（`appendLine` / `insert` / `delete`）を実装する
  - [ ] 既存の `buildString` DSL を `StringBuilder` 全メソッド対応に拡張する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `buildString { append("hello"); appendLine(); append("world") }` → `"hello\nworld"` が `kotlinc` と一致する

---

### 📦 Stdlib — String 追加 II

- [x] STDLIB-315: `String.replaceFirstChar {}` を実装する
  - [x] Sema に `String.replaceFirstChar((Char) -> Char): String` stub を登録する
  - [x] Runtime に `kk_string_replaceFirstChar` を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `"hello".replaceFirstChar { it.uppercaseChar() }` → `"Hello"` が `kotlinc` と一致する

- [ ] STDLIB-316: `String.chunked(size)` / `String.windowed(size, step)` / `String.zipWithNext()` を実装する
  - [ ] Sema に各 stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abcdef".chunked(2)` → `["ab", "cd", "ef"]` が `kotlinc` と一致する

- [ ] STDLIB-317: `String.asIterable()` / `String.asSequence()` を実装する
  - [ ] Sema に `String.asIterable(): Iterable<Char>` / `String.asSequence(): Sequence<Char>` stub を登録する
  - [ ] Runtime でイテレータ生成を実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abc".asSequence().map { it.uppercase() }.joinToString("")` → `"ABC"` が `kotlinc` と一致する

- [ ] STDLIB-318: `String.commonPrefixWith(other)` / `String.commonSuffixWith(other)` を実装する
  - [ ] Sema に `commonPrefixWith(String): String` / `commonSuffixWith(String): String` stub を登録する
  - [ ] Runtime に `kk_string_commonPrefixWith` / `kk_string_commonSuffixWith` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abcdef".commonPrefixWith("abcxyz")` → `"abc"` が `kotlinc` と一致する

- [ ] STDLIB-319: `String.toBigDecimal()` / `String.toBigInteger()` を実装する
  - [ ] Sema に `String.toBigDecimal(): java.math.BigDecimal` / `String.toBigInteger(): java.math.BigInteger` stub を登録する
  - [ ] Runtime に任意精度演算ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"12345678901234567890".toBigInteger()` の文字列表現が `kotlinc` と一致する

---

### 📦 Stdlib — File I/O

- [ ] STDLIB-320: `java.io.File` 基本操作（`readText` / `writeText` / `readLines`）を実装する
  - [ ] Sema に `File(String)` コンストラクタと `readText(): String` / `writeText(String)` / `readLines(): List<String>` stub を登録する
  - [ ] Runtime に `kk_file_readText` / `kk_file_writeText` / `kk_file_readLines` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp/test.txt").writeText("hello"); File("/tmp/test.txt").readText()` → `"hello"` が動作する

- [ ] STDLIB-321: `File.exists()` / `File.isFile` / `File.isDirectory` / `File.name` / `File.path` を実装する
  - [ ] Sema に各プロパティ / メソッド stub を登録する
  - [ ] Runtime に `kk_file_exists` / `kk_file_isFile` 等を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp").isDirectory` → `true` が動作する

- [ ] STDLIB-322: `File.forEachLine {}` / `File.useLines {}` / `File.bufferedReader()` を実装する
  - [ ] Sema に各 member stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("test.txt").forEachLine { println(it) }` が各行を出力する

- [ ] STDLIB-323: `File.walk()` / `File.listFiles()` / `File.delete()` / `File.mkdirs()` を実装する
  - [ ] Sema に各 member stub を登録する
  - [ ] Runtime に `kk_file_walk` / `kk_file_listFiles` / `kk_file_delete` / `kk_file_mkdirs` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp/test").mkdirs()` でディレクトリが作成される

---

### 📦 Stdlib — synchronized / Concurrency 基本

- [ ] STDLIB-325: `synchronized(lock) {}` を実装する
  - [ ] Sema に `synchronized(Any, block: () -> T): T` stub を登録する
  - [ ] Lowering で mutex acquire / release に展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `synchronized(obj) { sharedVar++ }` が排他制御付きで動作する

---

### 📦 Stdlib — sequence / iterator ビルダー（stdlib 版）

- [ ] STDLIB-330: `sequence {}` ビルダー（`kotlin.sequences.sequence`）を実装する
  - [ ] Sema に `sequence(block: suspend SequenceScope<T>.() -> Unit): Sequence<T>` stub を登録する
  - [ ] `SequenceScope.yield(value)` / `yieldAll(iterable)` を解決可能にする
  - [ ] Runtime で continuation ベースの lazy sequence 生成を実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequence { yield(1); yield(2); yield(3) }.toList()` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-331: `iterator {}` ビルダー（`kotlin.sequences.iterator`）を実装する
  - [ ] Sema に `iterator(block: suspend IteratorScope<T>.() -> Unit): Iterator<T>` stub を登録する
  - [ ] Runtime で continuation ベースのイテレータ生成を実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val iter = iterator { yield(1); yield(2) }; println(iter.next())` → `1` が `kotlinc` と一致する

---

### 📦 Stdlib — Map-backed Delegation

- [ ] STDLIB-335: `by map` / `by mutableMap` プロパティ委譲を実装する
  - [ ] Sema でプロパティの `by` 式が `Map` / `MutableMap` 型の場合に `getValue` / `setValue` 呼び出しを解決する
  - [ ] Runtime / Lowering でプロパティ名をキーとした Map アクセスに展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `class User(map: Map<String, Any?>) { val name: String by map }` が動作し `kotlinc` と一致する

---

### 📦 Stdlib — Delegates 拡張

- [ ] STDLIB-340: `Delegates.notNull<T>()` を実装する
  - [ ] Sema に `Delegates.notNull<T>(): ReadWriteProperty<Any?, T>` stub を登録する
  - [ ] Runtime で未初期化アクセス時に `IllegalStateException` を throw する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `var x: String by Delegates.notNull()` が代入前アクセスで例外を投げ `kotlinc` と一致する

---

### 📦 Stdlib — List / Map 演算子

- [ ] STDLIB-345: `List.plus(element)` / `List.plus(collection)` / `List.minus(element)` operator を実装する
  - [ ] Sema に `List<T>.plus(T): List<T>` / `List<T>.plus(Iterable<T>): List<T>` / `List<T>.minus(T): List<T>` operator stub を登録する
  - [ ] Runtime に `kk_list_plus` / `kk_list_minus` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1, 2) + 3` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-346: `List.containsAll(collection)` を実装する
  - [ ] Sema に `List<T>.containsAll(Collection<T>): Boolean` stub を登録する
  - [ ] Runtime に `kk_list_containsAll` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3).containsAll(listOf(1,3))` → `true` が `kotlinc` と一致する

---

### 📦 Stdlib — Regex 拡張

- [ ] STDLIB-350: `Regex.matchEntire(input)` / `MatchResult.destructured` を実装する
  - [ ] Sema に `Regex.matchEntire(String): MatchResult?` / `MatchResult.destructured: Destructured` stub を登録する
  - [ ] Runtime で full-match チェックと destructured group アクセスを実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Regex("(\\d+)-(\\d+)").matchEntire("123-456")?.destructured?.let { (a, b) -> "$a $b" }` → `"123 456"` が `kotlinc` と一致する

- [ ] STDLIB-351: `Regex.replace(input) { matchResult -> replacement }` ラムダ版を実装する
  - [ ] Sema に `Regex.replace(String, (MatchResult) -> String): String` stub を登録する
  - [ ] Runtime に `kk_regex_replace_lambda` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Regex("[0-9]+").replace("a1b2") { "X" }` → `"aXbX"` が `kotlinc` と一致する

---

### 🛡️ Type Safety — Sema / Runtime 境界

- [ ] TYPE-101: Collection HOF 推論で `Any` に潰れている戻り型を generic 保持に置き換える
  - [ ] `CallTypeChecker+MemberCallInference.swift` の `flatMap` / `associateBy` / `associateWith` / `associate` / `mapIndexed` / `groupBy` の戻り型推論を棚卸しする
  - [ ] ラムダ戻り型 `R`、key 型 `K`、value 型 `V` を `Any` にフォールバックせず `TypeID` として保持する共通ヘルパーを導入する
  - [ ] `flatMap` を `List<R>`、`associateBy` を `Map<K, T>`、`associateWith` を `Map<T, V>`、`associate` を `Map<K, V>` として推論できるようにする
  - [ ] `mapIndexed` を `List<R>`、`groupBy` を `Map<K, List<T>>` として推論できるようにする
  - [ ] `Any` に落ちたことで通ってしまっていた不正プログラムの negative golden を追加する
  - [ ] 正常系の diff/golden ケースを追加する
  - **完了条件**: `listOf(1).mapIndexed { _, x -> "$x" }` の型が `List<String>` になり、`associateBy` / `flatMap` / `groupBy` でも `kotlinc` と同等の型推論結果になる

- [ ] TYPE-102: synthetic collection stub の暫定 `Any` 戻り型を実型ベースに置き換える
  - [ ] `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift` の `partition` / `mapIndexed` など、コメントで「use Any for now」としている箇所を一覧化する
  - [ ] synthetic stub 側で関数型 type parameter `R`、`Pair<List<T>, List<T>>`、`Map<K, V>` を表現するための builder を追加する
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

- [ ] TYPE-104: library manifest 読み込みの `[String: Any]` 辞書運用を typed manifest decode に置き換える
  - [ ] `LibraryDiscovery.swift` と `LinkPhase.swift` で個別に JSON を `[String: Any]` として解釈している箇所を共通化対象として整理する
  - [ ] `manifest.json` 用の `Decodable` struct を定義し、`formatVersion` / `moduleName` / `target` / `metadata` / `objects` / `inlineKIRDir` を型付きで保持する
  - [ ] 現在の schema validation と path validation を typed manifest ベースへ移植する
  - [ ] decode failure と field mismatch を既存の `KSWIFTK-LIB-*` 診断コードへ対応付ける
  - [ ] `LinkPhase` の object path 解決も同じ manifest 型を使うように寄せる
  - [ ] manifest の異常系 fixture と golden を追加する
  - **完了条件**: manifest 読み込みで `as? [String: Any]` が消え、schema 不整合が typed decode + 既存診断で一貫して報告される

- [ ] TYPE-105: property delegate lowering の force unwrap を前提条件付き API に置き換える
  - [ ] `KIRLoweringDriver+ModuleLowering+PropertyDecl.swift` の `delegateExpression!` 利用箇所を `guard let` か専用 helper に置き換える
  - [ ] delegate 付き property であることを表す小さな内部モデルまたは引数型を導入し、呼び出し側で前提を確定させる
  - [ ] 不整合 AST が来た場合に crash ではなくコンパイラ診断または内部エラー文脈付き failure を返す方針を決めて実装する
  - [ ] delegate lowering 回りの回帰テストを追加する
  - **完了条件**: `delegateExpression!` が消え、delegate 前提違反時の失敗モードが追跡可能になる

- [ ] TYPE-106: symbol lookup の `first!` / force unwrap を診断可能な helper に置き換える
  - [ ] Sema / KIR で `lookupByShortName(...).first!` を使っている箇所を棚卸しし、stdlib symbol 前提のパターンを分類する
  - [ ] 「存在しない場合は compiler bug」「ユーザー入力起因なら診断」のどちらかを明示する helper を追加する
  - [ ] `List` / `Map` / `Pair` などの標準シンボル参照を helper 経由へ移行する
  - [ ] helper 導入後も既存診断文言が崩れないことを確認するテストを追加する
  - **完了条件**: 主要な type inference / stub 生成コードから `first!` が消え、失敗理由が追える

- [ ] TYPE-107: runtime comparator / collection HOF の生 `Int` 関数ポインタ運用を型付き ABI wrapper で局所化する
  - [ ] `RuntimeComparator.swift` / `RuntimeCollectionHOF.swift` / `RuntimeSequence.swift` の `unsafeBitCast` 利用をシグネチャ別に分類する
  - [ ] comparator selector、comparator lambda、collection unary/binary lambda ごとの wrapper typealias / decode helper を定義する
  - [ ] `closureRaw` と `fnPtr` の妥当性確認を共通 helper に集約し、失敗時の戻り値ポリシーを統一する
  - [ ] ABI spec / extern 宣言 / runtime 実装のシグネチャ差異を検出するテストを追加する
  - [ ] comparator 系の正常系と ABI mismatch 系テストを拡充する
  - **完了条件**: `unsafeBitCast` は wrapper helper の内部に閉じ込められ、各 runtime 関数本体では生シグネチャを直接扱わない

- [ ] TYPE-108: type safety 回帰を継続検知するテスト束を追加する
  - [ ] `mapIndexed` / `flatMap` / `associate*` / `groupBy` / `partition` の推論結果を固定する golden ケースを追加する
  - [ ] array erase heuristic が再導入されていないことを確認する negative ケースを追加する
  - [ ] typed manifest decode の異常系 fixture を追加する
  - [ ] delegate lowering 前提違反と runtime ABI mismatch の回帰テストを追加する
  - [ ] `Scripts/test_case_registry.json` に今回の TYPE タスク用テンプレートを登録する
  - **完了条件**: 今回洗い出した型安全性の穴に対応する回帰テストが一通り揃い、再発を CI で検知できる

- [ ] TYPE-109: runtime type check の文字列ベース型判定を型付き表現へ置き換える
  - [ ] `RuntimeTypeCheckToken.swift` と `ControlFlowLowerer+ThrowCatchAndWhen.swift` で `"Any"` などの型名文字列に依存している箇所を棚卸しする
  - [ ] builtin type / nominal type / unknown type を表す内部 enum または typed descriptor を導入する
  - [ ] `encodeBuiltinTypeName(_:)` と `simpleName(of:)` を、文字列 switch のまま外へ漏らさず typed API の内部実装へ閉じ込める
  - [ ] catch / `is` / `!is` / reified token 経路が同じ typed descriptor を使うように揃える
  - [ ] 型 alias や未解決 nominal 型で名前一致だけで誤判定しないことを確認するテストを追加する
  - **完了条件**: runtime type check の主要分岐から型名文字列比較が消え、型判定が `TypeID` / symbol ベースで一貫する

- [ ] TYPE-110: unresolved 型を `Any` に落とす制御フロー型推論を診断主導に置き換える
  - [ ] `ControlFlowLowerer+ThrowCatchAndWhen.swift` の unknown type → `Any` fallback を調査し、どの経路がユーザー入力起因か分類する
  - [ ] `catch` 節、`when is` 条件、destructuring 推論で unresolved component/type を `Any` 扱いせず、`invalid` または専用エラー経路へ寄せる
  - [ ] `ControlFlowTypeChecker+DestructuringInference.swift` の `componentType = anyType` fallback を見直す
  - [ ] 誤って広い `catch` や destructuring が通ってしまう negative golden を追加する
  - **完了条件**: 未解決型や `componentN` 解決失敗が `Any` に吸収されず、診断として表面化する

- [ ] TYPE-111: object literal / callable reference / lambda 文脈推論の `anyType` 退避を縮小する
  - [ ] `ExprTypeChecker+ObjectLiteralInference.swift` と `ExprTypeChecker+NameLambdaAndCallableRefInference.swift` の `?? sema.types.anyType` を棚卸しする
  - [ ] 文脈型が取れないケースと本当に `Any` が正しいケースを分離し、前者は未解決状態を保持できるようにする
  - [ ] callable reference のパラメータ型・戻り型が取れない場合に、後段の解決へ渡す placeholder type を `Any` 以外で表現する
  - [ ] object literal の supertype 解決失敗時に過剰に `Any` object と見なさないようにする
  - [ ] diff/golden と negative ケースを追加する
  - **完了条件**: object literal / callable reference / lambda 推論で `Any` への早すぎる退避が減り、型エラー位置が `kotlinc` に近づく

- [ ] TYPE-112: internal JSON export を typed report に置き換える
  - [ ] `PhaseTimer.exportJSON()` の `[[String: Any]]` を `Codable` な report struct 配列へ置き換える
  - [ ] 既存呼び出し側が必要とする JSON shape を確認し、外部互換を保つ encoder 層を追加する
  - [ ] sub-phase も含めて key typo や数値型揺れが起きないようにする
  - [ ] export 形式の snapshot テストを追加する
  - **完了条件**: timing report の内部表現から `[String: Any]` が消え、JSON 出力が typed model 経由で生成される

- [ ] TYPE-113: coroutine / flow まわりの `Any` 型消去ポイントを棚卸しして縮小する
  - [ ] `Sema/TypeCheck/Helpers.swift` の `Flow<T>` を `nullableAnyType` に erase している箇所と、その依存先を洗い出す
  - [ ] `CallTypeChecker.swift` / `MemberCallInference.swift` / coroutine lowering で continuation や collector/emitter の型を `Any` に落としている箇所を分類する
  - [ ] 「現状必要な ABI 上の erase」と「Sema 内でも不要に erase している箇所」を切り分ける
  - [ ] まずは Sema 内で保持可能な generic 情報を残す最小変更を設計する
  - [ ] 代表ケースの golden と runtime 回帰テストを追加する
  - **完了条件**: coroutine / flow 系で不要な `Any` / `Any?` 退避が減り、少なくとも Sema レイヤでは要素型 `T` を追跡できる範囲が広がる

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
