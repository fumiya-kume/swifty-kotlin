# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-11

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

### 📦 Stdlib — スコープ関数・ユーティリティ

- [x] STDLIB-062: `require(condition)` / `check(condition)` / `error(message)` を実装する
  - [x] Sema に `require(Boolean)` / `check(Boolean)` / `error(String)` stub を登録する
  - [x] Runtime で条件不成立時に `IllegalArgumentException` / `IllegalStateException` を throw する
  - [x] diff/golden ケースを追加する
  - **完了条件**: `require(false)` が `IllegalArgumentException` を投げ `kotlinc` と一致する

- [ ] STDLIB-063: `TODO(reason)` / `println()` 引数なし版 / `readLine()` を実装する
  - [x] Sema に `TODO(String): Nothing` / `println(): Unit` / `readLine(): String?` stub を登録する
  - [x] Runtime でそれぞれ `NotImplementedError` throw / 改行出力 / stdin 読み取りを行う
  - [x] diff/golden ケースを追加する
  - **完了条件**: `TODO("not done")` が `NotImplementedError` を投げ `kotlinc` と一致する
  - **備考**: TODO は diff 通過。println()/readLine() は stub+runtime 実装済みだが、println は実行時 exit 232、readLine は Sema 解決要調査のため SKIP-DIFF。

---

### 📦 Stdlib — buildList / buildMap / buildString (DSL)

- [ ] STDLIB-070: `buildList {}` を stdlib DSL として実装する
  - [ ] Sema に `buildList(builderAction: MutableList<E>.() -> Unit): List<E>` stub を登録する
  - [ ] Lowering で MutableList 生成 + builder lambda 実行 + immutable 化に展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `buildList { add(1); add(2) }` → `[1, 2]` が `kotlinc` と一致する

- [x] STDLIB-071: `buildMap {}` を stdlib DSL として実装する
  - [x] Sema に `buildMap(builderAction: MutableMap<K,V>.() -> Unit): Map<K,V>` stub を登録する
  - [x] Lowering で MutableMap 生成 + builder lambda 実行 + immutable 化に展開する（既存実装を利用）
  - [x] diff/golden ケースを追加する
  - **完了条件**: `buildMap { put("a", 1) }` → `{a=1}` が `kotlinc` と一致する ✓

- [ ] STDLIB-072: `List.mapNotNull {}` / `List.filterNotNull()` のランタイム異常終了を解消する
  - [ ] `CodegenBackendIntegrationTests` で常時 skip されている `mapNotNull` / `filterNotNull` テストを再有効化する
  - [ ] codegen / runtime のどちらで exit 11 を起こしているか切り分ける
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1, 0, 2).mapNotNull { it }` と `listOf("a", null, "b").filterNotNull()` が `kotlinc` と一致し、常時 skip が不要になる

- [ ] STDLIB-073: `associateBy` / `associateWith` / `associate` の誤った key-value 生成を修正する
  - [ ] `CodegenBackendIntegrationTests` で常時 skip されている associate 系テストを再有効化する
  - [ ] key と value の構築順序、および Pair 展開の lowering を点検する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1, 2, 3).associateBy { it % 2 }` などの出力が `kotlinc` と一致し、常時 skip が不要になる

