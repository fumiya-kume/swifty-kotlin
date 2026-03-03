# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-03

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

## 未完了バックログ（16件）

### 📐 Type System

- [ ] TYPE-005: 符号なし整数型（`UInt`/`ULong`/`UByte`/`UShort`）の演算・型変換・stdlib を完全実装する（spec.md J8）
  - [ ] `UInt`/`ULong`/`UByte`/`UShort` を distinct な primitive 型として TypeSystem に登録し、signed 型との暗黙変換を禁止する
  - [ ] 四則演算・比較・ビット演算を符号なし意味論で LLVM IR へ lowering する（`udiv`/`urem`/`icmp ult` 等）
  - [ ] `toUInt()`/`toInt()` などの変換関数を stdlib stub として実装する
  - [ ] 符号なし型リテラル（`42u`/`42uL`）を Lexer/Parser で認識し型推論する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-005`
  - **完了条件**: `val x: UInt = 4294967295u` が overflow せず正しく演算され、`toInt()` で符号変換が動作する

---

### 🏗️ Class / Object

- [ ] CLASS-006: `data object` の型と等値比較を実装する（spec.md J6）
  - [ ] `data object Singleton` を singleton かつ equals/hashCode/toString 合成ありとして扱う
  - [ ] anonymous object の型を local nominal として推論し、呼び出しスコープ内で有効にする
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-006`
  - **完了条件**: `data object None` が `None == None` → `true`、`None.toString()` → `"None"` を返す


- [ ] CLASS-008: クラス委譲（`class A : Interface by delegateInstance`）を front-to-back で実装する（spec.md J7/J12）
  - [ ] class ヘッダの `: Interface by expr` 構文を Parser/AST で保持する（property delegation の `by` とは別パス）
  - [ ] Sema で delegate 式の型が対象 interface を実装していることを検証する
  - [ ] KIR lowering で interface の全メソッドを `delegateInstance.method(...)` へ転送するボイラープレートを合成する
  - [ ] クラス自身が一部メソッドを override する場合は override 側を優先する dispatch を生成する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-008`
  - **完了条件**: `class Logger(impl: Printer) : Printer by impl` が `impl` のメソッドを委譲し、override したメソッドだけ自前実装を呼ぶ

---

### 🧩 Functions

- [ ] FUNC-001: tail-recursive 関数（`tailrec fun`）の末尾呼び出し最適化を実装する（spec.md J9）
  - [ ] `tailrec` 修飾子を Sema で認識し、最後の式が self-recursive call であることを検証する
  - [ ] tail call が満たされない場合に `KSWIFTK-SEMA-TAILREC` warning を出す
  - [ ] KIR/Lowering で `tailrec fun` をループ（label jump）へ変換し、スタック消費を抑制する
  - [ ] 深い再帰が tailrec により StackOverflow を起こさないことを E2E テストで確認する
  - **完了条件**: `tailrec fun fact(n: Int, acc: Int = 1): Int` が 100000 段の再帰で StackOverflow しない


- [ ] FUNC-002: infix 関数宣言（`infix fun`）の構文と解決を実装する（spec.md J9）
  - [ ] `infix fun T.foo(arg: Type)` を parser/AST で infix function として保持する
  - [ ] `a foo b` 形式の中置呼び出しを Sema で receiver + infix function 呼び出しへ解決する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task FUNC-002`
  - **完了条件**: `1 to "one"` が `Pair(1, "one")` に、カスタム infix 関数が正しい優先順位で評価される（優先順位設定は既存実装済み）

---

### 🧬 Generics

- [ ] GEN-001: 複数 upper bound（`where T : A, T : B`）と F-bound（`T : Comparable<T>`）を完全実装する（spec.md J8）
  - [ ] `where` 句の複数 upper bound を `TypeParamDecl` に保持し、overload 解決で全境界を検証する
  - [ ] `T : Comparable<T>` のような自己参照 upper bound（F-bound）を循環検出せずに解決する
  - [ ] 複数 upper bound に違反する型引数に `KSWIFTK-SEMA-BOUND` 診断を出す
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task GEN-001`
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
  - [ ] `fun String?.isNullOrEmpty()` のような nullable receiver の拡張関数を Sema で登録・解決する
  - [ ] nullable receiver 拡張は `?.` なしに直接呼べることを Sema で許可する
  - [ ] nullable receiver 拡張の優先順位（non-null receiver extension より低い）を解決規則に反映する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task NULL-002`
  - **完了条件**: `null.isNullOrEmpty()` が `NullPointerException` を出さず `true` を返し `kotlinc` と一致する

---

### ⚡ Coroutines

- [ ] CORO-003: `Flow<T>` コールドストリームを実装する（spec.md J17）
  - [ ] runtime に `kk_flow_create` / `kk_flow_collect` / `kk_flow_emit` の C ABI 関数を追加する
  - [ ] `flow { emit(x) }` builder の lowering を実装し、collector lambda に suspension point を挿入する
  - [ ] `Flow.map`・`Flow.filter`・`Flow.take`・`Flow.collect` 中間オペレーターを stub として実装する
  - [ ] `Flow` はコールド（collect のたびに再実行）であることを runtime で保証する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CORO-003`
  - **完了条件**: `flow { emit(1); emit(2) }.map { it * 2 }.collect { println(it) }` が `2\n4` を出力し `kotlinc` と一致する

---

### 📦 Stdlib / DSL

- [ ] STDLIB-002: `buildString`/`buildList`/`buildMap` DSL builder を実装する（spec.md J9/J12）
  - [ ] `buildString { append("a"); append("b") }` を `StringBuilder` ベースの DSL として実装する
  - [ ] `buildList { add(1); add(2) }` を mutable list builder として実装する
  - [ ] builder lambda の receiver (`StringBuilder`/`MutableList`) を Sema で `this` として束縛する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task STDLIB-002`
  - **完了条件**: `buildString { append("hello "); append("world") }` が `"hello world"` を返す


