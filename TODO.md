# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-06

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

## 未完了バックログ（10件 + 完了17件）

### 📐 Type System

- [x] TYPE-005: 符号なし整数型（`UInt`/`ULong`/`UByte`/`UShort`）の演算・型変換・stdlib を完全実装する（spec.md J8）
  - [x] `UInt`/`ULong`/`UByte`/`UShort` を distinct な primitive 型として TypeSystem に登録し、signed 型との暗黙変換を禁止する
  - [x] 四則演算・比較・ビット演算を符号なし意味論で LLVM IR へ lowering する（`udiv`/`urem`/`icmp ult` 等）
  - [x] `toUInt()`/`toInt()` などの変換関数を stdlib stub として実装する ✓
  - [x] 符号なし型リテラル（`42u`/`42uL`）を Lexer/Parser で認識し型推論する
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-005`
  - **完了条件**: `val x: UInt = 4294967295u` が overflow せず正しく演算され、`toInt()` で符号変換が動作する

---

### 🧱 Declarations

- [ ] DECL-004: `lateinit var` と `::prop.isInitialized` を front-to-back で実装する（registry: `P5-110`, spec.md J7/J9）
  - [ ] `lateinit` 修飾子を property symbol / metadata に保持し、`val`・nullable 型・primitive 型・initializer 付き宣言を禁止して `KSWIFTK-SEMA-LATEINIT` 系診断を出す
  - [ ] backing storage に未初期化状態を保持し、未初期化読み取り時は `UninitializedPropertyAccessException` を投げ、代入後は通常 getter / setter として動作させる
  - [ ] bound property reference `::name.isInitialized` を owner scope 内で解決し、member / top-level property の初期化状態を参照できるようにする
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-110`
  - **完了条件**: `lateinit var name: String` が未初期化読み取りで例外を投げ、`::name.isInitialized` が代入前 `false` / 代入後 `true` を返す

---

### 🏗️ Class / Object

- [x] CLASS-006: `data object` の型と等値比較を実装する（spec.md J6）
  - [x] `data object Singleton` を singleton かつ equals/toString 合成ありとして扱う（hashCode は未実装）
  - [x] anonymous object の型を local nominal として推論し、呼び出しスコープ内で有効にする
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-006`
  - **完了条件**: `data object None` が `None == None` → `true`、`None.toString()` → `"None"` を返し、`val x = object { val value = 7 }; x.value` が解決される ✓


- [x] CLASS-008: クラス委譲（`class A : Interface by delegateInstance`）を front-to-back で実装する（spec.md J7/J12）
  - [x] class ヘッダの `: Interface by expr` 構文を Parser/AST で保持する（property delegation の `by` とは別パス）
  - [x] Sema で delegate 式の型が対象 interface を実装していることを検証する
  - [x] KIR lowering で interface の全メソッドを `delegateInstance.method(...)` へ転送するボイラープレートを合成する
  - [x] クラス自身が一部メソッドを override する場合は override 側を優先する dispatch を生成する
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-008`
  - **完了条件**: `class Logger(impl: Printer) : Printer by impl` が `impl` のメソッドを委譲し、override したメソッドだけ自前実装を呼ぶ（※itable 未実装のため diff は SKIP-DIFF、CLASS-008-FOLLOW 参照）

- [x] CLASS-008-FOLLOW: クラス委譲の既知の制限を解消する
  - [x] NativeEmitter（LLVM C API バックエンド）で `virtualCall` の itable ディスパッチを実装する（`kk_itable_lookup` を呼び、戻り値を関数ポインタとして indirect call する）
  - [x] 委譲フィールドを KIRGlobal ではなくインスタンスフィールド（receiver + fieldOffset）として保持する
  - **完了条件**: LLVM backend で `logger.print()` が正しく動作し、複数インスタンスで委譲が独立して動作する ✓

---

### 🧩 Functions

- [x] FUNC-001: tail-recursive 関数（`tailrec fun`）の末尾呼び出し最適化を実装する（spec.md J9）
  - [x] `tailrec` 修飾子を Sema で認識し、最後の式が self-recursive call であることを検証する
  - [x] tail call が満たされない場合に `KSWIFTK-SEMA-TAILREC` warning を出す
  - [x] KIR/Lowering で `tailrec fun` をループ（label jump）へ変換し、スタック消費を抑制する
  - [x] 深い再帰が tailrec により StackOverflow を起こさないことを E2E テストで確認する
  - **完了条件**: `tailrec fun fact(n: Int, acc: Int = 1): Int` が 100000 段の再帰で StackOverflow しない ✓


