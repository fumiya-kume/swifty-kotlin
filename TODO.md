# Kotlin Compiler Remaining Tasks

最終更新: 2026-03-02

## 運用ルール

- `TODO.md` は未完了タスクのみを管理する。
- タスクIDはカテゴリ接頭辞 (`LEX/TYPE/EXPR/CTRL/DECL/CLASS/PROP/FUNC/GEN/NULL/CORO/STDLIB/ANNO/TOOL/MPP`) + 3桁連番を使用する。
- 旧 `P5-*` IDは保持しない。完了履歴は Git 履歴を参照する。
- 相互参照で完了済みタスクを参照する場合は `既存実装済み` と記載する。
- 共通完了条件（全タスク共通）:
  1. `Scripts/diff_kotlinc.sh` が exit 0 かつ stdout 完全一致
  2. golden テストが byte 一致
  3. エラーケースで `KSWIFTK-*` 診断コード出力
  4. 各項目末尾エッジケース golden が通過

## 実装順（依存順 + 優先度）

1. Wave 1: Lexer/Type/Expr/Control を先行実装
2. Wave 2: Declarations/Class/Property/Function/Generics/Null を実装
3. Wave 3: Coroutine/Stdlib/Annotation/Tooling/MPP を実装

## 未完了バックログ

### Wave 1: Lexer/Type/Expr/Control

#### 🔤 Lexer / Literals

- [x] LEX-001: Char リテラルのエスケープシーケンス全網羅と Unicode escape を実装する（spec.md J4）
  - [x] `\t` / `\n` / `\r` / `\\` / `\'` / `\"` / `\$` の 7 種を Lexer で正しい Char コードに変換する
  - [x] `\uXXXX` Unicode エスケープを Lexer で 4 桁 hex → UTF-16 コードポイントへ変換する
  - [x] 不正なエスケープシーケンス（`\q` 等）に対して `KSWIFTK-LEX-*` 診断を出す
  - [x] Char 算術（`'a' + 1`・`'z' - 'a'`）の型推論と runtime 演算を実装する
  - [x] Char エスケープ・Unicode escape の diff/golden ケースを追加する（`Scripts/diff_cases/char_escape.kt` / `GoldenCases/Lexer/char_literals.kt`）
  - **完了条件**: `'\u0041'` が `'A'` と同一 Char 値になり、不正エスケープが診断される


#### 📐 Type System

- [x] TYPE-001: `Nothing` 型の型推論・制御フロー Unreachable 統合を完成させる（spec.md J8/J10）
  - [x] `throw`・`return`・`break`・`continue` の型を `Nothing` として型推論に一貫して伝播させる
  - [x] `Nothing` を LUB 規則のボトム型として扱い、`if/when/try` の分岐合流で正しく処理する
  - [x] `Nothing?` と `Nothing` の区別（`null` は `Nothing?`）を型システムに反映する
  - [x] 到達不能コード（`Nothing` の後の文）を DataFlow が unreachable と判定し diagnostic を出す
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-001`
  - **完了条件**: `val x: Int = if (cond) 1 else throw E()` が型エラーなしで `Int` と推論され、到達不能行が診断される


- [x] TYPE-002: intersection type（`T & U`）と captured type を型システムに追加する（spec.md J8）
  - [x] `TypeRef` に intersection 型（`A & B`）構文を Parser/AST で追加する（`T & Any` definitelyNonNull を含む）
  - [x] `inferExpr` で smart cast 後の refinement 型を intersection として表現できるようにする
  - [x] intersection 型のサブタイプ規則（`A & B <: A`、`A & B <: B`）を `TypeSystem.isSubtype` に追加する
  - [x] `T & Any`（definitely non-nullable）の型推論と `?.` 解決への影響を実装する
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-002`
  - **完了条件**: `fun <T> foo(x: T & Any)` の引数が non-null として扱われ、smart cast が不要になる