- [ ] STDLIB-004: スコープ関数（`let`/`run`/`with`/`apply`/`also`）を stdlib stub として実装する（spec.md J9）
  - [ ] `let`/`run`/`also` を `T` の extension inline 関数として、`with` をトップレベル inline 関数として stub 実装する
  - [ ] `apply` の receiver return と `also` の self return を型システムで正しく推論する
  - [ ] 各スコープ関数の lambda 引数の receiver / `it` を Sema でスコープ束縛する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task STDLIB-004`
  - **完了条件**: `val result = "hello".let { it.uppercase() }` / `mutableListOf<Int>().apply { add(1) }` が `kotlinc` と同一出力になる


- [ ] STDLIB-005: コレクション高階関数（`map`/`filter`/`flatMap`/`fold`/`reduce`/`forEach`/`any`/`all`/`none`/`groupBy`/`sortedBy`）を実装する（spec.md J15）
  - [ ] runtime/stdlib stub に `kk_list_map` / `kk_list_filter` / `kk_list_fold` 等の C ABI 関数を追加する
  - [ ] lambda を function pointer + closure として C ABI 経由で HOF に渡す lowering を実装する
  - [ ] `flatMap`・`groupBy`・`sortedBy` の安定ソートを実装する
  - [ ] `any`/`all`/`none`/`count`/`first`/`last`/`find` の短絡評価を runtime で保証する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task STDLIB-005`
  - **完了条件**: `listOf(1,2,3).filter { it > 1 }.map { it * 2 }` が `[4, 6]` を返し `kotlinc` と一致する


- [ ] STDLIB-006: String stdlib 関数（`trim`/`split`/`replace`/`startsWith`/`endsWith`/`toInt`/`toDouble`/`format`）を実装する（spec.md J15）
  - [ ] runtime/stdlib stub に `kk_string_trim` / `kk_string_split` / `kk_string_replace` 等を追加する
  - [ ] `String.toInt()` / `String.toDouble()` の失敗時に `NumberFormatException` を投げる動作を実装する
  - [ ] `String.format(vararg args)` を printf 相当の C ABI 関数へ lowering する
  - [ ] `startsWith`/`endsWith`/`contains`（文字列検索版）を stdlib stub として実装する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task STDLIB-006`
  - **完了条件**: `"  hello  ".trim()` / `"1,2,3".split(",")` / `"42".toInt()` が `kotlinc` と同一出力になる

---

### 🏷️ Annotations

- [ ] ANNO-001: `@Suppress` / `@Deprecated` / `@JvmStatic` など built-in アノテーションの特別処理を追加する（spec.md J6）
  - [ ] `@Suppress("UNCHECKED_CAST")` で指定した診断コードを当該 node で抑制する compiler ルールを追加する
  - [ ] `@Deprecated(..., level = ERROR/WARNING)` で呼び出し元に診断を発生させる
  - [ ] `@JvmStatic` on companion member → companion singleton 上の static-like (toplevel) 関数扱いへの lowering を追加する
  - [ ] `@Suppress`/`@Deprecated` の動作を確認する diff/golden ケースを追加する
  - **完了条件**: `@Suppress` が対象診断を抑制し、`@Deprecated(level = ERROR)` が呼び出し元をコンパイルエラーにする

---

### 🛠️ Diagnostics / Tooling

- [ ] TOOL-001: 診断コードを全 pass で体系化し、LSP 向け出力（location / severity / codeAction）を実装する
  - [ ] 全 Sema/Parse 診断を `KSWIFTK-{PASS}-{CODE}` 規則で列挙し、`DiagnosticRegistry` に集約する
  - [ ] 診断に source location（file / line / column）と severity（error/warning/note）を必ず付与する
  - [ ] JSON 形式（`-Xdiagnostics json`）で診断を出力するオプションを追加し、LSP が消費できるスキーマで出力する
  - [ ] `codeAction`（quick-fix 提案）を診断コードごとに定義し、最低 10 個の quick-fix を実装する
  - [ ] 診断 JSON 出力の golden ケースを追加し、スキーマ変更を検知する
  - **完了条件**: 全診断が `KSWIFTK-*` コードを持ち、JSON 出力が LSP 準拠スキーマで整合し、golden テストが pass する

---

### 🌐 Multiplatform

- [ ] MPP-001: `expect`/`actual` 宣言を parser/sema/metadata で扱う（spec.md J14 / Kotlin MPP）
  - [ ] `expect fun foo()` を abstract-like 宣言として Parser/AST で保持する
  - [ ] `actual fun foo()` を対応する `expect` の実装として Sema でマッチングする
  - [ ] `expect` に対する `actual` が存在しない場合に `KSWIFTK-MPP-UNRESOLVED` を出す
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task MPP-001`
  - **完了条件**: `expect fun platform()` に対する `actual fun platform()` が正しくリンクされ動作する

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