- [x] P5-2 FUNC-002: Infix function declarations (`infix fun`)
  - [x] Handle `infix` modifier in parser/AST
  - [x] Add resolution logic in Sema.
  - [x] Build cases and implement `to` in `RuntimeCollections.swift` that returns `Any` (underneath it produces a Pair struct)diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task FUNC-002`
  - **完了条件**: `1 to "one"` が `Pair(1, "one")` に、カスタム infix 関数が正しい優先順位で評価される（優先順位設定は既存実装済み）


- [ ] FUNC-004: class / data class receiver 上の `operator fun` を front-to-back で揃える（registry: `P5-120`, spec.md J7/J9）
  - [ ] member operator body から primary constructor property / member property を正しく解決し、`x` / `other.x` 参照が class / data class 内で通るようにする
  - [ ] `plus` / `minus` / `times` / `unaryMinus` / `get` の member operator declaration を overload 解決に載せ、operator desugaring と通常メソッド呼び出しを同じ symbol に束縛する
  - [ ] top-level / extension operator は `既存実装済み` とし、member operator の KIR / lowering / codegen parity を揃える
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-120`
  - **完了条件**: `data class Vec(val x: Int, val y: Int)` 上の `a + b` / `-a` / `vec[0]` が `kotlinc` と同一出力になる

---

### 🧬 Generics

- [x] GEN-001: 複数 upper bound（`where T : A, T : B`）と F-bound（`T : Comparable<T>`）を完全実装する（spec.md J8）
  - [x] `where` 句の複数 upper bound を `TypeParamDecl` に保持し、overload 解決で全境界を検証する
  - [x] `T : Comparable<T>` のような自己参照 upper bound（F-bound）を循環検出せずに解決する
  - [x] 複数 upper bound に違反する型引数に `KSWIFTK-SEMA-BOUND` 診断を出す
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task GEN-001`
  - **完了条件**: `fun <T> max(a: T, b: T): T where T : Comparable<T>` が `max(1, 2)` / `max("a", "b")` で動作する ✓


- [ ] GEN-004: `fun interface` の SAM conversion を end-to-end で実装する（registry: `GEN-004`, spec.md J9/J12）
  - [ ] `fun interface` を single abstract method を持つ nominal type として検証し、SAM 条件違反に `KSWIFTK-SEMA-SAM` 系診断を出す
  - [ ] lambda / callable reference を期待型の SAM signature に合わせて型推論し、Sema binding と hidden bridge 情報を KIR へ渡す
  - [ ] lowering / codegen で SAM wrapper 生成と call-site rewrite を実装し、引数位置 lambda が interface instance として渡るようにする
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task GEN-004`
  - **完了条件**: `fun interface Action { fun run(): String }` に対して `execute { "hello" }` が `"hello"` を出力し `kotlinc` と一致する

---

### 🛡️ Null Safety

- [x] NULL-001: platform type（nullability 不明型 `T!`）の扱いを実装する（spec.md J8）
  - [x] externally-declared symbol（`.kklib` import）で nullability 情報がない型を platform type として表現する
  - [x] platform type は nullable にも non-null にも代入でき、利用時に nullability 警告を出す
  - [x] platform type を明示した nullable/non-null へ代入する文脈で型チェックを緩和する
  - [x] golden / integration ケースを追加する → `platform_type.kt` / `LibraryMetadataImportIntegrationTests`
  - **完了条件**: 外部 API から返された型が `T!` として扱われ、null チェックなし使用に `KSWIFTK-SEMA-PLATFORM` warning が出る ✓


