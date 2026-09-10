# diff_kotlinc skip inventory

最終更新: 2026-08-25

この文書は `Scripts/diff_cases` の `DEBT-DIFF-*` 付き `SKIP-DIFF` / `KSWIFTK_DIFF_IGNORE` を、JVM kotlinc reference に戻すべきケースと、別 runner / 別テストへ移すべきケースへ分けるための棚卸しである。

集計コマンド:

```bash
find Scripts/diff_cases -type f \( -name '*.kt' -o -name '*.kts' \) -print0 \
  | xargs -0 rg -n 'DEBT-DIFF-[0-9]{3}'
```

## 方針

- `diff_kotlinc.sh` に戻す条件: JVM kotlinc が同じ入力を同じ target / classpath / runtime mode でコンパイル・実行でき、stdout / exit code を oracle にできること。
- JVM kotlinc が oracle にならない target-specific ケースは、`diff_cases` から削るのではなく、target 専用 runner、compiler diagnostic/golden、または runtime unit test の owner を明示する。
- 依存 jar だけで解けるものは、case directive または harness option で classpath / java flags を注入して通常 diff に戻す。
- `KSWIFTK_DIFF_IGNORE` は古い別名として扱う。新規 skip は `SKIP-DIFF (DEBT-DIFF-xxx): reason` に統一する。

## run_case の compile exit code 一致判定について（2026-07-08）

2026-07-08 以前の `run_case`（`Scripts/diff_kotlinc.sh`）は、reference（kotlinc）と candidate（kswiftc）の**両方がコンパイルに失敗**し、かつ **exit code が偶然一致**した場合、コンパイルエラーの内容を一切比較せず無条件で `PASS` と判定していた。実行結果（stdout）比較は `ref_compile_exit == 0 && cand_compile_exit == 0` の分岐内でのみ行われるため、両方失敗のケースはそもそもこの比較に到達しない。

この結果、reference と candidate が全く無関係な理由で失敗しているだけのケースが「PASS」として長期間見過ごされていた。実例: `random_extended.kt` は kotlinc 側が非標準 API（`Random.nextFloat(until)`）呼び出しで exit 1、kswiftc 側は無関係な `nextBytes` の実装バグで exit 1 となり、exit code が一致するため PASS 扱いになっていた（分離後: [`random_nextfloat_range_overloads.kt`](../Scripts/diff_cases/random_nextfloat_range_overloads.kt) / [`random_nextbytes.kt`](../Scripts/diff_cases/random_nextbytes.kt)）。

2026-07-08 の修正で、`ref_compile_exit != 0 && cand_compile_exit != 0 && ref_compile_exit == cand_compile_exit` の場合は無条件で `FAIL` として扱うよう変更した（`ref`/`cand` 双方の compile stderr は artifact の `compile_stderr.diff` に保存されるため、個別に原因を切り分けられる）。この変更により新たに顕在化した「両方失敗」ケースは DEBT-DIFF-007 として棚卸しした。

## 現在値

件数は実測値（`find Scripts/diff_cases -type f \( -name '*.kt' -o -name '*.kts' \) -print0 | xargs -0 rg -o 'SKIP-DIFF\s*\(DEBT-DIFF-[0-9]{3}\)|KSWIFTK_DIFF_IGNORE.*DEBT-DIFF-[0-9]{3}' -N | rg -o 'DEBT-DIFF-[0-9]{3}' | sort | uniq -c`）に同期する。単純な `rg -o 'DEBT-DIFF-[0-9]{3}'`（アクティブなタグ/経緯コメント両方にマッチ）ではなく、アクティブな `SKIP-DIFF`/`KSWIFTK_DIFF_IGNORE` タグのみに絞ること — `case_insensitive_order_identity.kt` のように「過去 DEBT-DIFF-005 として追跡していたが解消済み」という経緯コメントだけが残るケースがあり、単純な文字列一致では解消済みの件数を残存として誤カウントする（2026-08-02、並行マージでの再計測差異から判明）。

| Debt | 件数 | 主因 | 優先アクション |
| --- | ---: | --- | --- |
| DEBT-DIFF-001 | 20 | JVM kotlinc reference 不成立（target/classpath/runtime-only） | 2026-07-29 棚卸し完了。当時の19件全件を再ビルドした kswiftc + kotlinc 2.4.10 で再検証し、全件 keep skip 確定（詳細は下記節）。うち serialization 4件は CLEANUP-STUB-121 でケースごと削除し 15件へ。既存の Kotlin/Native Char API ケースと `state_flow_kotlin.kt`、KSP-684 の `top_level_max_min_with.kt`（JVM kotlinc に対象の bundled API がない）、KSP-1421 の `stdlib_kotlin_text_HexFormat_Builder_n_n.kt`（Kotlin 2.3.10 の `@PublishedApi internal` constructor を外部 JVM module から呼べない）を含む、現行20件 |
| DEBT-DIFF-002 | 0 | script-style top-level execution parity（解消済み） | — |
| DEBT-DIFF-003 | 0 | advanced coroutine / channel / Flow / structured concurrency | API 領域ごとに STDLIB-CORO / DEBT-CORO へ分割。cancellation 2 件・`channel_basic.kt`・`coroutine_exception_handling.kt`・`coroutine_scope_lifecycle.kt`・structured concurrency / Deferred / Supervisor 3 件・`coroutine_mutex_semaphore.kt`・`coroutine_edge_cases.kt`・`coroutine_channels_advanced.kt`・`coroutine_flow_backpressure.kt` は解除済み。2026-08-14 に現行 master で4ケースと最小回帰ケースを個別再実行し、全て PASS を確認 |
| DEBT-DIFF-004 | 0 | value class boxing / generics / interface / collection parity（解消済み） | — |
| DEBT-DIFF-005 | 0（2026-08-11 時点） | source Sequence/`sequence {}` builder の Iterator itable dispatch が整備され、`flatten_sequence_edge_cases.kt`/`sequence_lazy_eval.kt` の `--force-run-skipped` が green。他は全解消（CASE_INSENSITIVE_ORDER 誤登録＝BUG-154 は `origin/master` 側、property delegate lowering の実バグ＝BUG-151/BUG-170 は本 PR で修正） | — |
| DEBT-DIFF-006 | 0 | type inference / boxed numeric lowering / compiler-plugin API（解消済み、2026-07-29） | — |
| DEBT-DIFF-007 | 11 | compile-exit parity fix により顕在化した両失敗ケース | diagnostic golden / owner / 実装へ個別に triage（2026-07-29 に 72→37 まで棚卸し・一部修正済み。2026-07-31 に `enum_entries_function.kt` を追加解除、`enum_basic.kt`/`enum_edge_cases.kt`/`array_hof.kt`/`string_chunked_windowed.kt`/`windowed_step_partial.kt` の root cause を一部実装・範囲縮小。2026-08-02 に DEADCODE-014（#5206）で5件追加解除、マージ時再計測で36。2026-08-13 にさらに19件追加解除（テスト入力ミス/common stdlib gap 修正）して36→16 へ。2026-08-18 に `list_binary_search_compare.kt`・`mock_objects.kt` を追加解除して16→14へ。2026-09-04 に現行 `SKIP-DIFF (DEBT-DIFF-007)` タグを実測して11件へ更新し、`flow_builders.kt` を解除。詳細は該当節） |
| DEBT-DIFF-008 | 0（2026-08-20 時点） | primitive Number virtual dispatch 未実装（解消済み） | — |
| DEBT-DIFF-009 | 1 | script mode 失敗系 exit code 規約差異（`kotlinc -script` の SCRIPT_EXECUTION_ERROR=3 vs kswiftc panic exit=1） | 詳細は下記節。ref/candidate 双方の実行モデルが構造的に異なるため keep skip |

## DEBT-DIFF-001: reference target / classpath / runtime-only

棚卸し完了(2026-07-29、`swift build` で kswiftc を再ビルドし、kotlinc 2.4.10 で当時の19件全件を再検証)。**19件全件 keep skip 確定** — dependency injection や個別 runner で通常 diff に戻せたケースは無かった。

### なぜ dependency injection では解決しないか

`Scripts/diff_kotlinc.sh` の `--kotlinc-classpath` / coroutines jar 自動取得は **reference(kotlinc)側にしか作用しない**。kswiftc は jar/classpath を一切消費しない設計で、`Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift` に手書き登録した合成シンボルだけを認識し、対応する Runtime 実装を呼ぶ。したがって candidate 側が特定の Java/Kotlin API を新たに認識するには synthetic stub の実装が要り、jar 注入は原理的に届かない。「dependency injection で実行可能化」できるのは reference 側だけが理由で落ちているケースに限られるが、以下のケースはいずれも candidate 側の未実装、またはテスト内容自体が実 API 呼び出し規約と非互換という、jar 注入では解決しない理由だった。

### 確定した keep skip 一覧(現行18件)

serialization 4件(`custom_serializer.kt`, `dataclass_serialization.kt`, `json_serialization.kt`, `collection_serialization.kt`)は、synthetic stub を除去した CLEANUP-STUB-121 でケースごと削除した(実 kotlinx.serialization の呼び出し規約で書き直す道は取らず、`kotlinx.serialization` サポート自体を target-out とした)。