- [x] TYPE-003: 型投影（`out T` / `in T` / `*`）の use-site variance を完全実装する（spec.md J8）
  - [x] `TypeRef` の use-site `out`/`in`/`*` を covariant/contravariant/bivariant projection として保持する
  - [x] star projection `*` を `out Any?` として扱い、write を禁止・read を `Any?` として型付けする
  - [x] use-site variance と declaration-site variance の合成規則（in×in=out 等）を `TypeSystem` に実装する
  - [x] variance 違反のメンバアクセスに `KSWIFTK-SEMA-VAR-*` 診断を出す
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-003`（2026-03-02: diff case `Scripts/diff_cases/star_projection.kt` を追加）
  - **完了条件**: `val list: MutableList<out Number>` で `.add(...)` が型エラー、`.get(0)` が `Number` になる


- [x] TYPE-004: typealias の generic alias・循環検出・展開深度制限を完全実装する（spec.md J6/J8）
  - [x] `typealias Func<T> = (T) -> T` のような generic typealias を Sema で展開する
  - [x] 循環 alias（`typealias A = B; typealias B = A`）を detect し `KSWIFTK-SEMA-ALIAS-CYCLE` を出す
  - [x] alias 展開後の型が variance 制約を壊さないことを検証する
  - [x] recursive type の展開に最大深度制限（例: 32 段）を設けてループを防ぐ
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-004`（2026-03-02: diff case `Scripts/diff_cases/generic_typealias.kt` を追加）
  - **完了条件**: `typealias Predicate<T> = (T) -> Boolean` が call-site で正しく展開され型チェックが通る（`GoldenCases/Sema/generic_typealias.kt` で確認）

---


#### ⚙️ Expressions / Operators

- [x] EXPR-002: 演算子の優先順位テーブルを Kotlin 仕様完全準拠で実装する（spec.md J5）
  - [x] Kotlin 仕様の 16 優先順位レベル（postfix > prefix > type_rhs > multiplicative > additive > range > infix > Elvis > named checks > comparison > equality > conjunction > disjunction > spread > assignment）を Parser に実装する
  - [x] infix 関数呼び出し（`a shl b`・`a or b`）を中置演算子として正しい優先順位で解析する
  - [x] `!!` の postfix 優先順位（`.` より低くないこと）を確認する
  - [x] `a + b * c - d / e` 等の混在式が正しい AST 木を生成することを golden で固定する
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task EXPR-002`（2026-03-02: parser golden `GoldenCases/Parser/operator_precedence.kt` を追加）
  - **完了条件**: `1 + 2 * 3 == 7`・`true || false && false == true` が `kotlinc` と同一に評価される


- [ ] EXPR-003: bitwise / shift 演算子（`and`/`or`/`xor`/`inv`/`shl`/`shr`/`ushr`）を infix 関数として実装する（spec.md J9）
  - [ ] `Int`/`Long` の `and`/`or`/`xor`/`inv`/`shl`/`shr`/`ushr` を stdlib infix 関数として stub 実装する
  - [ ] Sema で infix 関数呼び出し構文（`a shl 3`）を overload resolver に通す
  - [ ] bit 演算の結果型推論（`Int and Int → Int`）を実装する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task EXPR-003`
  - **完了条件**: `(0xFF and 0x0F).toString(16)` が `kotlinc` と同一出力（`"f"`）になる


- [ ] EXPR-004: `@Label` / `return@label` / `break@label` / `continue@label` を完全実装する（spec.md J5/J6）
  - [ ] Parser/AST で `@Label` prefix を関数リテラル・ループ・`return`/`break`/`continue` に付与できるようにする
  - [ ] Sema で label scope を管理し、`return@label` が lambda/fun のいずれを対象にするか解決する
  - [ ] `break@outer` / `continue@outer` を nested loop の外側ループ制御フローへ接続する
  - [ ] `return@label` がラムダ内から外側関数へ non-local return する場合の lowering を実装する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task EXPR-004`（2026-03-02: parser golden `GoldenCases/Parser/labeled_control_flow.kt` を追加）
  - **完了条件**: `outer@ for (...) { for (...) { break@outer } }` が外側ループを抜け `kotlinc` と一致

---


#### 🔀 Control Flow

- [ ] CTRL-001: `when` の複数条件ブランチ（`,` 区切り）と exhaustive 診断精度を強化する（spec.md J5/J6）
  - [ ] `when` branch の condition として `,` 区切り複数値（`1, 2, 3 -> ...`）を Parser/AST で保持する
  - [ ] Sema で複数条件を OR 結合として型検査し、exhaustiveness に反映する
  - [ ] KIR lowering で複数条件を OR jump として展開し、重複ヒットを排除する
  - [ ] sealed/enum × 複数条件の exhaustiveness 診断精度を向上する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CTRL-001`
  - **完了条件**: `when (x) { 1, 2 -> "few"; else -> "many" }` が `kotlinc` と同一動作する