- [ ] STDLIB-074: `withIndex` / `forEachIndexed` / `mapIndexed` の link failure を解消する
  - [ ] `CodegenBackendIntegrationTests` で常時 skip されている indexed helper テストを再有効化する
  - [ ] シンボル解決・runtime 参照・link 入力を点検し `outputUnavailable` を解消する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf("a", "bb").mapIndexed { index, value -> index + value.length }` が `kotlinc` と一致し、常時 skip が不要になる

---

### 🧩 Frontend / Sema / Lowering の暫定対応解消

- [ ] MPP-001: `expect` / `actual` の nominal/typealias 互換判定を厳密化する
  - [ ] `same-kind/same-fqName` を無条件許可している暫定判定を廃止する
  - [ ] 型引数・上限・種別差分を含む互換条件を定義する
  - [ ] 不一致ケースと曖昧解決ケースの golden を追加する
  - **完了条件**: nominal/typealias の不正な `actual` が受理されず、正当な組み合わせのみ `expect/actual` link される

- [ ] PROP-001: property accessor のフラットトークン fallback 依存を解消する
  - [ ] `val x: T get() = expr` 形式を AST 段階で正規ノードとして構築する
  - [ ] `BuildASTPhase+PropertyParsing` の flat token 再解析 fallback を不要にする
  - [ ] inline accessor の diff/golden ケースを追加する
  - **完了条件**: inline accessor が fallback なしで安定して AST 化される

- [ ] TYPE-001: 継承解決時の primitive/built-in 型引数の all-or-nothing fallback を解消する
  - [ ] `Int` / `String` / `Boolean` などの built-in 型引数を DataFlowSemaPhase でも解決可能にする
  - [ ] 1 個の型引数解決失敗で supertype edge 全体の型引数を落とす処理を廃止する
  - [ ] 継承・型別名・generic supertype の golden を追加する
  - **完了条件**: primitive を含む型引数付き継承が後段任せにならず、DataFlowSemaPhase で一貫した型情報を保持できる

- [ ] GEN-001: class initializer 順序の legacy fallback を解消する
  - [ ] property initializer と init block の順序情報を常に lowering 入力へ保持する
  - [ ] `legacy ordering` fallback を削除する
  - [ ] 初期化順序依存ケースの diff/golden を追加する
  - **完了条件**: property / init block の実行順序が常に Kotlin 仕様どおりで、legacy fallback が不要になる

- [ ] GEN-002: virtual dispatch の null guard 不可時 direct dispatch fallback を解消する
  - [ ] callee 解決時に null guard を構築できない原因を切り分ける
  - [ ] `NativeEmitter+FunctionEmission` の direct dispatch fallback を不要にする
  - [ ] 例外経路と nullable receiver を含む codegen テストを追加する
  - **完了条件**: virtual dispatch が null guard 付きで一貫して生成され、fallback 経路に依存しない

### 📦 Stdlib — Char 拡張

- [ ] STDLIB-080: `Char.isDigit()` / `Char.isLetter()` / `Char.isWhitespace()` を実装する
  - [ ] Sema に `Char` の member stub (`isDigit`, `isLetter`, `isLetterOrDigit`, `isWhitespace`) を登録する
  - [ ] Runtime に `kk_char_isDigit` / `kk_char_isLetter` / `kk_char_isWhitespace` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `'A'.isLetter()` → `true`, `'1'.isDigit()` → `true` が `kotlinc` と一致する

- [ ] STDLIB-081: `Char.uppercase()` / `Char.lowercase()` / `Char.titlecase()` を実装する
  - [ ] Sema に `Char.uppercase(): String` / `Char.lowercase(): String` stub を登録する
  - [ ] Runtime に `kk_char_uppercase` / `kk_char_lowercase` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `'a'.uppercase()` → `"A"` が `kotlinc` と一致する

- [ ] STDLIB-082: `Char.isUpperCase()` / `Char.isLowerCase()` / `Char.code` を実装する
  - [ ] Sema に `Char.isUpperCase(): Boolean` / `Char.isLowerCase(): Boolean` / `Char.code: Int` を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `'A'.isUpperCase()` → `true`, `'A'.code` → `65` が `kotlinc` と一致する

- [ ] STDLIB-083: `Char.digitToInt()` / `Char.digitToIntOrNull()` を実装する
  - [ ] Sema に `Char.digitToInt(): Int` / `Char.digitToIntOrNull(): Int?` stub を登録する
  - [ ] Runtime に `kk_char_digitToInt` を追加し、非数字で `IllegalArgumentException` を throw する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `'5'.digitToInt()` → `5` が `kotlinc` と一致する

---

### 📦 Stdlib — Array 操作

- [ ] STDLIB-085: `Array<T>` コンストラクタ `Array(size) { init }` を実装する
  - [ ] Sema に `Array(Int, init: (Int) -> T)` の constructor stub を登録する
  - [ ] Lowering / Runtime で配列を初期化ラムダで生成する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Array(3) { it * 2 }` → `[0, 2, 4]` が `kotlinc` と一致する

- [ ] STDLIB-086: `IntArray` / `LongArray` / `DoubleArray` / `BooleanArray` などプリミティブ配列型を実装する
  - [ ] Sema に `IntArray(size)` / `intArrayOf(vararg Int)` 等の stub を登録する
  - [ ] Runtime に対応するプリミティブ配列ボックスを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `intArrayOf(1, 2, 3).size` → `3` が `kotlinc` と一致する

- [ ] STDLIB-087: `Array.toList()` / `Array.toMutableList()` / `List.toTypedArray()` を実装する
  - [ ] Sema に配列⇔リスト変換 stub を登録する
  - [ ] Runtime に変換ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `arrayOf(1, 2, 3).toList()` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-088: `Array.map {}` / `Array.filter {}` / `Array.forEach {}` を実装する
  - [ ] Sema に `Array<T>` の HOF stub (`map`, `filter`, `forEach`, `any`, `none`) を登録する
  - [ ] Runtime に `kk_array_map` / `kk_array_filter` / `kk_array_forEach` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `arrayOf(1, 2, 3).map { it * 2 }` → `[2, 4, 6]` が `kotlinc` と一致する

- [ ] STDLIB-089: `Array.copyOf()` / `Array.copyOfRange(from, to)` / `Array.fill(value)` を実装する
  - [ ] Sema に `copyOf` / `copyOfRange` / `fill` stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `arrayOf(1,2,3).copyOfRange(0, 2).toList()` → `[1, 2]` が `kotlinc` と一致する

---

### 📦 Stdlib — Range / Progression 拡張

- [ ] STDLIB-090: `IntRange.contains(value)` / `in` 演算子をサポートする
  - [ ] Sema に `IntRange.contains(Int): Boolean` stub を登録する
  - [ ] Lowering で `value in start..end` を効率的な比較命令に展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `5 in 1..10` → `true` が `kotlinc` と一致する

- [ ] STDLIB-091: `IntRange.toList()` / `IntRange.forEach {}` / `IntRange.map {}` を実装する
  - [ ] Sema に `IntRange` の HOF stub を登録する
  - [ ] Runtime に `kk_range_toList` / `kk_range_forEach` / `kk_range_map` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `(1..5).toList()` → `[1, 2, 3, 4, 5]` が `kotlinc` と一致する

- [ ] STDLIB-092: `IntRange.first` / `IntRange.last` / `IntRange.count()` プロパティを実装する
  - [ ] Sema に `IntRange.first: Int` / `IntRange.last: Int` のプロパティ stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `(1..5).first` → `1`, `(1..5).last` → `5` が `kotlinc` と一致する

- [ ] STDLIB-093: `IntRange.reversed()` / `IntProgression.step` を実装する
  - [ ] Sema に `IntRange.reversed()` / `IntProgression.step` stub を登録する
  - [ ] Runtime で逆順イテレーションとステップ付きイテレーションを正しく生成する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `(1..5).reversed().toList()` → `[5, 4, 3, 2, 1]` が `kotlinc` と一致する