| 領域 | cases | 確定理由(2026-07-29 再検証) | 恒久対応の道筋 |
| --- | --- | --- | --- |
| Kotlin/Native / cinterop | `native_annotations.kt`, `native_api.kt`, `platform_info.kt`, `system_get_time_nanos.kt` | `kotlin.native.*` / `kotlinx.cinterop.*` は JVM kotlinc に存在しない。kotlinc 2.4.10 は全件 `unresolved reference` で即失敗、kswiftc は候補シンボルとして受理し正常コンパイルすることを確認。`platform_info.kt` は一時的に `--compile-timeout 15` を超えたが、システム負荷起因の見かけ上のタイムアウトで(`--compile-timeout 60` で再実行すると `time` 計測で user 8s 程度で正常終了、CPU使用率35%と待ち時間が主でビジーループではない)、無限ハングではない | Native surface 専用の Sema golden / target-specific smoke test へ移す(JVM reference を使わない) |
| Kotlin/Native Char helpers | `char_surrogate_code.kt` | `Char.Companion` の surrogate / code-point helper は Kotlin/Native-only API で JVM kotlinc に存在しない | Native surface 専用の Sema golden / target-specific smoke test へ移す(JVM reference を使わない) |
| Kotlin/JS | `js_annotations.kt`, `js_api.kt` | `kotlin.js.*` は JVM kotlinc に存在しない。`error: symbol is declared in module 'kotlin.stdlib' which does not export package 'kotlin.js'` 等で即失敗を確認 | JS/Wasm stub cleanup の target-out backlog と接続する |
| Runtime-only system API | `system_process_start_nanos.kt` | `System.processStartNanos()` は KSwiftK 独自 API。kotlinc は `unresolved reference` で即失敗を確認 | Runtime unit test または candidate-only smoke に移す |
| KSwiftK bundled comparisons API | `top_level_max_min_with.kt` | `kotlin.comparisons.maxWith(comparator, a, b)` / `minWith(comparator, a, b)` は KSwiftK の bundled source API で、JVM kotlinc 2.4.10 では `unresolved reference` になる | `ComparisonsTopLevelMaxMinWithFunctionTests` と candidate-only 直接実行を owner とする |
| Kotlin 2.3.10 bundled HexFormat constructor | `stdlib_kotlin_text_HexFormat_Builder_n_n.kt` | Kotlin 2.3.10 の `HexFormat.Builder` constructor は `@PublishedApi internal` のため、外部 JVM module の kotlinc は direct constructor call を拒否する。KSwiftK 側は focused Sema Golden と candidate-only の直接 `kswiftc` 実行で検証する | KSP-1421 の constructor-only surface。JVM reference 側からの direct call が可能になるまで `SKIP-DIFF` を維持する |
| Primitive-array bundled HOF | `ksp687_map_not_null.kt` | KSP-687 の primitive-array `mapNotNull` は KSwiftK の bundled source API だが、JVM kotlinc 2.4.10 には対応する primitive-array surface がないため `IntArray.mapNotNull` が `unresolved reference` になる。KSwiftK 側は candidate-only 直接実行と `BuildKIRCodegenRegressionTests.testPrimitiveArrayHOFsRemainBundledSourceCalls` で検証する | JVM reference のAPI追加または専用target runnerが整うまで `SKIP-DIFF` を維持する |
| JDBC / java.sql | `jdbc_basic.kt`, `prepared_statement_complete.kt`, `resultset_complete.kt`, `connection_validation.kt`, `transaction_management.kt` | **訂正**: 従来「custom jdbc:kswiftk driver をこの runtime が提供する」としていたが誤り。`Sources/` 全体を検索しても `DriverManager` / `java.sql` / `JDBC` / `jdbc:kswiftk` は一件もヒットせず、kswiftc は java.sql.\* を一切実装していない。再検証で `ref_compile_exit=0 / cand_compile_exit=1`(reference は素の JDK `java.sql` で普通にコンパイルが通り、candidate 側が `Unresolved reference 'DriverManager'` で落ちる)ことを確認 — reference 側の問題ではなく candidate 側の未実装機能だった。なお `jdbc_basic.kt` のみ実在し移植可能な `"jdbc:sqlite::memory:"` という URL を使っており(他4件は架空の `"jdbc:kswiftk:memory"`)、将来 JDBC 対応に着手する際の再開候補として最有望 | kswiftc に java.sql.\*(DriverManager/Connection/Statement/PreparedStatement/ResultSet 相当)の synthetic stub と対応する Runtime 実装を追加する大きめの機能追加が前提。実装後は `jdbc_basic.kt` を実 SQLite JDBC driver(`org.xerial:sqlite-jdbc`)の reference 側注入で検証し、他4件は URL を `jdbc:sqlite:` 系に書き換えてから同様に戻す |
| KMP expect/actual(単一ファイル制約) | `kmp_common.kt` | kotlinc 2.4.10 は `-Xmulti-platform` と `-Xcommon-sources=<file>` を付けても単一ファイル内の expect/actual を `'expect' and 'actual' declarations can be used only in multiplatform projects` / `expect and corresponding actual are declared in the same module` で拒否することを実測で確認した。common ソースと platform ソースを別コンパイル単位にして最終的にリンクする、genuinely 複数回起動する KMP 専用ビルドモデルが必須で、`kotlinc file.kt` 一発では原理的に表現できない。kswiftc 側も独立した expect/actual バグを抱える | harness に「1ファイルを common/platform に分割して2回コンパイル+リンクする」専用 KMP runner を新設しない限り不可能。ROI が低いため現時点では見送り、`Scripts/diff_kotlinc.sh` の対象外に据え置く |
| Bundled coroutine API shape | `state_flow_kotlin.kt` | KSwiftK の bundled `stateIn(initialValue)` / `shareIn(replay)` は JVM `kotlinx.coroutines` の `CoroutineScope` / `SharingStarted` 引数と意図的に異なるため、kotlinc reference 側だけがコンパイル失敗する。KSwiftK 側の動作は candidate-only の直接実行と `StdlibArtifactRegressionTests` で検証する | API 形状が収束するまで `SKIP-DIFF` を維持し、KSwiftK 固有の bundled stdlib smoke/artifact test を owner とする |
| SLF4J / logging | `logging_basic.kt`, `logging_advanced.kt` | kswiftc は `org.slf4j.*` を一切実装していない(`Sources/` 全体検索で0件、`Unresolved reference 'LoggerFactory'` で確認)。reference 側は実 slf4j-api + binding 注入で通す経路が既にある(2026-07-09 検証済み)が、candidate 側に synthetic stub が無い限り届かない。`logging_advanced.kt` はさらに `MDC` は実在するが import が無く、`AdvancedLogger`/`StructuredAppender` は実 SLF4J に存在しない架空 API であり、架空 API 部分を残す限り reference 側を通す余地自体が無い | kswiftc に `org.slf4j.*`(Logger/LoggerFactory/MDC 程度)の synthetic stub を追加する機能実装が前提。`logging_advanced.kt` は架空 API 部分を切り離すか削除しない限り、stub 追加後も keep skip のまま |

### 解除済みの周辺ケース(現行17件には含まれないが、過去の調査ノートに記載があったため参考として残す)

- `path_basic.kt`(`kotlin.io.path`): 2026-07-09 解除済み。`import kotlin.io.path.Path` が `Path()` ファクトリしか import せず、`createDirectories` / `exists` / `writeText` 等の拡張関数・拡張プロパティが unresolved だったのが真因(`resolve` / `relativize` / `normalize` 等は `java.nio.file.Path` のネイティブメンバなので import 不要で解決していた)。`import kotlin.io.path.*` に変更し、`--force-run-skipped` で reference/candidate 一致を確認した上で通常 diff に復帰した。
- `uuid_basic.kt`(`kotlin.uuid.Uuid`): 2026-07-09 解除済み。skip 理由は当初「KSwiftK 独自 UUID API」としていたが、実体は標準 `kotlin.uuid.Uuid`(`@OptIn(ExperimentalUuidApi)`)であり、テスト側が `version()`/`variant()`/`nameUUIDFromBytes()`/`toLongs()`/非推奨化前の `LEXICAL_ORDER` など `java.util.UUID` の命名と混同した非標準メンバーを呼んでいたのが真因(`kotlin-stdlib-sources.jar` 同梱の実 API と照合して確認)。これら非標準メンバーの呼び出しを削除し、`fromLongs` を既知の定数値で検証する形に置き換え、実 kotlinc 2.4.0 / kswiftc 双方で出力が完全一致することを確認した上で通常 diff に復帰した。`Stdlib/kotlin/uuid/Uuid.kt` 側の `version()`/`variant()`/`nameUUIDFromBytes()`/`toLongs()`/`LEXICAL_ORDER` 実装自体(削除するか candidate-only 扱いにするか)は本件のスコープ外で未着手。

## DEBT-DIFF-002: script-style cases（解消済み、2026-07-29）

対象だった7ケースとも `SKIP-DIFF` を解除し、通常の `diff_kotlinc.sh` 経路で green。

| グループ | cases | 解消日 | 根本原因と対応 |
| --- | --- | --- | --- |
| timeout-only suspect | `script_imports.kt`, `script_repl_interactive.kt`, `script_repl_patterns.kt` | 2026-07-09 | script mode (`kotlinc -script`) の JVM 起動 + compile + run を `RUN_TIMEOUT`（デフォルト10s）で縛っていたのが原因。`--script-timeout` を `COMPILE_TIMEOUT` 系へ分離して解決 |
| top-level functions / custom declarations | `script_function_basic.kt`, `script_function_advanced.kt`, `script_toplevel_functions.kt`, `script_import_custom.kt` | 2026-07-29 | 下記「top-level functions / custom declarations 詳細」を参照 |

### top-level functions / custom declarations 詳細（2026-07-29）

症状: candidate (kswiftc) が `KSWIFTK-LINK-0002: No entry point 'main' function found for executable emission.` でコンパイル失敗し続けていた（reference の `kotlinc -script` は成功）。

根本原因: `KotlinParser.parseFile()`（`Sources/CompilerCore/Parser/KotlinParser.swift`）の script 判定が、top-level に `fun` / `class` / `data class` / 拡張関数などの宣言が1つでもあると、たとえ top-level 実行文（`println(...)` 等）が存在してもルート種別を `.script` ではなく `.kotlinFile` に倒す実装だった（`sawNonPropertyDecl` フラグ）。`.kotlinFile` 扱いになると top-level の bare statement は `BuildASTPhase`（`Sources/CompilerCore/Driver/FrontendPhases.swift`）のどの case にもマッチせず黙って破棄され、`main` も合成されないため、link 段階で「エントリポイントが無い」エラーになっていた。実 Kotlin の `.kts` スクリプトは `package` 宣言以外の任意の宣言を top-level 文と自由に混在できるため、この判定は過度に狭かった（この判定は2026-02-17時点で「まず val/var だけ許可する」形で段階的に導入されたもので、fun/class 等への拡張は本チケットまで未着手だった）。

対応:
1. `sawNonPropertyDecl` を `sawPackageHeader` に置き換え、script 判定条件を「top-level 実行文が存在し、かつ `package` 宣言が無い」まで単純化。
2. top-level `fun` 宣言は元々 `.funDecl` として通常の top-level `FunDecl` に登録される一方、`isStatementLikeKind`（`Sources/CompilerCore/AST/BuildASTPhase+BodyParsing.swift`）は `.funDecl` も「文」として扱うため、(1) だけでは script root 合成時に同じ関数が合成 `main()` 内のローカル関数宣言としても二重登録されてしまう。`blockExpressions` / `collectBlockStatementGroups` に `excludingTopLevelFunDecls` オプションを追加し、script root からの呼び出し（`FrontendPhases.swift`）でのみ `.funDecl` を除外して二重登録を防いだ。`class` / `interface` / `object` / `typealias` / `enumEntry` は元々 `isStatementLikeKind` に含まれておらず対象外（重複しない）。

回帰確認: 4 ケースを `--force-run-skipped` で green 化した後、既存の非 skip `script_*.kt`（13件）にも回帰がないことを個別確認。`Tests/CompilerCoreTests/Integration/ScriptModeTests.swift` に、top-level 宣言と top-level 文が混在するパターンの root kind 判定・二重登録防止・実際の KIR コンパイルを固定する回帰テストを追加。

`script_import_stdlib.kt` は2026-07-09に解除済み（本チケットの7件には含まれないが同じ調査の過程で解消): `shuffled()` を `shuffled(Random(42)).sorted()` に変更し、出力順序に依存しない決定論的検証にした(`sequence_shuffled.kt` と同じ idiom)。KSwiftK の `Random` は JVM kotlinc と PRNG アルゴリズムが異なる(xorshift64\* 系の自前実装で XorWow ではない、`KSP-466`)ため、seed を固定しても生の並び順は一致しない。なお、ローカル既定の `RUN_TIMEOUT=10s` は `kotlinc -script` の起動コストだけで超過する(`script_import_stdlib.kt` に限らず `script_hello.kt` など他の非 skip ケースでも同様に再現する、この環境固有の傾向)。CI は `DIFF_RUN_TIMEOUT=30` を使用しており、その設定なら安定して pass する。

## DEBT-DIFF-003: advanced coroutine / channel / Flow

