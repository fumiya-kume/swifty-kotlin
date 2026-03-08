# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-08

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

## 未完了バックログ（0件）

### 🧱 Declarations

- [x] DECL-004: `lateinit var` と `::prop.isInitialized` を front-to-back で実装する（registry: `P5-110`, spec.md J7/J9）
  - [x] `lateinit` 修飾子を property symbol / metadata に保持し、`val`・nullable 型・primitive 型・initializer 付き宣言を禁止して `KSWIFTK-SEMA-LATEINIT` 系診断を出す
  - [x] backing storage に未初期化状態を保持し、未初期化読み取り時は `UninitializedPropertyAccessException` を投げ、代入後は通常 getter / setter として動作させる
  - [x] bound property reference `::name.isInitialized` を owner scope 内で解決し、member / top-level property の初期化状態を参照できるようにする
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-110`
  - **完了条件**: `lateinit var name: String` が未初期化読み取りで例外を投げ、`::name.isInitialized` が代入前 `false` / 代入後 `true` を返す ✓

---

### 🧩 Functions

- [x] FUNC-004: class / data class receiver 上の `operator fun` を front-to-back で揃える（registry: `P5-120`, spec.md J7/J9）
  - [x] member operator body から primary constructor property / member property を正しく解決し、`x` / `other.x` 参照が class / data class 内で通るようにする
  - [x] `plus` / `minus` / `times` / `unaryMinus` / `get` の member operator declaration を overload 解決に載せ、operator desugaring と通常メソッド呼び出しを同じ symbol に束縛する
  - [x] top-level / extension operator は `既存実装済み` とし、member operator の KIR / lowering / codegen parity を揃える
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-120`
  - **完了条件**: `data class Vec(val x: Int, val y: Int)` 上の `a + b` / `-a` / `vec[0]` が `kotlinc` と同一出力になる ✓

---

### 🧬 Generics

- [x] GEN-004: `fun interface` の SAM conversion を end-to-end で実装する（registry: `GEN-004`, spec.md J9/J12）
  - [x] `fun interface` を single abstract method を持つ nominal type として検証し、SAM 条件違反に `KSWIFTK-SEMA-SAM` 系診断を出す
  - [x] lambda / callable reference を期待型の SAM signature に合わせて型推論し、Sema binding と hidden bridge 情報を KIR へ渡す
  - [x] lowering / codegen で SAM wrapper 生成と call-site rewrite を実装し、引数位置 lambda が interface instance として渡るようにする
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task GEN-004`
  - **完了条件**: `fun interface Action { fun run(): String }` に対して `execute { "hello" }` が `"hello"` を出力し `kotlinc` と一致する ✓

---

### ⚡ Coroutines

- [x] CORO-002: coroutine cancellation の end-to-end parity を復旧する（spec.md J17）
  - [x] `job.cancel()` / `job.join()` / `CancellationException` の surface API 解決を通し、runtime ABI は `既存実装済み` として `kk_job_cancel` / `kk_job_join` / cancellation helpers へ lowering する
  - [x] `repeat(times)` 依存は `STDLIB-008` で補完する
  - [x] `--kotlinc-classpath` に `kotlinx-coroutines-core` を渡す parity ワークフローを前提条件として明記する
  - **完了条件**: `job.cancel(); job.join()` が `CancellationException` を catch して `cancelled\ndone` を `kotlinc` と一致して出力する ✓

- [x] CORO-004: `withContext` / `Dispatchers` の解決・lowering を追加する（registry: `P5-133`, spec.md J17）
  - [x] `Dispatchers.Default` / `Dispatchers.IO` stub と `withContext` signature を Sema に登録し、import 解決から参照できるようにする
  - [x] `withContext(dispatcher) { ... }` を coroutine lowering で runtime `kk_with_context` へ rewrite する
  - [x] `kotlinx-coroutines-core` classpath 前提の diff ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-133`
  - **完了条件**: `withContext(Dispatchers.Default) { "hello" }` が `"hello"` を返し `kotlinc` と同一出力になる ✓

- [x] CORO-005: `Channel<T>` / `send` / `receive` / `close` を実装する（registry: `P5-134`, spec.md J17）
  - [x] `Channel<T>` nominal type と `kotlinx.coroutines.channels.*` import 解決を Sema に追加する
  - [x] `Channel()` / `send` / `receive` / `close` を runtime `kk_channel_create` / `kk_channel_send` / `kk_channel_receive` / `kk_channel_close` ABI へ lowering する
  - [x] `kotlinx-coroutines-core` classpath 前提の diff ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-134`
  - **完了条件**: `Channel<Int>()`, `send(42)`, `receive()` が `42` を出力し `kotlinc` と同一出力になる ✓

- [x] CORO-006: Kotlin 形式の `async { ... }` / `await()` parity を実装する（registry: `P5-135`, spec.md J17）
  - [x] suspend function reference 専用の launcher lowering を、suspend lambda / inline block 受け取りにも対応させる
  - [x] `Deferred<T>` 相当の型と `.await()` member 解決を Sema / KIR で揃える
  - [x] `kotlinx-coroutines-core` classpath 前提の diff ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-135`
  - **完了条件**: `val deferred = async { 1 + 2 }; println(deferred.await())` が `3` を出力し `kotlinc` と同一出力になる ✓