---

### 📦 Stdlib — Sequence 拡張

- [ ] STDLIB-095: `Sequence.flatMap {}` / `Sequence.forEach {}` を実装する
  - [ ] Sema に `Sequence<T>` の `flatMap` / `forEach` stub を登録する
  - [ ] Runtime に `kk_sequence_flatMap` / `kk_sequence_forEach` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1,2,3).forEach { print(it) }` → `123` が `kotlinc` と一致する

- [ ] STDLIB-096: `Sequence.zip(other)` / `Sequence.drop(n)` / `Sequence.distinct()` を実装する
  - [ ] Sema に `zip` / `drop` / `distinct` stub を登録する
  - [ ] Runtime に対応する lazy ステップ処理を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1,2,3).drop(1).toList()` → `[2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-097: `sequenceOf(vararg T)` / `generateSequence(seed) { nextFunc }` を実装する
  - [ ] Sema に `sequenceOf` / `generateSequence` stub を登録する
  - [ ] Runtime に `kk_sequence_of` / `kk_sequence_generate` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `generateSequence(1) { it * 2 }.take(5).toList()` → `[1, 2, 4, 8, 16]` が `kotlinc` と一致する

---

### 📦 Stdlib — Regex

- [ ] STDLIB-100: `Regex` 型と `String.matches(Regex)` / `String.contains(Regex)` を実装する
  - [ ] Sema に `Regex(String)` コンストラクタと `String.matches(Regex): Boolean` / `String.contains(Regex): Boolean` stub を登録する
  - [ ] Runtime に `kk_regex_create` / `kk_regex_matches` / `kk_regex_contains` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abc123".matches(Regex("[a-z]+[0-9]+"))` → `true` が `kotlinc` と一致する

- [ ] STDLIB-101: `Regex.find(input)` / `Regex.findAll(input)` を実装する
  - [ ] Sema に `Regex.find(String): MatchResult?` / `Regex.findAll(String): Sequence<MatchResult>` stub を登録する
  - [ ] `MatchResult` の `value` / `range` / `groupValues` プロパティを定義する
  - [ ] Runtime に `kk_regex_find` / `kk_regex_findAll` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Regex("[0-9]+").find("abc123")?.value` → `"123"` が `kotlinc` と一致する

- [ ] STDLIB-102: `String.replace(Regex, replacement)` / `String.split(Regex)` を実装する
  - [ ] Sema に `String.replace(Regex, String): String` / `String.split(Regex): List<String>` stub を登録する
  - [ ] Runtime に `kk_string_replaceRegex` / `kk_string_splitRegex` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abc123def".replace(Regex("[0-9]+"), "X")` → `"abcXdef"` が `kotlinc` と一致する

- [ ] STDLIB-103: `String.toRegex()` / `Regex.toPattern()` を実装する
  - [ ] Sema に `String.toRegex(): Regex` / `Regex.pattern: String` stub を登録する
  - [ ] Runtime に対応変換ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"[a-z]+".toRegex().pattern` → `"[a-z]+"` が `kotlinc` と一致する

---

### 📦 Stdlib — Collection 高度操作

- [ ] STDLIB-110: `List.chunked(size)` / `List.windowed(size, step)` を実装する
  - [ ] Sema に `chunked(Int): List<List<T>>` / `windowed(Int, Int): List<List<T>>` stub を登録する
  - [ ] Runtime に `kk_list_chunked` / `kk_list_windowed` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3,4,5).chunked(2)` → `[[1, 2], [3, 4], [5]]` が `kotlinc` と一致する

- [ ] STDLIB-111: `List.flatten()` / `List.flatMap {}` のネスト版を実装する
  - [ ] Sema に `List<List<T>>.flatten(): List<T>` stub を登録する
  - [ ] Runtime に `kk_list_flatten` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(listOf(1,2), listOf(3)).flatten()` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-112: `List.partition {}` を実装する
  - [ ] Sema に `partition(predicate: (T) -> Boolean): Pair<List<T>, List<T>>` stub を登録する
  - [ ] Runtime に `kk_list_partition` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3,4).partition { it % 2 == 0 }` → `([2, 4], [1, 3])` が `kotlinc` と一致する

- [ ] STDLIB-113: `List.indexOf(element)` / `List.lastIndexOf(element)` / `List.indexOfFirst {}` / `List.indexOfLast {}` を実装する
  - [ ] Sema に各 stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3,2).indexOf(2)` → `1` が `kotlinc` と一致する

- [ ] STDLIB-114: `List.filterIsInstance<T>()` を実装する
  - [ ] Sema に reified type parameter 付き `filterIsInstance<R>(): List<R>` stub を登録する
  - [ ] Runtime で RTTI を用いた型フィルタリングを行う
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1, "a", 2).filterIsInstance<Int>()` → `[1, 2]` が `kotlinc` と一致する

- [ ] STDLIB-115: `List.sortedWith(Comparator)` / `List.sortedDescending()` / `List.sortedByDescending {}` を実装する
  - [ ] Sema に各ソート stub を登録する
  - [ ] Runtime に `kk_list_sortedWith` / `kk_list_sortedDescending` / `kk_list_sortedByDescending` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(3,1,2).sortedDescending()` → `[3, 2, 1]` が `kotlinc` と一致する

---

### 📦 Stdlib — Pair / Triple

- [ ] STDLIB-120: `Triple<A, B, C>` 型を実装する
  - [ ] Sema に `Triple(A, B, C)` / `Triple.first` / `Triple.second` / `Triple.third` / `Triple.toString()` を登録する
  - [ ] Runtime に `RuntimeTripleBox` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Triple(1, "a", true).toString()` → `(1, a, true)` が `kotlinc` と一致する