- [x] NULL-002: nullable receiver（`T?.foo()`）拡張関数を Sema で解決する（spec.md J7/J9）
  - [x] `fun String?.isNullOrEmpty()` / `isNullOrBlank()` を stdlib ハードコードとして Sema で登録・解決する（`CallTypeChecker+MemberCallResolution.swift`）
  - [x] nullable receiver 拡張は `?.` なしに直接呼べることを Sema で許可する（isNullOrEmpty/isNullOrBlank 限定）
  - [x] 汎用 nullable receiver 拡張（ユーザー定義 `fun T?.foo()`）の登録・解決規則を Sema で実装する
  - [x] diff/golden ケースを追加する → `nullable_receiver_ext.kt` / `null_receiver_is_null_or_empty.kt`
  - **完了条件**: `null.isNullOrEmpty()` が `NullPointerException` を出さず `true` を返し、ユーザー定義 `fun T?.foo()` も `?.` なしで解決される ✓

---

### ⚡ Coroutines

- [ ] CORO-002: coroutine cancellation の end-to-end parity を復旧する（spec.md J17）
  - [ ] `job.cancel()` / `job.join()` / `CancellationException` の surface API 解決を通し、runtime ABI は `既存実装済み` として `kk_job_cancel` / `kk_job_join` / cancellation helpers へ lowering する
  - [ ] `repeat(times)` 依存は `STDLIB-008` で補完し、`Scripts/diff_cases/coroutine_cancellation.kt` を diff ハーネスで常時実行できる状態に戻す
  - [ ] `--kotlinc-classpath` に `kotlinx-coroutines-core` を渡す parity ワークフローを前提条件として明記する
  - **完了条件**: `job.cancel(); job.join()` が `CancellationException` を catch して `cancelled\ndone` を `kotlinc` と一致して出力する

- [x] CORO-003: `Flow<T>` コールドストリームを実装する（spec.md J17）
  - [x] runtime に `kk_flow_create` / `kk_flow_collect` / `kk_flow_emit` の C ABI 関数を追加する
  - [x] `flow { emit(x) }` builder の lowering を実装し、collector lambda に suspension point を挿入する
  - [x] `Flow.map`・`Flow.filter`・`Flow.take`・`Flow.collect` 中間オペレーターを stub として実装する
  - [x] `Flow` はコールド（collect のたびに再実行）であることを runtime で保証する
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CORO-003`
  - **完了条件**: `flow { emit(1); emit(2) }.map { it * 2 }.collect { println(it) }` が `2\n4` を出力し `kotlinc` と一致する ✓


- [ ] CORO-004: `withContext` / `Dispatchers` の解決・lowering を追加する（registry: `P5-133`, spec.md J17）
  - [ ] `Dispatchers.Default` / `Dispatchers.IO` stub と `withContext` signature を Sema に登録し、import 解決から参照できるようにする
  - [ ] `withContext(dispatcher) { ... }` を coroutine lowering で runtime `kk_with_context` へ rewrite する
  - [ ] `kotlinx-coroutines-core` classpath 前提の diff ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-133`
  - **完了条件**: `withContext(Dispatchers.Default) { "hello" }` が `"hello"` を返し `kotlinc` と同一出力になる


- [ ] CORO-005: `Channel<T>` / `send` / `receive` / `close` を実装する（registry: `P5-134`, spec.md J17）
  - [ ] `Channel<T>` nominal type と `kotlinx.coroutines.channels.*` import 解決を Sema に追加する
  - [ ] `Channel()` / `send` / `receive` / `close` を runtime `kk_channel_create` / `kk_channel_send` / `kk_channel_receive` / `kk_channel_close` ABI へ lowering する
  - [ ] `kotlinx-coroutines-core` classpath 前提の diff ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-134`
  - **完了条件**: `Channel<Int>()`, `send(42)`, `receive()` が `42` を出力し `kotlinc` と同一出力になる


- [ ] CORO-006: Kotlin 形式の `async { ... }` / `await()` parity を実装する（registry: `P5-135`, spec.md J17）
  - [ ] suspend function reference 専用の launcher lowering を、suspend lambda / inline block 受け取りにも対応させる
  - [ ] `Deferred<T>` 相当の型と `.await()` member 解決を Sema / KIR で揃える
  - [ ] `kotlinx-coroutines-core` classpath 前提の diff ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-135`
  - **完了条件**: `val deferred = async { 1 + 2 }; println(deferred.await())` が `3` を出力し `kotlinc` と同一出力になる

---

### 📦 Stdlib / DSL