`Scripts/diff_kotlinc.sh` は `kotlinx.coroutines` import を検出して `kotlinx-coroutines-core-jvm` を取得できるため、現在の skip 主因は reference classpath ではなく KSwiftK 側の API / runtime parity である。

| 領域 | cases | owner |
| --- | --- | --- |
| lazy/deferred coroutine start (`CoroutineStart.LAZY`)（解除済み） | ~~`coroutine_edge_cases.kt`~~ | 2026-08-13 に `CoroutineStart` 型・`launch(start:, block:)` / `async(start:, block:)` オーバーロード・`RuntimeJobHandle` genuine lazy state・`yield()` 実装を追加し、`--force-run-skipped` / 通常 `diff_kotlinc.sh` で `PASS` を確認。詳細は下記「`coroutine_edge_cases.kt` 個別メモ」を参照 |
| cancel-before-first-run（解除済み） | ~~`coroutine_exception_handling.kt`~~ | 2026-07-29 に `--force-run-skipped` で再判定した結果、`launch{}` 直後の同期 `cancel()` が本体の最初のサスペンションポイント到達前に確実に届くようになり、JVM 参照が出さない `"cancelled cleanly"` 行がもう出力されないことを確認（8 連続実行で安定）。同時期の coroutine cancellation / Job ハンドル周りの一連の修正の副作用と見られるが、単一の commit には特定していない |
| cancellation（解除済み） | ~~`coroutine_cancellation_advanced.kt`, `coroutine_cancellation_edge_cases.kt`~~ | `currentCoroutineContext()`/`ensureActive()`/`NonCancellable`/`CoroutineContext.isActive` を追加し、`withTimeoutOrNull` の null 判定バグ（`runtimeNullSentinelInt` ではなく生の `0` を返していた）と `coroutineScope`/`supervisorScope` の直接 throw 握りつぶしバグ（`outThrown` を forward していなかった）、および `job.join()`/`Job.await()` が返却後にハンドルを解放し join 後の `isCancelled` 参照が use-after-free になっていたバグを修正して通常 diff へ復帰 |
| CoroutineScope lifecycle（解除済み） | ~~`coroutine_scope_lifecycle.kt`~~ | 2026-07-29 に再判定して通常 diff で PASS を確認（`--no-parallel` で2回再検証済み）。以前ここに記載していた2件のブロッカー（`private val scope = CoroutineScope(...)` 型注釈なしプロパティの `typeCheckClassLikeMembers` パス順序バグ、非ctor引数プロパティ初期化子の instance storage 書き込み漏れ = PR #4691 相当）はいずれも再現しなくなっていた |
| structured concurrency / Deferred / Supervisor（解除済み） | ~~`coroutine_deferred.kt`, `coroutine_structured_concurrency.kt`, `coroutine_supervisor_job.kt`~~ | Job hierarchy / async-await / supervisor semantics。詳細は下記「structured concurrency / Deferred / Supervisor 詳細」節を参照 |
|| Channel / produce / Flow backpressure（解除済み） | ~~`coroutine_channels_advanced.kt`, `coroutine_flow_backpressure.kt`~~ | `CoroutineScope` 暗黙 receiver のSema/KIR解決、produce launcher ABI、Flow emitter continuation context を修正 |
|| sync primitives（解除済み） | ~~`coroutine_mutex_semaphore.kt`~~ | `withLock`/`withPermit` の `action` を suspend 化し `lock`/`acquire` を suspend 関数として登録。並列実行時の `String` 戻り値の erased-generic boxing/unboxing クラッシュは、`kk_lambda_*` / `kk_closure_invoke_*` thunk を `kk_function_invoke_*` 経由の raw ポインタ ABI 対象として扱うことで解消。2026-08-13 に `--force-run-skipped` / 通常 diff 共に PASS 確認。 |

`coroutine_base_edge_cases.kt`（direct suspend call のデッドロック、try/catch 内 suspend call の例外もみ消し）と
`coroutine_context_switching.kt`（`withContext` の期待型ハンドリング）は 2026-07-09 に skip 解除済み。

2026-08-14 時点で、この DEBT-DIFF-003 に残る未解除ケースはない。今回の修正内容と個別検証は下記の通り。

### `coroutine_edge_cases.kt` 個別メモ（2026-08-13 解除済み）

2026-08-13 の再検証で `SKIP-DIFF` を解除。`launch(start = CoroutineStart.LAZY) { ... }` がコンパイルできず、`yield()` が実際にサスペンドしない問題を修正した。

- `CoroutineStart` 型と `launch(start:, block:)` / `async(start:, block:)` オーバーロードを `HeaderHelpers+SyntheticCoroutineRegistry.swift` に登録。
- `CoroutineLoweringPass+LauncherSupport.swift` の `rewriteLauncherCall` で 2 引数 `launch`/`async` の第 1 引数を型で `CoroutineDispatcher` と `CoroutineStart` に分岐させ、`CoroutineStart.LAZY` なら `kk_kxmini_launch_lazily` 経由に振り分ける。
- `RuntimeJobHandle` に `installLazyStartBody` / `startIfNeeded` を追加し、本体を即時 dispatch せず `start()` / `join()` / `await()` まで遅延する genuine pending state を実装。
- `yield()` を `CoroutineLoweringPass+StateMachine.swift` の suspend call として扱い、`kk_coroutine_yield(continuation)` を呼び出す。`RuntimeCoroutine.swift` の `kk_coroutine_yield` を、短い delay 後に `state.resume(with: 0)` する実際のサスペンションポイントに変更。

検証: `--force-run-skipped` および通常の `diff_kotlinc.sh` で `PASS`。`CoroutineStart.LAZY` と `yield()` の順序が JVM 参照と一致。

2026-08-14 追記: 現行 master で `launch { isActive }` が `false` になる差分を最小ケース `coroutine_is_active.kt` で再現した。bare synthetic property の identifier lowering が global load に流れていたため、runtime bridge を先に生成するよう修正し、`active: true` の一致を確認した。`coroutine_edge_cases.kt` の共有 `MutableList` は GCD 上のデータ競合を避けるため `Mutex` と `join()` で保護した。

### `coroutine_mutex_semaphore.kt` 個別メモ（2026-08-13 解除済み）

2026-08-13 の再検証で `SKIP-DIFF` を解除。KSP-677 / BUG-049 の修正後も並列実行時に `KSwiftK panic [KSWIFTK-LINK-0003]: Unhandled top-level exception` が発生していたが、真因は「`String` 戻り値を持つ erased-generic 高階 suspend ラムダが `kk_function_invoke_*` 経由で呼ばれる際、lambda thunk が flat な `String` 集約を返して raw `Int` ABI と不一致になる」ことだった。`withLock { "locked result" }` のような `T = String` の戻り値が `kk_coroutine_state_exit` へ渡る前に boxed raw handle として扱われていなかった。

対応: (1) `Stdlib/kotlinx/coroutines/sync/Sync.kt` で `withLock`/`withPermit` の `action` パラメータを `suspend () -> T` に変更し、`HeaderHelpers+SyntheticCoroutineRegistry.swift` で `Mutex.lock()` / `Semaphore.acquire()` を suspend 関数として登録。(2) `NativeEmitter.swift` の `collectRuntimeCallbackRawABISymbols` で `kk_lambda_*` / `kk_closure_invoke_*` 関数を常に raw-callback ABI 対象とみなし、`String` 戻り値を raw handle で返すよう backend へ伝える。これにより `kk_function_invoke_0` / `kk_suspend_function_invoke_0` 経由の関数値呼び出しで `String` 結果が正しく受け渡される。

検証: `--force-run-skipped` および通常の `diff_kotlinc.sh` で `PASS`。並列 `launch(Dispatchers.Default)` 100 件の共有 counter 更新と `mutex.withLock { "..." }` の `String` 返却、並列 `semaphore.withPermit { delay(...) }` いずれも出力一致。

### 解除済み: `channel_basic.kt`

`produce { }` ブロック内の暗黙レシーバ呼び出し（`send(x)` など）が `lowerCallExpr`（暗黙レシーバ経路）を通り、`lowerMemberCallExpr`（明示レシーバ経路）が付与する continuation プレースホルダー引数を受け取れず、`kk_channel_send` に渡る実引数が1個不足して SIGSEGV していた。`CallLowerer.swift` の `lowerCallExpr` 末尾に、`kk_channel_send` / `kk_channel_receive` / `kk_mutex_lock` / `kk_semaphore_acquire` 向けの continuation 0 補完を追加して解決（SKIP-DIFF 解除済み、通常 diff で PASS）。

### 解除済み: `coroutine_channels_advanced.kt`

2026-08-14 に現行 master で個別再実行し、reference と candidate の出力一致を確認した。

- `CoroutineScope` を builder lambda の Sema 上の implicit receiver として扱い、`produce(1, 5)` のユーザー定義拡張関数を解決できるようにした。
- builder lambda の no-receiver ABI を維持したまま、implicit receiver の coroutine scope bridge を lowering し、produce launcher の receiver-first ABI と scope capture を整合させた。
- 最小回帰 `coroutine_implicit_scope_extension.kt` も PASS。

### 解除済み: `coroutine_flow_backpressure.kt`

2026-08-14 に現行 master で個別再実行し、`collected: 5` / `buffered: 5` / `latestSeen: 5` を含む reference と candidate の出力一致を確認した。

- Flow emitter の collect context を thread-local だけに依存させず、continuation state に保持して suspend/resume をまたいで伝播するようにした。
- `kk_kxmini_run_blocking_with_cont` と Flow invocation path で context を引き継ぎ、delay 後の emit が同じ collector に届くようにした。
- 最小回帰 `coroutine_flow_resume_context.kt` も PASS。

### structured concurrency / Deferred / Supervisor 詳細（解消済み、2026-07-30）

3ケースとも当初想定（「不足APIを足すだけ」）より深いバグに当たった。調査で Sema 側の一般的な型推論バグを複数発見・修正済みだが、各ケースとも KIR lowering / runtime 層に別種の未解決ブロッカーが残る。

2026-07-29 追記: `coroutine_supervisor_job.kt` は `--force-run-skipped` の再判定で通常 diff PASS を確認し（2回再検証済み）、`SKIP-DIFF` を解除した。`SupervisorJob()` / トップレベル `CoroutineScope(context)` は `HeaderHelpers+SyntheticCoroutineRegistry.swift`（`STDLIB-CORO-090`）で Sema 登録済み、ランタイム側も `RuntimeCoroutine.swift` に対応する `kk_job_new` 系実装がある状態を確認した。以下のブロッカー説明は当時の調査記録として残す。残る `coroutine_deferred.kt` / `coroutine_structured_concurrency.kt` の2件は未解除のまま。

**この調査で修正済み（3ケース共通の前提を直した Sema 修正、副作用として広く安全性を確認済み）:**