- [ ] STDLIB-121: `Pair.toList()` / `Triple.toList()` を実装する
  - [ ] Sema に `Pair.toList(): List<Any?>` / `Triple.toList(): List<Any?>` stub を登録する
  - [ ] Runtime に変換ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Pair(1, 2).toList()` → `[1, 2]` が `kotlinc` と一致する

---

### 📦 Stdlib — 例外型の拡充

- [ ] STDLIB-125: `IllegalArgumentException` / `IllegalStateException` / `IndexOutOfBoundsException` を実装する
  - [ ] Sema に各例外クラスのコンストラクタ stub と supertype 関係を登録する
  - [ ] Runtime で例外メッセージ付き throw を正しくハンドルする
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `throw IllegalArgumentException("bad arg")` が catch 可能で `kotlinc` と一致する

- [ ] STDLIB-126: `UnsupportedOperationException` / `NoSuchElementException` / `ArithmeticException` / `ClassCastException` を実装する
  - [ ] Sema に各例外クラスの supertype 階層を登録する
  - [ ] Runtime で例外ごとの型判定を正しく行う
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf<Int>().first()` が `NoSuchElementException` を投げ `kotlinc` と一致する

- [ ] STDLIB-127: `Throwable.message` / `Throwable.cause` / `Throwable.stackTraceToString()` プロパティを実装する
  - [ ] Sema に `Throwable.message: String?` / `Throwable.cause: Throwable?` プロパティ stub を登録する
  - [ ] Runtime で例外プロパティアクセスを正しく解決する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `try { ... } catch (e: Exception) { println(e.message) }` が `kotlinc` と一致する

---

### 📦 Stdlib — I/O / システム

- [ ] STDLIB-130: `print(message)` 複数引数版 / `readln()` を実装する
  - [ ] Sema に `print(Any?)` / `readln(): String` stub を登録する
  - [ ] Runtime で stdin 読み取りを実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `readln()` が入力を返し `kotlinc` と一致する

- [ ] STDLIB-131: `System.currentTimeMillis()` 相当の時刻取得を実装する
  - [ ] Sema に `kotlin.system.measureTimeMillis {}` / `System.currentTimeMillis()` stub を登録する
  - [ ] Runtime に `kk_system_currentTimeMillis` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `measureTimeMillis { Thread.sleep(100) }` の戻り値が正の整数になる

- [ ] STDLIB-132: `kotlin.system.exitProcess(status)` を実装する
  - [ ] Sema に `exitProcess(Int): Nothing` stub を登録する
  - [ ] Runtime で `exit()` システムコールに展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `exitProcess(0)` でプロセスが終了する

---

### 📦 Stdlib — String 追加

- [ ] STDLIB-140: `String.get(index)` / `String[index]` operator を実装する
  - [ ] Sema に `String.get(Int): Char` / `operator get(Int): Char` stub を登録する
  - [ ] Runtime に `kk_string_get` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"hello"[1]` → `'e'` が `kotlinc` と一致する

- [ ] STDLIB-141: `String.compareTo(other, ignoreCase)` を実装する
  - [ ] Sema に `String.compareTo(String, Boolean): Int` stub を登録する（`ignoreCase` デフォルト引数付き）
  - [ ] Runtime に `kk_string_compareToIgnoreCase` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abc".compareTo("ABC", true)` → `0` が `kotlinc` と一致する

- [ ] STDLIB-142: `String.toBoolean()` / `String.toBooleanStrict()` を実装する
  - [ ] Sema に `String.toBoolean(): Boolean` / `String.toBooleanStrict(): Boolean` stub を登録する
  - [ ] Runtime に `kk_string_toBoolean` / `kk_string_toBooleanStrict` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"true".toBoolean()` → `true`, `"yes".toBooleanStrict()` が例外を投げ `kotlinc` と一致する

- [ ] STDLIB-143: `String.lines()` / `String.lineSequence()` を実装する
  - [ ] Sema に `String.lines(): List<String>` / `String.lineSequence(): Sequence<String>` stub を登録する
  - [ ] Runtime に `kk_string_lines` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"a\nb\nc".lines()` → `[a, b, c]` が `kotlinc` と一致する

- [ ] STDLIB-144: `String.trimStart()` / `String.trimEnd()` / `String.trimStart { predicate }` を実装する
  - [ ] Sema に `trimStart(): String` / `trimEnd(): String` と predicate 版 stub を登録する
  - [ ] Runtime に `kk_string_trimStart` / `kk_string_trimEnd` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"  hello  ".trimStart()` → `"hello  "` が `kotlinc` と一致する

- [ ] STDLIB-145: `String.toByteArray()` / `String.encodeToByteArray()` を実装する
  - [ ] Sema に `String.toByteArray(): ByteArray` / `String.encodeToByteArray(): ByteArray` stub を登録する
  - [ ] Runtime に `kk_string_toByteArray` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abc".toByteArray().size` → `3` が `kotlinc` と一致する

---

### 📦 Stdlib — 数値拡張・追加