- [x] CTRL-002: `try` を式として使う場合の型推論と `finally` 影響を実装する（spec.md J6/J11）
  - [x] `val x = try { ... } catch { ... }` の型を `try`/`catch` 最終式の LUB で推論する
  - [x] `finally` ブロックの戻り値が型推論を汚染しない（`Unit` 扱い）ことを保証する
  - [x] `catch` ブランチが複数ある場合の各ブランチ型合流を実装する
  - [x] some exception type のみ catch し残りを再 throw する制御フロー型推論を実装する
  - [x] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CTRL-002`（2026-03-02: diff case `Scripts/diff_cases/try_expression.kt` を追加）
  - **完了条件**: `val x: String = try { "ok" } catch (e: Exception) { "err" }` が型エラーなしでコンパイルされる


- [ ] CTRL-003: `do-while` の condition スコープと `break`/`continue`・初回実行を完全実装する（spec.md J5/J6）
  - [ ] `do { body } while (cond)` のパースで condition が body スコープ外であることを保証する
  - [ ] `do-while` 内の `break` / `continue` を正しい label ターゲットに接続する
  - [ ] do-while の初回実行保証（condition が false でも body が 1 回実行）を codegen で保証する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CTRL-003`
  - **完了条件**: `do { ... } while (false)` が body を 1 回実行し、`break` が正しくループを脱出する

---


### Wave 2: Declarations/Class/Property/Function/Generics/Null

#### 📋 Declarations

- [ ] DECL-001: top-level property の backing field・getter/setter・初期化順序を front-to-back で実装する（spec.md J6/J7）
  - [ ] top-level `val`/`var` を property シンボルとして扱い、getter/setter ABI を生成する
  - [ ] top-level property の初期化順序（宣言順・依存あり）を global initializer で保証する
  - [ ] top-level `var` への setter を通した代入（`Pkg.x = 1`）を解決する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task DECL-001`
  - **完了条件**: top-level `val pi = 3.14` と `var counter = 0` が `kotlinc` と同一動作する


- [ ] DECL-002: `const val` のコンパイル時定数畳み込みを実装する（spec.md J6/J7）
  - [ ] `const val` を宣言時に型チェックし、primitive/String 限定であることを検証する
  - [ ] `const val` を参照する式を Sema/KIR で定数値に畳み込み、実 getter 呼び出しを省く
  - [ ] annotation 引数に `const val` を使えることを Sema で検証する（既存実装済み 連携）
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task DECL-002`
  - **完了条件**: `const val MAX = 100; if (x > MAX) ...` が `if (x > 100)` と同等にコンパイルされる


- [ ] DECL-003: `object` declaration（singleton）の lazy 初期化と init block 実行順序を実装する（spec.md J6/J7）
  - [ ] `object Foo { ... }` を one-time lazy init singleton としてシンボル化し、global initializer guard を生成する
  - [ ] object への最初のアクセス時に初期化が走り、2 回目以降はキャッシュを返すことを保証する
  - [ ] object body の init block 実行順序（property initializer → init block）を codegen で保証する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task DECL-003`
  - **完了条件**: `object Counter { var n = 0 }` が singleton 保証で動作し、`kotlinc` と同一出力になる

---


#### 🏗️ Class / Object

- [ ] CLASS-001: `companion object` を最上位シングルトンとして front-to-back で実装する（spec.md J6/J7）
  - [ ] Parser/AST に `companionObjectDecl`（`companion object [Name] { ... }`）を追加し、`ClassDecl` に保持する
  - [ ] Sema で companion を owner class と同一 FQName スコープに配置し、unqualified な companion member 参照を解決する
  - [ ] companion object を global singleton としてシンボル化し、lazy 初期化パターン（またはスタティック初期化相当）を lowering で生成する
  - [ ] `ClassName.memberName` 形式の companion member 参照を member call lowering へ接続する
  - [ ] `companion object` の `const val`・factory 関数を含む diff/golden ケースを追加する
  - **完了条件**: `Foo.create()` のような companion factory が動作し、companion singleton が一度だけ初期化される


- [ ] CLASS-002: abstract class / abstract member の制約と override 強制を実装する（spec.md J6/J7）
  - [ ] `abstract class` / `abstract fun` / `abstract val` を Sema で認識し、インスタンス化禁止を診断する
  - [ ] concrete subclass がすべての abstract member を override しない場合に `KSWIFTK-SEMA-ABSTRACT` を出す
  - [ ] `abstract class` への direct `super.foo()` 呼び出しを禁止し診断する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-002`
  - **完了条件**: `abstract class A { abstract fun f() }; class B : A() { override fun f() = 1 }` が正しくコンパイルされる