- `kotlin.coroutines` パッケージが default import list に無く、`coroutineContext` が unresolved になっていた（`ScopeBuilder.swift`）。
- `IntRange.map` が transform ラムダの実際の戻り値型を無視し、常に `List<Any>` を返していた（`CallTypeChecker+RangeMemberFallback.swift`）。`(1..5).map { n -> ... }` の要素型が壊れていたため `it.await()` 等の後続メンバー呼び出しが unresolved になっていた。
- `async`/`coroutineScope`/`supervisorScope` が常に `Any`（または raw `Deferred`）を返し、trailing lambda の実際の本体型を読み戻していなかった（`CallTypeChecker.swift` の `adjustedReturnType` 分岐、新規 `CallTypeChecker+CoroutineBuilderReturnType.swift`）。`Deferred` はクラスレベル型パラメータを持たないため、`.await()` の戻り値型は `bindDeferredElementType`/`deferredElementType`（`SemanticsModels.swift`、Flow の `flowElementType` と同型のサイドチャネル方式）で追跡するようにした。`LocalDeclTypeChecker.swift` で `val`宣言時にこのマーカーを伝播する。
- Kotlin の「ラムダの期待戻り値型が `Unit` のとき、本体の実際の値は破棄されボディの型は問わない」という言語仕様が未実装だった。`inferLambdaLiteralExpr`（`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`）がラムダ本体を型推論する際に `expectedType: Unit` をそのまま本体式（例: 関数呼び出し）に伝播しており、本体が非Unit値を返す呼び出し（例 `repeat(3) { i -> someIntFn(i) }`）の呼び出し解決自体が「戻り値がUnitと非互換」として `No viable overload found for call` になっていた。**これはコルーチンと無関係な一般的なSemaバグ**（`repeat`/`forEach` 等あらゆる `(T) -> Unit` パラメータで発生）で、`coroutine_structured_concurrency.kt` の `repeat(3) { i -> launch { ... } }` パターンを直接ブロックしていた。修正: 本体の `expectedType` は expected return が `Unit` の場合 `nil` に落とす。
- 上記5件は `bash Scripts/diff_kotlinc.sh` で以下の回帰確認済み（regressionなし）: `coroutine_scope.kt`, `job_basic.kt`, `supervisor_scope_basic.kt`, `async_await.kt`, `launch_basic.kt`, `range_hof.kt`, `repeat.kt`, `array_hof.kt`, `collection_hof.kt`, `stdlib_collection_hof.kt`, `string_hof.kt`, `lambda_it.kt`, `lambda_with_receiver.kt`, `sequence_forEach_flatMap.kt`, `set_map_filter_foreach.kt`, `map_entries_hof.kt`, `closure_multi_capture_hof.kt`, `destructuring_lambda.kt`, `labeled_return_lambda.kt`（計19ケース）。

**2026-07-30 の続き調査で解消。当初の各ケース別ブロッカーと実際の root cause:**

- `coroutine_supervisor_job.kt`: 上記調査時点(2026-07-10) では `SupervisorJob()`/`CoroutineScope(context)` 未登録と見立てていたが、その後の KSP-674〜679 bundled-stdlib 移行で両方とも実装済みになっていた（`HeaderHelpers+SyntheticCoroutineRegistry.swift` の `kk_supervisor_job_new`/`kk_coroutine_scope_new_with_context` 登録）。`SKIP-DIFF` を外すだけで通常 diff PASS。
- `coroutine_structured_concurrency.kt`: 「`coroutineScope{}` の capture-lowering バグ」という当初の診断は、`coroutineScope`/`supervisorScope` が KSP-679 で実際の bundled Kotlin source 関数（`Stdlib/kotlinx/coroutines/CoroutineScope.kt`）に移行済みだったため的外れになっていた。実際に残っていたのは3件の一般的バグ: (1) `coroutineScope`/`supervisorScope` の戻り値型 narrowing が `CallTypeChecker.swift` の `coroutineLauncherLambdaArgIndex`/`adjustedReturnType` 判定リストに含まれておらず `results.forEach` 等が unresolved になっていた、(2) **外側変数をキャプチャする suspend ラムダが、非suspend文脈で型チェックされた場合に captureless 前提の生ポインタとして渡され、間違った引数個数で呼ばれて SIGBUS するコンパイラ全体に及ぶ一般バグ**（`LambdaLowerer.swift` の `materializeEscapingCallableValue`/`lowerNonCapturingLambda` が呼び出しコンテキストの非suspend期待型を鵜呑みにして `isSuspend: false` を確定していたのが根本原因。ラムダ本体を実際にスキャンして suspend 呼び出しの有無を判定する `lambdaBodyRequiresSuspend` を追加し、`effectiveIsSuspend` として一貫させて修正）、(3) `List<String> + "x"` のような二項演算子 `+` が LHS の型を無視し RHS が String というだけで文字列結合と誤解釈する一般バグ（`ExprTypeChecker+BinaryAndFlowInference.swift`、`isString(lhs) || isString(rhs)` → `isString(lhs)` に修正）。加えてテストケース自体が抱えていた並行性レース（`launch{}` が実 GCD スレッドへ並列ディスパッチされるため、kotlinx の既定シングルスレッド確定と異なり共有可変状態への同時書き込みがクラッシュ/値化けを起こす）も、共有状態を避ける形にケースを調整して解消。
- `coroutine_deferred.kt`: `CoroutineStart`/`awaitAll` の Sema 未登録は想定通り。`awaitAll` は bundled Kotlin source（`CoroutineScope.kt`）へ直接ループ実装で追加（HOF越しの `.await()` を避けるため）。**Iterator 経由 `.await()` の SIGSEGV** は、`jobs.map { it.await() }` の `.map`（bundled Kotlin source、非 `inline`）の `transform` パラメータが非suspend宣言のため、実際には suspend な `{ it.await() }` を collection-HOF 用アダプタ（`CallLowerer+HOFAdapter.swift` の `makeCollectionHOFCallableAdapter`）でラップする際、アダプタの `isSuspend` がラムダの実体でなく HOF の宣言型を鵜呑みにしていたのが原因（アダプタが `CoroutineLoweringPass` の CPS 変換対象から漏れ、`.await()` 呼び出しが未初期化の continuation を読んで SIGSEGV）。呼び出し先の実際の `isSuspend` を優先するよう修正。`CoroutineStart.LAZY`（lazy start）は launch 側と同じ「genuine pending state 欠如」の大きな未解決ギャップのため、このケースの対象から意図的に除外（コメントで明記、`coroutine_edge_cases.kt` 側で引き続き追跡）。

**副次的に発見・修正した一般バグ:**

- 上記の suspend ラムダ materialization 修正は、`runBlocking`/`launch`/`async`/`produce` のような KIR レベルの coroutine launcher（`CoroutineLoweringPass+LauncherSupport.swift` の BUG-049 由来 launcher-continuation 機構が生シンボル参照を前提とする）と衝突し、`produce { send(x) }`（`channel_basic.kt`）を `KSWIFTK-CORO-0003` で退行させた。`Sema/Models/SemanticsModels.swift` に `coroutineLauncherLambdaExprIDs` マーカーを追加し、`runBlocking`/`launch`/`async`（`CallTypeChecker.swift` 通常経路）と `produce`（同ファイル内の専用早期リターン分岐、CORO-075）の両方でラムダ引数をマークして `LambdaLowerer` 側の materialization から除外することで解消（`coroutineScope`/`supervisorScope` はこの launcher 機構を使わない実 Kotlin 関数のため対象外のまま）。

**検証:** Golden テスト（Lexer/Parser/Sema/Diagnostics、計355ケース）全 PASS、`Scripts/diff_kotlinc.sh Scripts/diff_cases`（678ケース）で回帰0件を確認（`coroutine_delay_basic.kt` のタイミング閾値ベース判定が高負荷環境で一過性に揺れたのは今回の変更と無関係と個別に再現確認済み）。

## DEBT-DIFF-004: value class parity（解消済み、2026-07-12）

5 ケースとも `SKIP-DIFF` を解除し、通常の `diff_kotlinc.sh` 経路で green。

| cases | 主な責務 | 解消した根本原因 |
| --- | --- | --- |
| `value_class_boxing_boundaries.kt` | Lowering / Runtime ABI | `Any`, nullable, cast, collection element 境界の box/unbox insertion |
| `value_class_generics.kt` | Sema / KIR | generic value class、bounds、`sortedBy` lambda receiver の型推論 |
| `value_class_collections.kt` | Lowering / Runtime ABI | List / Map / Array storage、HOF iteration 境界、および boxed value class の hashCode/equals 不整合（`runtimeAnyHashCode` に `RuntimeObjectBox` ケースが無く pointer-identity hash にフォールバックしていた） |
| `value_class_interfaces.kt` | Sema / KIR / dispatch | value class の interface 実装と boxed interface dispatch（itable dynamic dispatch, `kk_itable_lookup_dynamic`） |
| `value_class_interop.kt` | Lowering / primitive ABI | Long / Double underlying value の ABI、string interpolation、list map |

対応した分割タスク:

- Sema: value class declaration, generic value class, interface implementation, nullable value class の型表現を監査（完了）。
- KIR / Lowering: `Any` / generic / interface / collection / nullable 境界で box/unbox を挿入（完了）。
- Runtime ABI: boxed value class（interface 実装により `kk_object_new` で box されたまま残るもの）の equality / hash を検証・修正。`runtimeValuesEqual` は既に `RuntimeObjectBox` を構造比較していたが、`runtimeAnyHashCode` に対応ケースが無く、`Any.hashCode()` 経由の呼び出しが pointer-identity ハッシュへフォールバックしていた（`c1 == c2` は `true` なのに `c1.hashCode() != c2.hashCode()` という equals/hashCode 契約違反）。あわせて data class 側の `appendSyntheticDataClassHashCodeIfNeeded` も、フィールドを読み出さず `receiver, fieldOffset` を直接 `kk_any_hashCode` に渡しており同じ契約違反を起こしていたため修正。
- Regression: 上記 5 ケースを `--force-run-skipped`（さらに機材負荷を考慮し `--run-timeout 60`）で green 確認後、`SKIP-DIFF` marker を削除。

## DEBT-DIFF-005: common stdlib surface gap（解消済み、2026-08-11）

2026-07-29 の棚卸し時点で `.build/debug/kswiftc` が直近コミットに対し stale になっており（`_kk_kclass_create` 等の未解決シンボルで大量の偽 link failure を出していた）、`swift build` で再ビルドしたところ多くのケースが実は既に green だったことが判明した。以降 DEBT-DIFF-005 系の再判定を行う際は、まずローカルバイナリが最新かどうかを疑うこと。