- [x] STDLIB-002: `buildString`/`buildList`/`buildMap` DSL builder を実装する（spec.md J9/J12）
  - [x] `buildString { append("a"); append("b") }` を `StringBuilder` ベースの DSL として実装する
  - [x] `buildList { add(1); add(2) }` を mutable list builder として実装する
  - [x] builder lambda の receiver (`StringBuilder`/`MutableList`) を Sema で `this` として束縛する
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task STDLIB-002`
  - **完了条件**: `buildString { append("hello "); append("world") }` が `"hello world"` を返す


- [x] STDLIB-004: スコープ関数（`let`/`run`/`with`/`apply`/`also`）を stdlib stub として実装する（spec.md J9）
  - [x] `let`/`run`/`also` を `T` の extension inline 関数として、`with` をトップレベル inline 関数として stub 実装する
  - [x] `apply` の receiver return と `also` の self return を型システムで正しく推論する
  - [x] 各スコープ関数の lambda 引数の receiver / `it` を Sema でスコープ束縛する
  - [x] diff/golden ケースを追加する → `Scripts/diff_cases/scope_functions.kt` / `GoldenCases/Sema/scope_functions.kt`
  - **完了条件**: `val result = "hello".let { it.uppercase() }` / `mutableListOf<Int>().apply { add(1) }` が `kotlinc` と同一出力になる ✓


- [x] STDLIB-005: コレクション高階関数（`map`/`filter`/`flatMap`/`fold`/`reduce`/`forEach`/`any`/`all`/`none`/`groupBy`/`sortedBy`）を実装する（spec.md J15）
  - [x] runtime/stdlib stub に `kk_list_map` / `kk_list_filter` / `kk_list_fold` 等の C ABI 関数を追加する（`RuntimeCollectionHOF.swift`）
  - [x] lambda を function pointer + closure として C ABI 経由で HOF に渡す lowering を実装する
  - [x] `flatMap`・`groupBy`・`sortedBy` の安定ソートを実装する
  - [x] `any`/`all`/`none`/`count`/`first`/`last`/`find` の短絡評価を runtime で保証する
  - [x] diff/golden ケースを追加する → `Scripts/diff_cases/collection_hof.kt`
  - **完了条件**: `listOf(1,2,3).filter { it > 1 }.map { it * 2 }` が `[4, 6]` を返し `kotlinc` と一致する ✓


- [x] STDLIB-006: String stdlib 関数（`trim`/`split`/`replace`/`startsWith`/`endsWith`/`toInt`/`toDouble`/`format`）を実装する（spec.md J15）
  - [x] runtime/stdlib stub に `kk_string_trim` / `kk_string_split` / `kk_string_replace` 等を追加する（`RuntimeStringArray.swift`）
  - [x] `String.toInt()` / `String.toDouble()` の失敗時に `NumberFormatException` を投げる動作を実装する
  - [x] `String.format(vararg args)` を printf 相当の C ABI 関数へ lowering する
  - [x] `startsWith`/`endsWith`/`contains`（文字列検索版）を stdlib stub として実装する
  - [x] diff/golden ケースを追加する → `Scripts/diff_cases/stdlib_string_ops.kt` / `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_string_ops.kt`
  - **完了条件**: `"  hello  ".trim()` / `"42".toInt()` / `"%s:%d".format("age", 7)` が `kotlinc` と同一出力になる ✓
  - `split()` は runtime / sema 経路では確認済みだが、diff 経路では `List.toString()` 未実装のため `println(list)` の JVM 出力 `[a, b, c]` までまだ比較できない


- [ ] STDLIB-007: multiline string helper `trimIndent()` / `trimMargin()` を実装する（spec.md J15）
  - [ ] raw string literal 本体は `既存実装済み` とし、`String.trimIndent()` / `trimMargin()` の synthetic stdlib signature と runtime helper を追加する
  - [ ] 改行・共通インデント除去・custom margin prefix の挙動を `kotlinc` に合わせる
  - [ ] diff/golden ケースを追加する → `Scripts/test_templates/diff/raw_string_basic.kt` を正式 diff ケースへ昇格し、`trimMargin()` 用ケースを追加する
  - **完了条件**: triple-quoted string に `trimIndent()` / `trimMargin()` を適用した出力が `kotlinc` と一致する


- [ ] STDLIB-008: `repeat(times) {}` を stdlib stub として実装する（spec.md J15）
  - [ ] `repeat(Int, action)` signature を Sema に登録し、lambda 引数 `it` を loop index として型推論できるようにする
  - [ ] lowering / codegen で counted loop へ展開し、単純な inline loop として実行できるようにする
  - [ ] standalone golden と `Scripts/diff_cases/coroutine_cancellation.kt` の unblock 用 diff ケースを追加する
  - **完了条件**: `repeat(3) { print(it) }` が `012` を出力し、coroutine parity ケースの前提を満たす

---

### 🏷️ Annotations

- [x] ANNO-001: `@Suppress` / `@Deprecated` / `@JvmStatic` など built-in アノテーションの特別処理を追加する（spec.md J6）
  - [x] `@Suppress("UNCHECKED_CAST")` で指定した診断コードを当該 node で抑制する compiler ルールを追加する（`Diagnostics.swift`）
  - [x] `@Deprecated(..., level = ERROR/WARNING)` で呼び出し元に診断を発生させる（`TypeCheck/Helpers+Deprecation.swift`）
  - [x] `@JvmStatic` on companion member → companion singleton 上の static-like (toplevel) 関数扱いへの lowering を追加する（`JvmStaticLoweringPass.swift`）
  - [x] `@Suppress`/`@Deprecated` の動作を確認する diff/golden ケースを追加する（`GoldenCases/Sema/suppress_annotation.kt`, `deprecated_annotation.kt`）
  - **完了条件**: `@Suppress` が対象診断を抑制し、`@Deprecated(level = ERROR)` が呼び出し元をコンパイルエラーにする ✓


- [ ] ANNO-002: `@file:Suppress` / `@file:JvmName` など file-level annotation を AST / Sema / metadata で扱う（registry: `P5-141`, spec.md J6/J14）
  - [ ] `ASTFile` に file annotation を保持し、package / import 前の `@file:` を parse / build AST で落とさず運ぶ
  - [ ] `@file:Suppress` を file-scope diagnostics に適用し、`@file:JvmName` を metadata / file facade naming に反映する
  - [ ] metadata serialize / deserialize と golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-141`
  - **完了条件**: `@file:Suppress("UNUSED")` が file 内の unused 診断を抑制し、`@file:JvmName("CustomName")` が metadata / export 名に反映される