- [ ] CLASS-003: `interface` default method（body あり fun in interface）を front-to-back で実装する（spec.md J6/J7/J13.2）
  - [ ] interface body 内に body を持つ fun 宣言を Parser/AST/Sema で保持する
  - [ ] concrete class が override しない場合に interface default 実装を itable 経由で dispatch する
  - [ ] default method と concrete override の共存を vtable/itable で正しく表現する（既存実装済み 連携）
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-003`
  - **完了条件**: interface default method が override されない場合に default 実装が呼ばれる


- [ ] CLASS-004: 多重インターフェース実装と diamond override の解決規則を実装する（spec.md J7/J13.2）
  - [ ] class が複数 interface を実装する場合の itable 割当ロジックを拡張する（slot conflict 解決）
  - [ ] 同名 default method を複数 interface が持つ場合に override を強制し `KSWIFTK-SEMA-DIAMOND` を出す
  - [ ] `super<InterfaceName>.method()` で特定 interface の default 実装を明示呼び出しできる
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-004`
  - **完了条件**: `class C : A, B` で両方に同名 default method があると `override` を強制し診断が出る


- [ ] CLASS-005: `open` / `final` / `override` 修飾子の継承制約を完全実装する（spec.md J6/J7）
  - [ ] `final` class または `final fun` を override しようとした場合に `KSWIFTK-SEMA-FINAL` を出す
  - [ ] `open` でない class への subclass 化を診断する（Kotlin はデフォルト `final`）
  - [ ] `override` 修飾子なしで親の関数を隠蔽した場合に Error/Warning を出す
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-005`
  - **完了条件**: non-open class の継承は診断され、`open class` の継承と override が `kotlinc` と一致する


- [ ] CLASS-006: `data object` / anonymous object の型と等値比較を実装する（spec.md J6）
  - [ ] `data object Singleton` を singleton かつ equals/hashCode/toString 合成ありとして扱う
  - [ ] anonymous object（`object : Interface { ... }`）を object literal（既存実装済み）と統合する
  - [ ] anonymous object の型を local nominal として推論し、呼び出しスコープ内で有効にする
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-006`
  - **完了条件**: `data object None` が `None == None` → `true`、`None.toString()` → `"None"` を返す