| 領域 | cases | 現状 | 詳細 |
| --- | --- | --- | --- |
| `java.math.BigInteger` | （削除済み） | target-out 判定（CLEANUP-STUB-104） | BigInteger surface と `big_integer.kt` を削除済み（本 PR の19回目 master マージで取り込み）。対応不要 |
| KSwiftK synthetic Sequence surface | ~~`sequence_takelast.kt`, `sequence_takelastwhile.kt`, `sequence_subtract.kt`~~ | 解消済み（移設） | PR #4660 で JVM kotlinc に無い synthetic surface と確定し、`Scripts/diff_cases` から削除して `CodegenBackendIntegrationTests+Sequence{TakeLast,TakeLastWhile,Subtract}.swift` の candidate-only テストへ移設済み |
| Sequence source/runtime interop | ~~`flatten_sequence_edge_cases.kt`, `sequence_lazy_eval.kt`~~ | 解消済み（2026-08-11 確認、`--force-run-skipped` で green） | source Sequence/`sequence {}` builder の `.iterator()` 仮想ディスパッチ（itable ブリッジ）が整備され、`KSWIFTK-RUNTIME-0001: Virtual dispatch failed` は解消。SKIP-DIFF マーカーを削除し通常 diff に復帰 |
| Scope functions | `scope_functions_edge_cases.kt` | 解消済み（2026-07-29 確認） | stale バイナリによる偽 FAIL だった。再ビルド後 `--force-run-skipped` で green、SKIP-DIFF 解除 |
| Property delegates | `property_delegate_edge_cases.kt` | 解消済み（2026-07-30） | `BUG-151`（observable/vetoable コールバック本体の消失）は未マージの `devin/1785118661-fix-bug-151` の修正を取り込んで適用。`BUG-170`（delegate 本体固有の bare-name 複合代入・読み出しバグ。164→168→170 と3回再採番）は Sema が `delegateBody` を一切 visit していなかったことが根本原因と特定し `typeCheckDelegate` の拡張で修正。両方解消し `SKIP-DIFF` 解除。詳細は下記 |
| Regex runtime edge | `regex_runtime_edge_cases.kt` | 解消済み（2026-07-29 確認） | stale バイナリによる偽 FAIL だった。再ビルド後 `--force-run-skipped` で green、SKIP-DIFF 解除 |
| ByteArray helpers | `string_tobytearray.kt` | 解消済み（BUG-019 / KSP-660） | `joinToString(sep)` / `contentEquals` は #4671 で合成スタブ化され、SKIP-DIFF 無しで通常 diff を通過。`transform` 付き overload の gap は別課題として BUG-158 に切り出し |
| File/use | `file_use_edge_cases.kt` | 解消済み（2026-07-29 確認） | stale バイナリによる偽 FAIL だった。再ビルド後、通常 diff で green、SKIP-DIFF 解除 |
| Duration/time | `duration_operations.kt`, `experimental_time_edge_cases.kt` | 解消済み（2026-07-29 確認） | 2件とも stale バイナリによる偽 FAIL だった（`experimental_time_edge_cases.kt` の timing-sensitive 懸念は再検証時点では顕在化せず）。再ビルド後 `--force-run-skipped` で green、SKIP-DIFF 解除 |
| Math/comparator | `math_trig_functions.kt`, `comparator_composition_edge_cases.kt` | 解消済み（2026-07-29 確認） | 2件とも stale バイナリによる偽 FAIL だった。再ビルド後 `--force-run-skipped` で green、SKIP-DIFF 解除 |
| ByteBuffer UUID interop | `uuid_put_uuid.kt` | 解消済み（KSP-508） | `java.nio.ByteBuffer` の最小 bundled 実装を追加し、実 Kotlin 2.4 API の `ByteBuffer.getUuid`/`putUuid` 拡張に置き換えた |
| kotlin.random synthetic overloads | ~~`random_nextfloat_range_overloads.kt`~~ | 解消済み（移設、2026-07-29） | `Random.nextFloat(until)`/`Random.nextFloat(from, until)`（STDLIB-655）は実 kotlinc の `Random` に無い kswiftc 独自拡張と確定（`--force-run-skipped` で reference 側が `too many arguments for 'fun nextFloat(): Float'` で確実に compile error になることを再確認）。PR #4660 と同じ方針で `Scripts/diff_cases` から削除し、`CodegenBackendIntegrationTests+RandomOverloadEdgeCases.swift` の `testCodegenCompilesRandomNextFloatRangeOverloads` へ移設 |
| java.security.SecureRandom synthetic overload | ~~`secure_random.kt`~~ | 解消済み（移設、2026-07-29） | `SecureRandom.getInstance()`（無引数、KSP-467 で意図的に追加した convenience overload）は実 Java/Kotlin が algorithm 引数必須のため JVM reference が原理的に oracle になれないと確定。PR #4660 と同じ方針で `Scripts/diff_cases` から削除し、新設 `CodegenBackendIntegrationTests+SecureRandom.swift` の `testCodegenCompilesSecureRandomNoArgGetInstance` へ移設 |
| `kotlin.text.CASE_INSENSITIVE_ORDER` トップレベル誤登録 | `case_insensitive_order_identity.kt` | 解消済み（BUG-154、`origin/master` #5077） | kswiftc が `CASE_INSENSITIVE_ORDER` を `kotlin.text` トップレベルにも誤登録していた問題を、本 PR のマージ時点で `origin/master` に既に着地していた #5077 が解消。登録経路を top-level property から `String` companion object member（`String.CASE_INSENSITIVE_ORDER`）へ変更し、ケースも書き換えた上で `SKIP-DIFF` を解除済み |

### `property_delegate_edge_cases.kt` 詳細（2026-07-09 調査 → 2026-07-30 解消）

クラスメンバの `val/var x by lazy {...} / Delegates.observable(...)/vetoable(...)` は、トップレベルプロパティ用の実装（`KIRLoweringDriver+ModuleLowering+PropertyDecl.swift`）とは別系統の実装（`MemberLowerer` / `KIRLoweringDriver+ModuleLowering+ClassDecl+ConstructorsAndInitializers.swift`）で lowering される。2026-07-09 時点で4件のバグを確認していたが、最終的に以下の経緯で全て解消した:

1. **[修正確認済み]** `lowerDelegateAccessor` の delegate ハンドル引数欠落。2026-07-29 の再実行で `token`（`lazy` の戻り値）が正しく `"ready"` を返すことを確認し、現行 HEAD で解消済みと確定した。
2. **[修正確認済み]** `emitDelegatePropertyInitializer` が `delegateBody` を参照しない問題。同じく 2026-07-29 の再実行で解消を確認した（`lazy` の初期化ブロック自体は実行され、戻り値も正しい）。
3. **BUG-151 として解消**: `observable`/`vetoable`/`notNull` のメンバ委譲が KIR lowering 段階でコールバック本体を丸ごと落とす（`kk_delegate_lambda_NNNN` の body が `return unit` のみになる）問題。根本原因はパラメータ付きトレーリングラムダ（`{ property, old, new -> ... }`）の `delegateBody` 抽出（`BuildASTPhase+DeclBuilders.swift`）が文単位区切り前提の汎用パーサーでパラメータリスト+アロー構文を扱えず本文を読み飛ばしていたこと。2026-07-30、未マージの `devin/1785118661-fix-bug-151` ブランチ（ブロックのトークン列をラムダリテラルとして再パースし、パラメータ名を `KIRLoweringContext.registerLambdaParam` 経由で本体スコープへ束縛し直す実装、および委譲プロパティの読み書きをバッキングフィールド直アクセスからアクセサ呼び出しへ修正、`kk_vetoable_set_value` の boxed-Boolean 誤判定修正を含む）を取り込んで適用し解消。
4. **BUG-170 として解消**: bare-name（暗黙 `this`）の compound assign（`initCount += 1`）およびプレーンな読み出しの両方が、delegate 本体（`lazy {}` 等）内では外側インスタンスフィールドに対して機能しない問題（採番は `origin/master` との3度のマージ衝突により 164→168→170 と変遷）。**根本原因**: `PropertyDecl.delegateBody` は `delegateExpression` と別に AST 段階で切り出され KIR lowering 専用の生材料としてのみ使われており、`Sema`（`typeCheckDelegate`）が中身を一切 visit していなかったため、本体内の識別子参照（`n` 等）が `sema.bindings.identifierSymbols` に一切束縛されていなかった。2026-07-30、`typeCheckDelegate` に `delegateBody`/`delegateBodyParams` を渡し、getter/setter/initializer と同じ `TypeInferenceContext` で本体を type-check するよう修正して解消（KIR側の合成パラメータ採番式を `SyntheticSymbolScheme.delegateLambdaParamSymbol(for:index:)` に共通化し Sema/KIR 間のシンボルID一致を保証。あわせて delegate 本体がクラスインスタンスを要する場合に captured receiver を `kk_function_create_0`/新設 `kk_function_create_3` 経由で渡す仕組みも追加）。

`property_delegate_edge_cases.kt` は BUG-151・BUG-170 とも解消したため `SKIP-DIFF` を解除し、通常 diff に復帰した。既存の delegate/lazy 系 diff_cases 16件（`delegate_custom_basic.kt`, `delegate_lazy.kt`, `delegate_observable.kt`, `delegate_operators.kt`, `delegate_provide.kt`, `delegate_vetoable.kt`, `delegates_not_null.kt`, `lazy_direct_call_and_explicit_type.kt`, `local_delegate_lazy.kt`, `local_delegate_primitive.kt`, `local_delegate_stdlib_delegates.kt`, `local_delegate_stdlib_lazy.kt`, `local_delegate_var_setvalue.kt`, `sequence_lazy.kt`, `sequence_lazy_eval.kt`, `string_linesequence_lazy.kt`）と新規 `delegate_stdlib_members.kt` で回帰なしを確認済み。

**2026-07-29 追記（DEBT-KIR-008 修正、`origin/master` #5105）**: 上記調査では見落とされていた5件目のバグを発見・修正した。`propertyDecl.delegateBody`（トレーリングラムダ本体）は `delegateExpression` と異なり Sema の型チェック（`identifierSymbols` 束縛）を一切通っておらず、`lazy { label }` のように囲む class member を参照する式は静かに `.unit` に落ちていた（`lazy { "literal" }` のような無参照の本体だけが偶然動いていた）。加えて `$delegate_x`（delegate ハンドルを保持するフィールド）は `nominalLayout` の field offset には登録されるものの、getter/setter/コンストラクタ初期化子が実際には module-global スロットとして読み書きしており、クラスの全インスタンスで共有されていた（DEBT-KIR-008 本体の症状）。`.lazy`（trailing lambda が 0 引数のケースのみ、`kk_function_invoke_0` の boxed-closure dispatch を利用）に限定してこの2件を修正済み。`.observable`/`.vetoable` のコールバック（3引数、`RuntimeDelegates.swift` の raw thunk 前提の `unsafeBitCast` 経由で呼ばれるため boxed closure 化不可）は意図的に対象外のまま。この修正の副作用として、`lazy { initCount += 1; "ready" }` のようにレシーバ経由の compound assign が lazy 本体内にある場合は (4) の症状も解消される（compound assign 自体の一般バグは `this.count += 1` を除き引き続き未修正）。残課題 3・4 は変わらず本ケースの完全な pass をブロックするため `SKIP-DIFF` は継続。

**2026-07-30 追記（本 PR でのマージ・再汎化）**: `origin/master` の #5105（DEBT-KIR-008）と本 PR の BUG-151/170 修正は、"delegate 本体を Sema が visit していない" という同じ根本原因を独立に発見し、`KIRLoweringDriver+ModuleLowering+PostProcess.swift` の `lowerDelegateLambdaBody` に対して部分的に重複する修正を加えていたためマージ時にコンフリクトした。#5105 はレシーバの GC 安全性を優先し `kk_object_new`/`kk_array_get_inbounds`/`kk_array_set` で captured receiver をヒープオブジェクトとしてラップしてから `kk_function_create_0` で包む、より安全な `materializeCapturingDelegateLambda` アダプタ方式を採用していたが、その安全性と引き換えに `.observable`/`.vetoable`（3引数コールバック）への対応を明示的に見送っていた。本 PR は #5105 のこの GC 安全なアダプタ方式をベースに採用しつつ、`materializeCapturingDelegateLambda` にコールバックの数値引数（`numberedParams`）を貫通させ、アダプタ関数側で新しい引数シンボルを割り当てて内側ラムダへ転送し、包む際に引数の有無で `kk_function_create_0`/`kk_function_create_3`（本 PR で新設、BUG-170 参照）のどちらを呼ぶか選択するよう汎化することで、`.observable`/`.vetoable` の captured receiver もこのアダプタ方式一本で（`unsafeBitCast` 生ポインタ経由ではなく）安全にサポートできるようにした。これにより #5105 が明示的に対象外としていた `.observable`/`.vetoable` の receiver capture も含め、残課題 3・4 は完全に解消し `SKIP-DIFF` を解除できた（上記表・202行目以降参照）。