---

### 📦 Stdlib / DSL

- [x] STDLIB-007: multiline string helper `trimIndent()` / `trimMargin()` を実装する（spec.md J15）
  - [x] raw string literal 本体は `既存実装済み` とし、`String.trimIndent()` / `trimMargin()` の synthetic stdlib signature と runtime helper を追加する
  - [x] 改行・共通インデント除去・custom margin prefix の挙動を `kotlinc` に合わせる
  - [x] diff/golden ケースを追加する → `Scripts/test_templates/diff/raw_string_basic.kt` を正式 diff ケースへ昇格し、`trimMargin()` 用ケースを追加する
  - **完了条件**: triple-quoted string に `trimIndent()` / `trimMargin()` を適用した出力が `kotlinc` と一致する ✓

- [x] STDLIB-008: `repeat(times) {}` を stdlib stub として実装する（spec.md J15）
  - [x] `repeat(Int, action)` signature を Sema に登録し、lambda 引数 `it` を loop index として型推論できるようにする
  - [x] lowering / codegen で counted loop へ展開し、単純な inline loop として実行できるようにする
  - [x] standalone golden と `Scripts/diff_cases/coroutine_cancellation.kt` の unblock 用 diff ケースを追加する
  - **完了条件**: `repeat(3) { print(it) }` が `012` を出力し、coroutine parity ケースの前提を満たす ✓

---

### 🏷️ Annotations

- [x] ANNO-002: `@file:Suppress` / `@file:JvmName` など file-level annotation を AST / Sema / metadata で扱う（registry: `P5-141`, spec.md J6/J14）
  - [x] `ASTFile` に file annotation を保持し、package / import 前の `@file:` を parse / build AST で落とさず運ぶ
  - [x] `@file:Suppress` を file-scope diagnostics に適用し、`@file:JvmName` を metadata / file facade naming に反映する
  - [x] metadata serialize / deserialize と golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task P5-141`
  - **完了条件**: `@file:Suppress("UNUSED")` が file 内の unused 診断を抑制し、`@file:JvmName("CustomName")` が metadata / export 名に反映される ✓

---

### 🪢 Property Delegation

- [x] PROP-001: プロパティ委譲（`val x by lazy { ... }` / `by Delegates.observable`）を実装する（spec.md 拡張）
  - [x] `by` キーワードを用いたプロパティ宣言の Parser/AST 対応を行う
  - [x] Sema にて `getValue` / `setValue` 規約メソッドの呼び出し解決を実装する
  - [x] Lowering で委譲用バックイングフィールドと対応するアクセサへと変換する処理を追加する
  - [x] diff/golden ケースを追加する
  - **完了条件**: カスタム `getValue`/`setValue` のデリゲートプロパティが動作する ✓

---

### 🏗️ Class / Object (Advanced)

- [x] CLASS-009: `value class`（`@JvmInline value class`）をサポートし、ゼロオーバーヘッドの型ラップを実装する
  - [x] `value class` の構文解釈と、単一プロパティしか持たないことの Semantic 検証を追加する
  - [x] 関数シグネチャにおける自動 Mangle と、Lowering 時の unbox 展開を実装する
  - [x] diff/golden ケースを追加する
  - **完了条件**: 実行時にラッパークラスの生成が省略され、直接ベース型として扱われる ✓

- [x] CLASS-010: `sealed interface` を実装し、インターフェースの網羅性チェックを支援する
  - [x] `sealed` 修飾子を `interface` に許可し、Sema にて実装クラス群を収集する
  - [x] Exhaustiveness (網羅性) 判定に `sealed interface` のサブタイプを含める
  - [x] diff/golden ケースを追加する
  - **完了条件**: 全実装をカバーしていない `when` 式で `KSWIFTK-SEMA-NON-EXHAUSTIVE-WHEN` エラーが発生する ✓

---

### 🧩 Functions (Advanced)

- [x] FUNC-005: Contracts (`kotlin.contracts.contract`) による高度なスマートキャストを実装する
  - [x] `contract { returns(true) implies (arg != null) }` 等の解析処理を追加する
  - [x] Contract 情報をメタデータに保持し、呼び出し元の Data-flow 状態に組み込む
  - [x] diff/golden ケースを追加する
  - **完了条件**: 独自の検証式を呼び出した直後にスマートキャストが発動する ✓

- [x] FUNC-006: Context Parameters / Receivers (`context(Foo) fun bar()`) をサポートする
  - [x] `context` 宣言の Parser 対応と、Sema レシーバスコープの拡張を実装する
  - [x] 呼び出し元からの暗黙的な Context 引数渡し (Lowering) を実装する
  - [x] diff/golden ケースを追加する
  - **完了条件**: Context スコープ内でのみアクセスできる関数の呼び出しが成功する ✓

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