- [ ] CLASS-007: constructor の `init` block と primary constructor property の初期化順序を保証する（spec.md J7）
  - [ ] primary constructor の `val`/`var` パラメータを property として宣言と同時に初期化する
  - [ ] class body 内の property 初期化と `init { }` block の実行を宣言順（上から下）で保証する
  - [ ] secondary constructor が `this(...)` で primary を必ず委譲（または `super(...)` 委譲）することを検証する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CLASS-007`
  - **完了条件**: `class A { val x = f(); init { println(x) }; val y = x + 1 }` が宣言順で初期化される

---


#### 🏠 Properties / Delegates

- [ ] PROP-001: property delegation（`by`）を `getValue`/`setValue`/`provideDelegate` operator へ fully desugar する（spec.md J7/J9/J12）
  - [ ] Parser/AST で `val x by delegate` 構文を `PropertyDecl.delegateExpr` として保持する
  - [ ] Sema で delegate 型の `getValue`/`setValue` operator 候補を overload resolver に通し、型を推論する
  - [ ] `provideDelegate` が定義されている場合は初期化時に呼び出しを挿入する
  - [ ] PropertyLowering で `val x by d` を `private val _x = d.provideDelegate(...)`, `get() = _x.getValue(...)` へ展開する
  - [ ] `by lazy { }` / `by observable(...)` / カスタム delegate の diff/golden ケースを追加する
  - **完了条件**: `val x by lazy { 42 }` が遅延初期化として動作し、`kotlinc` と同一出力になる


- [ ] PROP-002: `lazy` / `observable` / `vetoable` 標準 delegates を stdlib stub として接続する（spec.md J7）
  - [ ] runtime/stdlib stub に `kotlin.properties.Lazy<T>` / `ReadWriteProperty<T, V>` の C ABI インターフェースを追加する
  - [ ] `lazy { }` の thread-safety モード（`SYNCHRONIZED` / `NONE`）を compiler option で選択できるようにする
  - [ ] `observable` / `vetoable` を callback 付き delegate として lowering 経路に接続する
  - [ ] stdlib delegate を使った diff/golden ケース（`lazy`/`observable`）を追加する
  - **完了条件**: `by lazy`・`by Delegates.observable` が機能し、初期化・callback の順序が `kotlinc` と一致する


- [ ] PROP-003: computed property（getter-only）の backing field なし合成を完成させる（spec.md J7/J12）
  - [ ] PropertyLowering で `val x: Int get() = expr` 形式をバッキングフィールドなしの getter 呼び出しに lowering する
  - [ ] `var` property の custom getter/setter を accessor kind 引数なしの直接 call に整理し、`kk_property_access` 依存を解消する
  - [ ] getter-only property が override される場合の vtable slot 割当を確認する
  - [ ] getter/setter 双方にカスタム実装を持つ property の diff/golden ケースを追加する
  - **完了条件**: `val computed: String get() = "hello"` が毎回呼び出され、backing field が生成されないことを codegen で確認できる


- [ ] PROP-004: destructuring declaration（`val (a, b) = pair`）と `componentN` 解決を実装する（spec.md J5/J6/J9）
  - [ ] Parser/AST に `destructuringDecl`（`val (a, b, ...) = expr`）ノードを追加する
  - [ ] Sema で RHS の型から `component1()`〜`componentN()` を overload 解決し、各変数の型を推論する
  - [ ] `data class` の componentN 合成（既存実装済み）と連携し、for ループ内 destructuring（`for ((k, v) in map)`）を展開する
  - [ ] アンダースコア（`val (a, _, c) = triple`）で不要な component を skip する
  - [ ] lambda 引数の destructuring（`pairs.map { (a, b) -> a + b }`）を lambda body で展開する
  - [ ] destructuring の diff/golden ケース（data class・Map.Entry・lambda）を追加する
  - **完了条件**: `val (x, y) = Point(1, 2)` が `component1()`/`component2()` 呼び出しに展開され動作する


- [ ] PROP-005: extension property を型システム・member dispatch に統合する（spec.md J7/J9）
  - [ ] `val String.firstChar: Char get() = this[0]` を extension property シンボルとして Sema に登録する
  - [ ] extension property の `get`/`set` を extension function として ABI lowering する
  - [ ] extension property を import・overload resolver で解決し、member property より低い優先順位を保つ
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task PROP-005`
  - **完了条件**: `val String.firstChar get() = this[0]` が `"hello".firstChar` で `'h'` を返す


- [ ] PROP-006: getter/setter 内で backing field を参照する `field` キーワードを実装する（spec.md J7）
  - [ ] getter/setter body 内で `field` を backing field への参照として Sema で解決する
  - [ ] `field` への代入（setter 内）と読み取り（getter 内）を backing field load/store IR に lowering する
  - [ ] `field` を getter/setter 外で使うと `KSWIFTK-SEMA-FIELD` 診断を出す
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task PROP-006`
  - **完了条件**: `var x: Int = 0; set(v) { field = if (v < 0) 0 else v }` が setter で field に正しく書き込む


- [ ] PROP-007: `provideDelegate` operator と `KProperty<*>` stub を完全連携させる（spec.md J7/J9）
  - [ ] property 初期化時に `provideDelegate(thisRef, property)` を自動呼び出しし、delegate オブジェクトをキャッシュする
  - [ ] `thisRef` 引数（property が属する receiver）と `property` 引数（`KProperty<*>` stub）を lowering で渡す
  - [ ] `KProperty<*>` stub（name/returnType 最小）を metadata 経由で compiler から参照できる形で定義する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task PROP-007`
  - **完了条件**: `operator fun provideDelegate(...)` が property 初期化時に呼ばれ `getValue` が使用される

---


#### 🧩 Functions

- [ ] FUNC-001: tail-recursive 関数（`tailrec fun`）の末尾呼び出し最適化を実装する（spec.md J9）
  - [ ] `tailrec` 修飾子を Sema で認識し、最後の式が self-recursive call であることを検証する
  - [ ] tail call が満たされない場合に `KSWIFTK-SEMA-TAILREC` warning を出す
  - [ ] KIR/Lowering で `tailrec fun` をループ（label jump）へ変換し、スタック消費を抑制する
  - [ ] 深い再帰が tailrec により StackOverflow を起こさないことを E2E テストで確認する
  - **完了条件**: `tailrec fun fact(n: Int, acc: Int = 1): Int` が 100000 段の再帰で StackOverflow しない