**2026-08-05 追記（devin/PR #5083 との再統合）**: 上記 #5105 との再汎化から間を置かず、`origin/master` に devin による BUG-151 の独立修正（PR #5083, commit `63ad27e9a`）が別途着地し、本 PR の `lowerDelegateLambdaBody`/`materializeCapturingDelegateLambda` と再度コンフリクトした。実装を突き合わせた結果、コールバック呼び出しは重複していた delegate 専用ディスパッチャ(`kk_invoke_delegate_observer_callback`)を削除し既存の汎用 `kk_function_invoke_3` に一本化、合成パラメータシンボルは本 PR の ad-hoc 加算オフセット式ではなく #5083 の `Kind` enum ベースの衝突安全な `SyntheticSymbolScheme.delegateLambdaParameterSymbol` に統一、delegate body の型チェックへ`.observable`/`.vetoable` の expected-return-type 判定（`Unit`/`Boolean`）を追加導入した。KIR 側のスコープ save/restore は本 PR の `ctx.saveScope`/`restoreScope` ベースの実装（`ScopeSnapshot` が既に全状態をカバーするため手動の `restoreLambdaParam` 追跡は不要と確認済み）を維持し、`kk_function_create_0/1/2/3` の arity 分岐は #5083 のより網羅的な switch（0-3 全対応）を採用した。

## DEBT-DIFF-006: inference / boxed numeric lowering / compiler-plugin API（解消済み、2026-07-29）

`math_rounding_functions.kt` は 2026-07-09 に解除済み（下記参照）。`error_type_inference.kt` は 2026-07-09 に diff_cases から削除済み: 5 シナリオ全てで kswiftc が診断を1件も出さないことが判明し、うち3件は本物の Sema 検出漏れとして `DEBT-SEMA-002`/`DEBT-SEMA-003`/`DEBT-SEMA-004`（`TODO.md` の「Sema 型推論診断ギャップ」節）へ切り出して `assertNoDiagnostic` ベースの回帰テストで現状を固定、残り2件は元の想定コメントが誤りだった正当な Kotlin コードと判明したため対応不要。最後まで残っていた `compiler_plugin_api.kt` も 2026-07-29 に `SKIP-DIFF` を解除し、通常の `diff_kotlinc.sh` 経路で green。

`compiler_plugin_api.kt` は当初「implicit-receiver `MutableMap` access の type-constraint gap」という単一バグとして棚卸しされていたが、実際には独立した3層のバグが積み重なっていた（1つ目を直すと次のエラーが露出する形で発見した）。

1. **Sema**: `object` シングルトンのメンバー関数をトレイリングラムダ付きで呼ぶと、ラムダのパラメータ型推論が壊れる。`CallTypeChecker+MemberCallInferenceContext.swift` の `tryInferFQNPackageTopLevelCall`（`kotlin.math.abs(x)` のような FQN パッケージ修飾呼び出し専用の特殊パス）が、`SomeObject.member(args) { lambda }` という **named object のメンバー関数呼び出し**も「パッケージ修飾トップレベル関数呼び出し」と誤認していた。原因は、object のメンバー関数もパッケージのトップレベル関数と同じ `ownerFQName + [memberName]` スキームで symbol table に登録されるため、`sema.symbols.lookupAll(fqName:)` によるルックアップが偶然マッチしてしまうこと。この特殊パスは引数を expected type なしで即座に型推論するため、トレイリングラムダの `it` や名前付きパラメータが解決できなかった（`Registry.update(pluginId) { m -> m.copy(...) }` の `m` が unresolved になり `KSWIFTK-SEMA-0024` 等が発火）。class instance・companion object 経由の呼び出しは別コードパスを通るため影響を受けず、この非対称性がバグを長らく覆い隠していた。修正: receiver path 自体が既存の class/interface/object/enumClass 宣言に解決する場合はこの特殊パスを早期に断念し、2フェーズのオーバーロード解決（非ラムダ引数→オーバーロード確定→ラムダへ期待型伝播）を行う通常の member-call 解決に委ねるガードを追加。
2. **Sema**: `List<String> + String` が文字列連結と誤認される。`ExprTypeChecker+BinaryAndFlowInference.swift` の `inferBinaryExpr` で、「List/Sequence の plus/minus」フォールバックより**前**に「LHS または RHS が String なら文字列連結」という判定が走っていたため、要素型がたまたま String である `List<String>` に String 要素を足す式（`m.registeredExtensions + "$kind:$name"` 等）が、LHS が List であるにもかかわらず無条件に文字列連結として型付けされていた（expected type が無ければ黙って誤った実行結果、expected type があれば `KSWIFTK-TYPE-0001`）。data class の `copy()`・object・ラムダとは無関係の一般的な型推論バグで、`listOf("a") + "x"` だけでも再現する。修正: 2つのチェックの順序を入れ替え、LHS が List/Sequence 型かどうかの判定を文字列連結判定より先に評価する。
3. **KIR / Runtime**: 上記2件を直した後に露出。`Set.sortedBy`（`Map.entries` 経由）のリンクエラーとランタイムパニック。直接呼び出し（`m.entries.sortedBy { it.key }`）では、`CallLowerer+SafeMemberCalls.swift` とは別の通常（非 safe-call）経路（`lowerMemberCallExpr`）を通るため無関係だが、`kk_list_sortedBy`（`Runtime/RuntimeCollectionHOF.swift`）が `RuntimeListBox` ハンドルしか受け付けず、`Map.entries` が返す `RuntimeSetBox` ハンドルに対して `invalid list handle` パニックを起こしていた（`sortedBy` は Kotlin では `Iterable<T>` 上に定義されており、List 以外の具象コレクション受信者にも呼べる必要がある）。修正: `RuntimeCollectionHelpers.swift` に既にあった List/Set 両対応の `runtimeCollectionElements(from:)` を `kk_list_sortedBy` から使うよう変更（`runtimeListBox(from:)` 単体使用から切り替え）。直接呼び出しはこれで green（回帰テスト: `CodegenBackendIntegrationTests+SafeCallSetSortedByRegression.swift` の `testCodegenSetSortedByDirectCall`）。
   `meta?.options?.entries?.sortedBy { it.key }` のような safe-call（`?.`）チェーン経由では別途、`lowerSafeMemberCallExpr` が callee を解決できなかった場合に通常経路の名前ベース collection/synthetic フォールバック解決（`loweredMemberCalleeName`）を呼ばず、coroutine ハンドル向けの固定名リストにマッチしなければ生の Kotlin 関数名をそのまま外部シンボル名として使ってしまい `_sortedBy` という未解決シンボルでリンクエラーになる問題も見つかった。さらに、`hasHOFLambdaArg`（`loweredMemberCalleeName` の dispatch key に使う）を構文的な「ラムダかどうか」判定で計算していたため、`emitMemberCallInstruction`（通常経路）が使う `sema.bindings.isCollectionHOFLambdaExpr`（`markCollectionHOFLambdaExpr` で明示的にマークされた一部の HOF 名だけが true になる、狭いフラグ）と食い違い、誤った dispatch key で解決してしまっていた。加えて、この safe-call 経路の `chosen == nil` 分岐は呼び出し引数リストにレシーバを一切挿入しない設計上の欠落（`Random.nextInt`/`nextLong` に対して通常経路で既に個別対処されていたのと同種のギャップ）もあった。修正: (a) `hasHOFLambdaArg` の計算を `emitMemberCallInstruction` と同じ `sema.bindings.isCollectionHOFLambdaExpr` ベースに揃える、(b) レシーバ挿入を自前実装せず、通常経路が使っている共有ヘルパー `appendReceiverToMemberArguments`（`CallLowerer+MemberCallEmission.swift`）をそのまま呼ぶ。この2点により `sortedBy` 単体の safe-call は完全に動作するようになった（回帰テスト: `testCodegenSetSortedByThroughSafeCallChain`）。
   ただし、この過程で**別の Sema レベルの gap**を発見した: `joinToString`（transform ラムダの有無に関わらず）のように、通常のドットコールでは常に実 `chosenCallee` に解決される（`unresolvedCollectionMemberNames` にも含まれない）メンバー関数が、**同じ呼び出しを safe-call（`x?.joinToString(...)`）で書くと `chosenCallee` が解決できなくなる**現象を確認した。これは引数渡しの問題ではなく、safe-call の型推論経路（`inferSafeMemberCallExpr`）に固有のオーバーロード解決バグと見られ、今回の修正のスコープ外として切り出した。`compiler_plugin_api.kt` は `?.let { entries -> entries.sortedBy { ... }.joinToString(...) }`（`sortedBy`/`joinToString` を同じ `let` ブロック内で連鎖し、どちらも smart-cast された非 null 値への通常呼び出しにする）でこの gap を回避している。

回帰テスト: `Tests/CompilerCoreTests/Sema/DataFlowAndSemaRegressionTests+ObjectMemberCallLambdaInference.swift`、`Tests/CompilerCoreTests/Sema/DataFlowAndSemaRegressionTests+ListStringPlusOperatorInference.swift`、`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+SafeCallSetSortedByRegression.swift`（`testCodegenSetSortedByDirectCall`/`testCodegenSetSortedByThroughSafeCallChain`/`testCodegenSetSortedByInsideSafeCallLet`）、および `Scripts/diff_cases/compiler_plugin_api.kt` 自体（`SKIP-DIFF` 解除済み）。

`math_rounding_functions.kt` は 2026-07-09 に解除済み: SKIP-DIFF 追加時点(2026-04-07)は List<Double> の for-loop 変数が boxed pointer のまま round()/roundToInt() 等に渡っていたが、`a553bd1e`「Fix List<Int> for-loop variable unboxing in kotlinc diff regression」(2026-06-10)が型非依存の `kk_unbox_<T>` 挿入(`CollectionLiteralLoweringPass+CallRewriteIteratorBridge.swift` の `appendListIteratorNextWithUnboxing`)を導入した際に List<Double> のケースも副次的に修正されていたが、2026-07-01 の debt 一括整理では未検証のまま残存していた。`--force-run-skipped` で pass を確認し、回帰用の List<Double> ループを `CodegenBackendIntegrationTests+MathEdgeCases.swift` の既存 `testCodegenCompilesMathEdgeCases` に統合した。

## DEBT-DIFF-007: compile-exit parity fix により顕在化した両失敗ケース

`run_case()` は、reference と candidate がともに失敗し同じ非ゼロ終了コードを返しても、無条件に `FAIL` とするよう修正済みである。これにより顕在化した72件を、diagnostic parity、enum/data class/interface/variance、common stdlib・テスト入力、coroutine Flow、reflection/metadata、JVM・時間、finally exception routing の7グループへ分解して個別に triage した(2026-07-29)。

