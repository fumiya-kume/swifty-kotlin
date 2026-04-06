# Kotlin Compiler Remaining Tasks

最終更新: 2026-04-07

---

## 運用ルール

- `TODO.md` は未完了タスクを主に管理しつつ、直近で完了した大きめの項目は `[x]` で残してよい。
- タスクIDはカテゴリ接頭辞 (`LEX/TYPE/EXPR/CTRL/DECL/CLASS/PROP/FUNC/GEN/NULL/CORO/STDLIB/ANNO/TOOL/MPP`) + 3桁連番を使用する。
- 完了済みタスクを参照する場合は `[x]` または `既存実装済み` のどちらかで明示する。
- **Kotlin stdlib の公式一次ソース**: 下記「公式 API リファレンス」URL と **Kotlin 2.3.10** の `kotlin-stdlib`（必要なら [sources JAR](https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/2.3.10/kotlin-stdlib-2.3.10-sources.jar)）。言語・ツールチェーンのリリース種別・履歴は JetBrains 公式 [Kotlin release process](https://kotlinlang.org/docs/releases.html) を参照（バージョンアップ時は stdlib API 差分の確認が必要）。
- **残件数の手動集計は行わない**（チェックボックスとギャップ表を正とする）。
- 共通完了条件（全タスク共通）:
  1. `Scripts/diff_kotlinc.sh` が対象ケースで exit 0、stdout 完全一致、stderr の差分がない
  2. golden テストが byte 一致し、更新が必要な場合は理由を task に記録できる
  3. エラーケースでは `KSWIFTK-*` 診断コードが text / json の両形式で観測できる
  4. happy path だけでなく、各項目の末尾エッジケース golden が通過する
  5. 追加した ABI がある場合は `RuntimeABISpec` と `ABIMismatchTests` 系が一致する
  6. 追加・変更した宣言、lowering、runtime、テストの対応関係を task 本文から辿れる

### 完了条件の書き方

各 todo の **完了条件** は、なるべく次の 6 点に分けて書く。

1. **対象範囲**: 何の API / ケースまでをこの task の完了とみなすか
2. **宣言**: Sema / synthetic stub / 型解決で何が見える必要があるか
3. **Lowering**: どの呼び出し形が正しく KIR / lower に落ちる必要があるか
4. **Runtime / ABI**: 新旧 `kk_*` のどこが整合している必要があるか
5. **検証**: diff / golden / runtime test / smoke のどれで確認するか
6. **除外**: この task ではやらない範囲はどこか

---

## Kotlin stdlib（common / Kotlin/Native 相当）

**スコープ**: `kotlin.*` の **common** および **Native で意味のある** API。JVM/JS 専用・JDBC・KSP・`kotlinx.*` 拡張は **本セクションでは追わず**、下記「ターゲット外バックログ」へ。

### 公式 API リファレンス（版固定の参照元）

| 説明 | URL |
|------|-----|
| kotlin-stdlib トップ（パッケージ一覧） | [kotlinlang.org/api/core/kotlin-stdlib/](https://kotlinlang.org/api/core/kotlin-stdlib/) |
| 全シンボル索引 | [all-types.html](https://kotlinlang.org/api/core/kotlin-stdlib/all-types.html) |
| 代表パッケージ | [kotlin](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin/index.html) · [kotlin.collections](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/index.html) · [kotlin.ranges](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.ranges/index.html) · [kotlin.sequences](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.sequences/index.html) · [kotlin.text](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.text/index.html) · [kotlin.io](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.io/index.html) · [kotlin.concurrent](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.concurrent/index.html) · [kotlin.concurrent.atomics](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.concurrent.atomics/index.html) · [kotlin.math](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.math/index.html) · [kotlin.random](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.random/index.html) · [kotlin.reflect](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.reflect/index.html) · [kotlin.time](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.time/index.html) · [kotlin.properties](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.properties/index.html) · [kotlin.coroutines](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.coroutines/index.html) · [kotlin.native](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.native/index.html) |

**公式サイトの説明（要約）**（[kotlin-stdlib Core API トップ](https://kotlinlang.org/api/core/kotlin-stdlib/) より）: 標準ライブラリは、イディオムな高階関数（[`let`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin/let.html)、[`apply`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin/apply.html) 等）、[`use`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.io/use.html) や [`synchronized`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin/synchronized.html) など、コレクション（eager）とシーケンス（lazy）の操作、文字列・文字シーケンス、**および JVM では JDK クラス向け拡張**（ファイル・I/O・スレッド）を含む。KSwiftK は **JDK 拡張ではなく**、common / Native 相当の宣言を母集団とする。

**プラットフォーム表示**: 各パッケージの索引ページでは **Common / JVM / Native / JS / Wasm** などの対応が示される。ギャップ表の「非対象」判定に使う。

### kotlinlang.org/docs（言語ガイド・API と併読）

| 題材 | URL |
|------|-----|
| 委譲プロパティ（`lazy` 等） | [delegated-properties.html](https://kotlinlang.org/docs/delegated-properties.html) |
| 範囲と進行 | [ranges.html](https://kotlinlang.org/docs/ranges.html) |
| リフレクション概要 | [reflection.html](https://kotlinlang.org/docs/reflection.html) |

### 公式 API に列挙されるパッケージ（索引リンク）

[kotlin-stdlib トップ](https://kotlinlang.org/api/core/kotlin-stdlib/) の **Packages** 一覧に対応。抜けがあれば公式ページを正とする。

| パッケージ | 索引 |
|------------|------|
| `kotlin.annotation` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.annotation/index.html) |
| `kotlin.comparisons` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.comparisons/index.html) |
| `kotlin.contracts` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.contracts/index.html)（Experimental） |
| `kotlin.coroutines.cancellation` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.coroutines.cancellation/index.html) |
| `kotlin.coroutines.intrinsics` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.coroutines.intrinsics/index.html) |
| `kotlin.enums` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.enums/index.html) |
| `kotlin.experimental` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.experimental/index.html) |
| `kotlin.io.encoding` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.io.encoding/index.html)（Base64 等） |
| `kotlin.native.concurrent` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.native.concurrent/index.html) |
| `kotlin.native.ref` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.native.ref/index.html) |
| `kotlin.native.runtime` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.native.runtime/index.html) |
| `kotlin.system` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.system/index.html) |
| `kotlin.uuid` | [index.html](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.uuid/index.html) |