- [ ] STDLIB-150: `Int.coerceIn(min, max)` / `Int.coerceAtLeast(min)` / `Int.coerceAtMost(max)` を実装する
  - [ ] Sema に `Comparable<T>.coerceIn` / `coerceAtLeast` / `coerceAtMost` extension stub を登録する
  - [ ] Runtime / Lowering で比較・クランプ命令に展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `15.coerceIn(1, 10)` → `10` が `kotlinc` と一致する

- [ ] STDLIB-151: `Long.toInt()` / `Double.toInt()` / `Float.toInt()` / `Double.toLong()` 等の逆方向変換を実装する
  - [ ] Sema に各型の逆変換 stub を登録する
  - [ ] Runtime / Lowering で truncation / rounding 命令に展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `3.14.toInt()` → `3` が `kotlinc` と一致する

- [ ] STDLIB-152: `Int.toString(radix)` / `String.toInt(radix)` を実装する
  - [ ] Sema に `Int.toString(Int): String` / `String.toInt(Int): Int` stub を登録する
  - [ ] Runtime に `kk_int_toString_radix` / `kk_string_toInt_radix` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `255.toString(16)` → `"ff"` が `kotlinc` と一致する

- [ ] STDLIB-153: 数値定数 `Int.MAX_VALUE` / `Int.MIN_VALUE` / `Long.MAX_VALUE` / `Double.NaN` 等を実装する
  - [ ] Sema に各プリミティブ型の companion object 定数 stub を登録する
  - [ ] Lowering で定数値に直接展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `println(Int.MAX_VALUE)` → `2147483647` が `kotlinc` と一致する

---

### 📦 Stdlib — takeIf / takeUnless

- [ ] STDLIB-160: `T.takeIf { predicate }` / `T.takeUnless { predicate }` を実装する
  - [ ] Sema に `T.takeIf((T) -> Boolean): T?` / `T.takeUnless((T) -> Boolean): T?` generic extension stub を登録する
  - [ ] Lowering で inline 展開し、predicate が `false` / `true` の場合に `null` を返す
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `10.takeIf { it > 5 }` → `10`, `10.takeIf { it > 20 }` → `null` が `kotlinc` と一致する

---

### 📦 Stdlib — Random

- [ ] STDLIB-165: `kotlin.random.Random.nextInt()` / `Random.nextInt(range)` / `Random.nextDouble()` を実装する
  - [ ] Sema に `kotlin.random.Random` object と `nextInt()` / `nextInt(Int)` / `nextInt(Int, Int)` / `nextDouble()` / `nextBoolean()` stub を登録する
  - [ ] Runtime に `kk_random_nextInt` / `kk_random_nextDouble` / `kk_random_nextBoolean` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Random.nextInt(1, 10)` が 1〜9 の範囲の値を返す

- [ ] STDLIB-166: `List.shuffled()` / `List.random()` / `List.randomOrNull()` を実装する
  - [ ] Sema に `List<T>.shuffled(): List<T>` / `List<T>.random(): T` / `List<T>.randomOrNull(): T?` stub を登録する
  - [ ] Runtime に `kk_list_shuffled` / `kk_list_random` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3).shuffled().size` → `3` が `kotlinc` と一致する

---

### 📦 Stdlib — Enum ユーティリティ

- [ ] STDLIB-170: `Enum.name` / `Enum.ordinal` プロパティを実装する
  - [ ] Sema に `Enum<T>.name: String` / `Enum<T>.ordinal: Int` プロパティ stub を登録する
  - [ ] Runtime / Lowering で enum entry からname/ordinal を取得する仕組みを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `enum class Color { RED, GREEN }; Color.RED.name` → `"RED"` が `kotlinc` と一致する

- [ ] STDLIB-171: `enumValues<T>()` / `enumValueOf<T>(name)` を実装する
  - [ ] Sema に reified type parameter 付き `enumValues<T>(): Array<T>` / `enumValueOf<T>(String): T` stub を登録する
  - [ ] Runtime で enum entry の配列生成と名前逆引きを実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `enumValues<Color>().map { it.name }` → `[RED, GREEN]` が `kotlinc` と一致する

- [ ] STDLIB-172: `Enum.entries` プロパティ（Kotlin 1.9+）を実装する
  - [ ] Sema に `Enum<T>` companion の `entries: EnumEntries<T>` プロパティ stub を登録する
  - [ ] Lowering で companion property アクセスとして展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Color.entries.map { it.name }` → `[RED, GREEN]` が `kotlinc` と一致する

- [ ] STDLIB-173: `Enum.valueOf(name)` 静的メソッドを実装する
  - [ ] Sema に各 enum class の companion `valueOf(String): T` stub を自動登録する
  - [ ] Runtime で名前からの enum entry 逆引きを実装し、見つからない場合 `IllegalArgumentException` を throw する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `Color.valueOf("RED")` → `Color.RED` が `kotlinc` と一致する

---

### 📦 Stdlib — Comparator / compareBy

- [ ] STDLIB-175: `Comparator<T>` インターフェースと `compareBy {}` / `compareByDescending {}` を実装する
  - [ ] Sema に `Comparator<T>` 関数型インターフェースと `compareBy` / `compareByDescending` トップレベル関数を登録する
  - [ ] Runtime で Comparator ベースのソート呼び出しをサポートする
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf("bb","a","ccc").sortedWith(compareBy { it.length })` → `[a, bb, ccc]` が `kotlinc` と一致する

- [ ] STDLIB-176: `Comparator.thenBy {}` / `Comparator.thenByDescending {}` / `Comparator.reversed()` を実装する
  - [ ] Sema に `Comparator<T>.thenBy` / `thenByDescending` / `reversed` member stub を登録する
  - [ ] Runtime で chained comparator を実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `compareBy<String> { it.length }.thenBy { it }` で長さ→辞書順のソートが動作する