- [ ] FUNC-002: infix 関数宣言（`infix fun`）の構文と解決を実装する（spec.md J9）
  - [ ] `infix fun T.foo(arg: Type)` を parser/AST で infix function として保持する
  - [ ] `a foo b` 形式の中置呼び出しを Sema で receiver + infix function 呼び出しへ解決する
  - [x] infix 関数の優先順位を通常関数呼び出しより低く、`||`/`&&` より高く設定する（EXPR-002 連携）
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task FUNC-002`
  - **完了条件**: `1 to "one"` が `Pair(1, "one")` に、カスタム infix 関数が正しい優先順位で評価される


- [ ] FUNC-003: function type / lambda の `it`・型省略・destructuring を完全実装する（spec.md J9/J12）
  - [ ] 単一引数 lambda の暗黙引数（`it`）を Sema でスコープに束縛する
  - [ ] lambda パラメータの型が context から推論される場合（`list.map { it + 1 }`）に型注釈を省略できる
  - [ ] lambda パラメータを `(a, b)` 形式で destructuring する（PROP-004 連携）
  - [ ] trailing lambda 構文（`foo(1) { it * 2 }`）を parser で正しく扱う（既存実装済み 連携）
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task FUNC-003`
  - **完了条件**: `listOf(1,2,3).map { it * 2 }` / `pairs.map { (a,b) -> a + b }` が `kotlinc` と一致

---


#### 🧬 Generics

- [ ] GEN-001: 複数 upper bound（`where T : A, T : B`）と F-bound（`T : Comparable<T>`）を完全実装する（spec.md J8）
  - [ ] `where` 句の複数 upper bound を `TypeParamDecl` に保持し、overload 解決で全境界を検証する
  - [ ] `T : Comparable<T>` のような自己参照 upper bound（F-bound）を循環検出せずに解決する
  - [ ] 複数 upper bound に違反する型引数に `KSWIFTK-SEMA-BOUND` 診断を出す
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task GEN-001`
  - **完了条件**: `fun <T> max(a: T, b: T): T where T : Comparable<T>` が `max(1, 2)` / `max("a", "b")` で動作する


- [ ] GEN-002: variance（`out T`/`in T`）の declaration-site 制約違反診断を実装する（spec.md J8）
  - [ ] `class Box<out T>` で `in` 位置（関数引数）に `T` が登場したら `KSWIFTK-SEMA-VARIANCE` を出す
  - [ ] `class Sink<in T>` で `out` 位置（戻り値）に `T` が登場したら診断する
  - [ ] private member は variance チェックの例外となる規則（Kotlin 仕様）を実装する
  - [ ] contravariance の subtype 逆転（`Consumer<in Number>` に `IntConsumer` を代入不可）を型システムに反映する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task GEN-002`
  - **完了条件**: `class Producer<out T>(val value: T)` は OK、`fun set(v: T) {}` 追加は `KSWIFTK-SEMA-VARIANCE` になる


- [ ] GEN-003: `reified` inline 関数での `T::class` / `typeOf<T>()` を完全実装する（spec.md J12.2）
  - [ ] `reified T` の inline body 内で `T::class`・`typeOf<T>()` が有効になるよう lowering する
  - [ ] `typeOf<T>()` を runtime 型トークン（`KClass` stub）へ lowering し、`simpleName`・`qualifiedName` を実装する
  - [ ] non-inline 文脈で `T::class`（non-reified）を使った場合に `KSWIFTK-SEMA-REIFIED` 診断を出す
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task GEN-003`
  - **完了条件**: `inline fun <reified T> typeNameOf() = T::class.simpleName` が正しい型名を返す


- [ ] GEN-004: generic lambda と SAM conversion（functional interface）を実装する（spec.md J8/J12）
  - [ ] `fun interface` キーワードを Sema で認識し、SAM conversion の対象と判定する
  - [ ] lambda を SAM 型（`Runnable`・カスタム functional interface）へ暗黙変換する
  - [ ] SAM conversion 後の型推論と overload 解決への影響を実装する
  - [ ] SAM lambda が `invoke` 経由で呼ばれることと、object キャッシュを確認する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task GEN-004`
  - **完了条件**: `fun interface Action { fun run() }; val a: Action = { println("hi") }; a.run()` が動作する

---


#### 🛡️ Null Safety

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