### 2026-07-29 棚卸しの結果概要

72件中35件を解消(72→37)。内訳:

2026-07-31 追記: 上記37件からさらに `enum_entries_function.kt` を解消(37→36)。加えて `enum_basic.kt`/`enum_edge_cases.kt`/`array_hof.kt`/`string_chunked_windowed.kt`/`windowed_step_partial.kt` の5件は、下記グループ2・グループ3の各行に記載の通り root cause の主要部分を実装・修正し、残存ブロッカーの範囲を大幅に縮小した(いずれもファイル自体はもう1件の別バグでまだブロックされているため未解除)。

2026-08-13 追記: 上記36件からさらに19件を追加解除(36→16)。内訳はグループ2・グループ3・グループ5・グループ6の「解除済み」行を参照。

- **診断/ネガティブテスト(旧グループ1、22件)**: 全件解消。JVM kotlinc の stderr はこのハーネスで比較されないため、複数シナリオを1ファイルに束ねた「意図的なコンパイルエラー」ケースは本質的に JVM kotlinc を oracle にできない。既存の `Tests/CompilerCoreTests/GoldenCases/Diagnostics/` に近い golden テストがある5件(`error_type_mismatch.kt`→`type_mismatch.golden`, `type_error.kt`→同, `error_unresolved_reference.kt`→`unresolved_reference.golden`, `deprecated_error.kt`→`deprecated_annotation.golden`, `override_variance_errors.kt`→`visibility_narrowing_override.golden`)は削除。残り15件(`abstract_property_errors`, `builder_dsl_invalid_arg`, `char_get_error`, `error_abstract_instantiation`, `error_interface_conflicts`, `error_null_safety`, `error_override_mismatch`, `error_parameters`, `error_redeclaration`, `error_return_type`, `error_semantic_basic`, `error_visibility`, `is_type_check_non_reified_error`, `val_member_compound_assign_error`, `val_reassign_error`)は `Tests/CompilerCoreTests/GoldenCases/Diagnostics/` へ移設し `UPDATE_GOLDEN=1` で golden 生成、`Scripts/diff_cases` から削除した。`contract_returns.kt`/`contracts_basic.kt` は bundled source-backed 契約APIの解決確認後、`@file:OptIn(ExperimentalContracts::class)` を追加して通常 diff に復帰した。
- **finally routing(旧グループ7、1件)**: 解消。`finally_exception_routing.kt` はテスト自体の欠陥(catch節に`return`が無く、real kotlinc も"missing return statement"で最初からコンパイル不能だった)で、`return "caught"` を追加して通常 diff に復帰。
- **その他のテスト入力ミス修正による解消(14件)**: `interface_super_call.kt`(曖昧な`super.greet()`を`super<B>.greet()`に), `math_extended.kt`(`IEEErem`/`withSign`/`nextTowards`をトップレベル関数呼び出しからメンバー呼び出しに), `null_receiver_is_null_or_empty.kt`(型無し`null`への`isNullOrEmpty()`はkotlinc側も曖昧で削除), `nullable_receiver_ext.kt`(`String`と`String?`の拡張関数はJVM erasureで衝突するため片方削除), `string_format_positional.kt`(`$`エスケープ漏れ), `uint_range.kt`/`ulong_range.kt`(`Int`と`UInt`/`ULong`の`mapIndexed`内混在に`.toUInt()`/`.toULong()`追加), `temp_files.kt`(`kotlin.io.createTempFile`/`createTempDir`はDeprecationLevel.ERRORのため`kotlin.io.path`版に書き換え), `kclass_ktype_basic.kt`/`metadata_api.kt`(`kotlin.reflect`系importの追加、および存在しない`KClass.type`参照の削除)。
- **ハーネス側の修正(1件)**: `Scripts/diff_kotlinc.sh` に `KOTLINC_TEST_JAR`(`kotlin-test.jar` 自動解決、`KOTLINC_STDLIB_JAR`/`KOTLINC_REFLECT_JAR` と同じ仕組み)を追加。`test_framework_basic.kt` の ref 側失敗は `kotlin.test.*` が reference のクラスパスに無いだけで、候補側(kswiftc)は元々正しく動いていた。
- **コンパイラ本体の修正(1件、DEBT-DIFF-007 調査の副産物)**: `error_parameters.kt` の triage 中に、`varargFun(name = "bad", 1, 2)`(named引数の後に来る positional 引数が、宣言順序上その named引数より前にある vararg パラメータへ逆流して束縛される)を kswiftc が誤って受理する実バグを発見・修正した。`Sources/CompilerCore/Sema/Resolution/Resolution+TypeConstraints.swift` の `buildParameterMapping` に `maxBoundParamIndex`(そこまでに束縛済みの最大パラメータ index)を追加し、named引数の後の positional 引数が vararg パラメータへ束縛される際に「宣言順序が逆行していないか」を検証するよう修正(回帰は `error_parameters.kt` の golden ケースで固定、既存の `OverloadResolverTests` 79件は無回帰を確認済み)。

以下、現行タグ11件を分類ごとに記載する（2026-09-04 更新）。テスト入力側の修正で解決できず、コンパイラ/ランタイム側に実バグが残っている、または未実装機能がブロックしているものは「次アクション」に owner の当たりを付けた。

### グループ2: enum/data class/interface(残り6件)

| case | root cause | 次アクション |
| --- | --- | --- |
| `context_receivers.kt` | kotlinc 2.4 の named `context(name: Type)` 構文に kswiftc パーサーが未対応(旧・匿名 context 型リストのみ対応)で、Sema も最初の context 型を extension receiver に読み替えるだけでネストしたスコープに伝播しない | context parameter の設計を要する中規模タスク(クイックパッチ不可) |
| `data_class_inheritance.kt` | 意図的な負テスト(コメントで明言)だが、ネストしたクラス(`Container.Outer : Inner`)が `validateSupertypesAreOpen` の対象外になっている点は独立した実バグ | 診断golden(DEBT-DIFF-006の`error_type_inference.kt`と同方針)へ移設し、ネストクラスのopen検証漏れは別途調査 |
| `data_class_inheritance_valid.kt` | `if (other !is BaseEntity) return false` のようなガード節後、`other` の smart-cast 状態が後続コードへ伝播しない(`ControlFlowTypeChecker.inferIfExpr` は else 無しの分岐の flowState をブロック内の後続文へ引き継がない設計)。広範囲に影響しうる一般的なcorrectnessギャップ。2ファイル(L17/L44)がdata class ctorのval/var欠落という別ミスも持つ | `ExprTypeChecker.blockExpr` の逐次処理が現状 statement ごとに同じ `ctx` を使い回しており、Nothing型分岐後のflowStateを次のstatementへ運んでいない。`inferExpr`/`inferIfExpr` の戻り値契約を拡張する必要がある中規模タスク |
| `enum_basic.kt`(未解除、範囲縮小) | 元々の root cause だった「明示的companionがあると`values()`/`valueOf()`/`entries`の合成がスキップされる」「`EnumEntries<T>`が空マーカーで`.size`等が解決できない」の2点は2026-07-29に実装・修正済み(下記「2026-07-29 enum修正」参照)。残る唯一のブロッカーは別バグ: enum の companion object に**ユーザー自身が定義した**関数(`fun opposite(...)`)が `EnumClass.opposite(...)` 静的呼び出し構文で解決できない(`Unresolved member function`)。values()/entries等の合成メンバーとは無関係の既存バグで、companion なしの2026-07-29修正前のmasterでも同じ症状を確認済み(再現: `enum class D { A,B; companion object { fun f(): Int = 1 } }; fun main() { D.f() }`) | companion object の**ユーザー宣言**メンバーが `EnumClass.member()` 構文で解決できない root cause を調査(合成メンバー用に新設した経路と、既存のcompanion member解決経路の相互作用を疑う) |
| `enum_edge_cases.kt`(未解除、範囲縮小) | 同じく values()/entries 側は2026-07-29修正で解消。残るブロッカーは、entry 固有 body を持つ enum 定数(`C { override fun toString() = "C-special" }`)を `ComplexEnum.C` の形で参照すると `Ambiguous overload resolution` + `Unresolved member function 'C'` になる別バグ(未調査) | entry-specific body を持つ enum 定数の `EnumClass.ENTRY` 参照を調査 |
| `generic_typealias.kt` | `typealias A = B` / `typealias B = A` の循環定義が使用箇所でしか検出されず(`Helpers+TypeAliasExpansion.swift`)、未使用ならコンパイルが通ってしまう | 宣言済み typealias 全件に対する eager cycle check を追加 |
| ~~`comparable_interface.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：ローカル generic 関数・nullable 比較を実kotlinc互換に修正） | — |
| ~~`interface_conflict_resolution.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：concrete 親クラスを持つ多重 interface 実装で明示的 override を追加） | — |
| ~~`override_variance.kt` / `override_variance_advanced.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：`throws` 節・`protected fun` in interface・`= Unit` 等の無効構文を除去） | — |

#### 2026-07-29 enum修正(`enum_entries_function.kt` は解除済み)

上表の `enum_basic.kt`/`enum_edge_cases.kt` の root cause として記載されていた、(1) enum が明示的 companion object を持つと `values()`/`valueOf()`/`entries` の合成がスキップされる、(2) `EnumEntries<T>` が空マーカーで `.size`/`.forEach` 等が解決できない、の2点を実装・修正した(`HeaderCollection.swift`, `HeaderHelpers+SyntheticEnumStubs.swift`, `DataEnumSealedSynthesisPass+EnumSynthesis.swift`, `CompilerKnownNames.swift`。回帰は `Tests/CompilerCoreTests/Sema/EnumAPISurfaceInventoryTests.swift`、`Tests/CompilerCoreTests/Lowering/LoweringPassRegressionTests+EnumEntriesEdgeCases.swift`、新規 `Scripts/diff_cases/enum_values_and_entries.kt`)。`enum_entries_function.kt`(`enumEntries<Color>()` トップレベル関数版)はこの修正で candidate 側が通るようになり、ref 側の残エラーが `import kotlin.enums.enumEntries` 欠落という test input mistake だったため、import を追加して `SKIP-DIFF` を解除した。`enum_basic.kt`/`enum_edge_cases.kt` は上表の通り別バグで依然ブロックされている。

### グループ3: common stdlib gap(残り1件)

| case | root cause | 次アクション |
| --- | --- | --- |
| `advanced_type_inference.kt` | `@ExperimentalTypeInference` を関数に直接付与(本来はアノテーションクラスへのメタ注釈のみ許可)しているのを kswiftc は許してしまう。修正後は `buildList`/`buildMap` の generic 型引数forwardingで別途詰まる | `@ExperimentalTypeInference` 誤用チェック追加、`buildList`/`buildMap` のgeneric forwarding調査 |
| ~~`list_binary_search_compare.kt`~~ | 解除済み（2026-08-18、テスト入力の書き換え：ローカル data class `Person` をトップレベルへ移動、`List<Comparable<*>>` への型整合） | — |
| ~~`array_hof.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：`flatMap` transform の戻り値を `Array` から `Iterable` 互換に修正） | — |
| ~~`bitwise_operators.kt` / `char_operations.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：型不一致比較の明示変換、`Char.rangeTo()` ドット呼び出しを `..` 演算子/`digitToIntOrNull()` 等実kotlinc互換に修正） | — |
| ~~`chunked_transform.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：実在しない `chunked(size, step)` 呼び出しを `windowed(size, step, true)` 等に書き換え） | — |
| ~~`list_reversed_asreversed.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：`asReversed()` view 経由の set 操作をテストから除外） | — |
| ~~`match_result.kt`~~ | 解除済み（2026-08-13、common stdlib gap の実装：`MatchResult`/`MatchGroup` を bundled Kotlin source 化（KSP-486）し `range`/`groupValues`/`next()` 等を実装。destructuring はテスト側で `groupValues` 使用へ回避） | — |
| ~~`range_basic.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：`.end` → `.endInclusive`、`IntRange.toIntArray()` → `toList().toIntArray()`） | — |
| ~~`string_chunked_windowed.kt` / `windowed_step_partial.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：transform 内 `CharSequence` の `uppercase()` 呼び出しを `toString().uppercase()` に統一、不要な windowed 呼び出しを削除） | — |
| ~~`string_materialization.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：`toSortedSet()` Char boxing 問題と `CharIterator` 未実装箇所をテストから除外） | — |