**主に JVM / JS / Wasm 向け（KSwiftK では通常「非対象」）**: [`kotlin.io.path`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.io.path/index.html)（`java.nio.file.Path`）, [`kotlin.js`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.js/index.html), [`kotlin.jvm`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.jvm/index.html), [`kotlin.jvm.optionals`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.jvm.optionals/index.html), [`kotlin.streams`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.streams/index.html), [`kotlin.wasm`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.wasm/index.html), [`kotlin.wasm.unsafe`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.wasm.unsafe/index.html), [`org.w3c.dom`](https://kotlinlang.org/api/core/kotlin-stdlib/org.w3c.dom/index.html) ほか。

**Kotlin/Native 専用・C 相互運用（stdlib 索引上は別枠）**: [`kotlinx.cinterop`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlinx.cinterop/index.html)（Experimental）, [`kotlinx.cinterop.internal`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlinx.cinterop.internal/index.html) — ランタイム ABI とは別計画でよい。

### 完了の定義（3 層）

KSwiftK は公式 JVM jar と 1:1 ではない（独自 `kk_*` ABI）。次で測る。

| レイヤ | 内容 | 根拠 |
|--------|------|------|
| **A** | common（+ 追う Native）の宣言がコンパイル・実行可能、または未対応なら `KSWIFTK-*` | 上記 API ドキュメント |
| **B** | 合成スタブ・Lowering が呼び出しを正しく下ろす | `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift`, `StdlibFunctionLowerer.swift`, `CallLowerer+*.swift` |
| **C** | `RuntimeABISpec` の `kk_*` が実装され ABI テストと整合 | `Sources/RuntimeABI/RuntimeABISpec*.swift`, `Sources/Runtime/*.swift`, `Tests/RuntimeTests/ABIMismatchTests.swift` |

`RuntimeABISpec.specVersion` は [`Sources/RuntimeABI/RuntimeABISpec.swift`](Sources/RuntimeABI/RuntimeABISpec.swift) 内。ユニークな `section` 名は `rg 'section: "' Sources/RuntimeABI/RuntimeABISpec*.swift` で抽出可能。

### パッケージ単位チェックリスト（骨子）

ギャップ表（下）と併せて埋める。公式の全パッケージ一覧は上表。**達成度の細部はギャップ表の列を正とする**（チェックリストは「最終的に全部チェック」用の目安）。

- [ ] `kotlin`
- [ ] `kotlin.annotation`
- [ ] `kotlin.collections` / `kotlin.sequences`
- [ ] `kotlin.comparisons`
- [ ] `kotlin.ranges`
- [ ] `kotlin.text`（+ `Char`）
- [ ] `kotlin.io`（common のみ）
- [ ] `kotlin.io.encoding`（Base64 等; 公式ページで対応プラットフォームを確認）
- [ ] `kotlin.math` / `kotlin.random`
- [ ] `kotlin.concurrent` / `kotlin.concurrent.atomics`
- [ ] `kotlin.reflect`
- [ ] `kotlin.time`
- [ ] `kotlin.properties`（デリゲート）
- [ ] `kotlin.coroutines` / `kotlin.coroutines.cancellation` / `kotlin.coroutines.intrinsics`（言語・stdlib プリミティブ; **`kotlinx.coroutines` ライブラリはターゲット外**）
- [ ] `kotlin.enums`
- [ ] `kotlin.system`
- [ ] `kotlin.uuid`
- [ ] `kotlin.native` / `kotlin.native.concurrent` / `kotlin.native.ref` / `kotlin.native.runtime`
- [ ] `kotlin.contracts`（Experimental）
- [ ] `kotlin.experimental`（Experimental マーカー群）

### ギャップ表（マトリクス）

**記号（各列）**: `○`＝実装・網羅性は高い / `△`＝一部のみ・公式 stdlib 全体とは距離あり / `×`＝未または極小 / `―`＝対象外（KSwiftK のスコープに含めない）

| 公式 API / エリア | Sema | Lowering | Runtime `kk_*` | テスト | 状態 |
|-------------------|------|----------|----------------|--------|------|
| `kotlin`（スコープ関数 `let`/`apply`/`run`/`with`/`also`、`takeIf` 等） | ○ 合成スタブ | ○ 主にインライン展開 | △ 多くはインライン | `string_hof.kt`, `lambda_with_receiver.kt` 等 | **部分** |
| `kotlin`（`synchronized` / 比較・演算子基盤） | ○ | ○ | ○ `kk_synchronized` 等 | diff 多数 | **部分** |
| `kotlin.collections` / 可変コレクション | ○ | ○ | ○ `RuntimeCollections` / `Collection` 系 | `map_basic.kt`, `set_basic.kt`, `list_*` 等 | **部分** |
| `kotlin.sequences` | ○ | ○ | ○ `RuntimeSequence` | `sequence_*.kt`, `flatten_*.kt` | **部分** |
| `kotlin.ranges` / `UInt`/`ULong` 進行 | ○ | ○ | ○ Range 系 | `range_basic.kt`, `progression.kt`, `uint_range.kt` | **部分** |
| `kotlin.text` / `Char` / 文字列 | ○ | ○ | ○ String 大量 | `string_*.kt`, `char_operations.kt` | **部分** |
| `kotlin.text`（正規表現 `Regex`） | ○ | ○ | ○ `kk_regex_*` | `regex_*.kt` | **部分** |
| `kotlin.io`（common: ファイル・ストリーム） | ○ 合成 | ○ | ○ `RuntimeFileIO` | `file_*.kt`, `buffered_io.kt` | **部分** |
| `kotlin.io.encoding`（Base64 等） | ×〜△ | ×〜△ | ×（専用 `kk_*` 未定義） | `hexformat_basic.kt` 等は別系 | **未** |
| `kotlin.math` | ○ | ○ | ○ `RuntimeMath` | `math_*.kt` | **部分** |
| `kotlin.random` | ○ | ○ | ○ `RuntimeRandom` | `random_extended.kt`, `secure_random.kt` | **部分** |
| `kotlin.concurrent` / `synchronized` 周辺 | ○ | ○ | ○ | `mutex_basic.kt`, `semaphore_basic.kt` 等 | **部分** |
| `kotlin.concurrent.atomics` | ○ | ○ | ○ `RuntimeAtomic` | `atomic_basic.kt`, `experimental_atomic.kt` | **部分** |
| `kotlin.reflect`（`KClass`/`KType`/メンバ） | ○ | ○ | ○ `RuntimeReflection` | `type_reflection.kt`, `kclass_*.kt` | **部分**（全面ではない） |
| `kotlin.time` / `Duration` / `Instant` | ○ | ○ | ○ `RuntimeDuration`/`Instant`/`Time` | `duration_operations.kt`, `instant_basic.kt`, `clock_basic.kt` | **部分** |
| `kotlin.time`（`@ExperimentalTime` 高度 API） | △ | △ | △ | `experimental_time.kt` | **部分** |
| `kotlin.properties`（`lazy`/observable/vetoable 等） | ○ | ○ `StdlibDelegateLoweringPass` | ○ delegate box | `delegate_operators.kt` 等 | **部分** |
| `kotlin.coroutines`（`Continuation`/suspend 基盤） | ○ | ○ | ○ `RuntimeCoroutine` | `suspend_functions.kt` 等 | **部分** |
| `kotlin.coroutines.cancellation` | ○ | ○ | ○ | `coroutine_cancellation.kt` | **部分** |
| `kotlin.coroutines.intrinsics` | △（コンパイラ内部寄り） | ○ | △ | 主に内部・回帰 | **部分** |
| `kotlin.annotation` | ○ | ○ | △ | `annotation_basic.kt`, `native_annotations.kt` | **部分** |
| `kotlin.comparisons` / `Comparator` | ○ | ○ | ○ | `comparator_basic.kt`, `compare_values.kt` | **部分** |
| `kotlin.enums` / enum ユーティリティ | ○ | ○ | △ | `enum_basic.kt`, `enum_edge_cases.kt` | **部分** |
| `kotlin.contracts` | ○（効果モデル） | △ | ― | 主にセマ | **部分** |
| `kotlin.experimental`（マーカー） | △ | △ | ― | 個別機能に依存 | **部分** |
| `kotlin.system`（`measureTimeMillis` 等） | ○ | ○ | ○ | `measure_time.kt`, `system_current_time_millis.kt` | **部分** |
| `kotlin.uuid` | ○ | ○ | ○ | `uuid_basic.kt` | **部分** |
| `kotlin.native`（プラットフォーム情報等） | ○ | ○ | ○ | `platform_info.kt`, `kmp_common.kt` | **部分** |
| `kotlin.native.concurrent` | △ | △ | △ | `experimental_atomic.kt` 等と重複あり | **部分** |
| `kotlin.native.ref` / `kotlin.native.runtime` | △ | × | △ | 限定的 | **未〜部分** |
| `kotlin.jvm` / `kotlin.js` / `kotlin.streams` / `kotlin.io.path` | ― | ― | ― | ― | **非対象** |
| `kotlinx.cinterop`（C/ObjC 相互運用） | ― | ― | ― | ― | **非対象**（別計画） |

**状態の読み方**: **部分**＝実装・テストはあるが公式 stdlib の宣言集合を網羅していない。**未**＝ギャップが大きい。**非対象**＝ macOS ネイティブ LLVM ターゲットの stdlib 互換ロードマップに含めない。

Phase タスク（`STDLIB-GAP-PH*`）は、上表で **△ / × / 未〜部分** の行を優先して潰す。

Phase は **依存関係**順（難易度ではない）。

### Phase 1: プリミティブ・演算子・配列・String コア

- [ ] STDLIB-GAP-PH1: ギャップ表で `kotlin` / `kotlin.text` / `Array` 周辺の **未** を潰す
  - **完了条件**:
    - Phase 1 配下の `STDLIB-002` 〜 `STDLIB-005` がすべて完了している
    - ギャップ表の対象行について、少なくとも `×` が残らず、未対応分は `KSWIFTK-*` で明示的に落ちる
    - 追加した diff/golden ケースがこの Phase の責務であると追跡できる

- [ ] STDLIB-002: スコープ関数 (`let` / `run` / `with` / `apply` / `also` / `takeIf` / `takeUnless`) の境界条件を詰める
  - **A**: nullability・receiver あり/なし・ラムダ戻り値・ネスト時の解決順を公式 API に合わせる
  - **B**: `StdlibFunctionLowerer.swift` / call lowering で inline 展開時の receiver 評価順と副作用 1 回性を固定する
  - **C**: inline で落とせない経路がある場合に備え、必要な `kk_*` フォールバック有無を明示する
  - **テスト**: `Scripts/diff_cases/scope_functions.kt`, `takeif_takeunless.kt`, `takeif_takeunless_advanced.kt`, `lambda_with_receiver.kt`
  - **完了条件**:
    - 対象 API について receiver が 1 回だけ評価されるケースを diff で確認できる
    - nullable receiver, nested call, labeled return を含む少なくとも 1 件ずつのケースがある
    - inline 展開で処理する API と runtime fallback に逃がす API の境界がコード上で明確である
    - 未対応 overload があるなら `TODO.md` に残タスクとして分離されている

- [ ] STDLIB-003: `Char` 系 API の未整備領域を埋める
  - **A**: `isDigit` / `isLetter` / `digitToInt` / case conversion / escape 表現の宣言と診断を整合させる
  - **B**: [`HeaderHelpers+SyntheticCharStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticCharStubs.swift) の `CharCategory` / `CharDirectionality` TODO を解消する
  - **C**: [`RuntimeStringArray.swift`](Sources/Runtime/RuntimeStringArray.swift) と `RuntimeChar` 系の ABI 公開面を `RuntimeABISpec` と照合する
  - **テスト**: `Scripts/diff_cases/char_operations.kt`, `char_predicates.kt`, `char_digit_to_int.kt`, `char_case.kt`, `char_escape.kt`, `char_int_conversion.kt`, `char_arithmetic.kt`
  - **完了条件**:
    - `CharCategory` / `CharDirectionality` の扱いが stub TODO ではなく明示実装または明示非対応になっている
    - 正常系に加えて invalid radix / invalid char の失敗系が診断または例外として固定されている
    - `Char` API 追加分が `RuntimeABISpec` と runtime tests の両方で追えている

- [ ] STDLIB-004: `Array` / primitive array の生成・変換・インデックス境界を整理する
  - **A**: `arrayOf` / コンストラクタ / primitive array / 変換 API の宣言網羅を確認する
  - **B**: 配列 special-case lowering と vararg 展開の整合を確認する
  - **C**: `kk_array_*` の in-bounds / out-of-bounds / boxing 経路を ABI テストと揃える
  - **テスト**: `Scripts/diff_cases/array_of.kt`, `array_constructor.kt`, `array_conversions.kt`, `array_primitive_types.kt`, `array_index.kt`, `test_empty_array.kt`
  - **完了条件**:
    - 空配列、単要素、多要素、primitive array、boxing を少なくとも 1 件ずつ diff で通す
    - out-of-bounds と type safety の失敗ケースが golden または runtime test で固定される
    - vararg 展開と array constructor の lowering 差分が回帰しない形でテスト化されている

- [ ] STDLIB-005: `kotlin.text` の文字列変換・分割・置換の端ケースを揃える
  - **A**: `lines` / `lineSequence` / `substringBefore*` / `replaceFirstChar` / encoding 変換の common 範囲を確認する
  - **B**: lowering で String intrinsic と通常 call の分岐があれば差分を洗う
  - **C**: 既存 `RuntimeStringArray` 実装の例外メッセージと `KSWIFTK-*` 診断の責務境界を明確にする
  - **テスト**: `Scripts/diff_cases/string_lines.kt`, `string_linesequence.kt`, `string_linesequence_lazy.kt`, `string_substring_before_after.kt`, `string_replace_first_char.kt`, `string_replace_first_range.kt`, `string_encode_charset.kt`, `string_tobytearray_charset.kt`, `bytearray_decode_charset.kt`
  - **完了条件**:
    - eager (`lines`) と lazy (`lineSequence`) の違いが観測できるケースを保持する
    - 空文字列、区切り未存在、先頭/末尾一致、非 ASCII 文字列を含むケースを最低 1 件ずつ持つ
    - encoding 変換で成功系と失敗系の責務が runtime exception か compile diagnostics か整理されている

### Phase 2: コレクション・Sequence・Range

- [ ] STDLIB-GAP-PH2: ギャップ表で `kotlin.collections` / `kotlin.sequences` / `kotlin.ranges` の **未** を潰す
  - **完了条件**:
    - Phase 2 配下の `STDLIB-020` 〜 `STDLIB-023` がすべて完了している
    - collection / sequence / range の各行で、未対応がある場合は残 task が個別に切られている
    - lazy 性、mutation、境界条件の 3 軸で回帰テストがある

- [ ] STDLIB-020: `Sequence` の lazy 性と builder 系 API の評価順を固定する
  - **A**: `sequenceOf` / `generateSequence` / `yield` / `yieldAll` / iterator builder の宣言差分を洗う
  - **B**: `CollectionLiteralLoweringPass` と sequence lowering の plus/minus・builder rewrite の重複 TODO を解消する
  - **C**: [`RuntimeSequence.swift`](Sources/Runtime/RuntimeSequence.swift) の iterator 例外・invalid handle・Pair/Map 変換経路を ABI 仕様に合わせる
  - **テスト**: `Scripts/diff_cases/sequence_lazy.kt`, `sequence_lazy_eval.kt`, `sequence_of_generate.kt`, `sequence_takewhile_dropwhile.kt`, `sequence_drop_distinct_zip.kt`, `sequence_fold_reduce_indexed.kt`, `sequence_forEach_flatMap.kt`, `sequence_join_to_string.kt`
  - **完了条件**:
    - lazy evaluation が副作用カウンタなどで可視化されたケースを最低 2 件持つ
    - builder (`yield` / `yieldAll`) と generator (`generateSequence`) の両系統がカバーされる
    - plus/minus rewrite の重複 TODO が消えているか、残すなら独立 task になっている
    - iterator の失敗系が runtime tests で拘束されている

- [ ] STDLIB-021: mutable collection 変換 API と destination variant の差分を潰す
  - **A**: `associate*` / `zip` / `unzip` / `binarySearch` / `shuffle` / `sort` / `putAll` / `removeAll` / `retainAll` を公式宣言と突き合わせる
  - **B**: collection helper lowering の overload 解決と comparator 伝播を確認する
  - **C**: [`RuntimeCollections.swift`](Sources/Runtime/RuntimeCollections.swift) の mutation 後整合性・順序保証・比較器保持を点検する
  - **テスト**: `Scripts/diff_cases/list_associate_by.kt`, `list_associate_with.kt`, `list_zip.kt`, `list_unzip.kt`, `list_binary_search.kt`, `mutable_list_sort.kt`, `mutable_list_shuffle_reverse.kt`, `mutable_map_putall.kt`, `mutable_set_removeall_retainall.kt`
  - **完了条件**:
    - 破壊的更新 API と非破壊 API を取り違えていないことを diff で確認する
    - 順序保証が重要な API で LinkedHash 系の期待順序をテスト化する
    - comparator あり/なし両方の経路が最低 1 件ずつある

- [ ] STDLIB-022: range / progression / unsigned range の網羅性を上げる
  - **A**: `until` / `downTo` / `step` / `coerce*` / `UIntRange` / `ULongRange` / empty progression を整理する
  - **B**: range lowering と compare/intrinsic 展開が signed/unsigned で一貫するようにする
  - **C**: Range 系 `kk_*` の invalid handle panic とユーザー向け診断の境界を見直す
  - **テスト**: `Scripts/diff_cases/range_basic.kt`, `range_properties.kt`, `long_range.kt`, `unsigned_integers.kt`, `coercein.kt`, `coerce_long.kt`, `numeric_coercion.kt`
  - **完了条件**:
    - increasing / decreasing / empty progression をそれぞれ最低 1 件持つ
    - signed / unsigned で同名 API を使うケースを並べて差分確認できる
    - `coerce*` は境界内、下限超過、上限超過をすべて持つ

- [ ] STDLIB-023: `kotlin.enums` の `entries` / `enumEntries<T>()` 周辺を固める
  - **A**: `EnumEntries` / `enumValues<T>()` / `enumValueOf<T>()` の宣言と inline reified 制約を確認する
  - **B**: [`HeaderHelpers+SyntheticEnumStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticEnumStubs.swift) と lowering で generic helper が正しく選ばれるようにする
  - **C**: ランタイム側で `name` / `ordinal` / `entries` の安定順序を保証する
  - **テスト**: `Scripts/diff_cases/enum_basic.kt`, `enum_entries.kt`, `enum_entries_function.kt`, `enum_values.kt`, `enum_value_of.kt`, `enum_name_ordinal.kt`, `enum_edge_cases.kt`, `enum_init_order.kt`
  - **完了条件**:
    - `entries`, `enumValues<T>()`, `enumValueOf<T>()` の 3 系統がすべて通る
    - invalid name の失敗系と初期化順序が golden または diff で固定される
    - enum helper の generic / reified 解決が sema 側でも確認できる

### Phase 3: I/O・パス・時間・並行（common 範囲）

- [ ] STDLIB-GAP-PH3: ギャップ表で `kotlin.io`（common）, `kotlin.time`, `kotlin.concurrent` / atomics の **未** を潰す（実装照合: [`RuntimeFileIO.swift`](Sources/Runtime/RuntimeFileIO.swift) 等）
  - **完了条件**:
    - Phase 3 配下の `STDLIB-030` 〜 `STDLIB-033` がすべて完了している
    - file/time/concurrency それぞれで happy path と failure path の両方がある
    - ABI 追加がある場合は `RuntimeABISpec.specVersion` 更新要否を判断済みである

- [ ] STDLIB-030: `kotlin.io` common 範囲の file / buffered / `use` を仕様単位で締める
  - **A**: common と Native で意味のある `File`, buffered reader/writer, temp file/dir, `use` の対象 API を棚卸しする
  - **B**: [`HeaderHelpers+SyntheticTODOAndIOStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticTODOAndIOStubs.swift) と [`HeaderHelpers+SyntheticFileIOStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticFileIOStubs.swift) の宣言を実装と一致させる
  - **C**: [`RuntimeFileIO.swift`](Sources/Runtime/RuntimeFileIO.swift) の close 保障、例外経路、テンポラリ生成、存在確認 API を ABI テストで拘束する
  - **テスト**: `Scripts/diff_cases/file_basic.kt`, `file_exists.kt`, `file_props.kt`, `file_walk.kt`, `buffered_io.kt`, `closeable_use.kt`
  - **完了条件**:
    - open/read/write/close/use の主要ライフサイクルが一連で通る
    - close 時例外、存在しないパス、テンポラリ生成、walk の少なくとも 1 件ずつがある
    - resource leak を防ぐ観点で `use` の正常系と例外系が固定されている

- [ ] STDLIB-031: `kotlin.io.encoding`（Base64 / `HexFormat`）を独立に前進させる
  - **A**: 公式 API の common / Native 対応範囲を確認し、対象宣言を `TODO.md` 上で明文化する
  - **B**: 合成スタブ未整備なら専用 `Synthetic*` 追加、既存 string/bytearray helper で賄うならその方針を固定する
  - **C**: 専用 `kk_*` を導入するか既存 ABI を再利用するか決め、`RuntimeABISpec` で section を起こす
  - **テスト**: `Scripts/diff_cases/hexformat_basic.kt`, `string_encode_charset.kt`, `bytearray_decode_charset.kt`
  - **完了条件**:
    - Base64 と `HexFormat` のどちらをこの task の対象に含めるかを本文に明記する
    - encode/decode の往復成功ケースと不正入力失敗ケースを最低 1 件ずつ持つ
    - 専用 ABI を増やした場合は section 名と parity test が追加される

- [ ] STDLIB-032: `kotlin.time` の stable API と experimental API の境界を整理する
  - **A**: `Duration`, `Instant`, `measureTime*`, `Clock.System`, `TimeSource`, `TimeMark` のどこまでを stable 扱いで追うか確定する
  - **B**: [`HeaderHelpers+SyntheticExperimentalTimeStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticExperimentalTimeStubs.swift) / [`HeaderHelpers+SyntheticPlatformTimeConversionStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPlatformTimeConversionStubs.swift) の生成宣言を監査する
  - **C**: [`RuntimeDuration.swift`](Sources/Runtime/RuntimeDuration.swift), [`RuntimeInstant.swift`](Sources/Runtime/RuntimeInstant.swift), [`RuntimeTime.swift`](Sources/Runtime/RuntimeTime.swift) の ABI と invalid handle 振る舞いを揃える
  - **テスト**: `Scripts/diff_cases/measure_time.kt`, `measure_timed_value.kt`, `measure_time_duration.kt`, `duration_long_factory.kt`, `instant_basic.kt`, `clock_basic.kt`, `experimental_time.kt`, `platform_time_conversion.kt`, `system_nano_time.kt`
  - **完了条件**:
    - stable 範囲と experimental 範囲が task 内で明文化され、未対応が混在しない
    - `Duration`, `Instant`, `measureTime*` の 3 系統に最低 1 件ずつの diff または runtime test がある
    - invalid handle / overflow / negative duration などの境界が runtime tests で固定される

- [ ] STDLIB-033: `kotlin.concurrent` / `kotlin.concurrent.atomics` / Native concurrent の parity を上げる
  - **A**: `synchronized`, `Atomic*`, `AtomicReference`, experimental/native concurrent の対象 API を切り分ける
  - **B**: sema / lowering で typealias・generic atomics・cancellation 連携が破綻しないことを確認する
  - **C**: [`RuntimeAtomic.swift`](Sources/Runtime/RuntimeAtomic.swift) と coroutine state runtime の例外・CAS・update 系整合を詰める
  - **テスト**: `Scripts/diff_cases/atomic_basic.kt`, `experimental_atomic.kt`, `mutex_basic.kt`, `coroutine_cancellation.kt`
  - **完了条件**:
    - scalar atomics と `AtomicReference` 系が別ケースで確認できる
    - CAS / exchange / updateAndGet / getAndUpdate の主要更新 API が少なくとも 1 回ずつ使われる
    - cancellation と atomics の組み合わせで回帰しないことを runtime or diff で確認する

### Phase 4: リフレクション・数値・テキスト・その他 stdlib

- [ ] STDLIB-GAP-PH4: ギャップ表で `kotlin.math` / `kotlin.random` / `kotlin.reflect` / `kotlin.comparisons` / `kotlin.annotation` / `kotlin.system` / `kotlin.uuid` / `kotlin.native` 周辺の **部分** を潰す
  - **完了条件**:
    - Phase 4 配下の未完了 `STDLIB-*` がすべて完了している
    - ギャップ表の Phase 4 対象行について、「部分」の理由が task 本文で説明できるか、もしくは `○` まで引き上がっている
    - Phase 1〜4 完了時点で、対象スコープ内の未対応は独立 task か `KSWIFTK-*` 診断として追跡できる

- [x] STDLIB-REFLECT-066: 型リフレクション（`KType` / `KTypeProjection` 等）
  - **関連**: [`RuntimeReflection.swift`](Sources/Runtime/RuntimeReflection.swift), `Scripts/diff_cases/type_reflection.kt`
- [ ] STDLIB-REFLECT-067: `KClass` / metadata / メンバ introspection の残差を詰める
  - **A**: `KClass` の kind 判定、qualified name、members、supertype 表現の対象範囲を固める
  - **B**: codegen の reflection metadata emitter と sema で見える synthetic symbol が一致するようにする
  - **C**: [`RuntimeReflection.swift`](Sources/Runtime/RuntimeReflection.swift) と `kk_kclass_*` ABI を runtime metadata tests / ABI parity で拘束する
  - **テスト**: `Scripts/diff_cases/kclass_ktype_basic.kt`, `kclass_type_model.kt`, `type_reflection.kt`
  - **完了条件**:
    - `KType` だけでなく `KClass` 側の主要問い合わせ API が diff または runtime tests で観測できる
    - metadata emitter / decoder / runtime accessor の 3 層が同じ前提で動く
    - unsupported member reflection がある場合は silent failure ではなく task または診断で残る
- [ ] STDLIB-MATH-001: `kotlin.math` の対象 API 一覧を固定する
  - **A**: `abs`, `pow`, `sqrt`, 三角関数、対数、`PI` / `E`、丸め系 overload を対象群ごとに整理する
  - **B**: overload ごとの型 (`Float` / `Double` / 整数系) を task 本文で明文化する
  - **C**: 未対応 API は独立 task か診断方針へ落とす
  - **テスト**: 既存 `math_*.kt` を参照
  - **完了条件**:
    - 定数・単項関数・二項関数・丸め系の 4 群が整理されている
    - 無言欠落が残らない
- [ ] STDLIB-MATH-002: `kotlin.math` の sema / lowering を overload 単位で整える
  - **A**: [`HeaderHelpers+SyntheticMathStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMathStubs.swift) の external link と宣言集合を見直す
  - **B**: lowering で Float/Double/Int/Long の型選択が正しいことを確認する
  - **C**: 未対応 overload は誤った別 overload に落ちないようにする
  - **テスト**: `Scripts/diff_cases/math_float_overloads_edge.kt`, `math_extended.kt`
  - **完了条件**:
    - Float と Double の overload 差分が少なくとも 1 件ずつ見える
    - 誤った overload 解決が golden または diff で回帰しない
- [ ] STDLIB-MATH-003: `kotlin.math` の runtime / ABI と境界値を固定する
  - **A**: [`RuntimeMath.swift`](Sources/Runtime/RuntimeMath.swift) の NaN/Infinity/負値/丸め境界を整理する
  - **B**: 必要な `kk_math_*` ABI と parity を確認する
  - **C**: rounding mode 系の振る舞いを runtime tests で拘束する
  - **テスト**: `Scripts/diff_cases/math_advanced.kt`, `math_rounding_functions.kt`, `math_constants.kt`
  - **完了条件**:
    - NaN / Infinity / 負値 / 境界丸めのケースを含む
    - ABI parity と runtime tests の両方で追える

- [ ] STDLIB-RANDOM-001: `kotlin.random` の対象 API 一覧を固定する
  - **A**: default random、seeded random、範囲指定 API、byte 配列充填、secure random の対象を整理する
  - **B**: object API と instance API の境界を明文化する
  - **C**: 未対応 API は独立 task か診断方針へ落とす
  - **テスト**: 既存 `random_*.kt` を参照
  - **完了条件**:
    - default / seeded / secure の 3 系統が TODO から辿れる
    - 無言欠落が残らない
- [ ] STDLIB-RANDOM-002: `kotlin.random` の sema / lowering を整える
  - **A**: `Random` object と拡張/メンバ呼び出しの解決を固定する
  - **B**: range 引数や overload 選択が誤らないことを確認する
  - **C**: unsupported API は誤って default random へ落ちないようにする
  - **テスト**: `Scripts/diff_cases/random_extended.kt`, `random_seed.kt`
  - **完了条件**:
    - object 呼び出しと instance 呼び出しが別ケースで確認できる
    - 範囲 API の型選択が回帰しない
- [ ] STDLIB-RANDOM-003: `kotlin.random` の runtime / seed / 境界値を固定する
  - **A**: [`RuntimeRandom.swift`](Sources/Runtime/RuntimeRandom.swift) の seed 再現性、範囲境界、secure random フォールバックを整理する
  - **B**: 必要な ABI parity を確認する
  - **C**: 不正引数の失敗系を runtime or diff で固定する
  - **テスト**: `Scripts/diff_cases/random_seed.kt`, `secure_random.kt`, `random_extended.kt`
  - **完了条件**:
    - seeded 経路で再現性があるケースを最低 1 件持つ
    - default random と secure random を別ケースで検証する
    - 範囲境界と不正引数の失敗系を固定する

- [ ] STDLIB-COMP-001: `kotlin.comparisons` helper の対象 API 一覧を固定する
  - **A**: `compareValues`, `compareBy`, `thenBy`, `nullsFirst` / `nullsLast`, `maxBy*` / `minBy*` の対象を整理する
  - **B**: selector 合成 helper と ordering helper を分けて整理する
  - **C**: 未対応 helper は独立 task か診断方針へ落とす
  - **テスト**: 既存 comparator 系 case を参照
  - **完了条件**:
    - helper 群の責務が分かれている
    - 無言欠落が残らない
- [ ] STDLIB-COMP-002: `Comparator` 合成の sema / lowering を整える
  - **A**: comparator 合成が lowering 上で selector 順序を保つことを確認する
  - **B**: null ordering helper が正しく解決されることを確認する
  - **C**: comparator 合成順序が崩れたときに回帰検知できるようにする
  - **テスト**: `Scripts/diff_cases/compareby_multi.kt`, `compare_values.kt`, `comparator_basic.kt`
  - **完了条件**:
    - selector 1 個と複数 selector の両方がある
    - null ordering を伴う比較が少なくとも 1 件ある
- [ ] STDLIB-COMP-003: `Comparator` runtime 表現と failure path を固定する
  - **A**: comparator runtime の multi-selector 表現を整理する
  - **B**: invalid comparator の失敗系を runtime tests で拘束する
  - **C**: max/min helper が comparator と整合することを確認する
  - **テスト**: `Scripts/diff_cases/list_maxby_minby.kt`, `list_max_min_with.kt`, runtime comparator tests
  - **完了条件**:
    - comparator 合成順序が変わると壊れるケースを回帰として保持する
    - failure path が silent failure にならない

- [ ] STDLIB-ANNO-001: `kotlin.annotation` / Native annotation の対象一覧を固定する
  - **A**: annotation target、retention、repeatable / mustBeDocumented、Native 系 marker の対象範囲を整理する
  - **B**: runtime 実装不要な annotation と runtime 露出が必要な annotation を分離する
  - **C**: 未対応 annotation は独立 task か診断方針へ落とす
  - **テスト**: 既存 annotation 系 case を参照
  - **完了条件**:
    - target/retention/Native marker の 3 群が整理されている
    - 無言欠落が残らない
- [ ] STDLIB-ANNO-002: annotation sema / diagnostics を整える
  - **A**: annotation class と use-site / target 制約の診断を整える
  - **B**: retention / target の成功系と失敗系を固定する
  - **C**: Native marker の可視性条件が一貫するようにする
  - **テスト**: `Scripts/diff_cases/annotation_basic.kt`, `deprecated_error.kt`, `native_annotations.kt`
  - **完了条件**:
    - target/retention の成功系と失敗系が最低 1 件ずつある
    - annotation 由来診断が `KSWIFTK-*` で固定される

- [ ] STDLIB-REGEX-001: `kotlin.text.Regex` の対象 API 一覧を固定する
  - **A**: `Regex`, `RegexOption`, match / replace / split / named group の対象宣言を整理する
  - **B**: compile-time に見える API と runtime 実装必須 API を分離する
  - **C**: 未対応 API は独立 task か診断方針へ落とす
  - **テスト**: 既存 regex 系 case を参照
  - **完了条件**:
    - compile / match / replace / split / named group の各群が TODO から辿れる
    - 無言欠落が残らない
- [ ] STDLIB-REGEX-002: `Regex` の sema / lowering を整える
  - **A**: [`HeaderHelpers+SyntheticRegexStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticRegexStubs.swift) と lowering の解決経路を確認する
  - **B**: option 組み合わせと helper 解決が正しいことを確認する
  - **C**: unsupported API が誤った runtime helper に落ちないようにする
  - **テスト**: `Scripts/diff_cases/regex_basic.kt`, `regex_options.kt`
  - **完了条件**:
    - option 組み合わせのケースがある
    - 誤った helper 解決が回帰しない
- [ ] STDLIB-REGEX-003: `Regex` runtime / ABI と failure path を固定する
  - **A**: [`RuntimeRegex.swift`](Sources/Runtime/RuntimeRegex.swift) と `kk_regex_*` ABI の option 伝播、anchor、named group を整理する
  - **B**: invalid pattern や unsupported replacement の失敗系を拘束する
  - **C**: runtime tests / parity tests を追加する
  - **テスト**: `Scripts/diff_cases/regex_option_dotmatchesall.kt`, runtime regex tests
  - **完了条件**:
    - named group と anchor のケースがある
    - invalid pattern や unsupported replacement の失敗系が固定される
- [ ] STDLIB-ASSERT-001: `assert` / `check` / `require`
  - **A**: lazy message 付き overload、smart cast を伴う contracts、`assert` 無効化時の評価抑止まで定義どおりに揃える
  - **B**: `contract { returns() implies ... }` を使う built-in 前提が sema に反映されるかを確認する
  - **C**: [`RuntimeAssertions.swift`](Sources/Runtime/RuntimeAssertions.swift) と既存 runtime tests の責務を整理し、`kk_precondition_assert*` / `kk_require*` / `kk_check*` の ABI を固定する
  - **テスト**: `Scripts/diff_cases/assertions.kt`, `require_fail.kt`, `check_fail.kt`, `require_check_error.kt`, `contract_smartcast.kt`, `contract_returns.kt`
  - **完了条件**:
    - `assert`, `check`, `require` の eager / lazy message 両方が検証される
    - `assert` 無効化時に lazy message が評価されないことを runtime tests で確認する
    - contracts 由来の smart cast が成功するケースと失敗時診断ケースの両方がある
- [ ] STDLIB-I18N-COMMON-001: `kotlin.text` / common 範囲のフォーマット・ロケール（`java.*` 依存はターゲット外）
  - **A**: common として追う API と、`java.text` / `java.util.Locale` synthetic bridge 扱いに留める API を分離する
  - **B**: synthetic 宣言と lowering が locale/format helper をどこまで許容するかを文書化する
  - **C**: [`RuntimeDateFormat.swift`](Sources/Runtime/RuntimeDateFormat.swift) と number/locale runtime tests を根拠に、未完部分をサブタスク化する
  - **テスト**: `Scripts/diff_cases/locale_basic.kt`, `date_format_locale.kt`
  - **完了条件**:
    - common とターゲット外 (`java.*`) の境界が本文で読める
    - locale 基本情報、大小文字変換、数値/日付フォーマットのうち対象にしたものが明記されている
    - 対象外にした API は別 task またはバックログへ退避済みである
- [ ] STDLIB-TIME-EXP-001: `@ExperimentalTime` 系（`Clock` / `TimeMark` 等）— [kotlin.time](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.time/index.html)
  - **A**: `@OptIn(ExperimentalTime::class)` 必須 API と stable API を混同しない
  - **B**: experimental marker の宣言可視性・注釈解決・diagnostic を固める
  - **C**: runtime で `Clock.System` と `TimeMark` 差分計測が deterministic に扱えるようにする
  - **テスト**: `Scripts/diff_cases/experimental_time.kt`, `measure_timed_value.kt`
  - **完了条件**:
    - `@OptIn` 必須ケースと不要ケースが混ざらずにテスト化されている
    - `Clock.System.now()` と `TimeMark` 差分計測の両経路が検証される
    - experimental marker が見えない/解決できないケースは診断で落ちる
- [ ] STDLIB-PROP-001: `kotlin.properties` デリゲートの実装差分を詰める
  - **A**: `lazy`, `observable`, `vetoable` の宣言、thread-safety mode、再入可能性を棚卸しする
  - **B**: [`StdlibDelegateLoweringPass.swift`](Sources/CompilerCore/Lowering/StdlibDelegateLoweringPass.swift) と [`HeaderHelpers+SyntheticPropertyDelegateStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPropertyDelegateStubs.swift) の役割分担を明確にする
  - **C**: delegate box runtime の状態遷移・例外伝播・初期化回数を ABI/ランタイムテストで拘束する
  - **テスト**: `Scripts/diff_cases/delegate_observable.kt`, `delegate_vetoable.kt`, `delegate_operators.kt`
  - **完了条件**:
    - `lazy`, `observable`, `vetoable` の 3 系統がそれぞれ 1 ケース以上ある
    - `lazy` の初期化回数、`observable` の old/new 値、`vetoable` の reject 動作が確認できる
    - lowering 専用処理と runtime helper の責務境界がコード参照付きで追える
- [ ] STDLIB-CORO-001: `kotlin.coroutines.intrinsics` / cancellation の差分棚卸し
  - **A**: stdlib プリミティブとして追う intrinsics と、コンパイラ内部専用として割り切る領域を区別する
  - **B**: [`HeaderHelpers+SyntheticCoroutineStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticCoroutineStubs.swift) と coroutine lowering の対応表を作る
  - **C**: cancellation exception・resume path・timeout/cancel 境界を runtime tests で補強する
  - **テスト**: `Scripts/diff_cases/coroutine_cancellation.kt`, `coroutine_scope_timeout.kt`, `coro_withcontext.kt`
  - **完了条件**:
    - intrinsics の対象/非対象が本文で区別されている
    - timeout, explicit cancel, regular exception の 3 経路が別テストで見える
    - cancellation exception 判定 API が runtime tests で拘束される
- [ ] STDLIB-CORO-BASE-001: `kotlin.coroutines` 基盤 (`Continuation` / suspend primitive) の残差を詰める
  - **A**: `Continuation`, `CoroutineContext`, suspend primitive として最低限必要な宣言を整理する
  - **B**: coroutine lowering が suspend call / resume / throw channel を正しく下ろすことを確認する
  - **C**: `RuntimeCoroutine` と周辺 ABI が continuation state machine と整合することを runtime / integration tests で拘束する
  - **テスト**: `Scripts/diff_cases/suspend_functions.kt`, `coro_withcontext.kt`, `coroutine_launch_join.kt`
  - **完了条件**:
    - suspend 関数の正常終了、例外終了、resume 経路が別ケースで見える
    - `Continuation` ベースの最小動作が diff または integration test で確認できる
    - cancellation / intrinsics task と責務重複がない
- [ ] STDLIB-CONTRACT-001: `kotlin.contracts` の effect model を整理する
  - **A**: smart cast に効く built-in contracts と、ユーザー定義 contract DSL のどこまでを通すかを明記する
  - **B**: sema の data-flow 反映と diagnostics を golden で固定する
  - **C**: runtime 非依存タスクとして、`RuntimeABISpec` の対象外であることを明示する
  - **テスト**: `Scripts/diff_cases/contracts_basic.kt`, `contract_smartcast.kt`, `contract_returns.kt`
  - **完了条件**:
    - built-in contracts と user-defined DSL の扱いが明文化されている
    - smart cast 成功ケース、smart cast 不成立ケース、unsupported contract の診断ケースがある
    - runtime に依存しない task であることが TODO 上で分かる
- [ ] STDLIB-NATIVE-REF-001: `kotlin.native.ref` / `kotlin.native.runtime` の API 棚卸しを固定する
  - **A**: 対象 API、非対象 API、別計画 API の一覧を task 本文で明文化する
  - **B**: [`HeaderHelpers+SyntheticNativeInteropStubs.swift`](Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticNativeInteropStubs.swift) で今見えている宣言との対応を取る
  - **C**: runtime 実装が不要なものは ABI 対象外であることを明示する
  - **テスト**: `Scripts/diff_cases/platform_info.kt`, `kmp_common.kt`, `native_annotations.kt`
  - **完了条件**:
    - API ごとの扱いが「対応」「診断で落とす」「別計画」に分類されている
    - 無言欠落が残らない
- [ ] STDLIB-NATIVE-REF-002: `kotlin.native.ref` / `kotlin.native.runtime` の sema 露出を整える
  - **A**: 対応対象 API が sema から見えること、非対応 API が明示的に落ちることを確認する
  - **B**: synthetic stub の型・可視性・annotation が対象定義と一致するようにする
  - **C**: lowering が未対応 API を誤って runtime 呼び出しに落とさないことを確認する
  - **テスト**: 専用 diff case 追加、または既存 Native 系 case に失敗系を追加
  - **完了条件**:
    - 見える API と見えない API の境界が golden で確認できる
    - 非対応 API は `KSWIFTK-*` で落ちる
- [ ] STDLIB-NATIVE-REF-003: `kotlin.native.ref` / `kotlin.native.runtime` で本当に必要な runtime / ABI だけを実装する
  - **A**: `001` で「対応」とした API のうち runtime 実装が必要なものだけを対象にする
  - **B**: 必要な `kk_*` と `RuntimeABISpec` section を追加する
  - **C**: ABI parity と runtime tests で拘束する
  - **テスト**: 対応対象 API ごとの runtime test
  - **完了条件**:
    - 追加した runtime API が parity test を通る
    - sema だけで足りる API を過剰に ABI 化していない
- [ ] STDLIB-SYSTEM-001: `kotlin.system` の対象 API 一覧を固定する
  - **A**: `measureTimeMillis`, `measureNanoTime`, 現行 time helper との責務境界を整理する
  - **B**: inline helper と runtime call のどちらで扱うかを API ごとに決める
  - **C**: 未対応 API は独立 task か診断方針へ落とす
  - **テスト**: 既存 system/time 系 case を参照
  - **完了条件**:
    - milli / nano の両系統が TODO から辿れる
    - `kotlin.time` 系 task と責務重複しない
- [ ] STDLIB-SYSTEM-002: `kotlin.system` の sema / lowering を整える
  - **A**: system helper の解決経路を固定する
  - **B**: inline 展開か runtime helper かの境界を明文化する
  - **C**: time 系別 task と誤って混線しないことを確認する
  - **テスト**: `Scripts/diff_cases/measure_time.kt`, `system_current_time_millis.kt`
  - **完了条件**:
    - system helper の呼び出し経路が回帰しない
    - time 系 task と責務境界が明確である
- [ ] STDLIB-SYSTEM-003: `kotlin.system` の runtime / 計測系テストを固定する
  - **A**: duration/time runtime と重複しない最小 ABI で system time helper を拘束する
  - **B**: 精度差を前提に brittle でないテストを作る
  - **C**: milli/nano 両方の runtime 振る舞いを固定する
  - **テスト**: `Scripts/diff_cases/system_nano_time.kt`, runtime system/time tests
  - **完了条件**:
    - 戻り値の精度差を前提にしたテストが brittle にならない
    - runtime / parity の両方で追える

- [ ] STDLIB-UUID-001: `kotlin.uuid` の対象 API 一覧を固定する
  - **A**: parse / format / random / name-based UUID の対象宣言を公式 API と照合する
  - **B**: companion helper と instance method の対象を分けて整理する
  - **C**: 未対応 API は独立 task か診断方針へ落とす
  - **テスト**: 既存 UUID 系 case を参照
  - **完了条件**:
    - parse / format / random / name-based の 4 群が TODO から辿れる
    - 無言欠落が残らない
- [ ] STDLIB-UUID-002: `kotlin.uuid` の sema / lowering を整える
  - **A**: companion helper と instance method の解決を確認する
  - **B**: parse/format helper が誤って別経路に落ちないことを確認する
  - **C**: unsupported API が silent failure にならないようにする
  - **テスト**: `Scripts/diff_cases/uuid_basic.kt`
  - **完了条件**:
    - companion と instance の両経路が確認できる
    - helper 解決の回帰が検知できる
- [ ] STDLIB-UUID-003: `kotlin.uuid` の runtime / canonical form / failure path を固定する
  - **A**: canonical string、比較、hash、name-based deterministic 生成を拘束する
  - **B**: parse failure などの失敗系を固定する
  - **C**: runtime tests と parity 対象を整理する
  - **テスト**: UUID runtime tests, `Scripts/diff_cases/uuid_basic.kt`
  - **完了条件**:
    - 文字列表現の往復が通る
    - random 系と deterministic name-based 系が別ケースである
    - equality / hashCode / parse failure のいずれかが runtime test で固定される
- [ ] STDLIB-NATIVE-PLATFORM-001: `kotlin.native` の platform info 残差を詰める
  - **A**: 既存完了項目 `STDLIB-NATIVE-169` で covered でない問い合わせ API を明文化する
  - **B**: [`RuntimePlatform.swift`](Sources/Runtime/RuntimePlatform.swift) と synthetic 宣言の露出面を一致させる
  - **C**: platform info の最低限の問い合わせ API を diff で固定する
  - **テスト**: `Scripts/diff_cases/platform_info.kt`
  - **完了条件**:
    - platform info の残差だけを対象にしている
    - 既存完了項目と責務重複しない
- [ ] STDLIB-NATIVE-PLATFORM-002: common source set から見える Native bridge を整理する
  - **A**: `kmp_common.kt` などで見える common/Native bridge の対象宣言を整理する
  - **B**: common から使える宣言と Native 限定宣言の境界を sema で固定する
  - **C**: 境界違反時の診断または非露出を明示する
  - **テスト**: `Scripts/diff_cases/kmp_common.kt`
  - **完了条件**:
    - common から見えるもの/見えないものが golden or diff で確認できる
    - Native 専用宣言が common に漏れない
- [ ] STDLIB-NATIVE-CONCURRENT-001: `kotlin.native.concurrent` の対象 API 一覧を固定する
  - **A**: Native concurrent 専用 API のうち追うもの、追わないもの、別計画のものを列挙する
  - **B**: `kotlin.concurrent.atomics` と責務が重なるものを整理する
  - **C**: 実装対象と除外対象が TODO から辿れるようにする
  - **テスト**: `Scripts/diff_cases/experimental_atomic.kt`
  - **完了条件**:
    - package 境界と対象 API が本文で読める
    - 無言欠落が残らない
- [ ] STDLIB-NATIVE-CONCURRENT-002: `kotlin.native.concurrent` の sema / diagnostics を整える
  - **A**: 対応対象 API が見えること、非対応 API が診断で落ちることを確認する
  - **B**: experimental / opt-in 条件が必要ならそこで固定する
  - **C**: lowering が誤って atomics 側の runtime を再利用しないことを確認する
  - **テスト**: `experimental_atomic.kt` に成功系/失敗系を追加
  - **完了条件**:
    - success path と diagnostic path の両方がある
    - `kotlin.concurrent.atomics` と混線しない
- [ ] STDLIB-NATIVE-CONCURRENT-003: `kotlin.native.concurrent` で必要最小限の runtime / ABI を実装する
  - **A**: `001` で対応対象とした API のうち runtime が必要なものだけを対象にする
  - **B**: 必要な `kk_*` と `RuntimeABISpec` section を追加する
  - **C**: runtime / parity tests を追加する
  - **テスト**: Native concurrent 対応 API ごとの runtime test
  - **完了条件**:
    - ABI parity が通る
    - 過剰な runtime 実装を増やしていない
- [ ] STDLIB-EXPERIMENTAL-001: `kotlin.experimental` に残る marker 一覧を固定する
  - **A**: `kotlin.experimental` 名前空間に残る marker / annotation の一覧を作る
  - **B**: それぞれを「見えるだけ」「opt-in 必須」「別計画」に分類する
  - **C**: 関連 task (`time`, `atomics`, `native annotation`) への参照を持たせる
  - **テスト**: 既存関連 case 参照
  - **完了条件**:
    - marker ごとの扱いが TODO から辿れる
    - task 間の責務重複が減る
- [ ] STDLIB-EXPERIMENTAL-002: `kotlin.experimental` の opt-in / diagnostics を整える
  - **A**: opt-in 必須 marker の sema 診断を固定する
  - **B**: annotation 解決と use-site ルールが一貫するようにする
  - **C**: runtime 不要なものは ABI 対象外であることを確認する
  - **テスト**: `Scripts/diff_cases/experimental_time.kt`, `experimental_atomic.kt`, `native_annotations.kt`
  - **完了条件**:
    - marker が見えるケースと opt-in 不足ケースの両方がある
    - runtime 不要領域を ABI 化していない

### ギャップ表と TODO の対応

ギャップ表の各行は、最低でも次の todo で追跡できる状態を目標にする。

- `kotlin`（スコープ関数）: `STDLIB-GAP-PH1`, `STDLIB-002`
- `kotlin`（`synchronized` / 比較・演算子基盤）: `STDLIB-GAP-PH3`, `STDLIB-033`, `STDLIB-COMP-001`
- `kotlin.collections`: `STDLIB-GAP-PH2`, `STDLIB-021`
- `kotlin.sequences`: `STDLIB-GAP-PH2`, `STDLIB-020`
- `kotlin.ranges`: `STDLIB-GAP-PH2`, `STDLIB-022`
- `kotlin.text` / `Char`: `STDLIB-GAP-PH1`, `STDLIB-003`, `STDLIB-005`
- `kotlin.text.Regex`: `STDLIB-REGEX-001`〜`003`
- `kotlin.io`: `STDLIB-GAP-PH3`, `STDLIB-030`
- `kotlin.io.encoding`: `STDLIB-GAP-PH3`, `STDLIB-031`
- `kotlin.math`: `STDLIB-GAP-PH4`, `STDLIB-MATH-001`〜`003`
- `kotlin.random`: `STDLIB-GAP-PH4`, `STDLIB-RANDOM-001`〜`003`
- `kotlin.concurrent`: `STDLIB-GAP-PH3`, `STDLIB-033`
- `kotlin.concurrent.atomics`: `STDLIB-GAP-PH3`, `STDLIB-033`, `STDLIB-NATIVE-CONCURRENT-001`〜`003`
- `kotlin.reflect`: `STDLIB-GAP-PH4`, `STDLIB-REFLECT-066`, `STDLIB-REFLECT-067`
- `kotlin.time`: `STDLIB-GAP-PH3`, `STDLIB-032`, `STDLIB-TIME-EXP-001`, `STDLIB-SYSTEM-001`
- `kotlin.properties`: `STDLIB-PROP-001`
- `kotlin.coroutines`: `STDLIB-CORO-BASE-001`
- `kotlin.coroutines.cancellation`: `STDLIB-CORO-001`
- `kotlin.coroutines.intrinsics`: `STDLIB-CORO-001`
- `kotlin.annotation`: `STDLIB-ANNO-001`, `STDLIB-ANNO-002`
- `kotlin.comparisons`: `STDLIB-COMP-001`〜`003`
- `kotlin.enums`: `STDLIB-GAP-PH2`, `STDLIB-023`
- `kotlin.contracts`: `STDLIB-CONTRACT-001`, `STDLIB-ASSERT-001`
- `kotlin.experimental`: `STDLIB-EXPERIMENTAL-001`, `STDLIB-EXPERIMENTAL-002`
- `kotlin.system`: `STDLIB-SYSTEM-001`〜`003`
- `kotlin.uuid`: `STDLIB-UUID-001`〜`003`
- `kotlin.native`: `STDLIB-NATIVE-PLATFORM-001`, `STDLIB-NATIVE-PLATFORM-002`, `STDLIB-NATIVE-169`
- `kotlin.native.concurrent`: `STDLIB-NATIVE-CONCURRENT-001`〜`003`
- `kotlin.native.ref` / `kotlin.native.runtime`: `STDLIB-NATIVE-REF-001`〜`003`

### stdlib 完了条件

このセクションを「KSwiftK が対象とする stdlib 実装完了」とみなす条件は次のとおり。

1. パッケージ単位チェックリストで、対象外を除く対象 package がすべて `[x]` になる
2. ギャップ表で、対象内の行に `未` / `未〜部分` が残らない
3. `部分` が残る行は、その理由が「対象外の一部」または独立 backlog として説明できる
4. 各 todo が A/B/C と diff/golden/runtime/ABI parity で検証済みになる
5. ターゲット外バックログへ送った項目と、対象内の未実装項目が混ざっていない

### 完了済み（参照）

- [x] STDLIB-NATIVE-169: プラットフォーム情報 — [`RuntimePlatform.swift`](Sources/Runtime/RuntimePlatform.swift) 等
- [x] STDLIB-ATOMIC-CORE: スカラー Atomics 基本 — `Scripts/diff_cases/atomic_basic.kt`, [`RuntimeAtomic.swift`](Sources/Runtime/RuntimeAtomic.swift)

---

## ターゲット外バックログ（ツールチェーン・JVM/JS・kotlinx）

macOS ネイティブ LLVM とは別優先で追う項目（stdlib ロードマップと混ぜない）。

- [ ] JDBC / DB コネクション・トランザクション・プール
- [ ] JVM 風ロギングフレームワーク互換
- [ ] `kotlin.jvm` / `kotlin.js` / `kotlin.wasm*` / `java.nio.file` 系・`kotlin.streams`
- [ ] kotlinx-metadata / コンパイラプラグイン API / KSP / KAPT
- [ ] kotlinx.coroutines の Flow 拡張（SharedFlow、高度演算子など）
- [ ] JVM `java.time` / JS `Date` との相互運用
- [ ] `Runtime.getRuntime()` 系メモリ API（JVM モデル）
- [ ] HTTP・汎用シリアライゼーション（製品レベル）
- [ ] `java.text` 前提の日時・数値フォーマット

---

## テスト改善タスク

### 高優先度：テストカバレッジ拡充

- [ ] TEST-VAL-001: Value Classesテスト拡充 (現在4件→15件)
  - **追加内容**:
    - ボクシングの境界条件テスト
    - ジェネリクスとの組み合わせテスト
    - 配列とコレクションでの使用テスト
    - 継承とインターフェースのテスト
  - **関連ファイル**: `Scripts/diff_cases/value_class_*.kt`
  - **具体ケース**:
    - `value_class_basic.kt` / `value_class_unboxing.kt` / `value_classes.kt` の重複と不足を整理する
    - nullable value class、`Any` への boxing、interface dispatch、generic return 境界を追加する
    - golden と diff の両方で観測すべきケースを分ける
  - **完了条件**:
    - diff ケースを 10 件以上追加し、既存 3 系列の責務重複を減らす
    - `Tests/CompilerCoreTests/GoldenCases/Sema/value_class.*` に型表現差分が出るケースを最低 3 件追加する

- [ ] TEST-SCRIPT-002: Scriptモードテスト拡充 (現在3件→10件)
  - **追加内容**:
    - 複雑な式の評価テスト
    - トップレベル関数定義テスト
    - import文の使用テスト
    - REPL的な使用ケース
  - **関連ファイル**: `Scripts/diff_cases/script_*.kt`
  - **具体ケース**:
    - `script_hello.kt`, `script_val_expr.kt`, `script_multi_stmt.kt`, `script_lambda_expr.kt`, `script_function_basic.kt`, `script_function_advanced.kt`, `script_import_stdlib.kt`, `script_import_custom.kt`, `script_repl_interactive.kt`, `script_complex_expr.kt` の責務を再配分する
    - script mode 固有のトップレベル初期化順、import 解決、複数 statement の値規則を追加する
  - **完了条件**:
    - CLI から script mode を直接叩く統合テストを追加する
    - 同名ローカル宣言と import shadowing のエラー系を最低 2 件入れる

- [ ] TEST-CORO-003: 高度なCoroutine機能テスト (現在29件→40件)
  - **追加内容**:
    - Structured Concurrencyテスト
    - Flowのバックプレッシャーテスト
    - Coroutineのエッジケース
    - Exception handling in coroutines
  - **関連ファイル**: `Scripts/diff_cases/*coroutine*.kt`
  - **具体ケース**:
    - `coroutine_scope.kt`, `coroutine_scope_timeout.kt`, `coroutine_launch_join.kt`, `coroutine_cancellation.kt`, `channel_backpressure.kt`, `coro_channel_backpressure.kt`, `flow_error_handling.kt` の gaps を埋める
    - parent/child cancel 伝播、timeout 後 resume 禁止、例外と cancellation の優先順位を追加する
  - **完了条件**:
    - timeout/cancel/exception を組み合わせた diff ケースを最低 5 件追加する
    - Runtime 側ユニットテストに cancellation exception と state machine 遷移の回帰を最低 3 件追加する

- [ ] TEST-ERR-004: エラーケースと診断コード網羅 (現在3件→20件)
  - **追加内容**:
    - 型推論エラーパターン (KSWIFTK-TYPE-*)
    - セマンティックエラーパターン (KSWIFTK-SEMA-*)
    - リンカエラーパターン (KSWIFTK-LINK-*)
    - 診断コードの網羅的テスト
  - **関連ファイル**: `Scripts/diff_cases/*error*.kt`
  - **具体ケース**:
    - `type_error.kt`, `error_call.kt`, `deprecated_error.kt`, `val_reassign_error.kt`, `abstract_property_errors.kt`, `data_class_inheritance_errors.kt`, `override_variance_errors.kt`, `is_type_check_non_reified_error.kt` を起点に診断カテゴリを分ける
    - `-Xdiagnostics json` と text 両方でコードが出ることを確認する
  - **完了条件**:
    - `KSWIFTK-TYPE-*`, `KSWIFTK-SEMA-*`, `KSWIFTK-LINK-*`, `KSWIFTK-CORO-*` の各カテゴリで最低 3 件ずつ golden を持つ
    - 診断コード未付与の失敗ケースをゼロにする

### 中優先度：テスト品質とインフラ改善

- [ ] TEST-SMOKE-005: Smoke Testsの軽微な拡充 (現在5件→8件)
  - **追加内容**:
    - 空ファイルのハンドリングテスト
    - 不正なUTF-8文字の処理テスト
    - 巨大ファイルの処理テスト
    - 複数ファイル入力の基本テスト
  - **関連ファイル**: `Tests/CompilerCoreTests/Integration/SmokeTests.swift`
  - **完了条件**:
    - CLI の exit code / stderr / diagnostics format の最低限を確認する smoke を追加する
    - temp directory 依存ケースを deterministic にする

- [ ] TEST-INT-006: Integration Testsの整理と重複削減
  - **改善内容**:
    - jscpdで検出された重複テストの統合
    - テストヘルパーの共通化
    - テストカテゴリの明確化 (Unit/Integration/E2E/Regression)
    - 2,460テストメソッドの整理
  - **関連ファイル**: `Tests/CompilerCoreTests/Integration/*.swift`
  - **完了条件**:
    - 重複削減前後でテスト意図が失われていないことを diff/coverage で確認する
    - helper 化した assertion は 3 系列以上のテストで再利用される状態にする

- [ ] TEST-CI-007: CIパイプラインの最適化
  - **改善内容**:
    - 並列実行の動的worker数調整
    - kotlincダウンロードのキャッシュ改善
    - タイムアウトの段階的短縮 (120→60分)
    - アーティファクト保持期間延長 (14→30日)
  - **関連ファイル**: `.github/workflows/ci.yml`
  - **完了条件**:
    - 変更前後で wall-clock と cache hit rate を比較できる計測値を残す
    - flake による再実行率が悪化しないことを確認する

- [ ] TEST-REPORT-008: テストレポート形式の改善
  - **改善内容**:
    - TSV→JSON形式での詳細レポート
    - 失敗ケースの詳細情報追加
    - Golden Testsのスマート更新検出
    - 差分の可視化改善
  - **関連ファイル**: `Scripts/diff_kotlinc_ci_summary.sh`
  - **完了条件**:
    - CI artifact だけで失敗した diff case・golden case・runtime test を一意に辿れる
    - ローカル再現コマンドをレポートに含める

#### Phase 5: 実験的機能と高度API (低優先度)
#### Phase 5: プラットフォーム固有機能 (低優先度)

- [ ] STDLIB-JVM-166: Javaプレビュー機能完全実装

- [ ] STDLIB-JS-167: JavaScript固有API完全実装

- [ ] STDLIB-NATIVE-168: Native固有API完全実装

#### Phase 5: 非推奨APIと移行 (低優先度)
#### Phase 5: 高度リフレクションとメタプログラミング (低優先度)

- [x] STDLIB-REFL-172: メタデータAPI完全実装
  - **仕様**: kotlinx-metadata互換のメタデータAPI
  - **実装内容**:
    - KmFunction: 関数メタデータ
    - KmConstructor: コンストラクタメタデータ
    - KmAnnotation: アノテーションメタデータ
    - compilerPluginMetadata: コンパイラプラグインメタデータ
    - メタデータシリアライズ: メタデータのシリアライズ/デシリアライズ
  - **現状**: 完全実装済み - KmFunction/KmConstructor/KmAnnotation/KmCompilerPluginMetadata/RuntimeMetadataCodec全API利用可能
  - **関連ファイル**: `RuntimeMetadata.swift`
  - **テストケース**: `Scripts/diff_cases/metadata_api.kt`

- [ ] STDLIB-REFL-173: コンパイラプラグインAPI完全実装
  - **仕様**: コンパイラプラグインAPIの完全サポート
  - **実装内容**:
    - CommandProcessor: コンパイラコマンド処理
    - ExtensionRegistrar: 拡張登録
    - IrGenerationExtension: IR生成拡張
    - ClassBuilderInterceptor: クラスビルダーインターセプト
    - プラグインメタデータ: プラグイン情報の保存
  - **現状**: コンパイラプラグインAPIは未実装
  - **関連ファイル**: `CompilerPlugin.swift`
  - **テストケース**: `Scripts/diff_cases/compiler_plugin_api.kt`

- [x] STDLIB-REFL-174: KSP（シンボル処理）基本実装
  - **仕様**: Kotlin Symbol Processingの基本的なサポート
  - **実装内容**:
    - SymbolProcessor: シンボルプロセッサインターフェース
    - KSPLogger: ロギング機能
    - Resolver: シンボル解決
    - CodeGenerator: コード生成
    - プロセッサ登録: プロセッサの登録と実行
  - **現状**: 完全実装済み - 全APIが利用可能
  - **関連ファイル**: `RuntimeKSP.swift`
  - **テストケース**: `Scripts/diff_cases/ksp_basic.kt`
  - **実装API**: kk_ksp_logger_new, kk_ksp_logger_info, kk_ksp_logger_warn, kk_ksp_logger_error, kk_ksp_logger_messages, kk_ksp_resolver_new, kk_ksp_resolver_add_file, kk_ksp_resolver_add_symbol, kk_ksp_resolver_add_annotated_symbol, kk_ksp_resolver_get_all_files, kk_ksp_resolver_get_all_symbols, kk_ksp_resolver_get_symbols_with_annotation, kk_ksp_codegen_new, kk_ksp_codegen_create_file, kk_ksp_codegen_generated_files, kk_ksp_register_processor, kk_ksp_registered_processors, kk_ksp_run_processors

- [ ] STDLIB-REFL-175: アノテーション処理高度機能完全実装
  - **仕様**: アノテーション処理の高度な機能
  - **実装内容**:
    - KAPT統合: Kotlin Annotation Processing Tool
    - ラウンド処理: 複数ラウンドの処理
    - 増分処理: 増分コンパイル対応
    - オプション管理: プロセッサオプション
    - エラー報告: コンパイルエラーの生成
  - **現状**: アノテーション処理は未実装
  - **関連ファイル**: `RuntimeKAPT.swift`
  - **テストケース**: `Scripts/diff_cases/annotation_processing.kt`

#### Phase 5: 高度Flowとコルーチン (低優先度)

- [ ] STDLIB-FLOW-176: Flow高度演算子完全実装
  - **仕様**: kotlinx.coroutinesの高度Flow演算子
  - **実装内容**:
    - 変換演算子: map, filter, transform, takeWhile, dropWhile
    - フラット化: flatMapConcat, flatMapMerge, flatMapLatest
    - 組合せ演算子: combine, zip, merge
    - バッファリング: buffer, conflate, flowOn
    - タイミング: debounce, sample, delayEach
  - **現状**: 基本的なFlowは実装済み、高度な演算子は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_advanced_operators.kt`

- [x] STDLIB-FLOW-177: SharedFlowとStateFlow完全実装
  - **仕様**: ホットストリームの完全サポート
  - **実装内容**:
    - SharedFlow: マルチキャストホットフロー
    - StateFlow: 状態保持ホットフロー
    - shareIn(): コールドフローからSharedFlowへの変換
    - stateIn(): コールドフローからStateFlowへの変換
    - リプレイキャッシュ: 過去値のキャッシュ機能
  - **現状**: 実装完了（`RuntimeSharedFlowHandle`、`RuntimeStateFlowHandle`、各C関数エントリポイント）
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/shared_state_flow.kt`

- [ ] STDLIB-FLOW-178: Flowビルダー完全実装
  - **仕様**: 全てのFlowビルダーの完全サポート
  - **実装内容**:
    - flowOf(): 固定値からのフロー生成
    - emptyFlow(): 空フロー生成
    - channelFlow(): チャネルベースのフロー
    - callbackFlow(): コールバックベースのフロー
    - asFlow(): コレクションからのフロー変換
  - **現状**: 基本的なflowビルダーは実装済み、高度なビルダーは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_builders.kt`

- [ ] STDLIB-FLOW-179: Flowエラーハンドリング完全実装
  - **仕様**: Flowの完全なエラーハンドリング
  - **実装内容**:
    - catch(): 上流例外の処理
    - retry(): 失敗時のリトライ
    - retryWhen(): 条件付きリトライ
    - onErrorReturn(): エラー時のデフォルト値
    - onErrorResume(): エラー時の代替フロー
  - **現状**: Flowエラーハンドリングは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_error_handling.kt`

#### Phase 5: 高度時間測定 (低優先度)

- [x] STDLIB-TIME-180: 実験的時間API完全実装
  - **仕様**: 実験的時間APIの完全サポート
  - **実装内容**:
    - @ExperimentalTime: 実験的時間APIマーカー (`HeaderHelpers+SyntheticExperimentalTimeStubs.swift`)
    - Clockインターフェース: 時計の抽象化 (`kk_clock_now`)
    - Clock.System: システム時計実装 (`kk_clock_system_now`)
    - TimeSource: 時間ソースの抽象化 (`kk_time_source_mark_now`)
    - TimeMark: 時間マークと差分計算 (`kk_time_mark_elapsed_now` など)
    - TimeSource.Monotonic: モノトニック時間ソース (`kk_time_source_monotonic_mark_now`)
  - **現状**: 実装完了; ABISpec/ABIParity/BridgeCoverage に Clock 関数を追加
  - **関連ファイル**: `RuntimeTime.swift`, `RuntimeInstant.swift`, `HeaderHelpers+SyntheticExperimentalTimeStubs.swift`, `HeaderHelpers+SyntheticClockStubs.swift`
  - **テストケース**: `Scripts/diff_cases/experimental_time.kt`

- [ ] STDLIB-TIME-181: プラットフォーム時間変換完全実装
  - **仕様**: プラットフォーム固有の時間API変換
  - **実装内容**:
    - JVM: Instant.toJavaInstant(), java.time.Instant.toKotlinInstant()
    - JVM: Duration.toJavaDuration(), java.time.Duration.toKotlinDuration()
    - JS: Instant.toJSDate(), Date.toKotlinInstant()
    - Native: プラットフォーム固有時間API
    - 変換の安全性: 型安全な時間変換
  - **現状**: プラットフォーム時間変換は未実装
  - **関連ファイル**: `RuntimeTime.swift`
  - **テストケース**: `Scripts/diff_cases/platform_time_conversion.kt`

### テスト改善の実装方針

1. **網羅性優先**: Value Classesとエラーケースから優先実装
2. **段階的追加**: 各カテゴリを段階的に拡充
3. **CI連携**: 新規テストはCIで自動実行されるように設定
4. **ドキュメント化**: 各テストケースの目的と期待結果を明記