- [ ] NULL-003: nullable な型引数（`List<String?>`）と non-null 型引数（`List<String>`）の区別を実装する（spec.md J8）
  - [ ] `List<String?>` と `List<String>` を異なる型として扱い代入を制限する
  - [ ] `T` が `String?` にバインドされる場合と `String` にバインドされる場合を overload 解決で区別する
  - [ ] nullable 型引数を持つ generic type の `get()`/`set()` 呼び出し型を正しく推論する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task NULL-003`
  - **完了条件**: `val list: List<String?> = listOf("a", null)` の `list[1]` が `String?` 型になる

---


### Wave 3: Coroutine/Stdlib/Annotation/Tooling/MPP

#### ⚡ Coroutines

- [ ] CORO-001: structured concurrency（`CoroutineScope` / `cancel` / `Job`）の runtime C ABI を整備する（spec.md J17）
  - [ ] runtime に `kk_coroutine_scope_new` / `kk_coroutine_scope_cancel` / `kk_job_join` を追加する
  - [ ] `coroutineScope { }` ブロックの開始・終了・cancel 伝播を lowering で生成する
  - [ ] `launch` / `async` で生成した `Job` / `Deferred<T>` の lifecycle を parent scope へ登録する
  - [ ] `cancel` 呼び出し後に子 coroutine が `CancellationException` を受け取る E2E ケースを追加する
  - **完了条件**: `coroutineScope { launch { delay(100) } }` が scope 終了後に全子 coroutine の完了を待ち、cancel が子へ伝播する

---


- [ ] CORO-002: coroutine cancellation と `CancellationException` の伝播を実装する（spec.md J17）
  - [ ] cancellation を suspension point で確認するチェックを各 `kk_coroutine_*` helper に追加する
  - [ ] `job.cancel()` 呼び出し後に子 coroutine が次の suspension point で `CancellationException` を受け取る
  - [ ] `CancellationException` は silent re-throw（catch で再 throw）する規則を Sema/runtime に反映する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task CORO-002`
  - **完了条件**: `launch { while(true) delay(10) }.cancel()` が coroutine を停止し `CancellationException` が伝播する

---


#### 📦 Stdlib / DSL

- [ ] STDLIB-001: `Array<T>` / `List<T>` / `Map<K,V>` のリテラル（`listOf`/`mapOf`/`arrayOf`）を stdlib stub で最小実装する（spec.md J15）
  - [ ] runtime/stdlib stub に `kk_list_of` / `kk_map_of` / `kk_array_of` の C ABI 関数を追加する
  - [ ] `listOf(...)` / `mapOf(...)` / `arrayOf(...)` を上記 ABI に lowering する compiler-side shim を実装する
  - [ ] `List<T>` / `Map<K, V>` の `size`・`get`・`contains`・`iterator` を stub で実装する
  - [ ] `for (x in list)` が stub 実装の `iterator()` 経由で動作することを確認する
  - [ ] `listOf`/`mapOf`/`arrayOf` を含む diff/golden ケースを追加する
  - **完了条件**: `listOf(1, 2, 3).size` / `for (x in listOf(...))` が `kotlinc` と同一出力になる


- [ ] STDLIB-002: `buildString`/`buildList`/`buildMap` DSL builder を実装する（spec.md J9/J12）
  - [ ] `buildString { append("a"); append("b") }` を `StringBuilder` ベースの DSL として実装する
  - [ ] `buildList { add(1); add(2) }` を mutable list builder として実装する
  - [ ] builder lambda の receiver (`StringBuilder`/`MutableList`) を Sema で `this` として束縛する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task STDLIB-002`
  - **完了条件**: `buildString { append("hello "); append("world") }` が `"hello world"` を返す


- [ ] STDLIB-003: `Sequence<T>` と lazy evaluation chain（`asSequence`/`map`/`filter`/`toList`）を実装する
  - [ ] `Sequence<T>` を lazy iterator-based collection として runtime stub に定義する
  - [ ] `asSequence()`・`map`・`filter`・`take`・`toList()` を Sequence extension stub として実装する
  - [ ] Sequence は terminal operation（`toList()` 等）まで評価しない lazy semantics を保証する
  - [ ] `sequence { yield(x) }` builder を coroutine-based lazy generator として stub 実装する
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task STDLIB-003`
  - **完了条件**: `listOf(1,2,3).asSequence().map { it*2 }.filter { it>2 }.toList()` が `[4, 6]` を返す

---


#### 🏷️ Annotations

