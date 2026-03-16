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

### 📦 Runtime Hardening — Silent Fallback 排除

- STDLIB-238/239: Sequence runtime 硬化は既存実装済み（PR #311）
- STDLIB-240: Collection HOF invalid container fallback 硬化は既存実装済み（PR #312）
- STDLIB-241: Collection HOF lambda throw fallback 厳格化は既存実装済み（PR #285）
- STDLIB-242/249: Collection conversion / Delegate runtime 硬化は既存実装済み（PR #310）
- STDLIB-243/251: Range runtime / Dispatch lookup 硬化は既存実装済み（PR #307）
- STDLIB-244/253: Regex / Boxing runtime 硬化は既存実装済み（PR #309）
- STDLIB-245/246: String runtime 硬化は既存実装済み（PR #313）
- STDLIB-247/248: Comparator / Pair/Triple runtime 硬化は既存実装済み（PR #306）
- STDLIB-250/252: Coroutine/Flow/Channel / low-level String ABI 硬化は既存実装済み
- STDLIB-254/256: Builder DSL / Enum string equality 硬化は既存実装済み（PR #308）
- STDLIB-255: Random runtime invalid range 硬化は既存実装済み（PR #315）

- [ ] STDLIB-257: Precondition lazy message fallback の失敗経路を明確化する
  - 背景: `require {}` / `check {}` の lazy message 評価失敗が default message fallback に見える余地がある
  - [ ] [Sources/Runtime/RuntimePreconditions.swift](/Users/kuu/kotlin-compiler/Sources/Runtime/RuntimePreconditions.swift) の `preconditionWithLazyMessage` / `runtimeEvaluateLazyMessage` を棚卸しする
  - [ ] lazy message closure 自体の失敗と、通常の precondition failure を区別できるよう契約を整理する
  - [ ] lazy message throw の回帰ケースを追加する
  - **完了条件**: lazy message 評価失敗が通常の `require/check` 失敗に紛れず観測できる

---

### 📦 Stdlib — File I/O

- [ ] STDLIB-320: `java.io.File` 基本操作（`readText` / `writeText` / `readLines`）を実装する
  - [ ] Sema に `File(String)` コンストラクタと `readText(): String` / `writeText(String)` / `readLines(): List<String>` stub を登録する
  - [x] Runtime に `kk_file_readText` / `kk_file_writeText` / `kk_file_readLines` を追加する（PR #333, `Sources/Runtime/RuntimeFileIO.swift`）
  - [ ] Codegen/Lowering に `kk_file_*` extern 宣言とメンバー呼び出し変換を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp/test.txt").writeText("hello"); File("/tmp/test.txt").readText()` → `"hello"` が動作する

- [ ] STDLIB-321: `File.exists()` / `File.isFile` / `File.isDirectory` / `File.name` / `File.path` を実装する
  - [ ] Sema に各プロパティ / メソッド stub を登録する
  - [x] Runtime に `kk_file_exists` / `kk_file_isFile` / `kk_file_isDirectory` / `kk_file_name` / `kk_file_path` を追加する（PR #333, `Sources/Runtime/RuntimeFileIO.swift`）
  - [ ] Codegen/Lowering に `kk_file_*` extern 宣言とメンバー呼び出し変換を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("/tmp").isDirectory` → `true` が動作する

- [ ] STDLIB-322: `File.forEachLine {}` / `File.useLines {}` / `File.bufferedReader()` を実装する
  - [ ] Sema に各 member stub を登録する
  - [ ] Runtime に `kk_file_useLines` / `kk_file_bufferedReader` を追加する（`kk_file_forEachLine` は PR #333 で実装済み）
  - [ ] Codegen/Lowering に `kk_file_*` extern 宣言とメンバー呼び出し変換を追加する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `File("test.txt").forEachLine { println(it) }` が各行を出力する

- [ ] STDLIB-323: `File.walk()` / `File.listFiles()` / `File.delete()` / `File.mkdirs()` を実装する
  - [ ] Sema に各 member stub を登録する
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
  - [ ] Runtime で continuation ベースのイテレータ生成を実装する
  - [ ] diff/golden ケースを追加する
  - **完了条件**: `val iter = iterator { yield(1); yield(2) }; println(iter.next())` → `1` が `kotlinc` と一致する

---

### 🛡️ Type Safety — Sema / Runtime 境界

- TYPE-107 〜 TYPE-113 は既存実装済み（PR #276-282）
- TYPE-104/105/106 は既存実装済み

- [ ] TYPE-101: Collection HOF 推論で `Any` に潰れている戻り型を generic 保持に置き換える
  - [ ] `CallTypeChecker+MemberCallInference.swift` の `flatMap` / `associateBy` / `associateWith` / `associate` / `mapIndexed` / `groupBy` の戻り型推論を棚卸しする
  - [ ] ラムダ戻り型 `R`、key 型 `K`、value 型 `V` を `Any` にフォールバックせず `TypeID` として保持する共通ヘルパーを導入する
  - [ ] `flatMap` を `List<R>`、`associateBy` を `Map<K, T>`、`associateWith` を `Map<T, V>`、`associate` を `Map<K, V>` として推論できるようにする
  - [ ] `mapIndexed` を `List<R>`、`groupBy` を `Map<K, List<T>>` として推論できるようにする
  - [ ] `Any` に落ちたことで通ってしまっていた不正プログラムの negative golden を追加する
  - [ ] 正常系の diff/golden ケースを追加する
  - **完了条件**: `listOf(1).mapIndexed { _, x -> "$x" }` の型が `List<String>` になり、`associateBy` / `flatMap` / `groupBy` でも `kotlinc` と同等の型推論結果になる

- [ ] TYPE-102: synthetic collection stub の暫定 `Any` 戻り型を実型ベースに置き換える
  - [ ] `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift` の `partition` など、コメントで「use Any for now」としている箇所を対応する（`mapIndexed` stub は `List<R>` で定義済み）
  - [ ] synthetic stub 側で関数型 type parameter `R`、`Pair<List<T>, List<T>>`、`Map<K, V>` を表現するための builder を追加する
  - [ ] `mapIndexed` の stub 定義（`List<R>`）を推論コード（`CallTypeChecker+MemberCallInference.swift`）が利用するよう連携する（現在は stub を無視して `List<Any>` を返している）
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