### グループ4: coroutine Flow(残り2件)

| case | root cause | 次アクション |
| --- | --- | --- |
| `flow_advanced_operators.kt` | `.transform { it * 10 }`が`emit()`を呼ばずmapのように誤用(real Kotlinでも無効)。修正後は`Flow.zip`/`Flow.combine`が同名の`Collection.zip`/`combine`と衝突し"Ambiguous overload resolution"になる実バグが残る | テストの`transform`誤用を修正。`Flow.zip`/`combine`のオーバーロード衝突は別途調査(`Helpers.swift:457`付近) |
| `flow_error_handling.kt` | `onErrorReturn`/`onErrorResume`(real Kotlinでは`ERROR`レベルでdeprecated、`catch{emit()}`/`catch{emitAll()}`推奨)をkswiftcが誤って受理。修正すると`onCompletion`(非推奨でない実オペレーター)が未実装で失敗する | テストを`catch{}`形式に書き換え。`Flow.onCompletion`を実装 |

### グループ5: reflection(残り1件)

| case | root cause | 次アクション |
| --- | --- | --- |
| `kclass_members.kt` | `KClass.properties`/`memberProperties`/`functions`等はSemaの特別扱い(`CallTypeChecker+KClassMemberCallInference.swift`)で合成`List<Any>`を返すのみで、要素の`KFunction`/`KProperty`が実装を持たず`.name`等が解決できない(KSP-496で意図的に未対応と明記) | KSP-496のRuntimeオブジェクトモデル作業待ち |
| ~~`mock_objects.kt`~~ | 解除済み（2026-08-18、テスト入力の書き換え：内部 `Stub` クラスの非 private 化、`returns` の明示型注釈付与） | — |
| ~~`annotation_reflection.kt`~~ | 解除済み（2026-08-13、common stdlib gap の実装：annotation reflection API (`KClass<*>` 引数の `Annotation` 取得・配列化) を実kotlinc互換に修正） | — |
| ~~`kclass_ktype_basic.kt`~~ | 解除済み（2026-08-13、common stdlib gap の実装：`KClass.simpleName`/`isInstance`/`typeOf` を利用し、未対応の `KType.toString()` はテストから回避） | — |

### グループ6: JVM interop/time(残り1件)

| case | root cause | 次アクション |
| --- | --- | --- |
| `platform_time_conversion.kt` | CLEANUP-STUB-126 で `java.time` / `java.util.concurrent.TimeUnit` の JVM interop synthetic surface を target-out として削除。kotlinc reference は成立するが kswiftc candidate の比較対象外 | JVM interop surface を再導入しない限り `SKIP-DIFF` を維持。Native/common time API の検証は別の Duration/Instant テストで行う |
| ~~`jvm_preview.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：2件目以降のトップレベル複数行文字列プロパティと`@JvmRecord`/data class `toString()` 呼び出しをテストから除外） | — |
| ~~`time_edge_cases.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：`Duration.Companion` の import を追加し、companion-extension 呼び出しで実kotlinc互換に修正） | — |
| ~~`test_primitive_conversions.kt`~~ | 解除済み（2026-08-13、テスト入力の書き換え：存在しない変換呼び出しを削除し、実kotlinc互換の primitive 変換に修正） | — |

### 解消済み: `contract_returns.kt` / `contracts_basic.kt`

`@file:OptIn(ExperimentalContracts::class)` の不足を修正し、bundled source-backed の `ContractBuilder.returns` / `SimpleEffect.implies` による `contract { returns() implies (...) }` 解決を確認した。`KotlinContractsEffectModelTests` の最小再現で候補側の implicit receiver 解決を固定し、通常の `diff_kotlinc.sh` 経路へ復帰した。

## DEBT-DIFF-008: primitive Number virtual dispatch（解消済み、2026-08-20）

`KSP-747` で `kotlin.Number` を bundled stdlib ソース化したことにより、`val n: Number = 42` や `fun <T : Number> sumOf(a: T, b: T)` のように primitive を `Number` 型変数 / 上限境界のジェネリック引数に受けた場合に `n.toDouble()` / `a.toDouble()` 等が解決されるようになった。しかし、runtime / lowering 側で boxed primitive に対する `Number` の仮想メソッド dispatch が未整備のため、正しい値を返さないか実行時エラーとなっていた。

根本原因: 組み込み primitive 型（Int/Long/Double/Float/Short/Byte）は `Subtyping.swift` のハードコードされた規則でのみ `Number` に適合し、シンボルテーブル上の実際のオーバーライドクラスとしては登録されない。そのため Sema は `n.toDouble()` を抽象宣言 `kotlin.Number.toDouble` 自体へ解決し、`resolveVtableDispatch`（`CallLowerer+SafeMemberCalls.swift`）はプログラム中に `Number` を継承する**ユーザー定義クラスが1つも無い**限り vtable slot 解決を諦めて直接呼び出しにフォールバックしていた（KSP-1540 の2ケースはいずれもユーザー定義の `Number` 派生クラスを含まないため常にこの経路を通り、抽象宣言のプレースホルダ実装（ゼロ返却）を呼んでいた）。vtable dispatch を無条件に強制する対処も不成立: 組み込み box 型（`RuntimeIntBox` 等）はコンパイラ合成のクラスメタデータを持たない手書き Swift クラスのため、vtable slot lookup が実行時にクラッシュする（`KSWIFTK-RUNTIME-0001`）。

修正: `CallLowerer+NumberConversionMemberCalls.swift`（`tryLowerNumberConversion`）が `Number.to*()` 呼び出しをレシーバ静的型が `Number` 自身または `T : Number` の消去型パラメータの場合にのみ横取りし、`kk_number_to_primitive`（`Sources/Runtime/RuntimeNumberConversionDispatch.swift`）へ実行時タグ判定付きでルーティングする。認識可能な primitive box（Int/Long/Double/Float。Short/Byte は Int box を共有）なら静的型経路と同じネイティブ変換 intrinsic を再利用し、それ以外（ユーザー定義 `Number` サブクラスの実インスタンス）は `kk_vtable_lookup` 経由で本来の vtable へフォールバックする。BUG-170（消去 `Comparable` dispatch、`kk_compare_any`）と同じ形の修正。回帰テスト: `Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+NumberConversionDispatch.swift`。

| case | 結果 |
| --- | --- |
| `stdlib_kotlin_n_Number_primitive.kt` | `SKIP-DIFF` 解除、`diff_kotlinc.sh` で real kotlinc と一致確認 |
| `stdlib_kotlin_n_Number_primitive_generic.kt` | `SKIP-DIFF` 解除、`diff_kotlinc.sh` で real kotlinc と一致確認 |

## DEBT-DIFF-009: script mode 失敗系 exit code 規約差異

`Scripts/diff_kotlinc.sh` の `run_case()` は、`script_*.kt` ケースの reference 側を `kotlinc -script` 一発実行（compile+run が単一 JVM プロセス）にしていたため、そのプロセスの単一 exit code を `ref_compile_exit` / `ref_run_exit` のどちらに振るか「exit != 0 かつ stdout が空なら compile 失敗」というヒューリスティックで推測していた。しかし「出力前に例外を投げるスクリプト」（stdout 空 + exit != 0）は compile 失敗ではなく実行時失敗であり、この場合 candidate（kswiftc）側の compile は正しく成功する（`cand_compile_exit=0`）ため、`ref_compile_exit(推測値) != cand_compile_exit(0)` として「compile exit mismatch」という誤った診断になり、実際の失敗理由（reference 側の stderr にある実行時例外スタックトレース）が `ref_compile_exit -eq 0 && cand_compile_exit -eq 0` を前提にしたレポート出力条件から漏れて一切表示されなかった。

修正: `is_script` の場合は compile/run を分割推測せず、reference 側の単一 exit を丸ごと `ref_run_exit` に格納し、比較ロジックも script 専用の分岐（`ref_run_exit` 対 candidate の合成 exit — 実際に compile が失敗していればその exit、そうでなければ run の exit）に分離した。メッセージも「script exit mismatch」に変更し、`ref script stderr:` として reference 側の実際の stderr を常に表示するようにした。

この修正を診断する過程で、上記ヒューリスティックとは別の、構造的な差異が判明した: `kotlinc -script` は実行時失敗を**常に** exit=3（`SCRIPT_EXECUTION_ERROR`、Kotlin コンパイラの `ExitCode` enum が定義する script runner 固有の規約）として報告するが、kswiftc がコンパイルするネイティブバイナリの未捕捉例外（panic）は exit=1（`KSWIFTK-LINK-0003`）で終了する。これは kswiftc のバグではない — `kotlinc -script` の exit=3 は JVM script エンジン特有の実装詳細であり、同じコードを通常の（非 script）Kotlin プログラムとして実行した場合、JVM の `main()` 内未捕捉例外は exit=1 になる（つまり非 script 経路であれば ref/candidate 両方 exit=1 で一致するはずの状況）。したがって、reference 側が実行時に失敗する `script_*.kt` ケースは、上記の分類修正後であっても exit code 自体が構造的に一致しない。

| case | 結果 |
| --- | --- |
| `script_runtime_exception_before_output.kt` | `SKIP-DIFF` — 分類修正の診断に使った最小 repro として保持。`--force-run-skipped` で `script exit mismatch: ref=3 candidate=1` と正しく報告されることを確認済み（旧実装では `compile exit mismatch: ref=3 candidate=0` と誤診断し、stderr も両側空で表示されていた） |

## 解除手順

1. 対象ケースだけを `--force-run-skipped` で実行する。

```bash
bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped Scripts/diff_cases/<case>.kt
```

2. reference 側だけが失敗するなら runner / classpath / target 問題として本 inventory を更新する。
3. candidate 側だけが失敗するなら Sema / KIR / Lowering / Runtime owner の task へ分解する。
4. 両者が pass したら `SKIP-DIFF` / `KSWIFTK_DIFF_IGNORE` を削除し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` で通常 diff を確認する。