- [ ] STDLIB-177: `naturalOrder<T>()` / `reverseOrder<T>()` トップレベル関数を実装する
  - [ ] Sema に `naturalOrder<T: Comparable<T>>(): Comparator<T>` / `reverseOrder<T>()` stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(3,1,2).sortedWith(reverseOrder())` → `[3, 2, 1]` が `kotlinc` と一致する

---

### 📦 Stdlib — Destructuring（componentN）

- [ ] STDLIB-180: `Pair.component1()` / `Pair.component2()` destructuring を実装する
  - [ ] Sema に `Pair<A,B>.component1(): A` / `component2(): B` operator stub を登録する
  - [ ] Lowering で destructuring declaration を componentN 呼び出しに展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val (a, b) = Pair(1, "x"); println("$a $b")` → `1 x` が `kotlinc` と一致する

- [ ] STDLIB-181: `Triple.component1()` / `component2()` / `component3()` destructuring を実装する
  - [ ] Sema に `Triple<A,B,C>` の componentN operator stub を登録する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val (a, b, c) = Triple(1, "x", true)` が動作し `kotlinc` と一致する

- [ ] STDLIB-182: `Map.Entry.component1()` / `component2()` destructuring を実装する
  - [ ] Sema に `Map.Entry<K,V>.component1(): K` / `component2(): V` を登録する
  - [ ] `for ((key, value) in map)` パターンで destructuring が動作するようにする
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `for ((k, v) in mapOf("a" to 1)) { println("$k=$v") }` → `a=1` が `kotlinc` と一致する

- [ ] STDLIB-183: `List` の `component1()` 〜 `component5()` destructuring を実装する
  - [ ] Sema に `List<T>.component1()` 〜 `component5()` operator stub を登録する
  - [ ] Runtime でインデックスアクセスに展開する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val (a, b, c) = listOf(1, 2, 3)` が動作し `kotlinc` と一致する

---

### 📦 Stdlib — String 高度操作

- [ ] STDLIB-185: `String.removePrefix(prefix)` / `String.removeSuffix(suffix)` / `String.removeSurrounding(delimiter)` を実装する
  - [ ] Sema に `removePrefix(String): String` / `removeSuffix(String): String` / `removeSurrounding(String): String` stub を登録する
  - [ ] Runtime に `kk_string_removePrefix` / `kk_string_removeSuffix` / `kk_string_removeSurrounding` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"[hello]".removeSurrounding("[", "]")` → `"hello"` が `kotlinc` と一致する

- [ ] STDLIB-186: `String.substringBefore(delimiter)` / `String.substringAfter(delimiter)` / `substringBeforeLast` / `substringAfterLast` を実装する
  - [ ] Sema に各 stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"hello.world.kt".substringAfterLast(".")` → `"kt"` が `kotlinc` と一致する

- [ ] STDLIB-187: `String.isEmpty()` / `String.isNotEmpty()` / `String.isBlank()` / `String.isNotBlank()` を実装する
  - [ ] Sema に各 member stub を登録する
  - [ ] Runtime に `kk_string_isEmpty` / `kk_string_isBlank` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"".isEmpty()` → `true`, `"  ".isBlank()` → `true` が `kotlinc` と一致する

- [ ] STDLIB-188: `String.replaceFirst(oldValue, newValue)` / `String.replaceRange(range, replacement)` を実装する
  - [ ] Sema に `replaceFirst(String, String): String` / `replaceRange(IntRange, String): String` stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abcabc".replaceFirst("abc", "X")` → `"Xabc"` が `kotlinc` と一致する

- [ ] STDLIB-189: `String.filter {}` / `String.map {}` / `String.count {}` / `String.any {}` / `String.all {}` / `String.none {}` を実装する
  - [ ] Sema に `CharSequence` の HOF stub を登録し、`String` を `Iterable<Char>` として扱えるようにする
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"hello123".filter { it.isLetter() }` → `"hello"` が `kotlinc` と一致する

- [ ] STDLIB-190: `String.first()` / `String.last()` / `String.single()` / `String.firstOrNull()` を実装する
  - [ ] Sema に各 stub を登録する
  - [ ] Runtime に対応ヘルパーを追加し、空文字列で `NoSuchElementException` を throw する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"hello".first()` → `'h'`, `"".firstOrNull()` → `null` が `kotlinc` と一致する

- [ ] STDLIB-191: `String.prependIndent(indent)` / `String.replaceIndent(newIndent)` を実装する
  - [ ] Sema に `prependIndent(String): String` stub を登録する
  - [ ] Runtime に `kk_string_prependIndent` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abc\ndef".prependIndent("  ")` → `"  abc\n  def"` が `kotlinc` と一致する

- [ ] STDLIB-192: `String.equals(other, ignoreCase)` を実装する
  - [ ] Sema に `String.equals(String, Boolean): Boolean` stub を登録する（`ignoreCase` デフォルト引数付き）
  - [ ] Runtime に `kk_string_equalsIgnoreCase` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `"abc".equals("ABC", ignoreCase = true)` → `true` が `kotlinc` と一致する

---

### 📦 Stdlib — Map 高度操作