- [ ] ANNO-001: `@Suppress` / `@Deprecated` / `@JvmStatic` など built-in アノテーションの特別処理を追加する（spec.md J6）
  - [ ] `@Suppress("UNCHECKED_CAST")` で指定した診断コードを当該 node で抑制する compiler ルールを追加する
  - [ ] `@Deprecated(..., level = ERROR/WARNING)` で呼び出し元に診断を発生させる
  - [ ] `@JvmStatic` on companion member → companion singleton 上の static-like (toplevel) 関数扱いへの lowering を追加する
  - [ ] `@Suppress`/`@Deprecated` の動作を確認する diff/golden ケースを追加する
  - **完了条件**: `@Suppress` が対象診断を抑制し、`@Deprecated(level = ERROR)` が呼び出し元をコンパイルエラーにする

---


#### 🛠️ Diagnostics / Tooling

- [ ] TOOL-001: 診断コードを全 pass で体系化し、LSP 向け出力（location / severity / codeAction）を実装する
  - [ ] 全 Sema/Parse 診断を `KSWIFTK-{PASS}-{CODE}` 規則で列挙し、`DiagnosticRegistry` に集約する
  - [ ] 診断に source location（file / line / column）と severity（error/warning/note）を必ず付与する
  - [ ] JSON 形式（`-Xdiagnostics json`）で診断を出力するオプションを追加し、LSP が消費できるスキーマで出力する
  - [ ] `codeAction`（quick-fix 提案）を診断コードごとに定義し、最低 10 個の quick-fix を実装する
  - [ ] 診断 JSON 出力の golden ケースを追加し、スキーマ変更を検知する
  - **完了条件**: 全診断が `KSWIFTK-*` コードを持ち、JSON 出力が LSP 準拠スキーマで整合し、golden テストが pass する


- [ ] TOOL-002: source-map / DWARF debug info 出力を LLVM C API backend に実装する（spec.md J1/J15）
  - [ ] LLVM C API で `DIBuilder` を使い、source file / compilation unit メタデータを生成する
  - [ ] 関数・変数宣言に対応する `DISubprogram` / `DILocalVariable` を生成し、IR に attach する
  - [ ] 各 KIR instruction の source location（file/line/column）を AST から伝播し、LLVM `DebugLoc` を設定する
  - [ ] `-g` フラグ付きビルドの object file に DWARF section が含まれることを `dwarfdump` / `llvm-dwarfdump` で確認する
  - [ ] debugger（lldb）でステップ実行できる最小 E2E ケースをドキュメント化する
  - **完了条件**: `-g` ビルドの object に DWARF .debug_info が存在し、`lldb` でソース行にブレークポイントが設定できる


#### 🌐 Multiplatform

- [ ] MPP-001: `expect`/`actual` 宣言を parser/sema/metadata で扱う（spec.md J14 / Kotlin MPP）
  - [ ] `expect fun foo()` を abstract-like 宣言として Parser/AST で保持する
  - [ ] `actual fun foo()` を対応する `expect` の実装として Sema でマッチングする
  - [ ] `expect` に対する `actual` が存在しない場合に `KSWIFTK-MPP-UNRESOLVED` を出す
  - [ ] diff/golden ケースを追加する → `bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task MPP-001`
  - **完了条件**: `expect fun platform()` に対する `actual fun platform()` が正しくリンクされ動作する


## 🧪 テストケース一括管理

テストケース生成は `Scripts/test_case_registry.json` をソースオブジェクトとして運用する。

### ワークフロー

```bash
# 特定タスクのテストケースを一括生成
bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --task TYPE-001

# カテゴリ単位で一括生成（例: expressions カテゴリの全テスト）
bash Scripts/generate_test_case.sh --from-registry Scripts/test_case_registry.json --category expressions

# 単体テストの手動生成
bash Scripts/generate_test_case.sh --type golden-sema --name my_test --from-file path/to/template.kt

# golden ファイルの自動更新
UPDATE_GOLDEN=1 swift test --filter GoldenHarnessTests
```

### ファイル構成

| パス | 説明 |
|---|---|
| `Scripts/test_case_registry.json` | 全タスクのテストケース定義（タスク ID・カテゴリ・テンプレートパス） |
| `Scripts/generate_test_case.sh` | テストケース scaffold ジェネレータ |
| `Scripts/test_templates/{lexer,parser,sema,diff}/` | カテゴリ別 Kotlin テンプレート |
| `Tests/CompilerCoreTests/GoldenCases/{Lexer,Parser,Sema}/` | golden テスト（`.kt` + `.golden`） |
| `Scripts/diff_cases/` | diff テスト（`kotlinc` との出力比較） |