---

### 🛠️ Diagnostics / Tooling

- [x] TOOL-001: 診断コードを全 pass で体系化し、LSP 向け出力（location / severity / codeAction）を実装する
  - [x] 全 Sema/Parse 診断を `KSWIFTK-{PASS}-{CODE}` 規則で列挙し、`DiagnosticRegistry` に集約する（`DiagnosticRegistry.swift`）
  - [x] 診断に source location（file / line / column）と severity（error/warning/note）を必ず付与する
  - [x] JSON 形式（`-Xdiagnostics json`）で診断を出力するオプションを追加し、LSP が消費できるスキーマで出力する（`Diagnostics.swift` / CLI `-Xdiagnostics json`）
  - [x] `codeAction`（quick-fix 提案）を診断コードごとに定義し、最低 10 個の quick-fix を実装する
  - [x] 診断 JSON 出力の golden ケースを追加し、スキーマ変更を検知する（`DiagnosticEngineTests.swift`）
  - **完了条件**: 全診断が `KSWIFTK-*` コードを持ち、JSON 出力が LSP 準拠スキーマで整合し、golden テストが pass する ✓

---

### 🌐 Multiplatform

- [x] MPP-001: `expect`/`actual` 宣言を parser/sema/metadata で扱う（spec.md J14 / Kotlin MPP）
  - [x] `expect fun foo()` を abstract-like 宣言として Parser/AST で保持する（`SemanticsModels.swift` の `SymbolFlags`）
  - [x] `actual fun foo()` を対応する `expect` の実装として Sema でマッチングする（`DataFlow/ExpectActual.swift`）
  - [x] `expect` に対する `actual` が存在しない場合に `KSWIFTK-MPP-UNRESOLVED` を出す
  - [x] diff/golden ケースを追加する → `GoldenCases/Sema/expect_actual.kt`
  - **完了条件**: `expect fun platform()` に対する `actual fun platform()` が正しくリンクされ動作する ✓

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
| `Scripts/diff_cases/` | diff テスト（`kotlinc` との出力比較） |