- [ ] STDLIB-195: `Map.getOrDefault(key, defaultValue)` / `Map.getOrElse(key) { defaultValue }` を実装する
  - [ ] Sema に `Map<K,V>.getOrDefault(K, V): V` / `Map<K,V>.getOrElse(K, () -> V): V` stub を登録する
  - [ ] Runtime に `kk_map_getOrDefault` / `kk_map_getOrElse` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1).getOrDefault("b", 0)` → `0` が `kotlinc` と一致する

- [ ] STDLIB-196: `MutableMap.getOrPut(key) { defaultValue }` を実装する
  - [ ] Sema に `MutableMap<K,V>.getOrPut(K, () -> V): V` stub を登録する
  - [ ] Runtime でキーが存在しない場合に default を挿入する処理を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `mutableMapOf("a" to 1).getOrPut("b") { 2 }` → `2` が `kotlinc` と一致する

- [ ] STDLIB-197: `Map.plus(pair)` / `Map.minus(key)` operator を実装する
  - [ ] Sema に `Map<K,V>.plus(Pair<K,V>): Map<K,V>` / `Map<K,V>.minus(K): Map<K,V>` operator stub を登録する
  - [ ] Runtime に新しい Map を生成する `kk_map_plus` / `kk_map_minus` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1) + ("b" to 2)` → `{a=1, b=2}` が `kotlinc` と一致する

- [ ] STDLIB-198: `Map.count {}` / `Map.any {}` / `Map.all {}` / `Map.none {}` を実装する
  - [ ] Sema に `Map<K,V>` の述語 HOF stub を登録する
  - [ ] Runtime に `kk_map_count` / `kk_map_any` / `kk_map_all` / `kk_map_none` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1, "b" to 2).count { it.value > 1 }` → `1` が `kotlinc` と一致する

- [ ] STDLIB-199: `Map.flatMap {}` / `Map.maxByOrNull {}` / `Map.minByOrNull {}` を実装する
  - [ ] Sema に `Map<K,V>` の `flatMap` / `maxByOrNull` / `minByOrNull` stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1, "b" to 2).maxByOrNull { it.value }?.key` → `"b"` が `kotlinc` と一致する

- [ ] STDLIB-200: `List<Pair<K,V>>.toMap()` / `Iterable<Pair<K,V>>.toMap()` を実装する
  - [ ] Sema に `Iterable<Pair<K,V>>.toMap(): Map<K,V>` stub を登録する
  - [ ] Runtime に `kk_list_toMap` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf("a" to 1, "b" to 2).toMap()` → `{a=1, b=2}` が `kotlinc` と一致する

---

### 📦 Stdlib — MutableList 高度操作

- [ ] STDLIB-205: `MutableList.sort()` / `MutableList.sortBy {}` / `MutableList.sortByDescending {}` を実装する
  - [ ] Sema に `MutableList<T>.sort()` / `sortBy` / `sortByDescending` stub を登録する（in-place sort）
  - [ ] Runtime に `kk_mutable_list_sort` / `kk_mutable_list_sortBy` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val l = mutableListOf(3,1,2); l.sort(); println(l)` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-206: `MutableList.shuffle()` / `MutableList.reverse()` を実装する
  - [ ] Sema に `MutableList<T>.shuffle()` / `reverse()` stub を登録する（in-place 操作）
  - [ ] Runtime に `kk_mutable_list_shuffle` / `kk_mutable_list_reverse` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val l = mutableListOf(1,2,3); l.reverse(); println(l)` → `[3, 2, 1]` が `kotlinc` と一致する

- [ ] STDLIB-207: `MutableList.addAll(collection)` / `MutableList.removeAll(collection)` / `MutableList.retainAll(collection)` を実装する
  - [ ] Sema に `addAll(Collection<E>): Boolean` / `removeAll(Collection<E>): Boolean` / `retainAll(Collection<E>): Boolean` stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val l = mutableListOf(1,2); l.addAll(listOf(3,4)); println(l)` → `[1, 2, 3, 4]` が `kotlinc` と一致する

- [ ] STDLIB-208: `MutableList.add(index, element)` / `MutableList.set(index, element)` / `MutableList[index] = value` を実装する
  - [ ] Sema に `add(Int, E)` / `set(Int, E): E` / `operator set(Int, E)` stub を登録する
  - [ ] Runtime に `kk_mutable_list_add_at` / `kk_mutable_list_set` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val l = mutableListOf(1,3); l.add(1, 2); println(l)` → `[1, 2, 3]` が `kotlinc` と一致する

---

### 📦 Stdlib — Collection ユーティリティ

- [ ] STDLIB-210: `List.firstOrNull()` / `List.lastOrNull()` 引数なし版を実装する
  - [ ] Sema に `List<T>.firstOrNull(): T?` / `List<T>.lastOrNull(): T?` stub を登録する（predicate なし）
  - [ ] Runtime に `kk_list_firstOrNull` / `kk_list_lastOrNull` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `emptyList<Int>().firstOrNull()` → `null` が `kotlinc` と一致する

- [ ] STDLIB-211: `List.single()` / `List.singleOrNull()` を実装する
  - [ ] Sema に `single(): T` / `singleOrNull(): T?` stub を登録する
  - [ ] Runtime で要素数が 1 でない場合に `IllegalArgumentException` を throw する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `listOf(42).single()` → `42` が `kotlinc` と一致する

- [ ] STDLIB-212: `List.getOrNull(index)` / `List.getOrElse(index) { default }` / `List.elementAtOrNull(index)` を実装する
  - [ ] Sema に `getOrNull(Int): T?` / `getOrElse(Int, (Int) -> T): T` / `elementAtOrNull(Int): T?` stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
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

- [ ] STDLIB-235: `@Deprecated(message)` annotation を実装する
  - [ ] Sema に `@Deprecated` annotation class を登録し、使用箇所で warning 診断を出す
  - [ ] metadata に annotation を保持し、library import 時にも warning を伝搬する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `@Deprecated("use newFun")` 付き関数の呼び出しで warning が出る

- [ ] STDLIB-236: `@JvmStatic` / `@JvmOverloads` / `@JvmField` annotation を実装する
  - [ ] Sema に各 annotation class を登録し、companion object member / default parameter / field に対する lowering を調整する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `@JvmStatic fun create()` が static メソッドとして codegen される

- [ ] STDLIB-237: `@Throws(ExceptionClass::class)` annotation を実装する
  - [ ] Sema に `@Throws` annotation class を登録し、metadata に伝搬する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `@Throws(IOException::class)` が metadata に反映される

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

- [ ] STDLIB-260: `MutableMap.put(key, value)` / `MutableMap.remove(key)` / `MutableMap.clear()` を実装する
  - [ ] Sema に `MutableMap<K,V>.put(K, V): V?` / `remove(K): V?` / `clear()` stub を登録する
  - [ ] Runtime に `kk_mutable_map_put` / `kk_mutable_map_remove` / `kk_mutable_map_clear` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val m = mutableMapOf("a" to 1); m.put("b", 2); m.remove("a"); println(m)` → `{b=2}` が `kotlinc` と一致する

