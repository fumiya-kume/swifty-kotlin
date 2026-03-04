# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-05

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

## 未完了バックログ（6件 + 完了11件）

### 📐 Type System

- [x] TYPE-005: 符号なし整数型（`UInt`/`ULong`/`UByte`/`UShort`）の演算・型変換・stdlib を完全実装する（spec.md J8）
  - [x] `UInt`/`ULong`/`UByte`/`UShort` を distinct な primitive 型として TypeSystem に登録し、signed 型との暗黙変換を禁止する
  - [x] 四則演算・比較・ビット演算を符号なし意味論で LLVM IR へ lowering する（`udiv`/`urem`/`icmp ult` 等）
  - [x] `toUInt()`/`toInt()` などの変換関数を stdlib stub として実装する ✓
  - [x] 符号なし型リテラル（`42u`/`42uL`）を Lexer/Parser で認識し型推論する
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-005`
  - **完了条件**: `val x: UInt = 4294967295u` が overflow せず正しく演算され、`toInt()` で符号変換が動作する

---

### 🏗️ Class / Object

- [x] CLASS-006: `data object` の型と等値比較を実装する（spec.md J6）
  - [x] `data object Singleton` を singleton かつ equals/toString 合成ありとして扱う（hashCode は未実装）
  - [ ] anonymous object の型を local nominal として推論し、呼び出しスコープ内で有効にする
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-006`
  - **完了条件**: `data object None` が `None == None` → `true`、`None.toString()` → `"None"` を返す ✓


- [x] CLASS-008: クラス委譲（`class A : Interface by delegateInstance`）を front-to-back で実装する（spec.md J7/J12）
  - [x] class ヘッダの `: Interface by expr` 構文を Parser/AST で保持する（property delegation の `by` とは別パス）
  - [x] Sema で delegate 式の型が対象 interface を実装していることを検証する
  - [x] KIR lowering で interface の全メソッドを `delegateInstance.method(...)` へ転送するボイラープレートを合成する
  - [x] クラス自身が一部メソッドを override する場合は override 側を優先する dispatch を生成する
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-008`
  - **完了条件**: `class Logger(impl: Printer) : Printer by impl` が `impl` のメソッドを委譲し、override したメソッドだけ自前実装を呼ぶ（※itable 未実装のため diff は SKIP-DIFF、CLASS-008-FOLLOW 参照）

- [ ] CLASS-008-FOLLOW: クラス委譲の既知の制限を解消する
  - [x] NativeEmitter（LLVM C API バックエンド）で `virtualCall` の itable ディスパッチを実装する（`kk_itable_lookup` を呼び、戻り値を関数ポインタとして indirect call する）
  - [ ] 委譲フィールドを KIRGlobal ではなくインスタンスフィールド（receiver + fieldOffset）として保持する
  - **完了条件**: `-Xir backend=synthetic-c` なしで `logger.print()` が正しく動作し、複数インスタンスで委譲が独立して動作する

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

---

### 🧬 Generics

- [ ] GEN-001: 複数 upper bound（`where T : A, T : B`）と F-bound（`T : Comparable<T>`）を完全実装する（spec.md J8）
  - [x] `where` 句の複数 upper bound を `TypeParamDecl` に保持し、overload 解決で全境界を検証する
  - [x] `T : Comparable<T>` のような自己参照 upper bound（F-bound）を循環検出せずに解決する
  - [x] 複数 upper bound に違反する型引数に `KSWIFTK-SEMA-BOUND` 診断を出す
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task GEN-001`（SKIP-DIFF: ジェネリック本体内での比較演算が E2E 未完全）
  - **完了条件**: `fun <T> max(a: T, b: T): T where T : Comparable<T>` が `max(1, 2)` / `max("a", "b")` で動作する

---

### 🛡️ Null Safety