- [ ] STDLIB-261: `MutableMap[key] = value` operator set / `MutableMap.putAll(map)` を実装する
  - [ ] Sema に `MutableMap<K,V>.set(K, V)` operator と `putAll(Map<K,V>)` stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val m = mutableMapOf<String, Int>(); m["a"] = 1; println(m)` → `{a=1}` が `kotlinc` と一致する

- [ ] STDLIB-262: `Map.getValue(key)` を実装する
  - [ ] Sema に `Map<K,V>.getValue(K): V` stub を登録する（キー不在時 `NoSuchElementException` throw）
  - [ ] Runtime に `kk_map_getValue` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `mapOf("a" to 1).getValue("a")` → `1`, `getValue("b")` が例外を投げ `kotlinc` と一致する

---

### 📦 Stdlib — MutableSet / Set 操作

- [ ] STDLIB-265: `MutableSet.add(element)` / `MutableSet.remove(element)` / `MutableSet.clear()` / `MutableSet.addAll(collection)` を実装する
  - [ ] Sema に `MutableSet<E>` の member stub を登録する
  - [ ] Runtime に `kk_mutable_set_add` / `kk_mutable_set_remove` / `kk_mutable_set_clear` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val s = mutableSetOf(1, 2); s.add(3); s.remove(1); println(s)` → `[2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-266: `Set.intersect(other)` / `Set.union(other)` / `Set.subtract(other)` を実装する
  - [ ] Sema に `Set<T>.intersect(Iterable<T>): Set<T>` / `union` / `subtract` stub を登録する
  - [ ] Runtime に `kk_set_intersect` / `kk_set_union` / `kk_set_subtract` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `setOf(1,2,3).intersect(setOf(2,3,4))` → `[2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-267: `Set.contains(element)` / `Set.containsAll(elements)` / `Set.isEmpty()` / `Set.size` を実装する
  - [ ] Sema に `Set<E>` の基本プロパティ / メソッド stub を登録する
  - [ ] Runtime に対応ヘルパーを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `setOf(1, 2, 3).contains(2)` → `true` が `kotlinc` と一致する

- [ ] STDLIB-268: `Set.map {}` / `Set.filter {}` / `Set.forEach {}` / `Set.toList()` を実装する
  - [ ] Sema に `Set<T>` の HOF stub を登録する
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `setOf(1, 2, 3).map { it * 2 }` → `[2, 4, 6]` が `kotlinc` と一致する

---

### 📦 Stdlib — Sequence 高度操作

- [ ] STDLIB-270: `Sequence.takeWhile {}` / `Sequence.dropWhile {}` を実装する
  - [ ] Sema に `Sequence<T>.takeWhile((T) -> Boolean): Sequence<T>` / `dropWhile` stub を登録する
  - [ ] Runtime に lazy ステップとして `kk_sequence_takeWhile` / `kk_sequence_dropWhile` を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1,2,3,4,5).takeWhile { it < 4 }.toList()` → `[1, 2, 3]` が `kotlinc` と一致する

- [ ] STDLIB-271: `Sequence.mapNotNull {}` / `Sequence.filterNotNull()` / `Sequence.mapIndexed {}` / `Sequence.withIndex()` を実装する
  - [ ] Sema に各 stub を登録する
  - [ ] Runtime に対応する lazy ステップを追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `sequenceOf(1, null, 3).filterNotNull().toList()` → `[1, 3]` が `kotlinc` と一致する

- [ ] STDLIB-272: `Sequence.sorted()` / `Sequence.sortedBy {}` / `Sequence.sortedDescending()` を実装する
  - [ ] Sema に各 stub を登録する（terminal 化して list 経由でソート）
  - [ ] Runtime に対応ランタイム関数を追加する
  - [ ] diff/golden ケースを追加する
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

- [ ] STDLIB-315: `String.replaceFirstChar {}` を実装する
  - [ ] Sema に `String.replaceFirstChar((Char) -> Char): String` stub を登録する
  - [ ] Runtime に `kk_string_replaceFirstChar` を追加する
  - [ ] diff/golden ケースを追加する
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
| `Scripts/diff_cases/` | diff テスト（`kotlinc` との出力比較） |