- [ ] NULL-001: platform type（nullability 不明型 `T!`）の扱いを実装する（spec.md J8）
  - [ ] externally-declared symbol（`.kklib` import）で nullability 情報がない型を platform type として表現する
  - [ ] platform type は nullable にも non-null にも代入でき、利用時に nullability 警告を出す
  - [ ] platform type を明示した nullable/non-null へ代入する文脈で型チェックを緩和する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task NULL-001`
  - **完了条件**: 外部 API から返された型が `T!` として扱われ、null チェックなし使用に `KSWIFTK-SEMA-PLATFORM` warning が出る


- [ ] NULL-002: nullable receiver（`T?.foo()`）拡張関数を Sema で解決する（spec.md J7/J9）
  - [x] `fun String?.isNullOrEmpty()` / `isNullOrBlank()` を stdlib ハードコードとして Sema で登録・解決する（`CallTypeChecker+Part3.swift`）
  - [x] nullable receiver 拡張は `?.` なしに直接呼べることを Sema で許可する（isNullOrEmpty/isNullOrBlank 限定）
  - [ ] 汎用 nullable receiver 拡張（ユーザー定義 `fun T?.foo()`）の登録・解決規則を Sema で実装する
  - [x] diff/golden ケースを追加する → `nullable_receiver_ext.kt` / `null_receiver_is_null_or_empty.kt`
  - **完了条件**: `null.isNullOrEmpty()` が `NullPointerException` を出さず `true` を返し `kotlinc` と一致する ✓（stdlib 限定）

---

### ⚡ Coroutines

- [ ] CORO-003: `Flow<T>` コールドストリームを実装する（spec.md J17）
  - [x] runtime に `kk_flow_create` / `kk_flow_collect` / `kk_flow_emit` の C ABI 関数を追加する（stub: `kk_flow_collect` は collector 未呼び出し）
  - [ ] `flow { emit(x) }` builder の lowering を実装し、collector lambda に suspension point を挿入する
  - [ ] `Flow.map`・`Flow.filter`・`Flow.take`・`Flow.collect` 中間オペレーターを stub として実装する
  - [ ] `Flow` はコールド（collect のたびに再実行）であることを runtime で保証する（現在 `kk_flow_collect` は no-op）
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CORO-003`
  - **完了条件**: `flow { emit(1); emit(2) }.map { it * 2 }.collect { println(it) }` が `2\n4` を出力し `kotlinc` と一致する

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


- [ ] STDLIB-006: String stdlib 関数（`trim`/`split`/`replace`/`startsWith`/`endsWith`/`toInt`/`toDouble`/`format`）を実装する（spec.md J15）
  - [x] runtime/stdlib stub に `kk_string_trim` / `kk_string_split` / `kk_string_replace` 等を追加する（`RuntimeStringArray.swift`）
  - [x] `String.toInt()` / `String.toDouble()` の失敗時に `NumberFormatException` を投げる動作を実装する
  - [ ] `String.format(vararg args)` を printf 相当の C ABI 関数へ lowering する（未実装）
  - [x] `startsWith`/`endsWith`/`contains`（文字列検索版）を stdlib stub として実装する
  - [x] diff/golden ケースを追加する → `Scripts/diff_cases/string_stdlib.kt`
  - **完了条件**: `"  hello  ".trim()` / `"1,2,3".split(",")` / `"42".toInt()` が `kotlinc` と同一出力になる ✓（`String.format` を除く）

---

### 🏷️ Annotations

- [x] ANNO-001: `@Suppress` / `@Deprecated` / `@JvmStatic` など built-in アノテーションの特別処理を追加する（spec.md J6）
  - [x] `@Suppress("UNCHECKED_CAST")` で指定した診断コードを当該 node で抑制する compiler ルールを追加する（`Diagnostics.swift`）
  - [x] `@Deprecated(..., level = ERROR/WARNING)` で呼び出し元に診断を発生させる（`TypeCheckHelpers+Deprecation.swift`）
  - [x] `@JvmStatic` on companion member → companion singleton 上の static-like (toplevel) 関数扱いへの lowering を追加する（`JvmStaticLoweringPass.swift`）
  - [x] `@Suppress`/`@Deprecated` の動作を確認する diff/golden ケースを追加する（`GoldenCases/Sema/suppress_annotation.kt`, `deprecated_annotation.kt`）
  - **完了条件**: `@Suppress` が対象診断を抑制し、`@Deprecated(level = ERROR)` が呼び出し元をコンパイルエラーにする ✓

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
  - [x] `actual fun foo()` を対応する `expect` の実装として Sema でマッチングする（`DataFlowSemaPhase+ExpectActual.swift`）
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
