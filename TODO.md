# Kotlin Compiler Remaining Tasks

### Diff skip 追跡（残り 4 件）
- [~] DEBT-DIFF-007: `run_case` の compile-exit-code-match 誤判定修正（2026-07-08、`Scripts/diff_kotlinc.sh`）で新規に顕在化した ref/candidate 不一致を、診断/ネガティブテスト・enum/data class/interface 未実装・common stdlib gap・coroutine Flow・reflection・JVM interop・finally routing の7グループへ分解して triage 済み（2026-07-29、`docs/diff-skip-inventory.md` の DEBT-DIFF-007 節）。2026-08-13 更新：今回さらに19件のテスト入力ミス/common stdlib gap ケースを修正し `SKIP-DIFF` を解除。2026-08-18 更新：`list_binary_search_compare.kt`・`mock_objects.kt` をテスト入力ミス修正で追加解除（36→16→14）。アクティブな `SKIP-DIFF (DEBT-DIFF-007)` は14件残存（enum/data class/interface・coroutine Flow・reflection member access・JVM interop・contracts・context receivers 等、コンパイラ/ランタイム実装待ち）。新たに見つかった未修正の実バグ多数（`Unit`を明示的な値として使えない一般的ギャップ、`if (x !is T) return` 後に smart-cast が後続コードへ伝播しない一般的ギャップ、トップレベルの2件目以降の複数行文字列プロパティが `null` になる疑いのある一般的初期化順序バグ、等）も同節に記録済み。

## Dead Code 削除タスク（DEADCODE: 2026-07-11〜12 再監査）

> 2026-06-12 監査分の履歴は [`docs/dead-code-audit.md`](docs/dead-code-audit.md) に保存。今回は現 HEAD で (1) Swift の USR/index 解析（Periphery 3.7.4、public/Codable は保持）、(2) 識別子の宣言・呼び出し箇所の `rg` 照合、(3) 2,791 件の Runtime `@_cdecl`（`kk_*` 2,739 件 + `__kk_*` 52 件）に対する CompilerCore / CompilerBackend / bundled Kotlin / Runtime 内部 / Tests / ABI テーブル経路の照合、を併用した。
> 根拠略号: **R0** = 宣言以外の参照 0、**D** = 参照元が別の dead symbol のみ、**W0** = 代入/初期化のみで read 0、**E0** = Runtime export に emit/内部/テスト経路 0、**T** = 製品からは未使用でテストのみ。同名 overload や別 lexical scope は USR 単位で分離済み。
> 1 checkbox = 1 method / property / type / enum case を原則とする。D 項目は参照元タスクを先に削除し、最後に owner type/file を整理する。`RuntimeABISpec` 登録は使用証拠ではないため、E0 削除時は spec/parity/snapshot も同時に消す。
> 除外を実済み: `kk_print_string_flat` は Backend が直接 emit するため alive。`kk_atomic_*` は prefix + suffix の 2 段階動的生成、URLSession delegate / `@main` / XCTest・Swift Testing discovery / protocol witness / Hashable・Codable 合成参照も alive として除外。
> 完了ゲートは refactor PR gate（全テスト + golden + `diff_kotlinc.sh` green）。完全に到達不能な単独 private helper のみを削除する PR は、対象 module テスト + `git diff --check` を最低ゲートとし、まとめ PR 時に full gate を実施する。

### 監査基盤 / 残領域

- [~] DEADCODE-014: 旧「未監査領域」を継続監査する。2026-07-12 時点で tracked `.c/.h/.cc/.cpp` は 0 件、`DiagnosticRegistry` 108 descriptor は全て production 発行箇所あり、stored/global/Tests helper の検出結果は下記に分割済み。**2026-07-31 更新**: 「SKIP-DIFF 62 件」は stale な数値だったと判明（実測は当時110件）。kswiftc を再ビルドして全件 `--force-run-skipped` で再判定し、9件を解除（`comparator_basic.kt`/`interface_properties.kt`/`kconstructor_basic.kt`/`math_exp_log_functions.kt`/`random_overload_edge_cases.kt`/`file_use_edge_cases.kt`/`coroutine_exception_handling.kt`/`coroutine_scope_lifecycle.kt`/`coroutine_supervisor_job.kt`）。並行して別セッションが `DEBT-DIFF-001` の完全棚卸しと `DEBT-DIFF-007`(72→37) の大規模 triage を実施していたため、その成果を `git reset --hard origin/master` で取り込んだ上で作業を継続（このとき `BUG-152`(#5068) が本セッションの CharSequence.length 修正と完全に重複していたと判明し、重複分は破棄）。本セッション側の net-new な実装: (1) `EnumClass.values()` が Sema 未登録で完全に unresolved だったバグと `entries` のメンバー転送不可バグを修正（`enum_entries_function.kt` を追加解除、`enum_basic.kt`/`enum_edge_cases.kt` は別バグ=`BUG-177` で依然ブロック中）、(2) `Array<T>` の `mapIndexed`/`filterIndexed`/`mapNotNull`/`filterNot`/`filterNotNull`/`reduceIndexed`/`first`/`firstOrNull`/`last`/`lastOrNull` 未解決バグを修正（`array_hof.kt` も 2026-08-13 現在 SKIP-DIFF タグが無く active（`--force-run-skipped` で PASS））。詳細・各コミットの root cause は [`docs/diff-skip-inventory.md`](docs/diff-skip-inventory.md) 参照。2026-08-18 実測では active な SKIP-DIFF は 35 distinct file（35 tag instance、内訳は docs/diff-skip-inventory.md）。`list_binary_search_compare.kt`・`mock_objects.kt` を追加解除。`compiler_plugin_api.kt` は 2026-08-13 現在 SKIP-DIFF タグが無く active（`--force-run-skipped` で PASS）

---

## AI slop クリーンアップ（SLOP: 2026-08-19 監査）

> 調査方法: AI 生成コードに特有の劣化パターン（残置デバッグ出力・無条件 pass アサーション・タスク番号入り識別子・同義 private ヘルパーのファイル間重複・無条件 disable）を rg で横断検索し、ヒットを個別にコード確認して slop と確定したもののみ登録。`// Note:` / placeholder / 変更経緯コメント類は設計理由の説明として機能しているため誤検知として除外した。
> 完了ゲート: 各タスク記載の rg チェック 0 件 + 対象 suite green。bundled .kt を触るタスクは共通ゲート G（`swift_test.sh` / Golden / `diff_kotlinc.sh`）も適用。
> タスク番号 prefix 命名（`ksp4NN*`）は [[BUG-218]]（同一パッケージ別ファイルの同名 private トップレベル宣言が SEMA-0001 で誤衝突する重複検出バグ）の回避策として発生したもの。`__kk` prefix の共有ヘルパー（`MatchResult.kt` の `__kkIsGroupNameStart` 等の既存規約）へ統合する形なら BUG-218 の修正を待たずに着手できる。素朴な private 命名へ戻す場合は BUG-218 が前提。

---

## コード共通化タスク（REFACT: 2026-06-28 調査）

> 調査方法: KIR 層・Lowering 層・Sema 層・テスト層を横断して重複パターンを抽出。
> 優先度は影響ファイル数と「新 primitive 型追加時の修正箇所数」で決定。
> 完了ゲートは全テスト + golden + `diff_kotlinc.sh` green。

## Lowering 小粒リファクタ（RF-LOWER: 2026-09-06 調査）

> 対象は (1) Collection の source-backed 呼び出し保護・移行済み特例の整理、(2) 式の分類・コピー伝播の一元化、(3) Inline 展開の責務・終了条件の整理。パス計測・順序契約・並列 lowering の有効化は本系列に含めない。以下は静的調査に基づく実行タスクであり、旧経路の到達不能性・性能改善・新規バグの再現を確認済みとは扱わない。
>
> **粒度と競合回避**: 原則1 checkbox = 1責務 = 1 PR。処理の移動と挙動変更を混ぜず、対象外の整形・改名をしない。主な編集範囲は各項の「対象」に限定し、呼び出し元の配線・対応テスト以外へ広がる場合は着手前に新IDへ再分割する。ファイル分割だけを最終成果にせず、後続の状態管理・判定・終了条件の改善へ接続する。
> - **共通ファイルは直列**: `CollectionLiteralLoweringRegistry.swift`、`CollectionLiteralLoweringPass+CallRewrite.swift`、`+CallRewriteFactories.swift`、`+PreScan.swift`、`+VirtualCallRewrite.swift`、`+LookupTables.swift`、`+RewriteState.swift`、`InlineLoweringPass.swift` を変更するPRは、同じファイルを触る先行PRのマージ後のHEADから開始する。前提が満たされても編集範囲が重なれば並列にしない。
> - **独立した変更だけ並列**: Collection 系と Inline 系は別レーン。STATE-004後の virtual-call の葉ファイルは、共有 dispatcher / state / lookup に追記しない範囲で並列可。抽出前の巨大ファイルを複数PRが同時に分割する運用は禁止する。
> - **テストも編集範囲を分離**: 既存 suite / helper を再利用し、追加は責務別 extension または既存 fixture に置く。巨大な `CollectionLiteralLoweringTests.swift` の一括移動・既存 diff ケースの無関係な整理を混ぜない。純粋な stdout 比較の新規実行テストは `Tests/CompilerBackendTests/Fixtures/` を使う。
> - **台帳の運用**: `TODO.md` の更新は自タスクの状態・実績・必要な前提だけに限定し、セクション全体の整形・完了項目の一括削除を同時に行わない。
>
> **既存タスクとの境界**: `buildList` capacity の Kotlin 化・Sema stub 削除は KSP-697、collection factory 自体の移行は KSP-699 等の担当。本系列は残存 Lowering の整理であり、同じ移行を別実装しない。由来判定は既存の symbol / import 情報を利用し、RF-GOLDEN-002 の表示用分類や ARCH-021 の well-known 基盤を重複実装しない。全パス verifier・位置配列API変更は ARCH-018/019 の担当で、Inline 内の局所的な検証とは分ける。各系列を始める際に関連PRのマージ状況・現コードを再確認する。
>
> **共通完了ゲート**: 対象 Core Lowering / KIR suite、必要な Backend fixture・source注入 / stdlib artifact 経路、該当 Kotlin 差分ケースに加え、`CLAUDE.md` のRF必須ゲート（全 Swift テスト・Golden・全 `diff_kotlinc.sh`、存在する場合の `loc_report.sh` 指標）を各PRで満たす。API / ABI・例外・boxing・決定性を維持し、移動のみのPRではKIR/LLVM IRの不変性も確認する。バグを発見したら最小 Kotlin 再現と回帰テストを同じ修正PRに含め、既存の誤動作を期待値更新で固定しない。ABI export を削除する必要がある場合は利用者ゼロの確認・Spec/parity/リンク検証を同じPRに含め、残存理由がある経路をテストだけ消して完了扱いにしない。
>
> 以下のSwiftファイル名は、特記がなければ `Sources/CompilerCore/Lowering/` 配下。新設する責務別ファイル名は案であり、着手時に既存の同責務ファイルがあれば再利用する。

### 1. Collection の source-backed 保護・Builder DSL 残存処理（RF-LOWER-CALL）

> 主な順序: CALL-001 → 002 → 003 → 004 → 005 → 006。CALL-007は002後に分岐でき、007 → 008 → 009 → 010 → 011 → 012 → 013 → 014 → 015。014はSTATE-009、015は006も待つ。Builder側とpolicy側で lookup / dispatcher / test の編集が重なる場合は直列化する。API群単位で不要なrewriteと対応lookupを一緒に減らし、別の巨大な名前allowlistへ移し替えない。

- [x] RF-LOWER-CALL-001: Builder DSL の現行経路と削除前提を回帰テストにする（前提: なし）
  - 対象: Builder DSL の既存 Core / Backend tests、`CollectionBuilders.kt` を利用する最小入力。`buildList` / `buildSet` / `buildMap` のcapacity有無、source / artifact、ユーザー同名関数を確認し、必要な `--no-stdlib` fallback と `symbol: nil` の手組みKIRを区別する。KSP-697の残存stub・`__kk_build_*` のemit元も照合する。
  - 完了条件: 正しい呼び出し先・実行結果・負のcapacity・builderから漏れたreceiverのfreezeを既存テストと対応付け、不足分だけ追加する。旧変換テストだけを根拠に製品経路が必要／不要と判定しない。削除可能な経路と未解決の前提を本項の完了メモに残す。
  - 完了根拠（現行経路の実測。製品コードは無変更、テスト2ファイル追加のみ）:
    - `CollectionLiteralLoweringPass` は `LoweringPhase.swift:28` で `InlineLoweringPass`（同:40）より前に走る。`buildList` はまだ未展開の `.call` なので、rewrite 判定 `isStdlibBuilderDSLCall`（`+PreScan.swift:36`）は構造的に load-bearing であり「inline が先に潰すから死んでいる」わけではない。
    - source 経路（bundled stdlib をソース同時コンパイル）: 6オーバーロード（3種 × capacity有無）すべて rewrite されず、`CollectionBuilders.kt` の `__kk_builder_{list,set,map}_{new,freeze}` に落ちる。
    - artifact 経路（`.kklib` 経由）: 同上。LLVM IR に `__kk_build_*` は1件も現れない。
    - `--no-stdlib`: `buildList` だけが `HeaderHelpers+SyntheticBuilderDSLStubs.swift` の残存 synthetic stub に解決し、`.synthetic` 分岐経由で `__kk_build_list` / `__kk_build_list_with_capacity` へ rewrite される。`buildSet` / `buildMap` は `KSWIFTK-SEMA-0023` で未解決（stub が無い）。
    - `symbol: nil` の手組みKIR: 既存 `CollectionLiteralLoweringTests` 専用の形。`Driver.swift:182` が phase ごとに `hasError` で break するため、未解決呼び出しが Lowering に到達する製品経路は無い。
  - `isStdlibBuilderDSLCall` の分岐別到達性:
    - `guard let symbol else { return true }` → 製品到達なし。source の `.call` は常に symbol を持ち（KIR dump が `symbol=buildList`）、`CallLowerer.swift` の他の `symbol: nil` 生成箇所（145 / 855 / 962 / 1346 行）はいずれも固定の `kk_*` / `__kk_*` ランタイム名を emit するので、builder 名で nil symbol になる経路が無い。既存6ケースはすべてこの分岐だけを踏んでいる。
    - `.synthetic` → true → `--no-stdlib` の `buildList` のみ。**唯一の実利用者**。
    - `externalLinkName?.hasPrefix("kk_build_")` → 恒偽。実名は `__kk_build_list_with_capacity` で prefix が一致せず、かつ該当シンボルは直前の `.synthetic` で先に true を返す。`kk_`→`__kk_` 降格の取り残し。
    - `isSourceBackedStdlibBuilderDSLCall` → 全分岐 false（CALL-003 の対象）。
  - `__kk_build_*` の emit / 参照元（製品側4箇所）: `+LookupTables+BuilderDSL.swift`（6名の intern）→ `+CallRewriteFactories.swift:504-541` の rewrite、`HeaderHelpers+SyntheticBuilderDSLStubs.swift`（`__kk_build_list_with_capacity` の externalLinkName 1件）、`RuntimeABISpec+Collection.swift:1287-1340`（6エントリ）、`Sources/Runtime/RuntimeBuilderDSL.swift`（6 `@_cdecl`）。
  - KSP-697 との照合: `CollectionBuilders.kt` は capacity オーバーロードを含め Kotlin 実装済みで、stdlib 同梱時は `bundledIndex.contains` により stub 登録自体がスキップされる（新テストで synthetic overload 0件を固定）。KSP-697 の残作業は実質「stub ファイルの削除」だけであり、その唯一の消費者が `--no-stdlib` の `buildList`。
  - 既存テストとの対応付け:
    - 呼び出し先: `CollectionLiteralLoweringTests` の buildList/buildSet/buildMap 6ケースは `symbol: nil` の手組みKIRで、製品経路の根拠にはならない。`CollectionBuildersKSP950Tests` は source-backed 宣言の存在のみを見る。→ 製品経路の呼び出し先は未固定だったので新規追加。
    - 実行結果: `CodegenBackendIOHelpersTests.testCodegenBuildListProducesCorrectly` / `CodegenBackendIntegrationTests.testCodegenBuildMapUseRuntimeBuilder` / `testCodegenBuildSetUseRuntimeBuilder`（いずれも capacity なし）、`Scripts/diff_cases/{collection_builders,build_empty_collections}.kt`。
    - capacity / 負のcapacity / freeze / 例外伝播 / identity: `Scripts/diff_cases/ksp950_build_family.kt` のみ。CI の kotlinc diff ステップは `continue-on-error` なのでブロッキングではなかった。→ capacity・負のcapacity・freeze を Backend 実行テストへ昇格。
    - ユーザー同名関数: `Scripts/diff_cases/builder_dsl_shadowing.kt` は `Int -> Int` 形のみで、rewrite の `arguments.count == 2` capacity マッピングに当たるレシーバ付きラムダ形が未カバーだった。→ 新規追加。
  - 追加した不足分: `Tests/CompilerCoreTests/Lowering/BuilderDSLLoweringRoutingTests.swift`（5テスト: source の rewrite 非適用 / 解決先シンボルが全 true 分岐を外すこと + synthetic overload 0件 / ユーザー同名関数のレシーバ付きラムダ形 / `--no-stdlib` の buildList rewrite / `--no-stdlib` の buildSet・buildMap 未解決）、`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+CollectionBuilderDSL.swift`（5テスト: source / artifact 双方の LLVM IR 呼び出し先 + capacity・負のcapacity・freeze の実行結果）。artifact 側は `makeArtifactCompilationContext` で `.kklib` を明示指定している — `CompilerOptions.shouldUseDefaultStdlib` はプロセス既定 artifact を `emit == .executable` にしか適用しないため、`allowDefaultStdlibLibrary: true` だけでは IR を見るテストは source 注入になる（実行テストの方は `.executable` なので既定 artifact 経路）。
  - 削除可能な経路:
    - CALL-003 の `isSourceBackedStdlibBuilderDSLCall` は恒偽で、削除しても製品挙動は不変。`hasPrefix("kk_build_")` 分岐も同じく恒偽で、CALL-002/003 の範囲で一緒に畳める（症状が無いため本PRでは触っていない）。
    - CALL-005 / CALL-006（`buildSet` / `buildMap`）は製品到達経路がゼロ。rewrite 分岐・lookup 名・`RuntimeABISpec` エントリ・`@_cdecl` まで削除可能。
  - 未解決の前提:
    - **CALL-004 は前提未達**。`--no-stdlib` の `buildList` が rewrite の唯一の実利用者で、消すと `buildList<Int> { }` が呼び出し先を失う。KSP-697（stub 削除）を先に済ませるか、`--no-stdlib` で `buildList` を非サポートにすると明示的に決める必要がある。`--no-stdlib` では `buildSet`/`buildMap` が既に未解決なので、`buildList` だけ生きている現状は非対称。
    - 削除時の副作用: `__kk_build_*` 6件は `RuntimeABISpec+Collection.swift` と `RuntimeBuilderDSL.swift` の `@_cdecl` に登録済み。`Scripts/validate_runtime_abi_links.sh` と `__kk_cdecl_count` メトリクスが反応するので、CALL-004〜006 側で同時に扱う。
    - 既存 `CollectionLiteralLoweringTests` の6ケースは `symbol: nil` 契約のテストとして本PRでは温存した。source-backed 契約への置換は CALL-004〜006 の担当。
  - ゲート: `bash Scripts/swift_test.sh` / `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green。`Scripts/loc_report.sh` の変動は `loc_by_directory Tests` の +493 行（追加テスト分）のみで、`HeaderHelpers+Synthetic*` 行数・KIR/Lowering TODO/FIXME 数・`"kk_` リテラル数・`interner.resolve == "..."` 数・`kk_cdecl_count` / `__kk_cdecl_count` はいずれも不変。
- [ ] RF-LOWER-CALL-002: 未消費の `builderLambdaKinds` 事前走査と引数配線を除去する（前提: CALL-001）
  - 対象: `CollectionLiteralLoweringRegistry.swift`、`+PreScan.swift` の `collectBuilderLambdaKinds` / `scanBuilderLambdaEntries`、`+CallRewrite.swift` / `+CallRewriteFactories.swift` の引数転送。着手時に、辞書が渡されるだけでrewriteの判断に使われないことを再確認する。
  - 完了条件: 未使用と確認できた辞書構築・走査・引数がなくなり、Builder DSL の呼び出し先と出力が不変。`isStdlibBuilderDSLCall` や他のcollection事前走査は削除せず、lookupの一括整理も混ぜない。
- [ ] RF-LOWER-CALL-003: 常にfalseを返す source-backed Builder 判定の空実装を畳む（前提: CALL-002）
  - 対象: `+PreScan.swift` の `isSourceBackedStdlibBuilderDSLCall` と呼び出し元のみ。現行の全分岐がfalseであることを確認し、不要なFQName構築・比較を除去する。
  - 完了条件: source-backed builderをrewriteしない契約を維持し、nil symbol / synthetic / external linkの既存分岐は変えない。CALL-001の回帰がgreenで、恒偽helperへの参照が0件。
- [ ] RF-LOWER-CALL-004: `buildList` の旧runtime rewriteを削除する（前提: CALL-003、KSP-697の必要な移行・fallback整理完了）
  - 対象: `+CallRewriteFactories.swift` のbuildList分岐、`+LookupTables+BuilderDSL.swift` / `+LookupTables.swift` の対応名、該当テスト。capacity有無を一組として扱い、Kotlin本体・Semaの移行をこのPRで重複実装しない。
  - 完了条件: source / artifactの両経路でKotlin実装が使われ、Loweringの旧 `__kk_build_list*` への置換と不要lookupが0件。手組みKIRの旧期待値はsource-backed契約へ置換する。製品で必要なfallbackが残る場合は削除を強行せず、前提未達として扱う。
- [ ] RF-LOWER-CALL-005: `buildSet` の旧runtime rewriteを削除する（前提: CALL-004）
  - 対象: CALL-004と同じ責務ファイルのbuildSet分岐・対応lookup・テストのみ。capacity有無のsource / artifact経路とfallback到達性をCALL-001の結果に照らして再確認する。
  - 完了条件: 旧 `__kk_build_set*` への置換と不要lookupが0件で、要素重複・挿入順・capacity・freezeの契約を保持する。単に別名のbridgeへrenameして残さない。
- [ ] RF-LOWER-CALL-006: `buildMap` の旧rewriteと最後のBuilder専用配線を除去する（前提: CALL-005）
  - 対象: buildMap分岐・対応lookup・テスト、全利用者がなくなった `isStdlibBuilderDSLCall` / `BuilderDSLLookupNames` の登録口。汎用mutable Set / Map操作にまだ必要な名前はBuilder専用名と分ける。
  - 完了条件: 旧 `__kk_build_map*` への置換がなく、同一keyの更新・順序・capacity・freezeを保持する。Builder専用の未使用引数・lookup転送・predicateが残らず、他のfactory rewriteは不変。
- [ ] RF-LOWER-CALL-007: source-backed呼び出しの保持判断を専用policyへ抽出する（前提: CALL-002）
  - 対象: `+CallRewrite.swift` の `shouldPreserveSourceBackedAggregateCall` と `+VirtualCallRewrite.swift` の対応する保持判断、責務別policy。まず現行の判断順序を維持した抽出だけを行い、resolved symbol / source実装 / external bridge / 未解決を区別する入力を用意する。
  - 完了条件: source-backed member alias・imported宣言・ユーザー同名関数・nil symbolをテストし、direct / virtual callの既存差異を明示する。`isSourceBackedSymbol` の意味やSema flagsを変更せず、Sequenceのruntime表現例外をまだ消さない。CALL-008以降はこの境界を使う。
- [ ] RF-LOWER-CALL-008: Listの変換・filter系だけをsymbol基準の保持判断へ寄せる（前提: CALL-007）
  - 対象: policyと `+CallRewriteHOFTransforms.swift` / `+CallRewriteHandlers.swift` の `map*` / `flatMap*` / `filter*` 系のうちsource移行済み経路、必要なlookup・対応テスト。Map / Array / Sequenceの同名APIは対象外。
  - 完了条件: 選択済みKotlin宣言が保持され、不要なList rewrite・名前列挙を削除できる。通常・indexed・nullable要素・捕捉lambdaの代表ケースを固定し、未移行overloadを同名という理由で消さない。
- [ ] RF-LOWER-CALL-009: Listの畳み込み・累積系の保持判断を整理する（前提: CALL-008）
  - 対象: policyと `+CallRewriteHOFAccumulations.swift` の `fold*` / `reduce*` / `scan*` / `running*` 系、必要なlookup・テストのみ。
  - 完了条件: source移行済みoverloadの旧rewriteと保護用名前列挙が減り、空入力・nullable accumulator・例外・左右の評価順の契約を保持する。型消去境界のboxing/unboxingは別責務として維持する。
- [ ] RF-LOWER-CALL-010: Listの検索・述語系の保持判断を整理する（前提: CALL-009）
  - 対象: policyと検索・述語を扱う `+CallRewriteHOFCore.swift` / `+CallRewriteCollectionMember.swift` の該当分岐、必要なlookup・テスト。`find*` / `indexOf*` / `contains*` / `count` / `any` / `all` / `none` / `first*` / `last*` を着手時にoverload単位で照合する。
  - 完了条件: source移行済み経路だけを削減し、短絡評価・空入力・見つからない場合の戻り値／例外を保持する。Runtime ABIのboxed Bool変更（ARCH-011）を同時に行わない。
- [ ] RF-LOWER-CALL-011: Listのソート・極値系の保持判断を整理する（前提: CALL-010）
  - 対象: policyと `+CallRewriteHOFExtrema.swift` のList用 `sorted*` / `min*` / `max*` 分岐、必要なlookup・テスト。
  - 完了条件: Kotlin実装を削除済みruntime exportへredirectしないことを固定し、comparator / selector・空入力・null・同順位要素の挙動を維持する。名前列挙を別のList専用allowlistへ移すだけにしない。
- [ ] RF-LOWER-CALL-012: Map HOFのsource-backed保護と残存rewriteを整理する（前提: CALL-011）
  - 対象: policyと `+CallRewriteHandlers.swift` / Map HOF分岐、Map用lookup・テスト。`mapValues*` / `mapKeys*` / `filterKeys` / `filterValues` 等について解決先を確認する。
  - 完了条件: source実装の同名overloadを横取りせず、Listを返す操作とMapを返す操作の分類・重複key・挿入順・lambda例外を保持する。Set / factoryの変更は混ぜない。
- [ ] RF-LOWER-CALL-013: Arrayのsource-backed変換API保護を整理する（前提: CALL-012）
  - 対象: policy、`+CallRewriteArrayConversions.swift` / `+VirtualCallRewrite+Array.swift` のsource-backed変換分岐、対応lookup・テスト。`asList` / `toList` / `toTypedArray` / `sliceArray` / `copyOf*` / `reversedArray` 等の現在の移行状態を照合する。
  - 完了条件: generic / primitive / unsigned Arrayの宣言選択とview / copyの違いを保持し、型名・関数名だけを根拠に誤ったruntime表現へredirectしない。Arrayの格納形式やABI変更は対象外。
- [ ] RF-LOWER-CALL-014: Sequenceの保持例外を明示的な実行時表現に基づく判断へ置き換える（前提: CALL-013、STATE-009）
  - 対象: policyと `+CallRewriteSequencePipeline.swift` / `+CallRewriteSequenceTerminals.swift` のsource / runtime bridge選択。`Sequence`という静的型だけでは `RuntimeSequenceBox` とsourceオブジェクトを区別できないことを前提にする。
  - 完了条件: source / runtime由来、引数渡し、copy経由、由来不明をテストし、`map` / `filter` の既存例外を表現判定へ置換する。由来不明をsourceと決め打ちせず、遅延評価・例外タイミング・iterator bridgeを保持する。新しい全プログラム解析やRuntime表現統合は行わない。
- [ ] RF-LOWER-CALL-015: 移行済みAPIの保護用名前列挙を撤去してpolicyを閉じる（前提: CALL-006・014）
  - 対象: policyとdirect / virtual callの入口、使われなくなったlookupのみ。List / Map / Array / Sequence各群で保持済みの宣言を共通原則へ統合し、残るintrinsicは識別根拠・runtime表現・対応テストを明確にする。
  - 完了条件: `shouldPreserveSourceBackedAggregateCall` 相当の巨大なAPI名allowlistがなく、解決済みの通常Kotlin宣言を保持し、必要なbridgeだけを書き換える。別の巨大表への移設・source-backed全件の無条件skipで達成したことにしない。残作業があれば具体的なAPI単位へ再分割し、本項を先に完了しない。

### 2. 式分類・コピー伝播の一元化（RF-LOWER-STATE）

> STATE-001 → 002を先行。003と004はRegistryを共有するため直列。004後の005〜008は各葉ファイルだけなら並列可、共有ファイルを触るなら直列。009は003・007を待ち、010は003〜009の移行を待つ。CALL側と同一ファイルを変更する項目は、そのAPI群のPRとの同時着手を避ける。

- [ ] RF-LOWER-STATE-001: 分類・copy伝播の契約を小さなCoreテストへ固定する（前提: なし）
  - 対象: `CollectionRewriteState` / static classification / PreScanの既存テストと責務別追加テスト。List / Set / Map / Array / String / Range / Iterator / File / Pathを、直接値・引数・call result・copyの入口で確認する。
  - 完了条件: RangeとCharRange / ULongRangeの重なり、複数copy、未分類値、同じ変数への別値代入を扱い、単一enum化や無条件unionで意味が変わるケースを検出できる。現行にバグがある場合は誤動作を互換契約として固定しない。
- [ ] RF-LOWER-STATE-002: `KIRExprID` をキーにする分類ストアを導入する（前提: STATE-001）
  - 対象: `+RewriteState.swift` と局所テストのみ。複数分類を保持できるfactsを用い、静的型の情報とruntime表現の情報・unknownを別軸で表す。まず既存callerの記法を保つ互換アクセサを用意し、全ファイルの一括置換は行わない。
  - 完了条件: 状態の正本は一つで、copy伝播をストアの共通操作に集約する。旧 `inout Set<Int32>` の書き戻しと新APIの整合性を検証し、同じfactsの二重管理を残さない。アクセサごとの集合再構築等で走査コストが増えないか局所計測し、悪化時は境界を再設計する。
- [ ] RF-LOWER-STATE-003: PreScanの大量inout引数をstateに集約する（前提: STATE-002、CALL-002・003）
  - 対象: `+PreScan.swift` の `collectInitialCollectionExprIDs` / `handleCopyInstruction` / static seedとその内部helper、Registryの呼び出し口。種類別集合を個別に渡さず、STATE-002の状態APIを通す。
  - 完了条件: PreScanとrewrite本体でcopy伝播が別実装にならず、静的型・factory・call resultの初期分類が不変。走査回数削減や分類精度の変更はこの配線PRへ混ぜない。
- [ ] RF-LOWER-STATE-004: virtual-call dispatcherの状態受け渡しを一つにする（前提: STATE-003）
  - 対象: `CollectionLiteralLoweringRegistry.swift` と `+VirtualCallRewrite.swift` の入口・dispatcher。葉の処理は変えず、dispatcherの境界でstateを受け渡す形にする。
  - 完了条件: Registryから十数個の集合を渡す引数列がなくなり、未rewrite時の元命令・結果型・throw channel・dispatch情報が保たれる。葉ファイルへの機械的な全面置換は005〜008に分ける。
- [ ] RF-LOWER-STATE-005: Array virtual-callの分類操作をstate APIへ寄せる（前提: STATE-004。CALL-013と同時編集しない）
  - 対象: `+VirtualCallRewrite+Array.swift` と対応テストのみ。dispatcherへの変更が必要ならSTATE-004との境界を先に調整する。
  - 完了条件: Array用の集合操作・結果tag付けが共通APIを使い、generic / primitive Arrayの分類と戻り値が不変。calleeやboxing規則の変更はしない。
- [ ] RF-LOWER-STATE-006: Range virtual-callの重なる分類をstate APIへ寄せる（前提: STATE-004）
  - 対象: `+VirtualCallRewrite+Range.swift` と対応テストのみ。Range / CharRange / ULongRangeを排他的な一種類へ潰さない。
  - 完了条件: `step` / `reversed` / iterator経由で必要な複合factsが維持され、境界値・unsigned・copy経路を固定する。rangeのruntime実装は変えない。
- [ ] RF-LOWER-STATE-007: Sequence virtual-callの分類操作をstate APIへ寄せる（前提: STATE-004）
  - 対象: `+VirtualCallRewrite+Sequence.swift` と対応テストのみ。既存のsource / runtime経路選択はまだ変更しない。
  - 完了条件: Sequence / Iterator関連の結果tagとcopy後の判断が不変。静的なSequence型をruntime handleの証拠として新たに登録しない。
- [ ] RF-LOWER-STATE-008: property virtual-callの分類参照をstate APIへ寄せる（前提: STATE-004）
  - 対象: `+VirtualCallRewrite+Properties.swift` と対応テストのみ。List / Map / Set / File / Path等の分類参照を移し、既存の型・symbolガードを保持する。
  - 完了条件: `size`等の同名propertyを持つユーザー型がcollectionへ誤分類されず、未分類時のfallbackが不変。property lowering全体やsource API移行は混ぜない。
- [ ] RF-LOWER-STATE-009: Sequenceの静的型とruntime由来を分類段階で区別する（前提: STATE-003・007）
  - 対象: `+StaticTypeClassification.swift` と `+PreScan.swift` のSequence分類・既知producer追跡、対応テスト。source宣言・既知runtime factory / bridge・引数・copyについて、確認できるfactsだけを記録する。
  - 完了条件: 同じSequence型でもsourceオブジェクト / `RuntimeSequenceBox` / unknownを区別でき、分岐や再代入で根拠が失われた値を既知として扱わない。一般的なCFG固定点解析まで必要なら別IDへ分割し、推測で分類を補わない。CALL-014が消費できる契約を固定する。
- [ ] RF-LOWER-STATE-010: state互換層を整理し、残存callerと分類コストを検証する（前提: STATE-003〜009）
  - 対象: `+RewriteState.swift` の不要になったadapter・テスト。direct-call / HOF / factory等の未改名callerは単一ストアのviewを使う限り維持でき、表記統一だけの全ファイル変更は行わない。
  - 完了条件: 種類追加時のcopy伝播更新が一箇所で済み、複数の正本・失われるinout書き戻し・不要adapterがない。多数のcopy / collection操作を含む入力で時間・メモリを変更前と比較し、集合viewの再構築やストア走査の悪化を隠さない。生成結果と決定性が不変。

### 3. Inline 展開の責務分離・終了条件（RF-LOWER-INLINE）

> INLINE-001 → 002 → 003 → 004 → 005 → 006 → 007 → 008 → 009 → 010 → 011 → 012を基本のマージ順とする。002〜009は `InlineLoweringPass.swift` を共有するため、個別の小PRとして順次マージする。抽出時に展開順序・ラベル採番・ABI・例外処理を変えず、固定回数の撤廃は安全な停止条件を用意した010後に行う。

- [ ] RF-LOWER-INLINE-001: Inlineの抽出前契約を既存回帰テストで固定する（前提: なし）
  - 対象: Inline関連Core / Backend suitesの不足分のみ。nested inline、同名別symbol、imported inline、捕捉lambda、reified、non-local return、try/catch/finally、virtual / super call、ラベル重複の検証先を対応付ける。
  - 完了条件: KIR call metadata・型・制御フローと実行結果・決定性を検証でき、巨大suiteの一括移動なしで後続の抽出PRを評価できる。長い依存鎖・循環・展開量制限の仕様変更は010以降で扱う。
- [ ] RF-LOWER-INLINE-002: ラベル走査・再配置と採番状態を分離する（前提: INLINE-001）
  - 対象: `nextAvailableLabel` / `remapLabels` / `inlineLabelCounter` の責務、既存 `KIR/KIRLabelRelocation.swift` の再利用可能部分。現在の採番規則を保つ関数単位の状態境界を作る。
  - 完了条件: `.label` / 各jumpの全参照が同じ規則で移され、caller・lambda・tailrec由来のラベルと衝突しない。既存helperと異なる採番規則を無条件に統合せず、KIR/LLVM IR不変性を確認する。
- [ ] RF-LOWER-INLINE-003: 式複製・alias置換・命令operand書換えを分離する（前提: INLINE-002）
  - 対象: `rewriteInstruction` / `definedResult` / `resolveAlias` / `cloneOrReuseExpr` / `cloneExpr` と関連状態。責務別の複製helperへ移し、必要な型置換処理は既存実装へ委譲する。
  - 完了条件: call / virtualCallのsymbol・throw channel・super / dispatch情報、再代入されるexpr、const / temporaryを正しく保持する。型置換規則や展開順序は変更せず、不要なpublic APIを増やさない。
- [ ] RF-LOWER-INLINE-004: 型引数代入・reified token生成を分離する（前提: INLINE-003）
  - 対象: `InlineTypeSubstitution` / `buildInlineTypeSubstitution` / `collectInlineTypeSubstitution` / `substituteInlineType` / `buildTypeParamTokenValues` 等の型代入責務。
  - 完了条件: generic / nullable / function型・receiver・reified tokenの置換結果が不変で、imported inlineにも同じ処理が適用される。Semaの型推論や制約解決のリファクタは混ぜない。
- [ ] RF-LOWER-INLINE-005: erased lambda / inline ABIのboxing helperを分離する（前提: INLINE-004）
  - 対象: `usesErasedLambdaABI` / `boxSubstitutedErasedArguments` / `unboxErasedLambdaArguments` / 戻り値のbox・unbox等、現在Inline内にあるABI補正helper。
  - 完了条件: primitive / nullable / erased genericの引数・戻り値とimported lambda ABIの契約が不変。`ABILoweringPass` 自体の変更や新たなboxing最適化を混ぜない。
- [ ] RF-LOWER-INLINE-006: 展開後の例外経路補正を分離する（前提: INLINE-005）
  - 対象: `rerouteUnprotectedThrows` とその入出力・呼び出し口。callerのthrownResult、ローカルcatch、finally guard、出口ラベルの責務を明示する。
  - 完了条件: inline内部のcall / virtualCall / rethrowがcallerのcatchへ届き、既に保護された経路を二重に書き換えない。non-local returnを含むtry/finallyの既存回帰がgreenで、例外ABIやcanThrowの意味を変更しない。
- [ ] RF-LOWER-INLINE-007: 通常inline本体の展開処理を分離する（前提: INLINE-006）
  - 対象: `expandInlineCall` の本体と局所状態のみ。複製・型代入・ABI・例外補正は003〜006の境界を使い、lambda展開の実装はまだ移さない。
  - 完了条件: 引数評価順・returnの出口統合・non-local return・receiver / super情報が不変。通常inlineのテストとimported inlineの実行回帰を通し、ファイル移動とアルゴリズム変更を分離できている。
- [ ] RF-LOWER-INLINE-008: lambda本体の解決・展開処理を分離する（前提: INLINE-007）
  - 対象: `resolveLambdaFunction` / `expandLambdaBody` とcapture・return処理の局所状態のみ。
  - 完了条件: 捕捉有無・receiver付きlambda・noinline / crossinline・通常return / non-local returnの契約が不変。同名関数への誤fallbackや二重展開がなく、通常inlineの複製helperを再実装しない。
- [ ] RF-LOWER-INLINE-009: 展開対象indexと依存スケジューリングを分離する（前提: INLINE-008）
  - 対象: `run` のfunction snapshot構築、`expandNestedBodylessInlineCalls`、`inlineTransform` の走査制御。SymbolIDを主キーにした依存情報を抽出し、まず既存の4回 / 8回制御を維持する。
  - 完了条件: module / imported / lambda本体・bodyless inlineを区別し、symbol既知の呼び出しを無関係な同名関数へ結び付けない。辞書の列挙順に依存しない処理順がテストされ、arenaの式ID割当と既存出力が不変。
- [ ] RF-LOWER-INLINE-010: 固定回数撤廃の前に循環・展開量制限・必須inline残存の契約を実装する（前提: INLINE-009）
  - 対象: 分離済みschedulerと対応Core / Backend tests。bodyがobjectに存在しない `isInlineOnly` / imported inline等の必須展開と、通常callとして残せる関数を区別する。再帰・相互再帰・大きな非循環グラフでの停止条件を定める。
  - 完了条件: 必須展開の未解決callをリンク段階まで黙って残さず、循環・予算超過時に決定的な診断で停止する。非必須callを不必要にエラー化しない。既存4回 / 8回境界と境界超えの最小ケースを追加し、不具合が再現したら同じPRで修正する。全パス `KIRVerifier` は重複実装しない。
- [ ] RF-LOWER-INLINE-011: bodyless inline snapshotの固定4回走査を依存順処理へ置き換える（前提: INLINE-010）
  - 対象: `expandNestedBodylessInlineCalls` 相当のschedulerのみ。calleeからcallerへ処理する決定的worklistを使い、lambda内の依存も含める。呼び出し側の8回走査はまだ変えない。
  - 完了条件: 4段を超える正当な依存鎖でも必須callが解消され、同じ元本体の二重展開がない。diamond依存・imported inline・lambda内依存・循環での停止を固定し、010の診断と展開量制限を維持する。
- [ ] RF-LOWER-INLINE-012: caller本体の固定8回再走査を進捗に基づく展開へ置き換える（前提: INLINE-011）
  - 対象: `inlineTransform` / `expandInlineCalls` 相当の反復制御のみ。新たに現れた展開対象を追跡し、対象がなくなるまで処理するが、010の循環・予算制限を必ず適用する。
  - 完了条件: 深い非循環inline・多段lambda・再帰で正しく完了／診断し、必須inline残存チェックがgreen。例外・non-local return・型・ABI・決定性の全回帰を通し、大きな入力で処理時間・生成命令数・arena増加を変更前と比較する。上限を単に増やしただけ、または無制限ループへの置換で完了としない。

## Stdlib Kotlin 化 実行計画（KSP）

> RF-STDLIB / M1–M17 / MIGRATION-* の**実行体**。設計: [`docs/stdlib-pipeline.md`](docs/stdlib-pipeline.md)。棚卸し日: 2026-07-01（シンボル名は当日時点の実コードで検証済み。行番号は書かない — アンカーは必ず rg で引く）。2026-07-10 ギャップ監査で KSP-CAP / KSP-INF / KSP-W6 / CLEANUP-STUB-096+ / バグバックログを追補。2026-08-12 ギャップ再調査（§9 分類表×実行体タスクの突合 + 「別タスク」言及の棚卸し + ガバナンス enforcing の実装確認）で KSP-683〜692 / CLEANUP-STUB-125 / BUG-211 を追補。
> 依存: W0 → W1 → W2 は直列。W3 以降は「前提」欄に従い並列可。**言語機能ブロッカーは KSP-CAP-* として独立管理し、各タスクは必要 CAP を「前提」に宣言する（ブロッカー先行の原則）**。
> **粒度ルール**: 1タスク = 1 PR。目安「削除対象 kk_* ≤ 15・単一責務・golden 更新1回」。超えると判明したら枝番でなく新番号で分割する。
> クローズ記録: 旧 `STDLIB-JVM-166`（Java プレビュー機能）/ `STDLIB-REFL-175`（アノテーション処理高度機能）は 2026-07-07 #4582 で未完了のまま削除されたが、**ターゲット外として意図的クローズ**とする（2026-07-10 決定。復活させない）。
>
> **共通ゲート G**（全タスクの完了条件に含む）: `bash Scripts/swift_test.sh` / `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` すべて green。`Scripts/loc_report.sh` が存在する場合、`HeaderHelpers+Synthetic*` 行数・`"kk_` リテラル数の悪化なし。**完了マークは enforcing（テスト or rg チェック）の green 実績を完了メモに書けるものに限る — ドキュメント同期や部分検証のみでの完了は禁止**。TODO.md 編集時のゲート: **タスク定義行の ID 重複ゼロ**（`rg -o '^- \[.\] [A-Z][A-Z0-9-]*-[0-9]+' TODO.md | sort | uniq -d` が空、または `Scripts/check_todo_ids.sh` で確認）。この検出はタスク定義行（`- [ ] ID:` / `- [x] ID:`）限定で、本文中の「前提: KSP-CAP-004」等のクロスリファレンスは対象外。
> **golden 更新 U**: `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` → `git diff -- Tests/CompilerCoreTests/GoldenCases` が機械的差分のみであること。
> **移行テンプレート T**（W2〜W4/W6 の各タスクはこの手順）:
> 1. タスク記載の diff ケースを `Scripts/diff_cases/` で確認・なければ追加し、**現行実装**で `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` green を確認（挙動の固定）
> 2. タスク記載の実装先 .kt に Kotlin 実装を書く（既存ファイル追記可）。ランタイム依存点は `@KsSymbolName("__kk_...") internal external fun __名前(...)` で宣言
> 3. 新規 .kt は `Sources/CompilerCore/Stdlib/kotlin/` 配下に置くだけで自動配線される（除外リスト機構は KSP-505 で撤廃済み）
> 4. **同一 PR** で、タスク記載の (a) `HeaderHelpers+Synthetic*` の該当登録 (b) `CallTypeChecker+*` / `CallLowerer+*` の名前文字列特例 case (c) Runtime の `@_cdecl` 関数 (d) `RuntimeABISpec` の該当エントリ（parity テスト含む）を削除する。「ブリッジ残留」指定の関数は削除せず `__kk_` prefix へ改名し spec を更新
> 5. U → G → タスク記載の rg 完了チェックが 0 件
> 6. **移行完了の2点確認**: ①.kt 本体が実ロジック（`= this` 等のフェイク禁止 — 実例: RangeCoercion.kt） ②Sema/KIR/Lowering に同名 name-string 特例が残っていない
> 7. **二重 oracle**: diff ケースに加え、bundled .kt を実行して期待値比較する自己完結テスト（KSP-INF-006 のハーネス整備後は必須。整備前は G の既存テストで代替可）
> 8. ブリッジ（`__kk_*`）を**追加**する場合は理由コード（syscall / メモリ表現 / GC・continuation / メタデータ / 性能=実測値添付）を PR 本文に明記し、`RuntimeABISpec` 登録 + specVersion 更新をセットで行う。本家 kotlin-stdlib から移植した .kt には Apache 2.0 帰属ヘッダを付ける（KSP-INF-013）

### KSP-CAP: コンパイラ言語機能ブロッカー（2026-07-10 実機プローブで全件実測。移行タスクより先行して解消する）

> stdlib を本家形の Kotlin で書くために必要な言語機能の台帳。再現 .kt は各タスク着手時に `Scripts/diff_cases/` or 回帰テストへ固定する（プローブ時の最小再現はセッション記録 probes/p01〜p12b にあり、診断コードから容易に再構成可能）。完了条件は共通で「再現ケースが期待動作でコンパイル・実行され、回帰テストとして固定される + G」。

- [~] KSP-CAP-004: `while(true)` CAS ループ / `Nothing` 戻り値無限ループの型検査を通す（`KSWIFTK-TYPE-0001`。PR #4984 で実装・検証済み、マージ後に [x] 化。ブロック対象: KSP-673・`AtomicMigration.kt` コメントの保留解除）
- [~] KSP-CAP-018: object 式によるクラス継承を通す（= BUG-215）。ブロック対象: KSP-491・KSP-681（`Delegates.observable`/`vetoable` が返す `object : ObservableProperty<T>(initialValue) { override fun ... }`）・KSP-441（object 式でパイプラインを表現する方針）
  - **注記**: 旧 KSP-CAP-016/017（同一症状、2026-08-06 記録）と旧 BUG-187/188 は、名前不明の TODO.md 編集（`f9dea8961c` 付近、DEBT-DIFF-005 統合コミット群）でブロッカー台帳から本文ごと消失し、`[x]` 化されないまま記録が失われていた。名前付きサブクラスのスーパークラス primary constructor 実引数伝搬（旧 KSP-CAP-016 症状の一部）は別途 `1128468186`（PR #5506, "Fix BUG-155: run superclass constructors and class-body initializers"）で修正済みと 2026-08-18 実機確認したため当該部分はクローズ、object 式経由の残り2症状のみ本項として採番し直す。
  - 症状は2系統（interface を実装する object 式のプロパティ dispatch は BUG-141 で修正済み。本項目は**クラス**継承）:
    1. 基底クラスの `open`/`abstract` メンバを object 式が override しても dispatch されない。`open class Base { open fun describe(): String = "base" }` `fun make(): Base = object : Base() { override fun describe() = "anon" }` に対し `make().describe()` が基底実装 `"base"` を返す
    2. スーパークラス実引数付きの object 式 `object : Base(x) {}` は実行時 `KSwiftK panic [KSWIFTK-RUNTIME-0001]: kk_array_get_inbounds precondition failed` でクラッシュする（名前付きサブクラスは `1128468186` で修正済みだが、object 式はこのクラッシュが残る点が異なる）
  - 最小再現（kotlinc は `anon` / `7`。2026-08-18 `.build/debug/kswiftc` で再実機確認済み）:
    ```kotlin
    open class Base { open fun describe(): String = "base" }
    fun make(): Base = object : Base() { override fun describe(): String = "anon" }
    fun main() { println(make().describe()) }   // "base"

    open class Base2(val v: Int)
    fun make2(x: Int): Base2 = object : Base2(x) {}
    fun main2() { println(make2(7).v) }         // KSWIFTK-RUNTIME-0001
    ```
  - **部分修正（2026-08-18）**: 症状1・症状2ともに、object 式が**メンバ宣言（override 関数/プロパティ）を1つ以上持つ**場合は解消した。真因は2つの独立バグだった:
    (a) 症状1（override dispatch）: `ExprTypeChecker+ObjectLiteralInference.swift`（object 式は関数本体の型検査中に処理されるため、全ての named nominal に対して vtable slot を計算する `LayoutSynthesis.synthesizeNominalLayouts` — `runValidationPasses` で実行 — が既に完了した*後*に symbol が生成される）が、`NominalLayout.vtableSlots` をスーパークラスから単純コピーするだけで、object 式自身の `override` メンバに対する override 解決（継承 slot の再利用判定）を一切行っていなかった。`LayoutSynthesis.swift` の該当ロジック（`MethodDispatchKey` 照合・`resolveOverriddenSlot`）を `Sources/CompilerCore/Sema/DataFlow/VtableOverrideMatching.swift` の共有関数へ抽出し、`ExprTypeChecker+ObjectLiteralInference.swift` からも呼ぶことで解決。
    (b) 症状2（super ctor 実引数）: `object : Base(x) { ... }` の `(x)` はパーサ（`BuildASTPhase+ExpressionParserLambdaObjectCallable.swift` の `parseObjectLiteral`）が `skipBalancedParenthesisIfNeeded()` で単に読み捨てており、`ObjectDecl` に実引数を保持するフィールド自体が存在しなかった（`SuperTypeEntry.constructorArgs` は名前付きクラス専用で、`ObjectDecl.superTypes` は `[TypeRefID]` のみ）。`ObjectDecl.superTypeConstructorArgs: [CallArgument]` を新設し、`parseCallArguments()`（通常の呼び出し実引数パーサ）で実引数を捕捉。さらに (1) `ExprTypeChecker+ObjectLiteralInference.swift` でこれらの式を外側スコープ（`ctx`/`locals`）に対して型検査するよう追加（怠ると KIR lowering 時に式が未解決のまま `unit` に落ちる、ジェネリック引数 `T` の参照を含む場合に顕在化）、(2) `ObjectLiteralLowerer.swift` に `emitObjectLiteralSuperConstructorCall`（PR #5506 の `emitSuperConstructorDelegation` と同型のロジック）を新設し、`kk_object_new` 直後・itable/vtable 登録の直後にスーパークラスの `<init>` を実引数付きで呼び出すよう配線。
    回帰: `Scripts/diff_cases/object_literal_class_inheritance.kt`（`diff_kotlinc.sh` PASS 確認済み）、`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+ObjectLiteralClassInheritance.swift`（5テスト、ジェネリック外側スコープ引数・複数行 expression-body・複数コンストラクタ解決のケースを含む）。
  - **追加修正（2026-08-18、Devin Review 指摘）**:
    (c) `emitObjectLiteralSuperConstructorCall` がスーパークラスの `<init>` オーバーロードを `lookupAll(...).first` で無条件に選んでいたため、複数コンストラクタを持つ基底クラスで意図しないオーバーロードが呼ばれうる問題を修正。`resolveObjectLiteralSuperConstructor`（`ObjectLiteralLowerer.swift`）を新設し、まず arity で絞り込み、複数残る場合は実引数の Sema 解決済み型（`sema.bindings.exprTypes`）とパラメータ型を突き合わせて一意に決定する（型パラメータはワイルドカード扱い、`VtableOverrideMatching.swift` の override slot 解決と同型のロジック）。デフォルト引数の補完は行わないため、その場合は従来通り `lookupAll` の先頭にフォールバックする（named class 側の `emitSuperConstructorDelegation` と同じ既知の残存ギャップ）。
    (d) `parseTail`（`KotlinParser+Statements.swift`）のニューライン継続ヒューリスティックが、`=` の次行が `object` キーワードで始まる場合を常に「新規トップレベル宣言の開始」と誤判定していたバグ（旧 BUG-216）を修正。`shouldStopStatementBefore` 呼び出し側とトレーリングラムダ相当の継続判定の両方に、`object` の次のトークンが `:`/`{`（名前なし = object 式）かを見る `isObjectExpressionStart` ガードを追加。本家 `kotlin.properties.Delegates.observable`/`vetoable` の実際の複数行ソース記述がそのまま解析できるようになった。
    回帰: `Scripts/diff_cases/object_literal_class_inheritance.kt` に複数行 expression-body ケースと複数コンストラクタケースを追加、`CodegenBackendIntegrationTests+ObjectLiteralClassInheritance.swift` に対応する2テストを追加。
  - **追加修正2（2026-08-19、Devin Review 指摘）**: `ObjectDecl.superTypeConstructorArgs` はエンクロージング側の Sema/KIR コンテキストで型検査・lowering されるが、既存の2つの capture 解析トラバーサル（Sema `CaptureAnalyzer.collectCapturedOuterSymbols` と KIR `LambdaLowerer+CaptureAnalysis.swift` の `collectBoundIdentifierSymbols`/`containsImplicitReceiverReference`/`containsImplicitReceiverMemberAccess`）が object 式をメンバ本体・プロパティ初期化子のみ辿る前提で `.objectLiteral` をリーフ扱いしており、super ctor 実引数を素通りしていた。ラムダの中で object 式を作り、外側ローカルを super ctor 実引数からのみ参照するケース（`fun make(x: Int): () -> Base = { object : Base(x) { ... } }`）で、そのローカルがラムダのキャプチャリストに含まれず実行時クラッシュ（`kk_array_get_inbounds precondition failed`）になっていた。4箇所すべてに `superTypeConstructorArgs` を辿る分岐を追加して解決。調査中に副次的に発見した第5のバグも同一 PR 内で修正: `parseBlock`（`KotlinParser+Statements.swift`）のブロック先頭宣言判定が、(d) で修正した `parseTail` とは別に同じ「`object` は常に新規宣言」誤判定を持っており、ラムダ本体が bare な object 式**のみ**の場合（`{ object : Base(x) { override fun ... } }`）に `object` を新規トップレベル宣言として誤パースし、override dispatch が基底実装に戻っていた（`isObjectExpressionStart` ガードを追加して解決）。回帰: `Scripts/diff_cases/object_literal_class_inheritance.kt` にラムダ内 object 式のケースを追加、`CodegenBackendIntegrationTests+ObjectLiteralClassInheritance.swift` に対応する2テストを追加。
  - **未解消（別途対応が必要、本 PR のスコープ外）**:
    1. メンバ宣言を1つも持たない object 式（`object : Base(x) {}` のような空ボディ）は上記修正の対象外。`declID`（`ObjectDecl`）自体が生成されず（`parseObjectLiteralDecl` が空ボディで `nil` を返す）、`ObjectLiteralLowerer.lowerObjectLiteralExpr` の別経路（`ensureObjectLiteralGeneratedDecls`、`classID=0` で `nominalLayout` を計算しない簡易パス）を通るため、この PR の修正が届かない。`Delegates.observable`/`vetoable` は必ず override メンバを持つため実害はないが、上記の最小再現2番目のケース単体は依然クラッシュする。
    2. 名前付き（非リテラル）`object : Base(x) { ... }` 宣言は本項目の対象外（症状1は名前付きでも再現しないが、症状2のコンストラクタ実引数破棄と、加えて base 型変数経由での virtual dispatch がレシーバに誤った定数値を積む別バグ — 発見元 p9、`.symbolRef` 定数が `loadGlobal` の代わりに使われている — が残存。詳細未起票、必要になったら新規 CAP として切り出す）

### KSP-W3: excludedBundledStdlibFiles 解消（前提: KSP-202。相互独立・並列可）

### KSP-W4: モジュール量産移行（各タスク = 1 PR。手順はすべて T）

#### kotlin.reflect [M 番号なし・新設]（棚卸し 2026-07-01: メタデータレジストリ依存のためブリッジ色が濃い）

- [~] KSP-496: KClass 公開 API 層を Kotlin 化し、メタデータレジストリを `__kk_` 降格する
  - 完了: 下敷き2ファイルを `Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt`/`KClassMemberIntrospection.kt` へ移設・実配線（ルート `Stdlib/` の死蔵版は削除）。Kotlin 化: `simpleName`/`qualifiedName`/`isInstance`/真偽値フラグ12種（isFinal/isOpen/isAbstract/isData/isSealed/isValue/isEnum/isInterface/isObject/isInner/isCompanion/isFun。チケット記載は「11種」だが実装対象は`CompilerKnownNames.swift`基準の12種）/`visibility`/`annotations`。`__kk_` 降格: rg で全列挙した `kk_kclass_*`/`kk_type_token_*`/`kk_ktype_*`/`kk_ktypeprojection_*`/`kk_kfunction_*`/`kk_kparameter_*`/`kk_kconstructor_*`/`kk_annotation_*`（`RuntimeStringArray.swift`/`RuntimeReflection.swift`、計 ~65 個。`cast`/`safeCast` の実体もリネーム済み）をリネームし、`RuntimeABISpec` 側も追従（未登録だった `kk_kclass_nested_classes` の欠落も是正）。
  - 「全部対応して」指示を受けた追加調査で、残り3カテゴリの根本原因を深掘りし、うち2件を実際に修正した（詳細は下記）。全カテゴリの完全移行には至っていないが、根本原因の解像度は大きく上がっている。
  - **修正済みの根本原因バグ（3件、いずれも `Sources/CompilerCore/` 内）**:
    1. `String::class`/`Char::class`/`Any::class` のように、`HeaderHelpers.ensureClassSymbol` が member 宣言（CharSequence 適合など）を持たせるためだけに登録する `kotlin.<Name>` 偽装 `.class` シンボルが存在する組み込み型で、`T::class` のスコープ解決がこの偽装シンボルを builtin 名フォールバックより先に見つけてしまい、`classRefTargetType` が偽装 nominal 型（`.classType`）になる問題。これにより `String::class.isInstance("x")` が `RuntimeTypeCheckToken.encode` で `nominalBase` として誤符号化され、常に `false` を返していた（正しくは `stringBase`）。修正: `RuntimeTypeCheckToken.encode`（`Sources/CompilerCore/KIR/RuntimeTypeCheckToken.swift`）に `encodeBuiltinDisguisedNominal` を追加し、`.nominal` 分類時にこの偽装を検出して builtin base へフォールバックするようにした。回帰テスト `testBuiltinClassRefTokenMatchesPrimitiveBase`（`Tests/CompilerCoreTests/KIR/RuntimeTypeCheckTokenTests.swift`）追加済み。
    2. 上記と同根で、`TypeSystem.isSubtype` が偽装 nominal 型（例: `String` の `kotlin.String` 偽装シンボル）と canonical builtin 型（`.stringStruct` 等）を無関係な型として扱っていたため、`fun <T : Any> KClass<T>.cast(value: Any?): T = value as T` を `String::class.cast(v)` のように呼ぶと、ジェネリック制約ソルバが `KSWIFTK-TYPE-0001: Conflicting bounds for type variable`（`Class#N is not a subtype of Class#N & String`）を出して失敗していた。修正: `TypeSystem`（`Sources/CompilerCore/Sema/TypeSystem/TypeSystem.swift`）に `stringClassSymbol`/`charClassSymbol`/`anyClassSymbol` を追加（`HeaderHelpers+SyntheticStringStubs.swift`/`+SyntheticCharStubs.swift`/`HeaderHelpers.swift` の登録箇所で設定）し、`Subtyping.swift` の `isSubtype` 冒頭で `normalizeBuiltinDisguisedClassType` により両辺を正規化するようにした。`fun <T : Any> KClass<T>.myCast(value: Any?): T = value as T` を `String::class.myCast(v)`（期待型 `String`）から呼ぶケースで実際にコンパイル・実行成功を確認済み。
    3. （KClass 無関係の汎用バグ、上記調査中に副産物として発見）`fun <T> foo(value: Any?): T { return value as T }` のように非 reified 型パラメータへ `as T` する「unchecked cast」で、`RuntimeTypeCheckToken.encode` が `.typeParam` を `unknownBase`(=0) として符号化し、`kk_op_is` の `default: return 0` に落ちて **常に ClassCastException を投げていた**（本来 JVM 型消去と同じく無条件成功すべき）。`is T`（非 reified）は既に `KSWIFTK-SEMA-0084` でコンパイルエラーになるためこの土台は `as`/`as?` 経由でしか到達しないことを確認済み。修正: `ExprLowerer+ControlFlowAndBlocks.swift` の `.asCast` lowering で、ターゲット型が非 reified 型パラメータの場合はランタイム呼び出しを発行せず `.copy` 命令で値をそのまま通すようにした。
  - **完了（KSP-689）**: `members`/`constructors`/`primaryConstructor`/`properties`/`memberProperties`/`declaredMemberProperties`/`functions`/`memberFunctions`/`declaredMemberFunctions`/`nestedClasses`/`supertypes` が返す `RuntimeKFunctionBox`/`RuntimeKPropertyStub` 等のランタイムハンドルへ安定 nominal 型 ID と supertype edge を付与し、真の interface 適合性チェック（`is`/`as`）を成立させた。`KCallable.name` は複数 Box 型を順に `tryCast` する共通 bridge へ統合し、新規 diff/codegen/Runtime 回帰で検証済み。実装は `IndexedValue`/`Map.Entry` の前例である `runtimeRegisterObjectType(rawValue:classID:)` + `runtimeRegisterTypeEdge(childTypeID:parentTypeID:)`（`RuntimeHelpers.swift`）を利用し、Sema 側で既にモデル化済みの `KFunction <: KCallable` 等の関係と一致させている。
    - ~~`cast`/`safeCast`~~ **完了**: 懸案だった「throwing な `@KsSymbolName` external を bundled stdlib から呼ぶ」形が実際に動くことを検証した。`ABILoweringPass` は `RuntimeABISpec` の `isThrowing` を参照して `outThrown` 引数を自動挿入するため、Kotlin 側の external 宣言は値引数のみを書けばよい（`CallLowerer+MemberCallEmission.swift` の `throwingCallees` はメンバーコール専用で、この経路には無関係）。`KClassBasicAPI.kt` に `__kk_kclass_cast`/`__kk_kclass_safeCast` ブリッジと `KClass<T>.cast`/`safeCast` 拡張を追加し、Sema（`CallTypeChecker+KClassMemberCallInference.swift`）と KIR（`CallLowerer+KClassReflectMemberCalls.swift` / `CallLowerer+MemberCalls.swift`）の特例、および使われなくなった `kClassCastReturnType`/`kClassSafeCastReturnType`/`kClassCastName`/`kClassSafeCastName` を削除。diff ケース `kclass_cast.kt` と実行テスト `BundledStdlibExecutionTests.testKClassCastAndSafeCastExecuteThroughBundledExtensions` を追加。
    - `findAnnotation`: reified 型引数を要求する点に加え、見つかったアノテーションのランタイム表現 `RuntimeAnnotationBox`（`Sources/Runtime/RuntimeTypes.swift`）が引数を汎用文字列配列としてしか保持しないため、`findAnnotation<A>(): A?` を精密な `A?` 型で返しても `A` の宣言プロパティへの実アクセスは機能しない（members/constructors と同根の「ランタイムハンドルが本物の Kotlin オブジェクトとして振る舞わない」問題）。現状の compiler 特例は正直に `Any?` を返しているため、`if (found != null)` のような存在確認以上の用途は元々サポートされていない。
    - `findAssociatedObject`: 単体では戻り値が `Any?`（`T` へのキャスト不要）かつ実体が `runtimeObjectRaw=` プレフィックス経由で本物のオブジェクトハンドルを返す設計のため、Kotlin ソース化自体は上記2つより低リスクに見えたが、**既に `HeaderHelpers` 側で reified・inline・`@ExperimentalAssociatedObjects` opt-in 要求を満たす専用の synthetic シンボルが登録済み**（`Tests/CompilerCoreTests/Sema/ReflectFindAssociatedObjectSyntheticTests.swift` で検証されている）であることが判明。Kotlin ソースへの置き換えはこの opt-in 強制や reified 型引数の意味論を含めて忠実に再現する必要があり、当初想定より複雑と判断してこのセッションでは見送った（着手しかけた変更は復元済み）。
  - **見つかったが対象外として別タスクに切り出したバグ（2件、いずれも KClass 無関係の汎用コンパイラバグ）**: (1) ジェネリック関数内の文/式に `@Suppress("UNCHECKED_CAST")` を付けると `KSWIFTK-TYPE-0001`/`KSWIFTK-SEMA-0022` 等の誤エラーが発生する（HEAD でも再現する既存バグ、確認済み）。(2) `inline fun <reified T>` の本体で発生した例外が呼び出し元の `try`/`catch` で捕捉されずクラッシュする（インライン展開と例外処理範囲の相互作用が疑われる）。
  - 副産物として発見・修正した既存バグ（他の bundled Kotlin 拡張全般に影響しうる）: (1) `kotlin.reflect` が `ScopeBuilder.swift` のデフォルトインポートパッケージ一覧に無く、`kotlin.reflect` 配下の拡張がスコープ解決で見つからなかった (2) `BundledDeclarationIndex.receiverOwnerFQName` が `.kClassType`（`T::class` 用の内部専用型表現）を未処理で、`KClass<...>` レシーバの拡張が優先規則の索引に正しく載っていなかった (3) `RuntimeABISpec+Operator.swift` の `__kk_kclass_find_associated_object` 登録に `isThrowing: false` が抜けており、実体（2引数、`outThrown` 無し）と齟齬していた。
  - **完了（2026-08-18 追補）**: KSP-689 が nominal 型 ID を付与した `members`/`constructors`/`nestedClasses`/`primaryConstructor`/`memberProperties`/`declaredMemberProperties`/`functions`/`memberFunctions`/`declaredMemberFunctions`/`supertypes`（10種）を、`KClassMemberIntrospection.kt` の通常 Kotlin 拡張宣言（既存の `__kk_kclass_*` ブリッジへ委譲するだけ）へ実際に移行し、`CallTypeChecker+KClassMemberCallInference.swift`/`CallLowerer+KClassReflectMemberCalls.swift`/`CallLowerer+MemberCalls.swift` の対応する compiler 特例を削除した。`properties`（"member"/"declaredMember" 接頭辞なし）のみ、本家 kotlin-stdlib に存在しない架空の名前であり `Scripts/diff_cases/kclass_interface_handles.kt` がこれをユーザー宣言で shadow できることに依存しているため、意図的に compiler 特例のまま残した。
  - 移行作業中に「bundled 宣言と同名のユーザー宣言があるとコンパイルが著しく遅くなる」ように見える事象を一時疑ったが、高負荷なローカル環境（他セッションの並行ビルドで load average 200 超）での壁時計計測がノイズだっただけで、負荷の低い状態で CPU 時間・フェーズ別内訳・複数回試行の中央値を取って比較したところ shadow の有無で有意差は無いことを確認した（誤報として撤回済み）。
  - **診断の訂正（2026-08-18 Devin レビュー起点の再調査）**: 当初「`properties` を bundle 化すると、bundled 宣言とユーザーのファイルローカル宣言が同名で共存した際にファイルローカル宣言が正しく優先されず `kclass_interface_handles.kt` が退行した」と記録していたが、これは誤診断だった。`resolveExtensionPropertyGetter`（`CallTypeChecker+MemberCallCompanionAndProperties.swift:44`）にデバッグ計装を入れて実際に追跡したところ、`ctx.cachedScopeLookup` はスコープの shadowing を正しく尊重しており、`memberProperties` を実際に bundle 化して同じ shadow 構成で再現しても、ユーザーのファイルローカル宣言側の getter が正しく選ばれ、呼び出されることを確認済み（`val KClass<*>.memberProperties: List<Any?> get() = listOf("USER_MARKER_VALUE")` という shadow 宣言で `klass.memberProperties` が `["USER_MARKER_VALUE"]` を返すことを確認）。宣言解決自体にバグは無い。
  - **正しく特定できた根本原因、修正済み（KClass 無関係の汎用バグ）**: `kclass_interface_handles.kt` の `properties` shadow 宣言の本体 `get() = listOf(ReflectionSample::value)` が使う「バインドされていないプロパティ callable reference」（`Type::property` / `instance::property`）が、期待型（expected type）の無い文脈で評価されると誤った型に推論されていた。`ExprTypeChecker+NameLambdaAndCallableRefInference.swift` の `inferCallableRefExpr` 内、プロパティ候補が見つかった2分岐（unbound/bound の分岐と、bare `::member` の分岐）が、期待型が無いとき `KProperty0<T>`/`KMutableProperty0<T>`/`KProperty1<Owner, T>`/`KMutableProperty1<Owner, T>` を構築せず、プロパティの**値の型**そのもの（`propertyType`）へ単純にフォールバックしていた（関数 callable reference 側の対応する分岐は `driver.helpers.callableFunctionType(for:bindReceiver:sema:)` で期待型の有無に関わらず正しい関数型を都度構築しており、プロパティ側だけこの扱いが欠落していた）。
    - 最小再現（修正前）: `class C(val v: Int); fun main() { val ref = C::v; println("ref = $ref") }` → 実際には `ref = 0`（期待される `KProperty1<C, Int>` の文字列表現ではなく、`v` の値の型 `Int` の既定値らしき `0` が出力されていた）。
    - 修正: `ExprTypeChecker+NameLambdaAndCallableRefInference.swift` に `kPropertyReferenceType(ownerType:valueType:isMutable:sema:interner:)` を追加し、`kotlin.reflect.KProperty0`/`KMutableProperty0`/`KProperty1`/`KMutableProperty1` を `sema.symbols.lookup(fqName:)` で解決して具体化した型を構築、`inferCallableRefExpr` の該当2分岐の `let resultType = expectedType ?? propertyType` を `let resultType = expectedType ?? (kPropertyReferenceType(...) ?? propertyType)` に変更した（型解決に失敗した場合のみ旧フォールバックへ委譲）。回帰テスト `Tests/CompilerCoreTests/Sema/PropertyCallableReferenceDefaultTypeTests.swift`（unbound/bound/mutable/bare の4パターン + 明示的期待型が引き続き優先されることの固定）と diff ケース `Scripts/diff_cases/kproperty_default_inference.kt` を追加。`kclass_interface_handles.kt` は `properties` を compiler 特例のままにした状態でも green（この根本原因修正により、shadow 宣言の本体が正しく実行され `is KProperty<*>` が `true` を返すようになったため）。
    - **Devin Review 起点の追補修正（3件）**: (a) `expectedType` が `KProperty<*>`/`Any` 等、上記4種の具体形でない場合に無条件採用してしまい KIR 側の wrapper 生成条件（`propertyReferenceShape`）を満たせなくなる欠落を発見・修正。`resolvedPropertyReferenceResultType`（関数 callable reference 側の `expectedFunctionType`/`expectedSamInterfaceType` 判定と同じ考え方）を追加し、`expectedType` は「4種の具体形」または「関数型/SAM型」のときのみ採用し、それ以外は `inferredType` を使うようにした（`val p: KProperty<*> = C::v; p is KProperty<*>` が `true` になることを確認）。(b) その過程で一度「関数型/SAM型の expectedType も却下する」実装を入れてしまい、`val f: (C) -> Int = C::v` のような「プロパティ参照を関数値として使う」既存の正当なケースを壊しかけたが、実際には `list.map(C::v)` も `val f: (C) -> Int = C::v` も **本PRとは無関係に master 上で既にリンクエラー（`Undefined symbols ... "_name"`, 生成される `kk_function_value_adapter_*` サンクが未定義シンボルを参照）になる pre-existing バグ**であることを確認した上で、関数型/SAM型は無条件採用（修正前の Sema 挙動と同一）に戻した。回帰テスト `testExplicitFunctionTypeExpectedTypeStillWinsOverKPropertyDefault`（`PropertyCallableReferenceDefaultTypeTests.swift`）で Sema 側の型 binding のみ固定（下記バグ3のため実行までは確認できない）。(c) **🔴 高深刻度・実際に修正**: クラスのメンバー関数内で書いた bare `::プロパティ名`（レシーバなし。Kotlin では `this::プロパティ名` と同義の bound reference）が、既定型推論で `KProperty0`/`KMutableProperty0` になった結果、`LambdaLowerer.lowerCallableRefExpr`（`Sources/CompilerCore/KIR/LambdaLowerer.swift`）の wrapper 生成経路に新たに到達可能になったが、`receiverExpr == nil` のため `captureArguments` が空のまま生成され、暗黙レシーバ `this` を全く捕捉していなかった。結果、生成される accessor はレシーバ引数を要求するのに呼び出し側は 0 引数で呼ぶという不整合が生じ、`::v.get()` が `KSWIFTK-RUNTIME-0001: kk_array_get_inbounds precondition failed` でクラッシュしていた（`class C(val v: Int) { fun r(): Int = ::v.get() }` で再現。real kotlinc はこれを正当なコードとしてコンパイル・実行できることを `diff_kotlinc.sh` で確認済み — bare `::member` のメンバープロパティ implicit-this bound reference は元々サポートすべき正当な文法だった）。修正: `lowerCallableRefExpr` で `targetSymbol` の解決を capture 判定より前に移動し、`receiverExpr == nil` かつ対象がプロパティで `parentSymbol` がクラス/interface/object/enum（`isNominalTypeContainerSymbol`、新設、`LambdaLowerer+CallableResolutionAndCapture.swift`）の場合、`driver.ctx.activeImplicitReceiverExprID()` を capture として追加するようにした（`this::member` と同じ捕捉経路）。回帰: `Tests/CompilerCoreTests/KIR/CallableRefTypeIdentityTests.swift` に `testKIRCapturesImplicitReceiverForBareMemberPropertyRef`、diff ケース `Scripts/diff_cases/kproperty_bare_member_implicit_receiver.kt`（get/set 両方、`diff_kotlinc.sh` で real kotlinc と実行結果一致を確認済み）を追加。
    - **Devin Review 起点の追補修正（さらに2件、いずれも 🔴/🟡 高深刻度）**: (d) **修正済み**: `lowerCallableRefExpr` の暗黙レシーバ capture 分岐は `parentSymbol` が nominal 型かどうかしか見ておらず、capture するレシーバの**型**が実際にそのプロパティの所有者と一致するかを検証していなかった。`with(sb) { ::v }`（`v` は外側クラスのプロパティ、`sb` は無関係な `StringBuilder`）のようにレシーバ付きスコープ関数の内側では `activeImplicitReceiverExprID()` がスコープ関数のレシーバに差し替わっている（`CallLowerer+ScopeFunctionLowering.swift`）ため、無関係な型のオブジェクトを capture し `.get()`/`.set()` が別オブジェクトのフィールドを読み書きする危険があった。修正: `implicitReceiverMatchesOwner`（新設、`LambdaLowerer+CallableResolutionAndCapture.swift`）で `arena.exprType(implicitReceiver)` のノミナル型が所有クラスと一致（またはそのサブタイプ）であることを確認し、一致しない場合は capture せず（result: `with(sb) { ::v }` は capture 前と同じ `KSWIFTK-RUNTIME-0001` の安全なクラッシュに留まり、メモリ破壊は起きない）。(e) **回避策で対応**: (d) の型一致チェックを追加しても、companion object / 単純な `object` / enum entry が所有者の場合は、レシーバの型が正しく一致した上でもなお SIGSEGV でクラッシュすることが判明した（`class C { companion object { val x: Int = 5; fun readX(): Int = ::x.get() } }`）。これは capture の型不一致ではなく、シングルトンインスタンスの表現・到達方法自体に別の未特定の問題があると見られる（根本原因は本PRの範囲外として未調査）。安全のため、capture 対象を `isCaptureEligibleInstanceContainerSymbol`（`isNominalTypeContainerSymbol` から改名・`.class` のみに限定、`.interface`/`.object`/`.enumClass` を除外）で `.class` のみに制限し、**Sema 側でも** `.class` 以外を所有者とする bare `::member` は既定型推論・`resolvedPropertyReferenceResultType` の両方をバイパスして修正前の（`expectedType` を無視する）フォールバック挙動に戻した。結果、companion/object/enum 所有のプロパティへの bare `::member` 参照は本PR前と同じ「コンパイルエラー」に留まり、real kotlinc が受理する一部のケース（companion のプロパティ参照）を「コンパイルは通るがクラッシュする」に変えてしまうことを避けている。real kotlinc はこのケースを受理する（`diff_kotlinc.sh` で compile exit mismatch を確認済み — 意図的な未サポートなので diff ケースには追加していない）。
  - **副産物として見つけた既存バグ（4件、いずれも上記修正とは無関係の pre-existing・修正は本PR範囲外）**:
    1. **修正済み（当初「itable 登録の複数インスタンス破壊バグ」と誤診断していたが、実体は Sema 型推論バグの別症状だった）**: 同一プロパティへの「変数に代入して直接 `is` チェック」と「`listOf(...)` 経由で `is` チェック」を同一関数内で両方行うと SIGSEGV でクラッシュする問題（`class C(val v: Int); fun main() { val ref: KProperty1<C, Int> = C::v; println(ref is KProperty<*>); val list: List<KProperty1<C, Int>> = listOf(C::v); println(list[0] is KProperty<*>) }` → SIGSEGV、`kk_fn_get_s108686` 相当の生成関数内、`str xzr, [x8]` で無効アドレス書き込み）。当初は「`kk_object_register_itable_iface`/`kk_object_register_itable_method`（`Sources/Runtime/RuntimeStringArray.swift`）が生ポインタキーの辞書に登録する設計のため、複数 wrapper インスタンスが絡むと状態破壊が起きる」という runtime 側の仮説を立て、Sema 修正と無関係に再現することまでは確認していたが、実際に `lldb` でクラッシュ箇所を追跡したところ itable 登録そのものは無関係で、原因は `listOf(vararg elements: T)` へ渡す `C::v` が **`T` が未解決な間に型検査される**ため（`val list` 自体の宣言型注釈は無関係 — vararg の個々の要素式は `T` の解決前に個別に型検査される）、`resolvedPropertyReferenceResultType` が `expectedType`（＝未解決の `T`、`.classType` ではなく `.typeParam` を返すため `isConcreteKPropertyReferenceShape` は正しく `false` を返す）を却下して自然型へフォールバックする経路自体は正しく機能していたものの、そもそも本 PR のこの Sema 修正が landing する前の時点で観測されていたバグであり、**本 PR の Sema 修正（`kPropertyReferenceType`/`resolvedPropertyReferenceResultType`）が既に完全に修正していた**（`lowerPropertyReferenceWrapperValue` の `.classType` ガードが通るようになり、レガシーの裸シンボル参照フォールバック — `PropertyLoweringPass` が引数ゼロの getter 呼び出しへ誤って書き換えてしまう経路 — に落ちなくなったため）。現在の master 上のビルドで上記リプロを再実行し、クラッシュしないこと（`true`/`true` を正しく出力）を確認済み。ここに再度回帰を固定: diff ケース `Scripts/diff_cases/kproperty_generic_vararg_inference.kt`（`listOf(vararg)` 経由のパターン）と `Scripts/diff_cases/kproperty_supertype_expected_type.kt`（`KProperty<*>`/`Any` 型変数へ代入した参照を実際に使うパターン）を追加、Sema テスト `CallableRefTypeIdentityTests.testUnboundPropertyRefInGenericVarargCallGetsConcreteKProperty1Type` で `listOf(...)` 内の `C::v` が正しく `KProperty1` classType へ bind されることを固定。いずれも `diff_kotlinc.sh` で real kotlinc と一致確認済み。
    2. **修正済み**（旧: バインドされていないトップレベルプロパティ参照の `.get()` が常に値型の既定値を返す）: `val topLevel: Int = 7; fun main() { val bare: KProperty0<Int> = ::topLevel; println(bare.get()) }` → 期待値 `7` に対し実際は `0` になっていた。根本原因: 定数初期化子を持つ**不変（`val`）トップレベルプロパティ**は通常の読み取り経路（`ExprLowerer+ControlFlowAndBlocks.swift`）では `propertyConstantInitializers`/`constValueExprKind` によって呼び出し箇所へ定数がインライン展開され、対応するグローバルスロットへは一度も `.storeGlobal` で書き込まれない。一方 `ensurePropertyReferenceAccessor`（`LambdaLowerer+PropertyReferenceLowering.swift`）の getter 生成は無条件に `.loadGlobal` を発行しており、この「一度も書き込まれない」グローバルスロットを読んでいた（`var`、または定数でない初期化式を持つ `val` は元々このバグの影響を受けない — 対象は「定数畳み込み対象の `val`」のみ）。修正: getter 生成時にも同じ「不変プロパティかつ定数初期化子を持つ場合はインライン定数を使う」判定を追加し、それ以外の場合のみ `.loadGlobal` にフォールバックするようにした。回帰: diff ケース `Scripts/diff_cases/kproperty_toplevel_bare_reference.kt`（const `val` / `var` 双方の get、`var` の set まで含めて real kotlinc と実行結果一致を確認済み）。
    3. **プロパティ callable reference を明示的な関数型として使う（HOF の引数、または関数型変数への代入）と、リンク時に未定義シンボルで失敗する**: `class C(val v: Int); fun main() { val f: (C) -> Int = C::v; println(f(C(1))) }` および `listOf(C(1)).map(C::v)` の両方が `Undefined symbols for architecture arm64: "_name"`（`kk_fn_kk_function_value_adapter_*` から参照）でリンク失敗する。Sema は期待型どおり関数型を正しく bind しているため、KIR の「プロパティ参照を関数値アダプタへ変換する」lowering（`LambdaLowerer.swift` の function-value-adapter 生成経路。`Sources/CompilerCore/KIR/LambdaLowerer+PropertyReferenceLowering.swift` のラッパー生成とは別経路）にコード生成バグがあると見られる。**`git checkout` で本PR以前のコミットへ戻した上で同一ケースを再現し、本PR完全に無関係の pre-existing バグであることを確認済み**。
    4. **修正済み（KSP-505 追補、2026-08-19）**（旧: companion object / `object` / enum entry が所有するプロパティへの bare `::member` 参照が SIGSEGV でクラッシュする）: `class C { companion object { val x: Int = 5; fun readX(): Int = ::x.get() } }` → 明示的な型注釈を与えて capture の型一致チェックを満たしても尚 SIGSEGV していた。
       - 根本原因（companion object / plain `object` のみ、singleton 全般ではなかった）: 二重の問題があった。(a) `ensurePropertyReferenceAccessor`（`LambdaLowerer+PropertyReferenceLowering.swift`）が所有者の種別を見ずに常に「レシーバ + フィールドオフセット」経路（`kk_array_get_inbounds`）で accessor を生成していたが、`.object` 所有プロパティの実際の格納先はインスタンスフィールドではなく単一のモジュールレベル global スロット（`ExprLowerer+ControlFlowAndBlocks.swift` の `pk == .object` 分岐と同じ）だった。(b) companion/object がインターフェースを実装せず仮想 dispatch も持たない場合、実体は一切ヒープ確保されず（`KIRLoweringDriver+ObjectInitializer.swift`）、その「レシーバ」は単なる `0`（null）のプレースホルダになる（`NativeEmitter+EmissionConstants.swift` の `.symbolRef` 定数畳み込みが `globalVariables`未登録シンボルを `zeroValue` にフォールバックするため）。したがって capture されたレシーバで `kk_array_get_inbounds(0, offset)` を呼び SIGSEGV していた。
       - 修正: `.object` 所有プロパティに限り、(1) `ensurePropertyReferenceAccessor` が `ownerType: nil` を渡して受信者なしの `.loadGlobal`/`.storeGlobal` 経路（既存の KSP-496 バグ2番の定数インライン最適化を含む）にフォールバックするようにし、(2) `LambdaLowerer.lowerCallableRefExpr` が bare/明示的レシーバ両方の callable ref で暗黙 this のキャプチャを一切行わないようにした（`isSingletonOwnedPropertyRef` 判定を新設。キャプチャ数と accessor の引数個数を一致させる必要があるため、両者は必ずセットで直す）。Sema 側（`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`）も `.object` 所有者を `.class` と同様に `KProperty0`/`KMutableProperty0` の型推論対象に含めるよう緩和した。
       - `.enumClass` は意図的に除外したまま: 同じ「シングルトン」直感に反し、`enum class E(val v: Int) { A(1), B(2) }` のようにエントリ毎に別インスタンス・別フィールド値を持つため、`.object` と同じ global 化を試すと **実際にリグレッションを引き起こすことを実測で確認**（`::v` が全エントリで `0` を返す誤った値バグに変わった）。よって `.enumClass` は KSP-496 時点の安全なフォールバック（`expectedType` を無視しコンパイルエラーのまま）を維持。
       - **未検証・範囲外**: 「エントリ固有 body 内で宣言されたプロパティ」（例: `enum class E { A { val x: Int = 5 } }` の `x`）は、所有者がエントリ自身の匿名サブクラス（`.class` 相当）になっている可能性があり、その場合は既存の `.class` 経路で最初から動く可能性がある。しかし検証しようとすると、エントリ固有 body を持つ enum 定数を `EnumClass.ENTRY` の形で参照するだけで無関係の pre-existing バグ（`Unresolved member function`。`docs/diff-skip-inventory.md` の `enum_edge_cases.kt` 項目に記載済み）にブロックされ、確認できなかった。
       - 修正ファイル: `Sources/CompilerCore/Sema/TypeCheck/ExprTypeChecker+NameLambdaAndCallableRefInference.swift`, `Sources/CompilerCore/KIR/LambdaLowerer.swift`, `Sources/CompilerCore/KIR/LambdaLowerer+CallableResolutionAndCapture.swift`, `Sources/CompilerCore/KIR/LambdaLowerer+PropertyReferenceLowering.swift`。回帰: diff ケース `Scripts/diff_cases/kproperty_singleton_bare_reference.kt`（companion の const `val`/`var` の get・set、`Companion.` 経由の直接アクセスでの反映確認、トップレベル `object` の明示レシーバ参照まで含めて `diff_kotlinc.sh` で real kotlinc と実行結果一致を確認済み）。
  - diff: `kclass_basic.kt`, `kclass_cast.kt`（新規）, `reflect_kclass_ktype.kt`, `kclass_type_model.kt`, `type_reflection.kt`, `reflection_dynamic_call.kt`, `kclass_interface_handles.kt`, `kproperty_default_inference.kt`（新規）, `kproperty_bare_member_implicit_receiver.kt`（新規）, `kproperty_toplevel_bare_reference.kt`（新規）, `kproperty_singleton_bare_reference.kt`（新規）, `kproperty_generic_vararg_inference.kt`（新規）, `kproperty_supertype_expected_type.kt`（新規） green（移行後も kotlinc と一致）。`kclass_members.kt`/`kclass_ktype_basic.kt`/`annotation_reflection.kt` は変更前から kotlinc 側が別理由（`kotlin.reflect.full` 未 import 等）で失敗しており未変更（git stash で移行前と同一エラーを確認済み）。

#### kotlin.coroutines / Flow / Channel [(c)/(b) 分類確定 + (b) 群のみ移行]（棚卸し 2026-07-01: スタブ 23 ファイル 10,849 行 / Runtime 7 ファイル 279 @_cdecl）

> 引き継ぎ注記(2026-07-10): 旧 `STDLIB-CORO-001`（`[~]` のまま 2026-07-07 #4582 で削除）の残課題は KSP-498/499 + KSP-674〜679 が正式に引き継ぐ。SharedFlow/StateFlow 等の細分は KSP-W6 の concurrent 節を参照。

- [ ] KSP-1543: real `ProducerScope` を用いた channelFlow/callbackFlow の (b) 実装を設計・実装する（KSP-686 完了メモの残課題として記録されたまま未起票だった — 2026-08-19 起票。当初 KSP-1542 として起票したが、master 側の別コミットが同番号を別内容〔`HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` 整理〕に使っていたためマージ時に 1543 へ採番し直した）。現状: `channelFlow`/`callbackFlow` は (a)（未実装 API）に分類されており、`channelFlow<Int> { send(1) }.collect { println(it) }` は `KSWIFTK-SEMA-0023: Unresolved function 'send'`、`callbackFlow<Int> { trySend(1); close() }.collect { println(it) }` は `trySend`/`close` 未解決でコンパイル終了する（リンク・実行には到達しない）。fiction の `emit` alias は両 builder とも compile/run して動作するが、real `ProducerScope` API の動作ではない。両 API とも `flow_builders.kt` の Sema 回帰テストで明示的な未解決診断として固定済み（`HeaderHelpers+SyntheticCoroutineRegistry.swift` の合成登録、`CallTypeChecker`/`TypeCheck/Helpers` の fallback、`FlowLoweringPass`/`CoroutineLoweringPass` の特例、未実装 `kk_channel_flow_*`/`kk_callback_flow_*` ABI allowlist は KSP-686 で削除済み）。

### KSP-W5: 後始末（W3/W4 の対応タスク完了後）

- [ ] KSP-1541: 機能スライス名の bundled `.kt` ファイルを kotlin-stdlib 本家準拠のファイル名へ統合・リネームする（KSP-505 手順(2)(3) の分割先。前提: 対象モジュールの M フェーズ完了）
  - 背景: `docs/stdlib-pipeline.md` §6「既存の機能スライス名（`ListFilterHOF.kt` 等）は当該モジュールの M フェーズ完了時に統合・リネームする」を実行するタスク。2026-08-18 時点では text（M1: `KSP-693` 未完了）/collections（M3: `KSP-426`/`KSP-428` 未完了）を含む複数のモジュールがまだ (b) 残ありで対象外（着手時に §9 棚卸し表で全モジュールを再確認すること）
  - 着手条件: `docs/stdlib-pipeline.md` §9 の3分類棚卸し表を rg で再確認し、対象モジュールの (b) 行（未移行の合成スタブ登録）が 0 件であること。モジュール単体で条件を満たせば、そのモジュールだけ先行して統合・リネームしてよい（粒度ルールにより 1 モジュール = 1 PR に分割可）
  - 手順: (1) 対象モジュール配下の機能スライスファイル（例: `collections/ListFilterHOF.kt`, `text/StringBasics.kt` 等）を本家 kotlin-stdlib のファイル名・配置（例: `collections/Collections.kt`, `text/Strings.kt`）へ統合・リネーム（`docs/stdlib-pipeline.md` §6）。挙動変更ゼロが条件 (2) `UPDATE_GOLDEN=1` で golden 更新し `git diff -- Tests/CompilerCoreTests/GoldenCases` が機械的差分のみであることを確認 (3) 共通ゲート G green

### KSP-W6: 追補モジュール移行（ギャップ監査 2026-07-10。手順は全て T。粒度ルール適用済み = 1タスク1PR）

> 2026-07-10 監査で判明した「(b) 分類なのに KSP タスクが無い」領域 + (c) 再分類監査（厳格原則: Swift 残留は言語コア/GC・continuation・メタデータ/OS syscall のみ）で b-reclass になった領域の実行体。各タスクの削除対象・特例位置は監査時点で実コード検証済み — 着手時は rg で再固定する。

#### delegates / reflect

- [ ] KSP-681: ObservableProperty/Delegates 残余を Kotlin 化する（KSP-491 の範囲を超える残り約20系統。前提: KSP-491, KSP-680）。BUG-017はKSP-CAP-013のPR #4976で独立に修正済みのため本タスクの前提から外れた
  - **2026-08-18 着手前ブロック中**: 前提 KSP-491 が KSP-CAP-018/019/020（object 式クラス継承 / delegate トレーリングラムダ / 拡張 operator getValue 解決）で着手前ブロック中のため、本タスクも同じ理由で着手不可。「KSP-491 の範囲を超える残り約20系統」の内訳を棚卸しした限りでは全て `kotlin.properties`/`ObservableProperty`/`Delegates` 系（`kotlin.reflect` の KProperty0/1/2 等は KSP-682/KSP-689 が別途カバー済み）で、KSP-491 と同じ「operator 規約による本家準拠の delegate 実装」を要するため、同じ3ブロッカーの影響を受ける可能性が高い。KSP-491 側のブロッカー解消（またはブロッカーを回避できる具体的な残り20系統の切り出し）が先決。詳細は KSP-491 の 2026-08-18 実機再プローブ注記を参照
#### bucket (b) 未起票追補（2026-08-14）

> `HeaderHelpers+SyntheticBucketedStubRegistry.swift` の `sourceBackedMigration` 登録で §9 分類表 (b) かつ既存 KSP タスクに未追跡だった residual 群。`TODO.md` 棚卸し日 2026-08-14。採番は KSP-695 の続き。
>
> 2026-08-14 現 HEAD で `SyntheticBase64Stubs` / `SyntheticHexFormatStubs` は存在しないため、Base64/HexFormat 対応タスクは追加しない。

- [ ] KSP-697: `buildList` capacity overload を Kotlin 化し `HeaderHelpers+SyntheticBuilderDSLStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticBuilderDSLStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/CollectionBuilders.kt`
  - 削除/降格 kk_*: `__kk_build_list_with_capacity` を活用 or 削除（`RuntimeBuilders.swift`/`RuntimeCollections.swift`。着手時 rg）
  - 手順: T
  - diff: `build_list.kt` 等既存 + capacity 引数ケース追加
  - 前提: なし

- [ ] KSP-699: CollectionFactory bootstrap stub を削除し factory 関数を完全に Kotlin 化する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticCollectionFactoryStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/CollectionFactories.kt`
  - 削除/降格 kk_*: `kk_list_of_not_null`（`RuntimeCollections.swift`/`RuntimeABISpec+BridgeCoverage.swift`/`CallLowerer+CollectionFactoryCalls.swift`）を `__kk_list_of` 経由化 or 削除。`__kk_emptyList`/`__kk_list_of`/`__kk_emptySet`/`__kk_set_of`/`__kk_emptyMap`/`__kk_map_of` は source 使用継続
  - 手順: T
  - diff: `collection_factory_*.kt` 既存 + `listOfNotNull` ケース
  - 前提: なし（KSP-700/703/704/705 と統合調整可）

- [ ] KSP-700: core collection / iterable / Comparable / List interface shells を Kotlin 化し、旧 synthetic shell 登録を residual 責務へ分離する
  - 対象 residual: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticComparableResiduals.swift`, `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticCollectionResiduals.swift`, `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticListResiduals.swift`（`LateListIndexedMembers` 含む）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/Comparable.kt`, `Sources/CompilerCore/Stdlib/kotlin/collections/` 新設 `Iterable.kt`/`Collection.kt`/`List.kt`/`MutableIterable.kt`/`MutableCollection.kt`/`AbstractList.kt`（既存 `MutableIterable.kt`/`AbstractCollection.kt`/`AbstractMutableCollection.kt`/`RandomAccess.kt` 活用）
  - 削除/降格 kk_*: interface shells には public `kk_*` なし。`Comparable` primitive conformances / `setupPrimitiveComparableImplementations` は (c) 残留として分離 or `__kk_` 降格
  - 手順: T
  - diff: `comparable_interface.kt` 等既存 + 新規 collection interface 宣言ケース
  - 前提: KSP-701, KSP-703, KSP-704, KSP-705, KSP-699（orchestrator 削除前に内部呼び出しを独立化）

- [ ] KSP-703: Map shell / HOF を Kotlin 化し `HeaderHelpers+SyntheticMapStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMapStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/` 新設 `Map.kt`/`MutableMap.kt`/`HashMap.kt`/`LinkedHashMap.kt`（`MapHOF.kt`/`MapLookupAndTransform.kt` 既存から統合）
  - 削除/降格 kk_*: `kk_map_*` public ブリッジ（`RuntimeSetAndMap.swift`/`RuntimeMapHOF.swift`。着手時 `rg -o '@_cdecl\("kk_map[a-zA-Z0-9_]*"\)' Sources/Runtime` 全層で再固定）を削除 or `__kk_` 降格
  - 手順: T
  - diff: `map_*.kt` 既存 + `HashMap`/`LinkedHashMap` 生成ケース
  - 前提: KSP-700, KSP-701

- [ ] KSP-704: Set shell / HOF を Kotlin 化し `HeaderHelpers+SyntheticSetStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticSetStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/` 新設 `Set.kt`/`MutableSet.kt`/`HashSet.kt`/`LinkedHashSet.kt`（`SetHOF.kt` 既存から統合）
  - 削除/降格 kk_*: `__kk_mutable_set_*` 等 demoted bridges を活用。`kk_set_*` public があれば削除（着手時 `rg -o '@_cdecl\("kk_set[a-zA-Z0-9_]*"\)' Sources/Runtime`）
  - 手順: T
  - diff: `set_*.kt` 既存 + `HashSet`/`LinkedHashSet` 生成ケース
  - 前提: KSP-700, KSP-701

- [ ] KSP-705: MutableList / MutableCollection `addAll` 群を Kotlin 化し関連 stub を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMutableListStubs.swift`（`addAll` 関連部分）, `HeaderHelpers+SyntheticMutableCollectionArrayAddAll.swift`, `HeaderHelpers+SyntheticMutableCollectionIterableAddAll.swift`, `HeaderHelpers+SyntheticMutableCollectionSequenceAddAll.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/` 新設 `MutableList.kt`/`MutableCollection.kt`（`MutableCollections.kt` 既存活用）
  - 削除/降格 kk_*: `__kk_mutable_list_addAll`, `__kk_mutable_collection_addAll_*` 等 demoted bridges を活用。`kk_mutable_*_addAll` public があれば削除（着手時 `rg 'kk_mutable.*addAll' Sources/Runtime Sources/CompilerCore`）
  - 手順: T
  - diff: `mutable_list_addAll.kt` 新規 + 既存 `list_*.kt`
  - 前提: KSP-700, KSP-701, KSP-703, KSP-704

- [ ] KSP-708: TypedRange (`IntRange`/`LongRange`/`CharRange`) class shells を Kotlin 化し `HeaderHelpers+SyntheticTypedRangeStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticTypedRangeStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/` 新設 `IntRange.kt`/`LongRange.kt`/`CharRange.kt`（`Ranges.kt` 既存インターフェース活用）
  - 削除/降格 kk_*: `kk_int_range_*`, `kk_long_range_*`, `kk_char_range_*` 等 public ブリッジを `__kk_` 降格 or 削除（`RuntimeRange*.swift`。着手時 `rg -o '@_cdecl\("kk_(int|long|char)_range[a-zA-Z0-9_]*"\)' Sources/Runtime` 全層で再固定）
  - 手順: T
  - diff: `range_basic.kt` 等既存 + 新規 TypedRange 単独ケース
  - 前提: KSP-451, KSP-456, KSP-700（Comparable）

- [ ] KSP-709: UnsignedRange (`UIntRange`/`ULongRange`) class shells を Kotlin 化し `HeaderHelpers+SyntheticUnsignedRangeStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticUnsignedRangeStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/` 新設 `UIntRange.kt`/`ULongRange.kt`
  - 削除/降格 kk_*: `kk_uint_range_*`, `kk_ulong_range_*` 等 public ブリッジ（`RuntimeRange*.swift`。着手時 rg）
  - 手順: T
  - diff: `range_basic.kt` 等既存 + unsigned range ケース追加
  - 前提: KSP-451, KSP-456, KSP-708

- [x] KSP-710: StringBuilder 公開 surface / supertypes を Kotlin 化し `HeaderHelpers+SyntheticStringBuilderStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticStringBuilderStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder.kt`（既存 source 継続）
  - 削除/降格 kk_*: `__kk_string_builder_*` demoted bridges は source 使用継続。`kk_string_builder_*` public があれば削除（着手時 `rg -o '@_cdecl\("kk_string_builder[a-zA-Z0-9_]*"\)' Sources/Runtime`）
  - 手順: T
  - diff: `string_builder_*.kt` 既存 + `Appendable`/`CharSequence` supertype ケース
  - 前提: KSP-711, KSP-717

- [x] KSP-713: `TODO()` / system / `Any.javaClass` 等の `SyntheticTODOAndIOStubs` 残余を Kotlin 化し縮小/削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticTODOAndIOStubs.swift`（KSP-692 分割後の残余）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/Preconditions.kt`（`TODO()`）、`kotlin/system/System.kt`、`kotlin/io/Buffer.kt`、`kotlin/JavaClass.kt`、`java/lang/{Class,System,Runtime}.kt`
  - 削除/降格 kk_*: `kk_io_default_buffer_size`、`kk_system_gc`、`kk_runtime_{getRuntime,totalMemory,freeMemory,maxMemory}`、`kk_any_javaClass`（現行の `__kk_*` bridges は source-backed 宣言の内部実装として保持）
  - 手順: T
  - diff: `todo_*.kt`, `system_*.kt` 既存 + 新規
  - 前提: KSP-651（sequence factory 移行後）, KSP-683（duration compat 整理）, KSP-698（Closeable）, KSP-699（CollectionFactory）, KSP-707（Precondition）
  - 完了（2026-09-04）: `kotlin/system/System.kt`、`kotlin/io/Buffer.kt`、`kotlin/JavaClass.kt`、`java/lang/{Class,System,Runtime}.kt` を source-backed 化。`TODO()`/console/system/`Any.javaClass`/`DEFAULT_BUFFER_SIZE` の専用Synthetic登録と純定数Runtime関数を削除し、GC/Runtime memory bridge は `__kk_*` に降格してKotlinラッパーからのみ利用する。対象ファイルに残るのは sequence、Kotlin/Native Platform/enum、MemoryModel、FileIO bootstrap、function-type fallback の残余。
  - 検証: JavaClass/System/IO focused Sema、System bundled-callee KIR、GC/Runtime memory、Runtime ABI parity、targeted Sema Golden shard（更新あり/なし）、`memory_management.kt` の直接ビルド・実行、`check_todo_ids.sh`、`validate_runtime_abi_links.sh`、`git diff --check`。

- [ ] KSP-714: RangeProgression / RangeInterface / RangeUntil クラス群を Kotlin 化し stub 群を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticRangeProgressionStubs.swift`, `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticRangeInterfaceStubs.swift`, `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticRangeUntilStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/` 新設 `IntProgression.kt`/`LongProgression.kt`/`CharProgression.kt`/`UIntProgression.kt`/`ULongProgression.kt`/`Progressions.kt`（`Ranges.kt` 既存インターフェース活用）
  - 削除/降格 kk_*: `kk_op_step`, `kk_op_downTo`, `kk_op_rangeUntil`, `kk_int_progression_*`, `kk_long_progression_*`, `kk_char_progression_*`, `kk_uint_progression_*`, `kk_ulong_progression_*` 等（`RuntimeRange*.swift`。着手時 rg）
  - 手順: T
  - diff: `range_progression.kt` 新規 + `range_basic.kt`/`range_until.kt` 既存
  - 前提: KSP-451, KSP-456, KSP-708, KSP-709

- [ ] KSP-717: `String` synthetic stub 残余（CharSequence / Appendable / String basics / Locale / normalize / number-to-string）を Kotlin 化し `HeaderHelpers+SyntheticStringStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticStringStubs.swift`
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/text/` 新設 `CharSequence.kt`/`Appendable.kt`/`StringBasics.kt`/`StringLocale.kt`/`StringNormalize.kt`/`StringNumberConversions.kt`（既存 `String*.kt` 群活用）
  - 削除/降格 kk_*: `kk_string_length`, `kk_int_toString_radix`, `kk_locale_new_*`, `__kk_string_builder_append_*`, `__kk_lowercase_locale`, `__kk_uppercase_locale`, `__kk_string_compareTo_locale`, `__kk_string_normalize_flat`, `__kk_string_isNormalized_flat` 等（`RuntimeString*.swift`。着手時 `rg 'kk_(string_length|int_toString|locale_new|lowercase|uppercase|string_compareTo|string_normalize|string_isNormalized)[a-zA-Z0-9_]*' Sources/Runtime` / `rg '__kk_(lowercase|uppercase|normalize|isNormalized|string_builder_append)[a-zA-Z0-9_]*' Sources/Runtime` で再固定）
  - 手順: T
  - diff: `string_*.kt` 既存拡張 + `charsequence_*.kt`/`locale_*.kt`/`normalize_*.kt` 新規
  - 前提: KSP-406, KSP-407, KSP-408, KSP-409, KSP-410, KSP-411, KSP-624, KSP-710, KSP-711

#### bucket (b) 未起票追補 第2弾（2026-08-16）

> 「Kotlin source 以外（Synthetic Swift stub / Runtime 公開 `kk_*` / Sema 名前特例）で実装が残っている stdlib 面」を master `eacdb9026` で再棚卸しし、既存 KSP タスクにどのタスクでも追跡されていなかった残余を 1タスク=1PR で起票したもの。Stdlib gap audit 2.3.10（KSP-719〜KSP-1502）との重複を避けるため採番は KSP-1502 の続き（KSP-1503〜）。
>
> 実測（2026-08-16, master `eacdb9026`）: bundled Kotlin source 153ファイル/23,266行、Synthetic stub 68ファイル/45,516行、Runtime 公開 `kk_*` 1,175、bridge `__kk_*` 688、`excludedBundledStdlibFiles` 0件。
>
> 各タスクの「削除/降格 kk_*」は棚卸し時点の列挙であり、着手時に必ず記載の `rg` で再固定する（先行タスクのマージで既に消えている場合は TODO 同期として完了化してよい）。

- [ ] KSP-1503: MutableList / AbstractMutableList の class shell と要素追加・削除メンバを Kotlin 化する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMutableListStubs.swift`（1364行のうち `registerSyntheticMutableListStub` / `registerSyntheticAbstractMutableListStub` / `set` / `add` / `add(index)` / `removeAt` / `removeFirst(OrNull)` / `removeLast(OrNull)` / `clear` / `removeAll` / `retainAll` / `plusAssign` / `minusAssign` 部分。`addAll` 群は KSP-705）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableCollections.kt` 追記（class shell は `Collections.kt` / 新設 `AbstractMutableList.kt`）
  - 削除/降格 kk_*: `kk_mutable_list_*`（`set`/`add`/`addAt`/`removeAt`/`removeFirst*`/`removeLast*`/`clear`/`removeAll`/`retainAll`）系を `__kk_` 降格。着手時 `rg -o '@_cdecl\("kk_(mutable_)?list_[a-zA-Z0-9_]*"\)' Sources/Runtime` と `rg 'removeFirstOrNull|retainAll' Sources/CompilerCore/Sema Sources/CompilerCore/KIR` で再固定
  - 手順: T
  - diff: `mutable_list_*.kt` 既存 + `removeFirstOrNull`/`removeLastOrNull`/`retainAll`/`minusAssign` 単独ケース
  - 前提: KSP-700, KSP-705

- [ ] KSP-1504: MutableList の in-place 並べ替え（`sort`/`sortWith`/`sortBy`/`sortByDescending`/`sortDescending`/`shuffle`/`reverse`）を Kotlin 化し `HeaderHelpers+SyntheticMutableListStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMutableListStubs.swift`（`registerMutableListSort*` / `registerMutableListShuffleMember` / `registerMutableListReverseMember`。KSP-705/KSP-1503 完了後の残余）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/ListSortingHOF.kt` 追記（in-place 版）
  - 削除/降格 kk_*: `kk_mutable_list_sort*` / `kk_mutable_list_shuffle` / `kk_mutable_list_reverse` 系（着手時 `rg -o '@_cdecl\("kk_[a-zA-Z0-9_]*(sort|shuffle|reverse)[a-zA-Z0-9_]*"\)' Sources/Runtime`）。`shuffle` の乱数コアは `__kk_random_*` へ降格
  - 手順: T
  - diff: `mutable_list_sort*.kt` 既存 + `shuffle(Random(7))` 決定性ケース、`sortBy`/`sortByDescending` 単独ケース
  - 前提: KSP-426, KSP-685, KSP-705, KSP-1503

- [ ] KSP-1509: `List<E>` の `random`/`randomOrNull` を Kotlin 化し `HeaderHelpers+SyntheticListAggregateMembers.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticListAggregateMembers.swift`（KSP-1505〜1508 完了後の残余 + `registerListAggregateMembers` orchestrator）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/ListAccessHOF.kt` 追記
  - 削除/降格 kk_*: `kk_list_random`, `kk_list_randomOrNull`（`Random` 引数版含む）。乱数コアは `__kk_random_*` へ降格
  - 手順: T
  - diff: `list_random*.kt` 既存 + `random(Random(7))` 決定値ケース、空リストの `randomOrNull`/例外ケース
  - 前提: KSP-685, KSP-1505, KSP-1506, KSP-1507, KSP-1508

- [ ] KSP-1511: `List<E>` の `sorted`/`sortedDescending`/`shuffled`/`sum` を Kotlin 化し `HeaderHelpers+SyntheticListTransformMembers.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticListTransformMembers.swift`（KSP-1510 完了後の残余。`sum`/`distinctBy` を含むファイル冒頭コメントの「not yet source-backed」分）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/ListSortingHOF.kt` / `ListAggregateHOF.kt` 追記
  - 削除/降格 kk_*: `kk_list_sorted`, `kk_list_sortedDescending`, `kk_list_shuffled`, `kk_list_shuffled_random` + 着手時 `rg -o '@_cdecl\("kk_list_(sum|distinctBy)[a-zA-Z0-9_]*"\)' Sources/Runtime`
  - 手順: T
  - diff: `list_sorted*.kt` 既存 + `shuffled(Random(7))` 決定値ケース（KSP-CAP-011 の非回帰確認）、`sum` の Int/Long/Double ケース
  - 前提: KSP-685, KSP-1510

- [ ] KSP-1517: `booleanArrayOf`/`byteArrayOf`/`charArrayOf`/`doubleArrayOf`/`floatArrayOf`/`intArrayOf`/`longArrayOf`/`shortArrayOf` と unsigned 版 factory を Kotlin 化し `HeaderHelpers+SyntheticArrayStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticArrayStubs.swift`（`*ArrayOf` factory + class shell。KSP-1514〜1516 完了後の残余）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayConversions.kt` / `UArrays.kt`（class shell は `ArrayIntrinsics.kt`）
  - 削除/降格 kk_*: `kk_array_of` ほか着手時 `rg -o '@_cdecl\("kk_[a-zA-Z]*[Aa]rray_?of[a-zA-Z0-9_]*"\)' Sources/Runtime` で列挙。vararg 実体化が compiler intrinsic 依存なら該当分のみ (c) 残置理由をファイル削除見送りの根拠として記録
  - 手順: T
  - diff: `array_factory*.kt` 既存 + 各 `*ArrayOf()` 空/複数要素ケース、`ubyteArrayOf` ケース
  - 前提: KSP-657, KSP-1514, KSP-1515, KSP-1516

- [ ] KSP-1519: `sequence {}` / `SequenceScope` / `yield` / `yieldAll` / `iterator {}` builder を Kotlin 化し `HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift`（`registerSyntheticSequenceBuilderStub` / `registerSyntheticIteratorBuilderStub` / `registerSyntheticGenerateSequence*` / `registerSyntheticSystemMember` / `registerSyntheticIOTopLevelProperty` の残余）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceBuilder.kt` 新設（`system`/`IO` 残余は KSP-713 と調整し `kotlin/system` / `kotlin/io` へ）
  - 削除/降格 kk_*: 着手時 `rg -o '@_cdecl\("kk_(sequence_builder|yield|iterator_builder)[a-zA-Z0-9_]*"\)' Sources/Runtime`。restricted suspension（`SequenceScope`）が coroutine intrinsic を要するため、必要な残置は `__kk_` bridge として明記
  - 手順: T
  - diff: `sequence_builder*.kt` 既存 + `yieldAll(sequence)` の遅延評価順序ケース、`iterator {}` ケース
  - 前提: KSP-651, KSP-713, KSP-1518

- [ ] KSP-1520: `kotlin.Comparator` fun interface 宣言を Kotlin source 化し `HeaderHelpers+SyntheticComparatorStubs.swift` を削除する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticComparatorStubs.swift`（120行。KSP-309/KSP-461 後は interface 本体のみ残存）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/comparisons/Comparator.kt` 新設（`fun interface Comparator<T> { fun compare(a: T, b: T): Int }`）
  - 削除/降格 kk_*: 対象 `kk_*` なし（比較コアは `__kk_compare_with_comparator` を継続使用）
  - 手順: T
  - diff: `comparator_*.kt` 既存 + SAM 変換（ラムダから Comparator）と `Comparator` 明示実装クラスの両ケース
  - 前提: KSP-461。compiler-known anchor として Sema 初期化が先行参照している場合は (c) 残置と結論付け、根拠を `docs/stdlib-pipeline.md` §9 に記録して完了とする

- [ ] KSP-1523: `UIntRange` の property / membership / aggregate を Kotlin 化する
  - 対象スタブ: `Sources/CompilerCore/Sema/Models/MemberRuntimeDispatch.swift` の `kk_uint_range_*` 名前生成、`HeaderHelpers+SyntheticUnsignedRangeStubs.swift` の該当メンバ登録
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeMembership.kt` 追記（unsigned 版）
  - 削除/降格 kk_*: `kk_uint_range_contains`, `_isEmpty`, `_first`, `_last`, `_firstOrNull`, `_lastOrNull`, `_count`, `_sum`, `_average`, `_reversed`, `_sorted`, `_toList`, `_toUIntArray`（13件）
  - 手順: T
  - diff: `uint_range_*.kt` 既存 + 空 range（`5u..1u`）の `isEmpty`/`firstOrNull`/`sum`、`UInt.MAX_VALUE` 境界ケース
  - 前提: KSP-451, KSP-709

- [ ] KSP-1524: `ULongRange` の property / membership / aggregate を Kotlin 化する
  - 対象スタブ: `Sources/CompilerCore/Sema/Models/MemberRuntimeDispatch.swift` の `kk_ulong_range_*` 名前生成、`HeaderHelpers+SyntheticUnsignedRangeStubs.swift` の該当メンバ登録
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeMembership.kt` 追記（unsigned 版）
  - 削除/降格 kk_*: `kk_ulong_range_contains`, `_isEmpty`, `_first`, `_last`, `_firstOrNull`, `_lastOrNull`, `_count`, `_sum`, `_average`, `_reversed`, `_sorted`, `_toList`, `_toULongArray`（13件）
  - 手順: T
  - diff: `ulong_range_*.kt` 既存 + `ULong.MAX_VALUE` 境界と空 range ケース
  - 前提: KSP-1523

- [ ] KSP-1527: `ULongRange` の map / filter 系 HOF を Kotlin 化する
  - 対象スタブ: 同上（`kk_ulong_range_*`）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt` 追記
  - 削除/降格 kk_*: `kk_ulong_range_map`, `_mapIndexed`, `_mapNotNull`, `_filter`, `_filterIndexed`, `_filterNot`（6件）
  - 手順: T
  - diff: `ulong_range_hof*.kt` 既存 + `mapNotNull`/`filterNot` ケース
  - 前提: KSP-1524, KSP-1525

- [ ] KSP-1528: `ULongRange` の fold / reduce / forEach / 述語検索 HOF を Kotlin 化する
  - 対象スタブ: 同上（`kk_ulong_range_*`）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt` 追記
  - 削除/降格 kk_*: `kk_ulong_range_fold`, `_foldIndexed`, `_reduce`, `_reduceIndexed`, `_forEach`, `_any`, `_all`, `_none`, `_find`, `_findLast`, `_first_predicate`, `_firstOrNull_predicate`, `_last_predicate`, `_lastOrNull_predicate`（14件）
  - 手順: T
  - diff: `ulong_range_fold*.kt` 既存 + `reduce` 空 range 例外ケース
  - 前提: KSP-1526, KSP-1527

- [x] KSP-1529: `UIntRange` の iterator / step / 構築演算子 / windowing を Kotlin 化する
  - 対象スタブ: `Sources/CompilerCore/Sema/Models/MemberRuntimeDispatch.swift`（`__kk_uint_step` 等の分岐）+ unsigned range 登録
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeIterators.kt` / `ProgressionConstructors.kt` 追記（unsigned 版）
  - 削除/降格 kk_*: `kk_uint_range_iterator`, `_hasNext`, `_next`, `_step`, `_chunked`, `_windowed`, `_take`, `_drop`, および `kk_uint_step`, `kk_uint_downTo`, `kk_uint_rangeTo`（`kk_uint_progression_fromClosedRange` は KSP-456 で整理済みか着手時に確認）
  - 手順: T
  - diff: `uint_progression*.kt` 既存 + `step 3` の最終要素、`downTo` 逆順、`windowed(partialWindows = true)` ケース
  - 前提: KSP-456, KSP-1523

- [ ] KSP-1530: `ULongRange` の iterator / step / 構築演算子 / windowing を Kotlin 化する
  - 対象スタブ: 同上（`kk_ulong_*`）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeIterators.kt` / `ProgressionConstructors.kt` 追記
  - 削除/降格 kk_*: `kk_ulong_range_iterator`, `_hasNext`, `_next`, `_step`, `_chunked`, `_windowed`, `_take`, `_drop`, および `kk_ulong_step`, `kk_ulong_downTo`, `kk_ulong_rangeTo`
  - 手順: T
  - diff: `ulong_progression*.kt` 既存 + `ULong.MAX_VALUE` 近傍の `step` オーバーフロー非回帰ケース
  - 前提: KSP-1529

- [ ] KSP-1532: `UInt` の数値変換メンバ（`toByte`/`toChar`/`toDouble`/`toFloat`/`toInt`/`toLong`/`toShort`/`toUByte`/`toULong`/`toUShort`）を Kotlin 化する
  - 対象: KSP-1531 で (b) と判定した UInt 受け手1件（SyntheticCoercionStubs.swift には登録せず、primitive lowerer/Runtime/ABI 経路を監査）
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/Numbers.kt` 追記 or 新設 `kotlin/UnsignedConversions.kt`
  - 削除/降格 kk_*: `kk_uint_to_char`（(c) の9件は compiler intrinsic owner として残す）
  - 手順: T
  - diff: `unsigned_conversions*.kt` 既存 + `UInt.MAX_VALUE.toInt()`（ラップ）と `toDouble()` の丸めケース
  - 前提: KSP-1531

- [ ] KSP-1533: `ULong` の数値変換メンバを Kotlin 化する
  - 対象: KSP-1531 で (b) と判定した ULong 受け手1件（SyntheticCoercionStubs.swift には登録せず、primitive lowerer/Runtime/ABI 経路を監査）
  - 実装先: KSP-1532 と同じ実装先ファイル
  - 削除/降格 kk_*: `kk_ulong_to_char`（`kk_ulong_to_uint`/`kk_ulong_to_long` は現行シンボルなし、representation-preserving copy。 (c) の7件は compiler intrinsic owner として残す）
  - 手順: T
  - diff: `unsigned_conversions*.kt` + `ULong.MAX_VALUE.toDouble()` の精度、`toInt()` の切り詰めケース
  - 前提: KSP-1531, KSP-1532

- [ ] KSP-1534: `UByte` の数値変換メンバを Kotlin 化する
  - 対象: KSP-1531 で (b) と判定した UByte 受け手1件（SyntheticCoercionStubs.swift には登録せず、primitive lowerer/Runtime/ABI 経路を監査）
  - 実装先: KSP-1532 と同じ実装先ファイル
  - 削除/降格 kk_*: `kk_ubyte_to_char`（(c) の9件は compiler intrinsic owner として残す）
  - 手順: T
  - diff: `unsigned_conversions*.kt` + `UByte(200).toByte()` 符号反転ケース
  - 前提: KSP-1531, KSP-1532

- [ ] KSP-1535: `UShort` の数値変換メンバを Kotlin 化する
  - 対象: KSP-1531 で (b) と判定した UShort 受け手1件（SyntheticCoercionStubs.swift には登録せず、primitive lowerer/Runtime/ABI 経路を監査）
  - 実装先: KSP-1532 と同じ実装先ファイル
  - 削除/降格 kk_*: `kk_ushort_to_char`（(c) の9件は compiler intrinsic owner として残す）
  - 手順: T
  - diff: `unsigned_conversions*.kt` + `UShort` 境界値ケース
  - 前提: KSP-1531, KSP-1532

- [ ] KSP-1542: `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` の Collection/MutableCollection/Iterable 型シェルとメンバ登録を整理する
  - 対象スタブ: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticCollectionTypeFallbacks.swift`（845行。KSP-701/KSP-665 の分離先で、呼び出し元は `HeaderHelpers+SyntheticCollectionResiduals.swift`（KSP-700 対象）の `registerSyntheticCollectionStubs` のみ）。対象は `registerSyntheticCollectionStub`/`registerSyntheticMutableCollectionStub`/`registerSyntheticIterableStub`（`Collection`/`MutableCollection`/`Iterable`/`Iterator`/`MutableIterator` 型シェルと `isEmpty`/`contains`/`random`/`randomOrNull`/`add`/`addAll`/`clear`/`remove`/`removeAll`/`retainAll`/`iterator`/`hasNext`/`next` メンバ）。`registerSyntheticAbstractCollectionStub`/`registerSyntheticAbstractMutableCollectionStub`/`registerSyntheticMutableIterableStub`（`AbstractCollection`/`AbstractMutableCollection`/`MutableIterable`）は既に bundled Kotlin source を再利用する fallback 専用のため対象外——`MutableIterable.iterator()` の covariant override も `MutableIterable.kt` のコメント通り BUG-200（library metadata が再型付けを表現できない）で compiler 残置と既に結論済みのため同様に対象外
  - 実装先: KSP-700 が新設する `Sources/CompilerCore/Stdlib/kotlin/collections/Collection.kt`/`MutableCollection.kt`/`Iterable.kt`（`Iterator`/`MutableIterator` の source 化が KSP-700 のスコープに含まれるかは着手時に確認）。型宣言が揃った後、この shell を `AbstractCollection` と同型の「既存シンボル再利用」パターンへ揃え、KSP-700 側との重複登録を除去する
  - 削除/降格 kk_*: 対象 public `kk_*` なし。`__kk_collection_*`/`__kk_mutable_collection_*`（`isEmpty`/`add`/`addAll`/`clear`/`remove`/`removeAll`/`retainAll`）・`kk_iterator_hasNext`/`kk_iterator_next`/`kk_range_iterator`・`kk_op_contains` は、List/Set/Iterator の runtime box が itable に自己登録しないため virtual dispatch を bypass する目的で必須（`Collections.kt` の KSP-435 コメント、本ファイル内 BUG-166 コメント参照）——KSP-700 後も (c) 残置が濃厚。`kk_list_random`/`kk_list_randomOrNull` は **KSP-1509 が `__kk_random_*` へ降格予定の同一ブリッジ**につき削除対象に含めない。着手時に KSP-1509 の進捗を確認し、先に完了していれば `externalLinkName` 参照が dangling にならないよう追従修正する
  - 手順: T。itable dispatch 制約により (b) 化不能と判明した分は KSP-1520 と同様「(c) 残置と結論付け、根拠を `docs/stdlib-pipeline.md` §9 に記録して完了とする」
  - diff: `collection_*.kt`, `iterable_*.kt`, `mutable_collection_*.kt` 既存拡張
  - 前提: KSP-700, KSP-701（着手時に KSP-1509 の削除対象ブリッジと突合）

### CLEANUP-STUB 追補（(a) 削除。2026-07-10 監査。採番は履歴最終 095 の続き。手順は RF-STUB-002 レシピ）

> 「本家で deprecated/obsolete かつ KSwiftK でも未実装」の二重死と fiction。**W6 の移行より先に実施を推奨**（移行対象面積が減る）。

- [ ] CLEANUP-STUB-107: `HeaderHelpers+SyntheticFileIOStubs.swift` を削除する
  - 対象ファイル: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticFileIOStubs.swift`（2319行）
  - 削除内容: `registerSyntheticFileIOStubs(...)` および `java.io.File` クラス・コンストラクタ・`readText`/`writeText`/`readLines`/`appendText`/`forEachLine`/`bufferedReader`/`delete`/`mkdirs`/`listFiles`/`walk`/`name`/`path`/`exists`/`isFile`/`isDirectory` 等の登録を削除
  - 呼び出し元: `HeaderHelpers.swift:1241`、`HeaderHelpers+SyntheticBucketedStubRegistry.swift:201`（`name: "FileIO"`）、`HeaderHelpers+SyntheticFileTreeWalkStubs.swift` 内のコメント参照を整理
  - 連動整理: bundled `Stdlib/kotlin/io/FileIO.kt`（および `FileStreamExtensions.kt`/`FileTraversal.kt`）の出番確認、Runtime `Sources/Runtime/RuntimeFileIO.swift`（`kk_file_*`/`kk_files_*` 等）、`Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`
  - テスト影響: `Tests/CompilerCoreTests/GoldenCases/Sema/file_*.golden`・`file_tree_walk.golden`、`Tests/CompilerBackendTests/Codegen/*File*` テスト群、`Tests/RuntimeTests/RuntimeFileTreeWalkTests.swift`、`Scripts/diff_cases/file_*.kt` 等の整理
- [ ] CLEANUP-STUB-115: `HeaderHelpers+SyntheticPathStubs.swift`（本体）を削除する
  - 対象ファイル: `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`（2102行）
  - 削除内容: `registerSyntheticPathStubs(...)` および `kotlin.io.path.Path` クラス・companion `createTempFile`/`createTempDirectory`/`list`/`walk`/`readBytes`/`readText`/`writeText`/`writeBytes`/`copyTo`/`resolve`/`parent`/`fileName`/`extension` 等の登録を削除
  - 呼び出し元: `HeaderHelpers.swift:1247`、`HeaderHelpers+SyntheticBucketedStubRegistry.swift:219`（`name: "Path"`）を削除
  - 連動整理: 3つの split ファイル（CLEANUP-STUB-116〜118）も併せて削除；Runtime `Sources/Runtime/RuntimePath.swift`（`kk_path_*` 273件、`kk_uri_*`/`kk_url_*` も含む）、`Sources/RuntimeABI/RuntimeABISpec+Path.swift`（114件）
  - テスト影響: `Tests/CompilerCoreTests/Sema/Path*FunctionTests.swift`（5ファイル）、`PathWalkOptionEnumTests.swift`、`Tests/CompilerBackendTests/Codegen/CodegenBackendIntegrationTests+PathCreateSymbolicLink.swift`、`Scripts/diff_cases/path_basic.kt`、Golden 該当ケースの整理
### バグバックログ（BUG-NNN。既存・未修正バグの追跡。PR 状態は各タスクの記載時点）

> このセクションは既存の未修正バグと、同じPR内で安全に修正できなかったバグの追跡用。新たに発見した修正可能なバグは、最小再現と回帰テストを含めて発見したPR内で修正し、報告だけのためにここへ追加しない。

- [~] BUG-215: object 式（匿名クラス）で**クラス**を継承すると、(1) 基底クラスの `open`/`abstract` メンバへの override が dispatch されず基底実装（`abstract` の場合は `null`）が使われ、(2) スーパークラス実引数付き `object : Base(x) {}` は実行時 `KSwiftK panic [KSWIFTK-RUNTIME-0001]: kk_array_get_inbounds precondition failed` でクラッシュする。interface を実装する object 式のプロパティ dispatch は BUG-141 で修正済みで、本件はクラス継承経路。最小再現: `open class Base { open fun describe(): String = "base" }` `fun make(): Base = object : Base() { override fun describe(): String = "anon" }` `fun main() { println(make().describe()) }` が `"base"`（kotlinc は `"anon"`）。(2) は `open class Base2(val v: Int)` `fun make2(x: Int): Base2 = object : Base2(x) {}` でクラッシュ。名前付きサブクラスのスーパークラス primary constructor 実引数伝搬は PR #5506（`1128468186`）で別途修正済みだが、object 式はこのクラッシュが残る点が異なる。発見元: 2026-08-06 に KSP-491 の着手前プローブで一度 `BUG-188` として台帳登録されたが、後続の TODO.md 統合編集で記録が失われていた。2026-08-18 `.build/debug/kswiftc` で再実機確認し、症状に変化なし（両方とも pre-existing）。台帳は KSP-CAP-018。**部分修正（2026-08-18、KSP-CAP-018）**: override メンバを1つ以上持つ object 式については (1)(2) とも解消（詳細・回帰は KSP-CAP-018 参照）。メンバ宣言を持たない空ボディの object 式（(2) の最小再現そのもの）は別経路のため未解消のまま残存。**採番注記**: master 側が独立に別内容（Platform.memoryModel の KIR 欠落）で `BUG-212` を先に登録していたためマージ時に `BUG-215` へ採番し直した（このセッション自身が KSP-681 調査時に発見した「TODO.md の BUG/CAP 番号衝突」の再発例）

- [ ] BUG-213: bundled stdlib のコレクション flow 型推論に無限/極端に深い再帰サイクルがあり、単独プロセスの薄いスタックだと `Thread stack size exceeded`（SIGBUS, EXC_BAD_ACCESS）でクラッシュする。症状: `fun noop() {}` のような1行ファイルを既定の `includeStdlib: true`（bundled source injection）で `runSema` するだけの最小テストを `swift_test.sh --filter` で単独実行すると、macOS のクラッシュレポート（`~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-*.ips`）に `"message": "Thread stack size exceeded"` が記録される。シンボリケートしたスタックは `TypeCheckDriver.inferExpr → ExprTypeChecker.inferLambdaLiteralExpr → ExprTypeChecker.inferExpr → CallTypeChecker.tryBuiltinFlowMemberCall → CallTypeChecker.tryInferMemberCallCollectionFlowSpecials → CallTypeChecker.inferMemberCallImpl → CallTypeChecker.inferMemberCallExpr → ExprTypeChecker.inferExpr → CallTypeChecker.inferCallExpr → ExprTypeChecker.inferExpr → ...` という同一9フレームの並びが数十回繰り返されるサイクルで、ユーザーコードではなく bundled stdlib 自身の関数本体（コレクション HOF チェーンを持つもの）を型検査中に発生している。**pre-existing（回帰ではない）を実証済み**: `git worktree add` で分岐元 `9b2b615107`（KSP-706 着手前の master 相当）へ切り替え、同型の最小テスト（`makeCompilationContext(inputs:[path])` + `runSema`、`includeStdlib` 既定値のまま）を単独 `--filter` 実行したところ、同一の `"Thread stack size exceeded"` クラッシュが再現した。発見元: KSP-706 の回帰テスト（`PairTripleNominalAnchorTests.testBundledSourcePairKeepsNilDeclSiteForGoldenStability`）を単独 `--filter` で実行した際に発覚。フル `swift_test.sh`（`--filter` 無し、または広い `--filter`）ではこれまで気づかれていなかったと見られ、狭い `--filter` で単一の bundled-stdlib フル Sema テストがプロセス内最初の（かつ唯一の）重い処理として実行される場合に限って再現しやすい可能性がある（プロセス起動直後のスレッドスタックサイズが影響していると推測）。今回修正しない理由: `CallTypeChecker` のコレクション flow 型推論（`tryBuiltinFlowMemberCall`/`tryInferMemberCallCollectionFlowSpecials` 周辺）の再帰構造の踏み込んだ調査が必要で、KSP-706（Sema header 収集順序のみの変更）のスコープを大きく超える

- [ ] BUG-221: class の `+`/文字列テンプレートによる Any 消去境界の文字列化 funnel（`CallLowerer.emitAnyToStringWithNullGuard` の `classToStringCallee` 分岐、BUG-204 の enum 専用対応を class にも拡張する形で本 PR にて新設）は、値の**静的型そのもの**が `toString()`（source 宣言・data class 等の合成いずれも可）を持っている場合に限って正しく override を呼ぶ。以下の2パターンは対象外のまま `kk_any_to_string` の汎用フォールバックへ落ち、`<object 0x...>` を出力する: (1) 自身では `toString()` を再宣言せず基底クラスの override をそのまま継承するサブクラスを、そのサブクラス自身の静的型で参照した場合 — `classToStringCallee` の `lookupAll(fqName:)` が厳密な fqName 一致（継承チェーンを辿らない）であるため。最小再現: `open class Base { override fun toString() = "Base!" }` `class Derived : Base()` `fun main() { val d: Derived = Derived(); println("d=" + d) }`（`val d: Base = Derived()` のように**基底クラス型**の変数で保持すれば `Base.toString` がその場で直接見つかり、かつ `Derived` インスタンスへの virtual dispatch も正しく効く — 本 PR で修正・回帰テスト済み。sealed class のサブクラスをその抽象基底型で保持する場合も同様）。(2) 静的型が `Any` の値 — 消去がこの funnel に到達する前に完了しているため `classToStringCallee` は class 型自体を観測できない。最小再現: `class Foo(val x: Int) { override fun toString() = "Foo($x)" }` `fun main() { val a: Any = Foo(1); println("a=" + a) }`。発見元: KSP-1502（`kotlin.uuid.Uuid.Companion` 実装）の副次調査で報告された「`+` 演算子が class の `toString()` override を呼ばず `<object 0x...>` を出力する」バグ（本 PR で修正、`classToStringCallee`/`emitAnyToStringWithNullGuard` の class 分岐と `ConsolePrintLoweringPass` の virtual dispatch 対応を追加）の検証中に、修正後もなお残る境界ケースとして発見。data class（`toString()` が `DataEnumSealedSynthesisPass` で合成される点で source 宣言と異なる）は当初「BuildKIR 時点でシンボルが存在しない」ため対象外と誤って想定していたが、`ConsolePrintLoweringPass`（`println`/`print`）が同じ `lookupAll` で既に data class の合成 `toString()` を解決できていた事実から、Sema がヘッダ収集時点でシグネチャを先行登録していると判明。`classToStringCallee` の synthetic 判定を「`kotlin.Any.toString` フォールバックのみ除外」という `ConsolePrintLoweringPass.isSyntheticAnyToString` と同じ基準に緩めることで data class・sealed data class とも本 PR で正しく解決できるようになった（nullable の null/非null 双方含め検証済み）。回帰テストは `Tests/CompilerCoreTests/Lowering/LoweringPassRegressionTests+ClassStringConversion.swift`（`testDataClassInterpolationCallsSynthesizedToString` 含む）・`Tests/CompilerBackendTests/Integration/BundledStdlibExecutionTests+ClassToStringOverride.swift`・`Scripts/diff_cases/class_tostring_concat_interpolation.kt`（(1)(2) は意図的に除外し、ヘッダコメントに残存ギャップとして明記）。今回修正しない理由: (1) は `lookupAll` を継承チェーンを辿る解決に置き換える設計変更が必要、(2) はこの funnel が静的型ベースの書き換えである以上原理的に解決できず、値ごとに実行時型を運ぶ真の仮想 `Any.toString()` ディスパッチ機構が別途必要になる。いずれも「Any 消去境界での class toString() 未呼び出し」バグ修正のスコープを大きく超える

- [ ] BUG-222: `object` シングルトンの `toString()` 処理に、レイヤの異なる2つの不具合がある（実 kotlinc 2.3.10 と実機照合済み）。(1) `println`/`print`（`ConsolePrintLoweringPass.classToStringExpression`）は `object` レシーバに対し常に単純名（`classSymbol.name`）を出力する分岐を toString シンボル解決より先に取っており、その object が `toString()` を override していても無視する。最小再現: `object Singleton { override fun toString(): String = "I am Singleton" }` `fun main() { println(Singleton) }` は kotlinc 実測 `"I am Singleton"` に対し本コンパイラは `"Singleton"` を出力する（`Singleton.toString()` の直接呼び出しは正しく `"I am Singleton"` を返す）。override を持たない object（例: `object Plain`）を単純名で出力すること自体はコード中のコメント（「Regular and data objects print their simple name」）からみて意図的な簡略化と見られ（kotlinc 実測では `Plain@<identityHash>` になる非決定値のため、素朴な simple-name 表示は再現性重視の妥当な代替とも解釈できる）バグとして扱わないが、override が実在する場合にまで単純名へ差し替えるのは override 自体の無視であり明確な不具合。(2) `object` シングルトンが `Any` 消去境界を越えると（`+`/文字列テンプレート、`Any` 型変数への代入のいずれでも）、override の有無によらず文字列化結果が無関係な値になる（実機観測では常に `"0"`）。最小再現: `object Plain; fun main() { val a: Any = Plain; println(a) }`（kotlinc 実測 `Plain@<identityHash>` に対し本コンパイラは `0`）。override の無い object でも同様に再現するため BUG-217 の各ケースとも (1) とも別レイヤの問題で、object シングルトンの実体表現が `runtimeElementToString`/`kk_any_to_string`（`Sources/Runtime/RuntimeCollectionHelpers.swift`/`RuntimeNumericCompat.swift`）が前提とする「GC 管理ヒープポインタで `objectPointers` レジストリに登録済み」という形を取っていない、または当該レジストリに登録されていない可能性が高い（未検証の仮説）。発見元: KSP-1502 の副次調査（class の `+`/文字列テンプレートでの `toString()` 未呼び出しバグ、本 PR で修正）の検証中、修正が `object` レシーバを意図的に対象外（`classToStringCallee` は `classSymbol.kind == .class` のみを対象とする）としたため、隣接ケースとして object を試して発見。今回調査・修正しない理由: (1) は `ConsolePrintLoweringPass` の object 分岐の設計意図の再検討と、override 存在チェックを単純名分岐より前に持ってくる改修が必要、(2) は object シングルトンの runtime 表現そのものの調査が必要で、いずれも「class の `+`/文字列テンプレートでの toString() 未呼び出し」バグ修正のスコープを大きく超える

- [ ] BUG-231: `Long`/`Double`/`ULong` の一部の値（`Long.MIN_VALUE`、`Double` の `-0.0`、`ULong` の `2^63`）を**static型のまま**（`Any` に消去せず unboxed のまま）扱う `kk_any_hashCode`（`Sources/Runtime/RuntimeNumericCompat.swift`）は、raw な64bit slot値がランタイムの null sentinel（`runtimeNullSentinelInt == Int.min == 0x8000000000000000`）と bit パターンで完全一致するため、実際には非nullの値であるにもかかわらず null として誤認識され `0` を返す。最小再現: `fun main() { println(Long.MIN_VALUE.hashCode()) }`（kotlinc実測 `-2147483648` に対し本コンパイラは `0`。同様に `(-0.0).hashCode()` と `9223372036854775808UL.hashCode()`（`2^63`）も `0` を返す）。`Any` に消去した場合（`val a: Any = Long.MIN_VALUE; a.hashCode()`）はこの3値を含め正しく動作する（BUG-230 の回帰テスト `testBoxedLongHashCode`/`testBoxedDoubleHashCode` で確認済み）— `Any` 消去境界では非Int/Bool/Char系プリミティブが常にボックス化され、boxed 値は heap ポインタとして表現されるため raw 値との衝突が原理的に起きない。既存の設計コメント（`kk_any_to_string` 冒頭）にある「nullable な `Float?`/`Double?`/`ULong?` は sentinel と衝突しうる値を持つ場合常にボックス化する」という対策は、これら3型の **nullable** 型にのみ適用されており、**non-nullable** な static型の値、および `Long` 型自体には同等の対策が及んでいない。発見元: BUG-230（数値プリミティブ hashCode 修正）の実測検証中、null sentinel との衝突を疑って `Long.MIN_VALUE`/`-0.0`/`2^63` を明示的に確認し発覚。今回修正しない理由: 対策には「non-nullable な `Long`/`Double`/`ULong` を `Any`-fallback 経路に渡す際は常にボックス化する」という boxing policy 自体の変更が必要で、性能・全呼び出し箇所への影響範囲の調査を要し、BUG-230（hashCode の計算式そのものの誤り）のスコープを大きく超える。

- [ ] BUG-232: data class のプロパティが `Long`/`Float`/`Double`/`ULong` 型の場合、その data class の `.hashCode()` は静的型呼び出し・`Any` 消去呼び出しのいずれでも各フィールドの値が正しくハッシュ化されない（BUG-230 の数値プリミティブ本体の修正はこの経路には及ばない）。原因は2つの独立した経路それぞれに存在する: (1) 直接呼び出し（コンパイラ合成の `hashCode()`、`appendSyntheticDataClassHashCodeIfNeeded`、`Sources/CompilerCore/Lowering/DataEnumSealedSynthesisPass+DataClassMethods.swift`）は各フィールドの `kk_any_hashCode` 呼び出しに渡す tag を独自に計算しており（`Boolean` は2、それ以外は全て1）、BUG-230 で `computeAnyFallbackTag` に追加した `Float`/`Double`/`ULong`/`Long` 用のタグ（5/6/7/8）を一切使わない。(2) `Any` 消去呼び出し（`runtimeAnyHashCode` の `RuntimeObjectBox` 分岐、`Sources/Runtime/RuntimeNumericCompat.swift`）は各フィールドを tag 0 で `kk_any_hashCode` に渡す点は(1)と同根の問題を抱える上、初期シードに実フィールドの hashCode ではなく `classID` を使っており、コンパイラ合成版（Kotlin準拠、先頭フィールドの hashCode をシードにする）とは異なる独立した誤ったフォーミュラになっている。さらにこのフォールド自体も、BUG-230 (2) で `List`/`Set`/`Map` に見つけたのと同じ「64bit `Int` で累積し32bitへの切り詰めがない」欠陥を抱えている（フィールド数が増えれば追加でさらに乖離する）。最小再現: `data class LongHolder(val x: Long); fun main() { val h = LongHolder(1L shl 40); println(h.hashCode()); val a: Any = h; println(a.hashCode()) }`（kotlinc実測は直接呼び出し・`Any`消去のいずれも同じ値 `256`（`Any.hashCode()` は同一メソッドへの仮想ディスパッチのため）に対し、本コンパイラは直接呼び出しが `1099511627776`（raw passthrough）、`Any`消去が `133621479305153003`（誤ったシード+raw passthroughの合成）と、期待値とも互いにも一致しない3つの異なる値になる）。発見元: BUG-230 の verify 中、`RuntimeObjectBox` 分岐の既存の "KNOWN LIMITATION" コメント（Boolean フィールドの tag 欠落について記載）を読み、同種の欠落が Long/Float/Double/ULong にも及んでいないか確認して発覚。今回修正しない理由: (1) は `DataEnumSealedSynthesisPass+DataClassMethods.swift` 側のタグ計算を `computeAnyFallbackTag` と統一する変更、(2) は `RuntimeObjectBox` 分岐のシード式・フォールド式自体をコンパイラ合成版と一致させる設計変更が必要で、いずれも「数値プリミティブ本体の hashCode 計算式の誤り」という BUG-230 のスコープを大きく超える別レイヤの問題。

- [ ] BUG-234: `getOrPut` で**既存エントリを読み戻す**と、`Double` 値だけが壊れた値になる。最小再現: `fun main() { println(mutableMapOf("k" to 2.5).getOrPut("k") { 9.5 }) }`（kotlinc 実測 `2.5` に対し本コンパイラは `2.144764178E-314` のようなポインタ由来の非正規化数）。実測した範囲: `Float` / `Char` / `Boolean` / `Int` / `Long` / `String` は正しい。map の作り方（`mapOf` / `to` 由来か `map[k] = v` 由来か）とローカルの型注釈の有無には依存しない。結果を `Double` として消費する経路（直接 `println(...)`、`val v: Double = ...` への代入）で症状が出る一方、文字列連結（`"" + m.getOrPut(...)`）は Any 消去経路を通るため正しく出力される。根本原因: bundled inline `kotlin.collections.getOrPut` は `return value`（`this[key]` の結果）と `return answer`（ラムダ結果）の**2つの return 地点**を持ち、`.kklib` 経由の展開では前者が boxed handle、後者が unboxed raw Double のまま同一のマージレジスタへ `copy` される。`InlineLoweringPass.unboxErasedInlineResultIfNeeded`（`Sources/CompilerCore/Lowering/InlineLoweringPass.swift:957`）は展開末尾の `expansion.returnedExpr` 1点だけを正規化し、そのガードはマージレジスタの型（compute 分岐由来の `Double`）を見て「既に raw」と判断するため、early-return 分岐の boxed handle は未変換のまま残る。呼び出し側はマージレジスタを raw Double とみなして `kk_box_double_nonnull` するので、boxed handle のビット列がそのまま double として出力される。今回修正しない理由: 展開内の各 return 地点で表現を揃える必要があり、`InlineLoweringPass` の return マージ構造そのものの変更になる。BUG-233（ABI-002）の boxing 修正スコープを超える。注意: BUG-233 修正前は `map[k] = v` で格納した値も raw だったため、その組み合わせに限っては「格納も読み出しも raw」で偶然正しく出力されていた。`mapOf` / `to` で構築した map では修正前から同じ症状が出るため、欠陥自体は BUG-233 とは独立に以前から存在する。

- [ ] BUG-235: `Collection<T>` 型レシーバに対する `first()` / `last()` が解決されず、リンク時に `Undefined symbols: _first` で失敗する。最小再現: `fun main() { val m = mutableMapOf("k" to 1); println(m.values.first()) }`。`List<T>` レシーバでは解決されるため、`map.values` のように静的型が `Collection<T>` になる経路だけが落ちる。根本原因: `Sources/CompilerCore/Sema/TypeCheck/CallTypeChecker+CollectionMemberFallback.swift:1197` の `collectionMembers` は `firstOrNull` / `lastOrNull` / `single` / `singleOrNull` / `elementAt` を列挙する一方で `first` / `last` を欠いており、source-backed 拡張へのフォールバックに入らない（`Collection` / `Set.joinToString` の非対称ガードと同型の欠落）。今回修正しない理由: 本 PR が触る KIR / ABI lowering とは別サブシステム（Sema のコレクションメンバフォールバック）であり、`collectionMembers` への追加は overload 解決の影響範囲を全 diff / Golden で再検証する必要がある。本 PR は BUG-233 の ABI-002 修正の検証を回しており、同一 PR に混ぜると原因の切り分けができなくなる。

- [ ] BUG-228: `super.p`（`super` 修飾でのプロパティ読み取り）が、静的に宣言された基底クラスの実装ではなく、レシーバの属するクラス自身の最も派生した override を観測する。メソッドの `super.f()` は正しく基底の実装を呼ぶため、プロパティだけ非対称に壊れている。最小再現: `open class Base { open val p = "bp" } ` `class Derived : Base() { override val p = "dp"; fun viaSuper() = super.p } ` `fun main() { println(Derived().viaSuper()) }` は kotlinc であれば `super.p` が Base 自身の実装（`bp`）を返すはずだが、本コンパイラは `dp`（Derived 自身の override）を返す。原因（未確定、要追加調査）: `super`（bare の superRef 式）自体の型は `ExprTypeChecker+NameLambdaAndCallableRefInference.swift` の `resolveUnqualifiedSuper` によって正しく直接基底クラス型に束縛されることを確認済みだが（`sema.bindings.exprTypes[superRefExprID]` が Base 型になる）、続く `.p` のメンバー名解決がこの型情報を使わず、レシーバの実行時クラス（`super` を書いた側のクラス自身）のスコープから素朴に名前 `p` を解決しているように見える（この場合は Derived 自身の宣言を発見してしまう）。関数呼び出しには `sema.bindings.isSuperCallExpr(exprID)`/`markSuperCall`（`CallTypeChecker+MemberCallInferenceRegularResolution.swift`）という専用の super 検出・処理経路が存在するが、プロパティ（非呼び出し）の名前解決には同等の仕組みが一切ない（`grep -rn "isSuperCallExpr\|markSuperCall"` は呼び出し系ファイルのみに出現）。どの汎用メンバー名解決関数がこの問題を引き起こしているかは未特定（`.superRef` を受け取る側の一般的な「レシーバの型 T からメンバー名 X を解決する」ロジックの特定に、BUG-227 のスコープ外の追加調査が必要）。発見元: BUG-227（プロパティの vtable 仮想ディスパッチ欠落）の回帰テスト作成中、「`super.p` を仮想化してしまうと今回の修正が既存の（静的だが無害な）バグを動的に間違った値を返すバグへ悪化させる」というリスクを検証する過程で発見。BUG-227 の修正では、レシーバ式が `.superRef` の場合は無条件に仮想ディスパッチを除外するガードを追加することで、本バグを悪化させないことのみ確認済み（`super.p` の出力値自体は修正前後で `dp` のまま不変）。今回修正しない理由: 根本原因である汎用メンバー名解決ロジックの特定自体に別調査が必要で、BUG-227（vtable 仮想ディスパッチの欠落）とは異なるレイヤ（Sema の名前解決）の別バグであり、スコープを大きく超える。

- [ ] BUG-229: 一次コンストラクタのパラメータプロパティ（`class Foo(open val p: String)` のような primary constructor 上の `val`/`var`）に `open` 修飾子を付けても、override 可能として認識されない。最小再現: `open class Base(open val p: String)` `class Derived(p: String) : Base(p) { override val p: String = p + "!" }` は kotlinc であれば正しくコンパイルされるはずだが、本コンパイラは `override val p` の宣言位置で `KSWIFTK-SEMA-FINAL: 'p' in 'Base' is final and cannot be overridden.` を報告する（クラス本体で `open val p: String = ...` と書いた場合は問題なく override できるため、one 次コンストラクタパラメータだけの非対称なギャップ）。原因: `Sources/CompilerCore/Sema/DataFlow/OpenFinalOverride.swift` の open/override 検証（`validateMemberOverrides`/`extractMemberMeta`）は `classDecl.memberFunctions`/`classDecl.memberProperties`（クラス本体の宣言）のみを走査し、`classDecl.primaryConstructorParams`（一次コンストラクタのパラメータプロパティ）を一切対象にしていない。そのため主コンストラクタの `val`/`var` パラメータに `open` を書いても対応する `SymbolFlags.openType` が設定されず、`isMemberOverridable` の判定（`sym.flags.contains(.openType) || ...`）で常に false となり「final」と誤診断される。発見元: BUG-227 の回帰テスト設計時に advisor の提案した追加ケース（primary constructor property override — vtable スロットへの登録漏れによる実行時 null 呼び出しリスクの確認目的）を試したところ、vtable の話に到達する前の Sema 検証で既に拒否されることが判明。今回修正しない理由: `OpenFinalOverride.swift` の modifier 抽出ロジックにコンストラクタパラメータ用の経路を新設する必要があり（`ConstructorParam` 自身の `open`/`override`/`abstract`/`final` 修飾子を読み、`classDecl.memberProperties` と同様に `validateMemberOverrides` へ合流させる改修）、かつプロパティ本体の symbol 登録側（`HeaderCollection.swift` 等）で primary constructor property に対して `.openType`/`.overrideMember` フラグが正しく設定される経路も別途確認・追加する必要がある。BUG-227（vtable 仮想ディスパッチの欠落）とは全く異なるレイヤ（Sema の修飾子検証、override 可否判定に到達する前段）の別バグであり、スコープを大きく超える。

---

## テストパイプライン集約タスク（Sema API tests migration）

`Tests/CompilerCoreTests` 内の重複した `runSema` / `runToKIR` / `runToLowering` / `runFrontend` / `makeSema` 呼び出しを 1 つの共有コンテキスト（`withTemporaryFiles` / `sharedCtx` / `sharedSema`）に集約し、テスト実行コストと行数を削減する。

> 現状（`origin/master`、Batch 82 マージ後、2026-08-03 時点）:
> - `runSema(`: 652
> - `runToKIR(`: 328
> - `runToLowering(`: 37
> - `runFrontend(`: 70
> - `makeSema(`: 129
>
> 目標: 同一ファイル / 同一スイート内で同じ入力を使う箇所を 1 回の pipeline 呼び出しにまとめ、上記カウントを再び半減させる。
> 進行中 PR: #5765 (Batch 83)。未 PR の作業ブランチ: `devin/consolidate-sema-api-tests-batch84` (Batch 84)。

- [ ] REFACT-TEST-002: 各テストで `makeSema()` を作り直している surface-inventory 系 Sema スイートに `sharedSema()` キャッシュを導入
  - 対象例: `IntegerNarrowingPassTests.swift` (8), `EnumAPISurfaceInventoryTests.swift` (8), `ExceptionSyntheticStubTests.swift` (4), `GenericInterfaceInheritanceTests.swift` (4), `ReflectKMutablePropertySyntheticTests.swift` (4), `ReflectKProperty2SyntheticTests.swift` (4), `ThrowableMemberSourceTests.swift` (4), `ReflectK*` 系・`NativeCInteropBetaInteropApiTests` など (2-3 件×多数)
- [~] REFACT-TEST-003: 同一入力で複数 `runToKIR(ctx)` を呼んでいる KIR テストを共有 `runToKIR(ctx)` に集約（必須ゲート未完了のため完了保留）
  - 独立した fixture 群を package／関数名で分離し、Regex、NativePlatform bridge（`Platform.memoryModel` は synthetic object-property state のため単独 context）、BuildKIR、BlockExpression、BuildAST body parsing、FileRewrite、Property Delegation を raw／lowered の共有 `CompilationContext` に集約した。既存のテスト名と対象 fixture の assertion は維持している。
  - `KotlinIOCommonEdgeCaseTests.swift` と `BuildKIRRegressionTests+ExpressionAndAdvancedScenarios+ControlFlowTryAndObjectLiteral.swift` は既に共有化済みのため変更しない。
  - `.kklib`、`searchPaths`、manifest 診断、import 解決など外部ライブラリ状態がケースごとに異なる `LibMetadataImportIntegrationTests.swift`、`LibraryMetadataManifestValidationTests.swift` および関連 import テストは、誤った診断混入を避けるため個別コンテキストのまま維持した。
  - `BuildKIRRegressionTests+NativePlatform.swift` の `Platform.memoryModel` は、他の Native bridge fixture と同一 context にまとめると runtime call が KIR から消えるため、元の単独 context を維持し、残りの NativePlatform fixture 群のみ共有した。この未修正コンパイラ不具合は BUG-212 として記録した。
  - 手動 `runSema`／`BuildKIRPhase` 検証、ABI／synthetic KIR の直接検証、benchmark 用 fixture、および before/after の LoweringPhase 順序を意図的に検証する単独ケースは対象外として棚卸し済み。
  - focused テストは確認済みだが、`bash Scripts/swift_test.sh`、`--filter Golden`、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases` の必須ゲートは未完了／未確認のため、全ゲート green 後に完了へ更新する。
- [ ] REFACT-TEST-005: 集約後に不要になった per-test pipeline ヘルパー・重複 `source` 文字列・個別 `withTemporaryFile` ブロックを削除し、migration スクリプト群を整理

---

## Golden fixture の単一目的化（RF-FIXTURE: 2026-09-06 調査）

### 現状と対象の選定

- 調査基準: `f637b7bdf77ce29a26ca00a782b34c5927df6d17`。`Tests/CompilerCoreTests/GoldenCases/Sema/` は入力 `.kt` / 期待値 `.golden` が各579件。履歴は同コミットの first-parent、2026-08-07 00:00〜2026-09-06 00:00（+09:00）の30日間で集計し、golden 517パス・延べ1,140回の変更を確認した。
- 再集計用: `git log f637b7bdf77ce29a26ca00a782b34c5927df6d17 --first-parent --since=2026-08-07T00:00:00+09:00 --until=2026-09-06T00:00:00+09:00 --format= --name-only -- 'Tests/CompilerCoreTests/GoldenCases/Sema/*.golden'` の非空行をパス別に数える。以下の「変更回数」はこの期間の golden 変更コミット数であり、当初報告の「調査範囲内11回」と集計範囲・方法を揃えた比較ではない。一括再生成・ハーネス変更も含むため、すべてを fixture の多責務化に起因すると断定しない。
- 候補抽出: **golden 変更7回以上、入力2,000 bytes以上、golden 15,000 bytes以上**のいずれかに該当する23件に、同型の `hashset_alias.kt` / `linkedhashset_alias.kt` を加えた25件を内容確認。3件を下記理由で除外し、22件をファイル単位で起票した。全579入力の詳細監査完了を意味しない。Lexer / Parser / Diagnostics の fixture は今回の対象外。
- 最大の変更集中点は `linkedhashmap_alias.golden`（20回、19,045 bytes、入力80行）。履歴には Map / MutableMap のほか、Iterable の map、Set / Collection、Pair / `to`、`println`、配列・Sequence の変換などの移行が含まれる。`arrayof_type_preserve.golden` は18回、`map_hofs.golden` は15回、`collection_mutable_conversions.golden` は14回。`map_hofs.kt` は11行しかなく、行数だけでなく依存する API 群の多さが問題になる。
- 大きな低頻度ケースも対象: `companion_object_private_access.kt` は163行 / golden 33,065 bytes、`stdlib_kotlin_collections_Collection_n.kt` は71行 / 28,285 bytes。`stdlib_kotlin_collections_MutableCollection_n.kt` と `stdlib_kotlin_collections_Map_flat.kt` は、同名の `Scripts/diff_cases/` 入力と Git blob が完全一致しており、実行用シナリオが Sema にも重複している。
- **分割対象外**: `list_collection_hofs_chained.kt`（8回）は HOF 間の型伝播そのものを検証する7行の連鎖ケースとして維持する。`stdlib_kotlin_comparisons_n_max.kt` / `stdlib_kotlin_comparisons_n_min.kt`（各1回）は引数・戻り値で単一 API の overload 行列を検証済みで、出力処理もない。golden のサイズだけを理由に分割しない。

### 共通方針・完了条件

> **粒度**: 1タスク = 既存入力1ファイルの整理 = 原則1 PR。元の `.kt` と `.golden`、必要な分割先ペア、実行検証の不足補完を同じタスクで扱う。001から順に1件ずつ進め、別の巨大 fixture へまとめ直さない。後続対象はファイル単位の新IDで追加する。
>
> **目的**: ディレクトリ移動ではなく、検証目的と不要な依存機能の分離。現ハーネス（`GoldenHarnessCaseDiscovery.swift`）は Sema 直下の `.kt` を列挙し同名 `.golden` と対応させるため、この構造を維持する。共通コンテキストへの集約タスクとは別物であり、ハーネス・正規化・診断表示を変えて差分を隠さない。
>
> **型検証**: 引数・戻り値・代入先などで具体的な型、nullability、型引数、callee を固定する。推論自体が目的の式には先に期待型を与えず、推論後の別の代入・引数で照合する。`println`、出力用の文字列補間、`toList`、`size`、不要な factory / HOF は除くが、目的である overload 解決や型伝播の依存まで除かない。
>
> **網羅の維持**: 着手時に元の検証項目 → 残す型ケース / 既存ケースへの移管 / 実行ケースへの移管の対応を作り、重複を確認してから分割する。各分割先は「1つの API 群または1つの型規則」を短く説明できること。既存の回帰ケース・不正入力・`<error>` を無言で削って green にしない。コンパイラ / ランタイムのバグが判明した場合は既存のバグ修正ルールに従う。
>
> **他系列との整合**: RF-GOLDEN-010 を先行させ、ハーネスの切り替えと fixture 分割は別 PR にする。着手時点の新しい出力で対象・優先度を再確認する。対象指定の専用 Golden 導入後に入力を分割・改名する場合、`.kt` / `.golden` だけでなく対象指定・実行 profile・メタデータ契約の担当も同じ PR で移管し、旧指定の孤立と新ケースへの重複コピーを検査する。
>
> **実行コスト**: 現ハーネスは8ケース単位で worker を起動するが、各ケースは個別の CompilationContext / Sema 実行を持つ。分割前後のケース数・batch 数・同条件の suite 時間 / メモリを確認し、総再コンパイル量の増加を無視しない。入力を1 API 呼び出しずつ無制限に細分化せず、独立した検証目的とコストを両立する粒度にする。
>
> **実行検証**: 値・順序・副作用回数・同一性・例外は既存の diff / Codegen 実行テストへ寄せる。以下の実行先はソース照合済みの候補であり、全項目の網羅や実行 green を今回確認したという意味ではない。不足だけを補い、新規 stdout 比較は `Tests/CompilerBackendTests/Fixtures/` + `CodegenBackendFixtureTests` の既存規約に従う。既存の実行ケース全体を Sema へ再コピーしない。
>
> **検証ゲート**: 編集前の Sema golden と対応実行テストを基準として確認 → 対象の型・callee・診断を維持して最小化 → `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6` → 更新モードなしで同じ suite と対応する diff / Codegen テストを実行。差分は対象ペアに限定してレビューし、最終的には RF 必須ゲート（全テスト / Golden / 全 diff、存在する場合は LoC 指標）を満たす。`bash Scripts/check_todo_ids.sh` と `git diff --check` も実施する。検証項目の対応・削減した依存 API・分割後最大 fixture の規模を PR に記録する。合計行数やファイル数の減少だけを完了条件にしない。

以下の対象入力名は `Tests/CompilerCoreTests/GoldenCases/Sema/` 配下、実行先の `.kt` は特記がなければ `Scripts/diff_cases/` 配下。括弧内は調査基準時の「入力行数 / golden 変更回数」。すべて分析・タスク登録のみで、fixture の編集・テスト実行は未着手。

### 第1群: 変更集中点（001〜005）

- [x] RF-FIXTURE-001: `linkedhashmap_alias.kt` を型エイリアス解決中心に最小化する（80行 / 20回）
  - 元入力には constructor の型引数推論、引数・戻り値・プロパティ型、`MutableMap` との互換性を残す。更新（set / remove / putAll）、参照（get / contains / keys / values / entries）、entries の HOF、iterator / destructuring の型検証は既存ケースと照合して必要分だけ別目的のペアへ分ける。
  - 型だけを見る箇所から `println`・出力用補間・`toList` を除く。実行先は `linkedhashmap_alias.kt` / `map_entries_hof.kt`。現 diff には更新・順序・HOF があるが、元入力の for-destructuring やプロパティ経由の操作まで同じ網羅ではないため、必要な実行項目を照合・補完する。
  - **完了記録（2026-09-07）**: Sema 入力は80行 → 46行（コメント込み。実質の宣言・式は26行）。`println` / 出力用補間 / `toList` / `size` は Sema 側から除去し、値・順序・副作用は実行ケースへ寄せた。検証項目の対応は下表。

    | 元入力の検証項目 | 対応 |
    |---|---|
    | 引数型 `LinkedHashMap<String, Int>` | Sema に残す（`processLinkedMap`） |
    | 戻り値型 + 明示型引数の constructor | Sema に残す（`createLinkedMap`） |
    | プロパティ型（期待型からの推論 / 明示型引数） | Sema に残す（`OrderedMapHolder.scores` / `.labels`） |
    | 期待型からの型引数推論（alias 側 / `MutableMap` 側） | Sema に残す（`fromAlias` / `fromMutable`） |
    | 明示型引数だけからの constructor 推論 | Sema に追加（`explicit` を期待型なしで宣言し、後続の代入と引数で照合。共通方針「推論自体が目的の式には先に期待型を与えず、推論後の別の代入・引数で照合する」に合わせた） |
    | `MutableMap` 値を alias 引数へ渡す互換性 | Sema に残す（`processLinkedMap(explicitAsMutable)`）。**実行ケースへは移せない**（下記の意図的なモデル差） |
    | 更新（set / remove / putAll） | 実行へ（`Scripts/diff_cases/linkedhashmap_alias.kt`。既存分） |
    | 参照 get（ヒット / ミス） | 実行へ補完（同ケースに追加） |
    | keys / values / entries の直接出力（`toList` なし） | 実行へ補完（同ケースに追加） |
    | entries の HOF | `Scripts/diff_cases/map_entries_hof.kt` に既存のため**変更なし**。`linkedhashmap_alias.kt` 側にも既存分がある |
    | iterator / for-destructuring | 実行へ補完（同ケースに追加）。`stdlib_kotlin_collections_Map_iterator.kt` は immutable `Map` のみで挿入順の `MutableMap` を網羅しない |
    | プロパティ経由の更新（`holder.scores[...]`） | 実行へ補完（同ケースに追加） |
    | 戻り値経由の更新（`createLinkedMap()`） | 実行へ補完（同ケースに追加） |
    | 空 map の `size` / `isEmpty` | 実行へ補完（同ケースに追加）。`hashmap_alias.kt` は source-backed な nominal class の `HashMap` を扱うもので、alias である `LinkedHashMap` は覆わない |
    | `LinkedHashMap<Double, Boolean>` | 実行へ補完（同ケースに追加）。Sema 側は `fromAlias` で型のみ照合 |
    | `LinkedHashMap<String, String>` | 削除。キー・値とも他の型引数ペアと重複し、alias 解決に新しい情報を足さない |

  - **ゲート結果（2026-09-07）**: `bash Scripts/swift_test.sh --filter Golden` green。`bash Scripts/diff_kotlinc.sh Scripts/diff_cases` は total=1232 failed=0 passed=1232 skipped=59 で green。`bash Scripts/check_todo_ids.sh` / `git diff --check` green。`Scripts/loc_report.sh` の追跡指標（`"kk_` リテラル数、KIR/Lowering の TODO/FIXME 数、`interner.resolve == "..."` 数、`@_cdecl`）はいずれも増加なし（`Sources` は ABI-002 の修正で +48行、うち大半はコメント）。`bash Scripts/swift_test.sh`（全テスト）は `RuntimeTests` と `CompilerCoreTests.JobComprehensiveTests` が失敗するが、いずれも `Runtime test isolation lock timed out` と `group.wait(timeout:)` 系の並行スタベーション（BUG-041 と同系）で、`SWIFT_TEST_PARALLEL=0` の単独実行では `RuntimeHelpersTests`（24件）・`JobComprehensiveTests`（19件）とも green。`RuntimeTests` は `Package.swift` 上 `Runtime` / `RuntimeABI` にのみ依存し `CompilerCore` をリンクしないため、本 PR の `ABILoweringPass` 変更とは因果関係がない。
  - **分割後の規模**: Sema の `.golden` は 19,045 bytes → 4,938 bytes。依存する stdlib シンボルは `kotlin.collections.MutableMap` 1件のみになり、`kotlin.Pair` / `Collection` / `Iterable` / `List` / `Set` / `MutableSet` / `Map` / `Map.Entry` / `Map.get` / `MutableMap.putAll` / `MutableMap.entries` への推移的展開は消えた。ケース数は Sema 側 ±0（分割先を新設していない）、実行側は `Scripts/diff_cases` に BUG-233 の回帰ケース1件を追加。
  - **意図的なモデル差**: `Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt` は `LinkedHashMap<K, V>` を `MutableMap<K, V>` の typealias として定義する（JVM stdlib の `java.util` クラスではなく mutable interface を指す、と同ファイル冒頭に明記）。このため `MutableMap<String, Int>` 値を `LinkedHashMap<String, Int>` 引数へ渡す元入力の式は kotlinc が拒否する（`argument type mismatch`）。Sema 側の assertion としては維持し、実行ケースでは alias 型で宣言した `aliasTyped` を渡す形に置き換えた。`HashSet` / `LinkedHashSet` は nominal class として定義されているため、RF-FIXTURE-007 / 008 とは前提が異なる。

  - **着手順の注記**: 共通方針は RF-GOLDEN-010 の先行を求めているが、本タスクはユーザー指示により先行着手した。ハーネス・正規化・診断表示は一切変更していない。

  - **同 PR 内で修正したバグ**: BUG-233 —— `.kklib` 経由の stdlib で `map[k] = v` / `getOrPut` が `Double` / `Float` / `Char` / `Boolean` を box せず raw のまま格納していた（`{k=4609434218613702656}`）。ライブラリから取り込んだ inline body の呼び出しが callee symbol を失い、ABILoweringPass が消去された型パラメータのスロットを判別できなくなるのが原因。`ABILoweringPass` に ABI-002 として boundary bridge の signature 復元を追加し、回帰ケース `Scripts/diff_cases/bug233_mutable_map_indexed_set_primitive_boxing.kt` を追加した。
  - **同 PR で修正しなかったバグ**: BUG-234（`getOrPut` の既存エントリ読み戻し）、BUG-235（`Collection<T>.first()` / `last()` の未解決シンボル）。いずれも理由をバグバックログに記載した。
- [ ] RF-FIXTURE-002: `arrayof_type_preserve.kt` の配列生成の型推論を生成方式ごとに分離する（74行 / 18回）
  - `arrayOf` の要素型 / 混在型、空配列の期待型、primitive factory 8型、`Array(size) { ... }` の initializer 推論・明示型引数と期待型の優先を区別する。特に `Array<Int>` を `Array<out Any>` に受けるケースを単なる期待型付き factory に置き換えない。
  - `println(array.size)` ではなく推論結果の型を照合し、Byte / Short は不要な数値変換と切り離せる入力にする。実行先は `arrayof_type_safety.kt` / `array_constructor.kt` / `array_primitive_types.kt`。これらだけで8型・混在型の実行結果を網羅するとみなさず、元ケースのうち実行が必要な項目だけ補完する。
- [ ] RF-FIXTURE-003: `map_hofs.kt` の Map HOF・分解宣言・変換を分離する（11行 / 15回）
  - `forEach` の entry destructuring、`map` / `filter` の引数・戻り値、`mapValues` / `mapKeys` の K/V 型伝播、`toList` の Pair 変換を別目的にする。Map と entries の Iterable HOF の解決先を混同しない。
  - ラムダ内外の `println` を型照合へ置き換え、必要のない String 操作を使わない。実行先は `map_hof.kt` / `map_entries_hof.kt`。destructuring と `toList` の型検証は、出力ケースがあるという理由だけでは削除しない。
- [ ] RF-FIXTURE-004: `collection_mutable_conversions.kt` の変換型と変更後の挙動を分離する（29行 / 14回）
  - `Iterable` / `Collection` → `MutableList`、`Iterable` → `MutableSet` / `HashSet`、`Map` → `MutableMap` を receiver / 変換 API 別に固定する。receiver をすべて具体的な List に変えて interface 経由の解決を失わない。
  - 型ケースから `add`・`contains`・set・`println` を除き、可変な戻り型を明示的に検証する。コピー独立性・変更結果は `collection_copies.kt` / `iterable_generic_surface.kt` と照合し、Map 変換などの不足を補完する。
- [ ] RF-FIXTURE-005: `unsigned_array_as_list.kt` を view / copy / size の型検証に分離する（31行 / 10回）
  - unsigned 4型の `asList`、`toList` / `size`、generic `Array<T>` の `toList` / `size` を区別する。unsigned 配列を型付き引数等で受け、ULongRange → 配列生成や出力への不要な依存を除く。
  - `List<UByte>` / `List<UShort>` / `List<UInt>` / `List<ULong>` の型を固定する。view が元配列の更新を反映し copy は反映しない挙動は、既存 `unsigned_array_conversions.kt` に寄せる。

### 第2群: 関連コレクションと I/O の依存削減（006〜015）

- [ ] RF-FIXTURE-006: `arraylist_alias.kt` の alias 解決と List 操作を分離する（67行 / 7回）
  - 引数・戻り値・プロパティ、ネストした型引数、上限制約、拡張 receiver、`MutableList` / `List` への互換性を残し、それぞれの型規則に不要な `add` / `removeAt` / get / size / 補間 / 出力を外す。
  - 更新・要素取得の実行先は `arraylist_alias.kt` / `ksp627_collection_aliases.kt`。ネスト・制約・拡張 receiver の型検証を、これらの実行ケースだけで代替しない。
- [ ] RF-FIXTURE-007: `hashset_alias.kt` の nominal 型・factory・Set 操作を分離する（64行 / 6回）
  - 現 `CollectionAliases.kt` の `HashSet` は typealias ではなくクラス。`hashSetOf` の期待型推論、`Set` / `MutableSet` への互換性、引数・戻り値・プロパティ、ネスト・上限制約・拡張 receiver を型検証として整理する。
  - add / remove / contains / size / 出力のシナリオを切り離す。実行先は `ksp627_collection_aliases.kt` と `CodegenBackendIntegrationTests.swift` の `testCodegenHashSetOfFactoryUsesMutableRuntimeSet`。factory と nominal constructor の検証を取り違えず、不足する削除操作などを補完する。
- [ ] RF-FIXTURE-008: `linkedhashset_alias.kt` の nominal 型と継承検証を分離する（72行 / 6回）
  - `LinkedHashSet` は open class。型引数・引数 / 戻り値 / プロパティ・`Set` / `MutableSet` 互換性、ネスト / 上限制約 / 拡張 receiver と、`MySet` による継承・継承メンバ解決を別目的にする。
  - 型だけを見る箇所の更新操作・文字列補間・出力を除く。実行先は `ksp627_collection_aliases.kt` / `bug196_linkedhashset_subclass.kt` と `testCodegenLinkedSetOfFactoryUsesMutableRuntimeSet`。既存の subclass 回帰を保持する。
- [ ] RF-FIXTURE-009: `list_collection_hofs.kt` の独立 HOF 群を目的別に分離する（9行 / 9回）
  - `mapIndexed`、`flatMap`、associate 系、`groupBy`、`partition` / destructuring の戻り型・ラムダ引数型を独立に固定する。文字列補間・`uppercase`・`first` など目的外の処理は最小のラムダに置き換える。
  - 実行先は `collection_hof.kt` / `list_associate_group_hofs.kt`。別入力 `list_collection_hofs_chained.kt` は連鎖推論の sentinel としてそのまま残し、分割先への再統合をしない。
- [ ] RF-FIXTURE-010: `flatten_sequence_stdlib.kt` の flatten 型解決と Sequence 実行シナリオを分離する（28行 / 7回）
  - `Sequence<Iterable<T>>` と `Sequence<Sequence<T>>` の overload / 要素型推論を型付き入力と戻り型で検証する。builder・`yield`・for・`take` / `drop`・`toList`・size・出力を同居させない。
  - 実行先は `flatten_sequence_edge_cases.kt`。元の `mixedSeq`（List と Sequence の混在）はこの diff にないため、標準 Kotlin で成立する型・診断と検証目的を確認して別途固定する。builder 内推論などを削るだけで既存の問題を隠さない。
- [ ] RF-FIXTURE-011: `flatten_stdlib.kt` を Iterable flatten の型伝播に最小化する（18行 / 7回）
  - Int / String の要素型保持と空入力の型引数を固定し、範囲 → `map` によるデータ生成・`take`・size・出力を除く。要素数の違いだけで同じ型検証を繰り返さない。
  - 空・単一・複数・大きな入力の値と順序は `flatten_core_test.kt` に寄せる。`flatten_comprehensive.kt` は現状 `flatMap { it }` の実行ケースなので、これだけを `flatten()` の回帰代替としない。
- [ ] RF-FIXTURE-012: `sequence_partition.kt` の戻り型と destructuring を実行条件から分離する（29行 / 7回）
  - `Sequence<T>.partition` の predicate 引数と `Pair<List<T>, List<T>>`、分解後の各 List 型を固定する。`asSequence`・Pair の出力用アクセス・空 / 全一致 / 不一致の重複シナリオを型 fixture に集約しない。
  - 実行先は `CodegenBackendSequenceEdgeCasesTests.testCodegenSequencePartitionSplitsElements`（通常・空は既存）。全一致 / 不一致 / `asSequence` 経由は不足を照合して補完し、List.partition のテストだけで Sequence の実行を代替しない。
- [ ] RF-FIXTURE-013: `progression.kt` の生成・変換操作の型と列挙結果を分離する（8行 / 7回）
  - 5種の `fromClosedRange` は Progression 自身の戻り型を固定し、`step` / `reversed` / `isEmpty` はそれぞれ必要な型検証へ分ける。全式を `toList` に接続して返す構成をやめる。
  - 要素列・端点・空判定・step の挙動は既存 `progression.kt` の実行ケースに寄せ、Int / Long / Char / UInt / ULong の型検証を維持する。
- [ ] RF-FIXTURE-014: `file_operations_advanced.kt` の File API 型解決とディレクトリ操作を分離する（28行 / 10回）
  - mkdirs / delete の戻り型、walk の戻り型、listFiles の nullable 戻り型を別目的で固定する。File を引数に受け、固定 `/tmp` パスの操作手順と `toList()?.size` / 出力を型検証から外す。
  - 実行先は `file_mkdirs.kt` / `file_walk.kt` / `file_listfiles.kt`。実ファイル生成・走査・削除はこれらの実行層で維持し、Sema が実行結果を検証しているとは扱わない。
- [ ] RF-FIXTURE-015: `file_use_lines.kt` を useLines のラムダ / 戻り型推論に絞る（17行 / 8回）
  - `File.useLines` のブロック引数 `Sequence<String>` と汎用戻り型の伝播を残し、File constructor、Sequence の `count` / `toList` 自体の型検証とは切り離す。Int と List 戻り値の推論範囲を狭めない。
  - 実行先は `file_uselines.kt` と `CodegenBackendFileUseLinesForEachLineTests`。count / 行走査は既存だが、List を返して useLines の外で使うケースは今回照合した実行先にないため補完する。

### 第3群: 大きな API surface / シナリオの分解（016〜022）

- [ ] RF-FIXTURE-016: `stdlib_kotlin_collections_Collection_n.kt` の Collection surface を API 群別に分ける（71行 / 6回）
  - containsAll / count / indices、nullable helper、plus overload、random overload、可変変換、signed / unsigned 配列変換に分ける。各入力は型付き receiver を受け、結果を連結した巨大な Boolean 式と `println` を除く。
  - nullability、Random あり / なし、要素 / Iterable / Sequence / Array の overload、配列変換12型の行列を維持する。実行先は同名 `stdlib_kotlin_collections_Collection_n.kt`。コピー独立性・乱数・配列内容は実行層に残す。
- [ ] RF-FIXTURE-017: `stdlib_kotlin_collections_MutableCollection_n.kt` の更新 surface と値検証を分離する（81行 / 3回）
  - addAll、remove / removeAll、retainAll、plusAssign / minusAssign を目的別に分け、Iterable / Collection / Sequence / Array と nullable 要素の overload・戻り型を固定する。型付き引数を使い、同じ mutableList の生成・出力を繰り返さない。
  - `StableIterable` の実走査、重複要素の削除、空入力、Set 更新などの値検証は、入力が完全一致する同名 diff に残す。静的 receiver / 引数型が変わって別 overload を検証する退行を防ぐ。
- [ ] RF-FIXTURE-018: `stdlib_kotlin_collections_Map_flat.kt` を flatMapTo の overload / destination 型に絞る（70行 / 2回）
  - Iterable と Sequence を返すラムダの overload、entry の K/V 型、nullable 要素、`MutableList<Any>` 等の広い destination と戻り型保持を型ケースにする。入力 Map・destination・変換元を引数に受け、不要な factory と処理手順を外す。
  - destination の同一性・追記順・呼び出し回数・`constrainOnce`・独自 one-shot Iterable・例外時の部分結果は、入力が完全一致する同名 diff に残す。これらの runtime シナリオを別の Sema fixture にコピーし直さない。
- [ ] RF-FIXTURE-019: `stdlib_kotlin_collections_MutableMap_n.kt` の更新・委譲・iterator を分離する（36行 / 2回）
  - nullable getOrPut、plusAssign / minusAssign、putAll、set / remove、Map による property delegation、withDefault / getValue、mutable iterator / entry.setValue を別目的に分ける。各型・overload を明示して出力用の更新連鎖を外す。
  - 実行先は同名 `stdlib_kotlin_collections_MutableMap_n.kt`。null / absent、wrapper と元 Map の共有、iterator.remove の結果を維持し、001の基本 Map 操作と分割先が重複しないよう照合する。
- [ ] RF-FIXTURE-020: `stdlib_kotlin_collections_n_if.kt` の ifEmpty 型推論と遅延評価を分離する（87行 / 2回）
  - Collection / Map / Array の overload、nullable 要素、receiver と fallback の異なる型からの戻り型推論を固定する。カウンタ・同一性比較・出力・空判定の実行シナリオを取り除く。
  - custom Collection / Map の subtype に対する解決は必要な型ケースとして独立させ、size の override を使う isEmpty の実行結果と fallback 評価回数・同一性は同名 diff に残す。型注釈を追加して元の推論パスを失わない。
- [ ] RF-FIXTURE-021: `companion_object_private_access.kt` のアクセス規則と companion 拡張を分離する（163行 / 4回）
  - private constructor（通常 / data class）、companion → インスタンスの private property / function、外側クラス → companion の private member、名前付き / 無名 companion の拡張関数 / 拡張プロパティを目的別の最小クラスにする。
  - メール検証の `contains`、業務的な分岐・演算、整形文字列、factory ごとの大量出力をアクセス可否の検証から外す。private の許可範囲と呼び出し先は Sema に残す。
  - 実行先 `companion_receiver_extension_function.kt` は companion 拡張関数の一部のみをカバーする。private access / data class / 拡張プロパティまで網羅済みとはせず、残すべき実行挙動があれば既存 fixture ハーネスで不足を補う。
- [ ] RF-FIXTURE-022: `stdlib_string_ops.kt` の String API を検証目的別に分離する（77行 / 5回）
  - trim / indent、検索・prefix / suffix、部分文字列、置換、split、大小文字 / equals、数値変換、format、空白判定・先頭要素などの API 群に分ける。既に明示された戻り型・nullable 戻り型と overload の区別は維持する。
  - `println` は元からないため、出力除去を成果としない。valid / invalid 入力で型が同じケースは、既存の型・実行検証と照合して冗長分だけ整理する。実行先は `stdlib_string_ops.kt` を起点に、prefix / suffix / indent 等の不足項目を API 別の既存実行ケースと照合する。

---

## Sema Golden と stdlib 実装契約の責務分離（RF-GOLDEN: 2026-09-06 調査）

### 現状・確認した根拠

- 調査基準は RF-FIXTURE と同じ `f637b7bdf77ce29a26ca00a782b34c5927df6d17`。`Sources/GoldenHarnessSupport/GoldenHarnessDump.swift` の `renderSemaOutput` は fixture の宣言・式を起点に `StableRenderContext.expandRequiredSymbols()` を呼び、関数の receiver / 引数 / 戻り型 / 上限境界 / 型パラメータ / 値パラメータ、プロパティ型へ推移的に広げたシンボルの flags / signature を出力する。
- bundled 除外は **展開後**の `isExcludedBundledSymbol` で行われ、`declSite.start.file` が `SourceOrigin.isBundledStdlib`（bundled / residual）のファイルかだけを判定する。宣言位置がある bundled symbol は除外される一方、nil の synthetic stub・互換 nominal・source-backed member alias は同じ扱いにならない。`SemanticSymbol` に独立した由来フィールドはなく、`SymbolTable.isSourceBackedSymbol` も importedLibrary または非 nil declSite の判定で、stdlib / ユーザー / 他ライブラリを識別する API ではない。
- `HeaderCollection.swift` の `predeclareBundledTupleHeaders` / `shouldRestoreDeclSiteForReusableSyntheticSymbol` には、Golden から除外されないために declSite を nil に保つ互換処理がある。`PairTripleNominalAnchorTests.testBundledSourcePairKeepsNilDeclSiteForGoldenStability` も **source-backed・非 synthetic の Pair に nil declSite を要求**する。Charset の先行登録にも同様の処理があり、表示都合がコンパイラ側の宣言位置に結び付いている。
- 同じ `HeaderCollection.swift` は runtime-linked な bundled extension に、receiver 配下の FQName・nil declSite・synthetic flag・同じ signature / externalLinkName を持つ member alias を作る。したがって `synthetic == stdlib 外部参照` でも `!synthetic == fixture の宣言` でもない。owner + name + arity の `BundledDeclarationIndex` は stub 抑制用で、同 arity の overload を識別する完全な参照キーではない。
- **重複変更の実例**: `410638346a4857d1db9908105845106d9134e2f0`（KSP-697 / #5904）の Sema golden 差分は106ファイル。`List` の `flags=synthetic` → `_` が94件、`Iterable` が51件、`MutableCollection` が12件に重複して現れる（件数は重なりあり）。`git show 410638346 --format= --unified=0 -- 'Tests/CompilerCoreTests/GoldenCases/Sema/*.golden'` で再確認できる。
- **フラグを捨ててはいけない実例**: 同コミットは、source 化で List の synthetic flag が消えた結果、`ControlFlowLowerer.usesDynamicIteratorDispatch` が通常 List を任意の Iterable 実装と誤認して専用 iterator 経路を失う問題も修正している。現 `CodegenBackendInterfaceIterableForLoopTests.testConcreteListForLoopStillUsesListIterator` は `kk_list_iterator_next` を直接検証する。同 suite には Iterable の汎用経路と BUG-231 の手書き List / Set 実装の override 呼び出しもあり、単純にすべての List を固定経路へ寄せる変更も許されない。
- 専用検証は一部存在する: `BundledDeclarationIndexTests` は source 所有と残存 stub / alias、`ListSyntheticMemberLinkTests` は nominal / factory / 外部リンク、`StdlibSurfaceSpecTests` は残存 bridge spec と登録、`RuntimeABIExternalLinkValidationTests` はリンク名・bundled `@KsSymbolName` の arity / signature、`ABIMismatchTests` / `ABIMismatchRuntimeExportParityTests` は spec / extern / runtime export を検証する。ただし surface-spec は source-backed API 全体の台帳ではなく、export parity にも対象除外があるため、これらの存在だけで移管完了とはしない。
- `GoldenHarnessSemaFormat` は flags の一部を表示するが、`throwingFunction` / `importedLibrary` や signature の `canThrow` は表示しない。`ABILoweringPass` は throwingFunction で outThrown の有無を変えるため、現 Golden が ABI 契約をすべて検証しているという前提も置かない。
- 現在の overload キーは同 FQName 内の receiver / parameter 型順から付けた `#N` で、同順位は SymbolID を使う。外部 symbol 行だけを削っても、`call=` / `ref=` / 型に残る番号・alias 名の揺れは解消しない。既存の dummy bundled file 不変テストは `fun main() { val x = 1 }` に空 package を注入するケースで、同じ stdlib API の synthetic / source-backed 切り替えの同値性までは扱っていない。

### 最優先: オーバーロード番号を宣言の意味に基づくキーへ置き換える

- `StableRenderContext` は参照集合を収集する前に **全 symbol を FQName 別に集め**、2件以上の場合だけソート順に `#0` / `#1` 等を割り当てる。未参照 overload の追加でも既存番号がずれ、1件 → 2件では suffix の有無まで変わる。型パラメータの `$<ownerID>` を桁揃えする現処理も、宣言内の位置に基づく正規化ではない。
- 現 HEAD の `stdlib_kotlin_collections_n_Set_interface.golden` には Set receiver の `call=kotlin.collections.containsAll#2` がある。報告された Collection overload 追加時の `#1` → `#2` という特定の履歴差分は今回の first-parent 調査では直接確認できず、この fixture は追加コミット `24f091058` の時点で `#2`。番号が他の候補に依存する構造はコードで確認できるため、選択対象を固定して未参照候補だけを追加する最小テストで再現する。
- 表示イメージ: `call=kotlin.collections.containsAll[recv=Set<T0>;params=Collection<T0>]`。これは省略表示例であり、実際のキーには宣言の種別・完全な型名・必要な型パラメータ / スコープ情報等を含める。単に `#番号` を削除する方式は採用しない。

- [ ] RF-GOLDEN-010: **P0 / 最優先** — 候補集合のソート順位ではなく、宣言の意味に基づく安定キーを Golden ハーネスに導入する（001〜009・RF-FIXTURE より先行、stdlib 検証移管の完了待ちは不要）
  - 対象: `GoldenHarnessStableRenderContext.swift` の FQName grouping / overloadSuffix / stableKey / overloadSortKey、`GoldenHarnessDump.swift` の宣言・`call=` / `ref=`、対応する GoldenHarness tests。stdlib に限らず同 FQName の各宣言を区別し、コンパイラ本体の overload 選択・SymbolID・flags・declSite・ABI は変えない。
  - キーは FQName・symbol kind・必要な owner / 宣言スコープ・receiver・引数型・generic arity 等に基づく構造とする。**overload が1件でも同じ形式**を使い、候補件数・登録順・全候補中の順位を表記の条件にしない。callable / constructor / property / accessor の区別と、owner を含むローカル・ネストした宣言の識別もケースに含める。
  - 型は `TypeKind` 等から構造的に符号化し、既存の `renderType` 文字列をそのままキーに流用しない。現 `Substitution.swift` の関数型表示は nullable な関数型と nullable 戻り型を同形にし得るため、`(() -> String)?` と `() -> String?` を区別する回帰を必須にする。`T` / `T?` / `T!`、star / in / out、関数の receiver / contextReceivers / suspend、KClass・intersection・再帰的境界を扱い、ABI 用の型消去や `erasedForMetadata` を識別に使わない。型構造にある追加属性は意味に必要なものを保持し、残りの検証先を001で明示する。
  - 型パラメータは名前や内部IDでなく宣言順の `T0` / `T1` 等へ正規化する。`classTypeParameterCount` と owner / callable のスコープを考慮し、同名パラメータ・再帰的境界・相互参照で衝突や無限再帰を起こさない。receiver / parameter / return / bounds の参照を一貫させ、raw ID や runtime link 名を識別根拠にしない。キー計算の memoization は CompilationContext 内に閉じ、別ケースの ID を再利用しない。
  - FQName の各要素・識別子・型構造の境界をエスケープ等で一意に表す。backtick 識別子に含まれる区切り文字や数値を通常のドット区切り / `[]` / `;` 等と混同しない。既存の全文正規化（`GoldenHarnessAPI.swift`）が意味キー・識別子・リテラル・診断本文を内部 ordinal と誤認して書き換えない感度テストを追加し、raw で異なる意味を normalized で同一化しない。
  - 同名同 arity の別宣言を識別できることを確認する。キー衝突時は必要な宣言スコープ等で区別し、SymbolID の tie-break / 新たな連番に戻らない。同一宣言の再利用・合成 alias・本当の別宣言・不正入力の重複診断を区別し、未参照候補が増えただけで無関係な fixture を落とさない。実装方式をまたぐ alias の同一視は006で扱う。
  - **先に書く不変テスト**: Set receiver の containsAll を選択したまま、同 FQName の未参照 Collection overload を追加してもキーが不変。さらに1件 → 2件、2件 → 3件、未参照候補の削除、登録順・内部ID・型パラメータ名の変更を確認する。fixture 自体の宣言追加ではなく、別入力 / テスト用 symbol table の未参照候補だけを変え、既存参照を比較する。
  - **感度テスト**: 選ばれた overload、receiver / 引数型、種別、generic arity / 必要なスコープが異なればキーも区別される。`call=` と `ref=` と宣言行の対応が保たれ、誤選択を検出できること。既存の数値ソート用テストは、この意味上の契約を直接確認する回帰へ置き換える。
  - 完了条件: raw / normalized の両方で上記回帰と `GoldenHarnessPersistenceTests` / `GoldenHarnessSemaComparisonNormalizationTests` / `GoldenHarnessNormalizationInvariantTests` が green。キーだけを新方式に接続し、Sema golden を更新・更新モードなしで再検証する。fixture 入力・参照 symbol の収集範囲・flags / signature / 診断の表示は減らさず、RF 必須ゲートも満たす。これにより後続の由来分離を待たず着手可能にする。

### 構造的削減の採用案: 対象指定の専用 Golden（2026-09-06 選択）

- TODO 上の設計方針として、通常 Golden から外部 symbol のメタデータ行を除き、**対象 API を明示する stdlib 専用 Golden**で保持する案を選択。実装着手・§8 の正式改訂は別途確認する。
- 現 HEAD の `stdlib_kotlin_*` は280件ではなく **289入力**（Sema 全579件）。現在は通常ケースと同じ suite / renderer を使う API 呼び出し側の入力であり、stdlib の宣言本体ではない。例えば `stdlib_kotlin_Pair_n_n.kt` が宣言するのは `makePair` 等だけなので、fixture 所有 symbol だけを出す変更を一律に適用すると専用ケースからも Pair のメタデータが消える。専用の対象指定・描画経路を先に用意する必要がある。
- KSP-697 の106変更は **通常53件・`stdlib_kotlin_*` 53件**。専用ケースをすべて従来の推移的 dump のまま残す方式では重複を解消できない。新規 API に固有ファイルを追加しても、そこで List 等の依存型メタデータを再出力すれば共有型の変更が再波及する。「106 → 1〜2」は未検証の目標であり、変更した契約の担当ケース数に局所化することを効果検証の基準とする。

### 責務・実施順序

> **通常の Sema Golden**: `symbol` 行は fixture 内の宣言とそれに属する合成宣言に限定する。外部参照の flags / sig / type メタデータ行は出さず、式の推論型・`ref=` / `call=` / `targs=`・診断で名前解決と型検証を維持する。外部参照キーは010・006を利用し、overload / receiver / nullability / 型制約等の意味上必要な差は残す。`call=kotlin.Enum.equals` のような実際の解決先変更は差分として残るべきもので、削減対象にしない。
>
> **対象指定の stdlib Golden**: 既存 `stdlib_kotlin_*` を活用するが、ファイル名だけで従来の全文出力を有効化しない。各ケースが担当する宣言とメタデータ契約を明示し、対象自身の flags / signature / type / 必要な由来等だけを専用節に出す。参照先の型や依存 API のメタデータへ推移的に広げない。原則1契約に1つの担当ケースを置き、同じ shared nominal を多数の期待値へ再複製しない。
>
> **併用する専用テスト**: ABI・externalLinkName・runtime export・bridge・実際の lowering 経路は既存の Sema / Lowering / Runtime / Codegen tests で引き続き検証する。メタデータが一致するだけでは正しい call や ABI を証明できない。全 symbol table を1つの巨大な stdlib Golden に移す解決にも、既存の実行検証を削除する解決にもしない。
>
> **保護条件**: synthetic 全除外、`kotlin.*` / パス prefix や declSite の有無だけでの所有判定、比較後の文字列から flags / signature を一括削除する方式は禁止。ユーザーの data / enum / object literal / accessor 等の合成宣言と stdlib receiver 拡張は fixture 所有として保持する。stdlib 以外の library の参照・型と必要なメタデータ検証も失わず、由来不明や専用対象の解決失敗を黙って省略しない。
>
> **順序**: **010が最優先**。その後は001を起点に002（所有・由来）と012（実行 profile）を進め、両方が揃って011（対象指定の基盤）→ 013（全量 inventory gate）→ 003（専用 Golden への移管）。004・005は001後、006は002・010後に進められ、003・004・005・006・011〜013が揃ってから007 → 008 → 009へ進む。**対象指定があるだけでは完了ではなく、検証移管・全量検査・007の情報保持テストが green になるまで、通常 Golden の情報を減らさない**。1タスク = 1責務 = 原則1 PR。RF-FIXTURE は個別入力の依存削減、本系列は横断の出力契約であり、010のキー更新・専用ケースの移管・008の通常出力切り替え・fixture 分割を混ぜない。
>
> **完了ゲート**: focused な GoldenHarness / Sema / KIR・Lowering / ABI / Codegen suite と RF 必須ゲート（全 Swift テスト、Golden、全 diff、存在する場合は LoC 指標）を満たし、source 注入 / stdlib artifact の必要な経路も確認する。通常側の不変性と専用側の変化検出を両方証明する。`docs/stdlib-pipeline.md` §8 の現行の一括更新許容方針は008で明示的に改訂するが、決定的なロード順や意味変更・出力形式移行時の一括更新は維持する。今回の記録は設計選択・タスク登録のみで、ハーネス実装・§8 改訂・テスト実行は未着手。

### タスク

- [ ] RF-GOLDEN-001: 通常 Golden に残す情報と専用テストへ移す情報の契約をテストケースで固定する（前提: 010）
  - 対象: `GoldenHarnessPersistenceTests.swift` / `GoldenHarnessSemaComparisonNormalizationTests.swift` と既存 stdlib Sema suites。`linkedhashmap_alias`、`map_hofs`、Pair / List を含む型、ユーザーの data / enum / object literal / accessor を代表ケースに、宣言・型・callee・診断・由来・flags・ABI の検証先を列挙する。
  - 「削る出力項目 → 具体的な既存 assertion または追加する assertion」を対応付ける。source / synthetic の実装差と、公開 signature / 解決先 / 診断の意味差を分け、現出力の特徴を固定する。既存 Golden に出ない throwingFunction / canThrow 等も専用契約側の監査対象として区別する。
  - メタデータ契約を kind 別に棚卸しする。現 formatter の flags / functionSignature / propertyType だけでは nominal の型パラメータ・宣言側 variance・上限・supertype と型引数、typealias の underlyingType / 型パラメータ、注釈等を網羅しない。既に出力される visibility も保持し、callable の reified / default / vararg / non-local-return 許可等と併せて、専用節か既存 Sema / Lowering / ABI assertion のどちらで検証するか明示する。全項目を無条件にキーへ詰めず、宣言の識別条件と検証したいメタデータを分ける。
  - 正例 fixture の新規 error diagnostic を機械的な golden 更新で受理しない基準を用意する。既存の error / `<error>` は基準時点で列挙し、意図した診断ケースか不具合かを確認してから扱う。特定の flag / API の不在が正しい契約は既存の残存 stub 検査等へ割り当て、存在すべき対象の解決失敗と混同しない。
  - 完了条件: 代表入力と期待する情報区分が再現可能なテストになり、移管未完了の項目が明示されていること。既定 renderer と既存 golden はまだ変更しない。
- [ ] RF-GOLDEN-002: declSite / synthetic flag に依存しない symbol の所有・由来判定を用意する（前提: 001）
  - 対象: `GoldenHarnessDump.swift` / `GoldenHarnessStableRenderContext.swift`、必要に応じて `HeaderCollection.swift` / `SymbolTable` の登録・import 情報。まず AST の宣言 binding と `SourceOrigin`、owner 関係、登録済み stdlib / import の識別情報を利用し、足りない由来は登録・引き継ぎ時に明示的に保持する。表示用分類のために production の flags / declSite / isSourceBackedSymbol の意味を変更しない。
  - fixture 所有（合成宣言を含む）、bundled / residual source、synthetic stdlib stub、source-backed member alias、imported stdlib、その他の library / 不明を区別する。type / value parameter や accessor は所有元の由来を追い、parent が不十分なら signature / 宣言 binding も照合する。source がない `--no-stdlib` の fallback と通常の imported library を混同しない。
  - 完了条件: nil declSite の Pair、synthetic な source accessor / alias、ユーザーの stdlib receiver 拡張と同名 package、stdlib 以外の import を誤分類しないテストが green。由来不明を黙って外部扱いしない。既定出力は未変更。
- [ ] RF-GOLDEN-012: Golden の source / artifact / no-stdlib 実行条件とケース識別を明示する（前提: 001・010）
  - 対象: `GoldenHarnessCase` / `GoldenHarnessAPI` / `GoldenHarnessWorker` / `GoldenHarnessPipeline` / Golden IO・テスト。現 API と worker は suite / sourcePath だけを受け、pipeline は stdlibLibraryPath 等を渡さないため、専用ケースが実際にどの stdlib モードを検証したかを固定できる入力を追加する。現在の既定 source 経路は維持し、profile が指定された場合だけ対応する CompilerOptions を明示する。
  - 必要な source / artifact / no-stdlib を区別し、未準備の artifact・不明な profile を source へ黙って fallback させない。`TestStdlibCache` は CompilerBackend を import するため、そのまま GoldenHarnessSupport に依存させず、artifact の準備と型検証を分離して Core の LLVM 非依存境界を維持する。artifact を必要とするテストの準備・実行レーンを明示する。
  - ケースは sourcePath と profile の組で識別し、batch 応答の照合・期待値の参照・保存にも同じ識別を通す。現 goldenURL は sourcePath だけから導出されるため、複数 profile が同じ期待値を上書きしない保存方式または比較専用方式を決める。profile 固有の由来メタデータは同値比較の対象から区別し、API が異なる no-stdlib と source を無条件に等価としない。
  - 完了条件: 単発 / batch / 直呼びで明示した経路が実際に使われ、同一 worker 内の A → B → A や異なる profile で状態・対象指定が漏れないこと。キャッシュや一時 artifact の絶対パスを Golden へ埋め込まず、必要な profile の期待値と実行実績を区別できる。全289ケースを機械的に全 profile へ倍増させない。
- [ ] RF-GOLDEN-011: 対象 API を明示する stdlib 専用 Golden の基盤を追加する（前提: 001・002・010・012）
  - 対象: `GoldenHarnessCaseDiscovery` / `GoldenHarnessAPI` / worker のケース伝達 / `GoldenHarnessDump` / persistence・normalization tests。各ケースが検証する宣言を010の意味キー相当の条件で指定し、002の由来判定と012の実行 profile を使う。指定方法はケース単位の隣接メタデータ等として設計し、全対象を1つの巨大な共有リストへ集めない。ファイル名 prefix だけで opt-in したことにはしない。
  - 対象選択と期待値を分離する。flags・正しい戻り型等の「検証したい値」で対象を絞って不正な実装を検査から外さず、識別に必要な overload 条件だけで選ぶ。識別条件自体が変わった場合も対象不一致として必ず失敗させる。metadata schema / 描画契約の版と、未知の項目・不正な型・重複指定を拒否する規則を定める。
  - 専用節は明示対象自身のメタデータを出し、001で必要とした visibility・nominal の型パラメータ / variance / 上限 / supertype 型引数・typealias 展開先・callable 属性等を、既存 assertion との分担どおり保持する。signature に現れる別 nominal や依存関数のメタデータへは自動展開しない。source-backed 対象を declSite 除外で消さず、対象の境界内だけを安定順で描画する。
  - 存在すべき対象0件・一意であるべき指定の複数一致・古いキー・通常 library / fixture の誤指定は失敗させ、更新モードでも空の対象節を確定しない。不在が正しい契約は001で割り当てた専用 assertion と区別する。glob 的な全 package / 全依存 symbol 指定を通常の運用にしない。
  - 完了条件: 対象の誤ったメタデータは差分または明示的失敗になり、依存型の無関係な変更は専用節を変えないこと。API・worker・保存・比較で対象と profile が失われないこと。通常 Golden の情報削減はまだ行わず、ケース間の担当・欠落検査は013で追加する。
- [ ] RF-GOLDEN-013: 専用ケースの全量棚卸し・欠落防止を discovery / CI のゲートにする（前提: 011・012）
  - 対象: `GoldenHarnessCaseDiscovery` / `GoldenHarnessStaticCases` / inventory・persistence tests / 必要な CI 配線。`.kt`・対象指定・期待値・profile の対応を検証し、孤立した指定 / golden、改名後の取り残し、既存専用ケースの指定欠落を検出する。対象指定ファイルの削除や読み込み失敗で通常モードへ黙って降格させず、既存専用期待値・必須の担当契約とも照合する。
  - 契約（宣言・検証項目・profile）ごとの担当重複と未担当を **全ケース集合で**検査する。現ハーネスの8件 batch / shard / filter の内側だけでは別 shard の重複を見落とすため、全量 preflight または独立した必須 inventory suite を設ける。意図した重複は理由を示し、新規API追加・正規の削除・fixture分割時の担当変更も検証可能にする。
  - `UPDATE_GOLDEN=1` は意味や対象指定の誤りを承認する操作にしない。mode / schema の意図しない変更や指定不正は書き込み前に拒否し、正規の移管・削除は担当契約を更新するレビュー対象にする。ケースの error が別ケースの正常結果に紛れず、直呼びでもケース単位の検査が働くことを確認する。
  - ビルド・CI 接続も確認する。`Package.swift` の GoldenHarnessSupport は sources 明示列挙なので、新規 Swift helper は列挙に追加する。`.github/workflows/ci.yml` の Golden / method shard の選択条件を確認し、新 suite・新 profile が未実行にも重複実行にもならないよう実行件数を照合する。既存の検証や対象除外を緩めて通さない。
  - 完了条件: shard をまたぐ重複・指定削除・孤立ファイル・不正 schema を負のケースで検出でき、通常実行と更新モードの両方でゲートが有効。更新前後の担当数 / case・profile 数を提示し、実行時間・メモリの増加も確認する。
- [ ] RF-GOLDEN-003: stdlib メタデータを対象指定の専用 Golden へ移管し、由来検証を補完する（前提: 001・011・013）
  - 対象: 既存 `stdlib_kotlin_*` 入力と期待値、`PairTripleNominalAnchorTests` / `BundledDeclarationIndexTests` / `ListSyntheticMemberLinkTests` 等。まず List / Iterable / MutableCollection、Pair / Triple、member alias のメタデータ契約を担当ケースへ割り当て、011の対象指定を追加する。新規ケースは不足する契約だけに限定する。
  - API 群ごとに001の「削るメタデータ → 担当する専用節 / assertion」を対応付ける。Collection API を呼ぶケースへ List の flags が現れる、といった依存型の重複を残さない。既存289ケースが対象指定なしで自動的にメタデータを担うとはせず、必要な契約の担当と API 呼び出しの型検証のみを行うものを区別する。
  - `synthetic` がないだけで source 所有と断定せず、AST / import との対応や残存 stub / alias の許可を既存 Sema テストで検証する。専用メタデータ抽出の分類結果をそのまま唯一の正解として使わない。既存の重要 lowering・ABI assertion は004・005で維持する。
  - 完了条件: 対象の誤った所有・重要 flags / signature / type の変更を専用側が検出し、001の移管項目に未対応がないこと。担当契約の重複検査が green で、通常 Golden に依存しない検証先を示せること。件数が大きければ API 群別の新IDへ分け、全件の大規模再編や通常出力の削減をこのタスクへ混ぜない。
- [ ] RF-GOLDEN-004: フラグ変更が iterator / lowering に与える影響を既存回帰 suite で担保する（前提: 001）
  - 対象: `ControlFlowLowerer.swift` に対する `CodegenBackendInterfaceIterableForLoopTests`、`StdlibArtifactRegressionTests`、対応する Core KIR / Lowering suites。`testConcreteListForLoopStillUsesListIterator`、`testIterableInterfaceForLoopLowersToIteratorNotRangeIntrinsics`、BUG-231 の手書き List / Set / Mutable 系実装の実行テストを移管先として明示し、足りない source 注入 / artifact 経路だけを補う。
  - KSP-697 の非 synthetic List でも専用の iterator 呼び出しが残り、interface 経由やユーザー実装の override は適切な経路を使うことを確認する。artifact の型代入テストだけを iterator の経路・実行検証の代わりにしない。001で重要と判定した data / enum 合成や inline 等も既存の対応 lowering テストへ紐付ける。
  - 完了条件: Golden の flags 表示を使わず、正しい KIR callee と実行結果を検証できること。重要分岐を誤った状態にした負の対照で検出力を確認し、出力安定化のために production の分岐を緩めない。
- [ ] RF-GOLDEN-005: ABI・bridge・throwing 契約の移管漏れを専用テストで補完する（前提: 001）
  - 対象: `RuntimeABIExternalLinkValidationTests` / `StdlibSurfaceSpecTests` / `ABIMismatchTests` / `ABIMismatchRuntimeExportParityTests` と ABI lowering tests。参照先の externalLinkName と `@KsSymbolName`、RuntimeABISpec、runtime export の対応・引数順 / 型 / arity / 戻り型を照合する。既存の constructor 特例や export parity の除外を把握し、必要な個別テストを確認する。
  - `ABILoweringPass` の throwingFunction → outThrown、非 throwing 呼び出し、source-backed bridge の実際の lowered call を確認する。`DurationSyntheticStubTests` の parse bridge flag assertion や collection mutation の ABI assertion は再利用し、symbol 名が登録されているだけ・spec とその派生表が一致するだけでは実 call / export との適合を証明したとしない。
  - 完了条件: 001の ABI / bridge 移管項目を具体的な assertion と正常 / 異常系で覆い、`validate_runtime_abi_links.sh` と関連 Runtime / Lowering テストが green。既存除外・許可リストを拡大して green にする変更はしない。
- [ ] RF-GOLDEN-006: 安定した宣言キーを stdlib の実装方式によらない公開参照へ対応付ける（前提: 002・010）
  - 対象: `StableRenderContext` の外部参照 / 型 / signature の描画と Sema formatter。番号の廃止・型パラメータの位置正規化は010で完了させ、ここでは002の由来判定を使い、synthetic member alias / bundled extension / imported 宣言を同じ公開 API へ対応付ける追加の投影だけを実装する。
  - 戻り型・nullability・variance・境界・suspend・default / vararg・named argument に必要な引数名など、型検証と呼び出し識別に必要な契約を保持する。member alias と元の extension は由来・対応が証明できる場合だけ同じ公開参照へ写し、同名同 arity の別 overload やユーザー override は潰さない。runtime link 名を公開 API の安定IDに使わない。
  - 完了条件: 同じ公開 API の synthetic / source-backed / imported 表現は同じ参照となり、別 overload は区別されること。010の不変・感度テストを維持し、由来の違いを吸収する追加投影の既定出力への接続は008まで行わない。
- [ ] RF-GOLDEN-007: 通常 symbol 行を fixture 所有の宣言に限定する描画経路と情報保持テストを追加する（前提: 003・004・005・006・011・012・013）
  - 対象: `GoldenHarnessDump.renderSemaOutput` / `StableRenderContext.expandRequiredSymbols` と GoldenHarness tests。現在の参照収集で表示される fixture 所有の宣言・合成メンバを保持し、外部宣言の flags / sig / type 行を省く。未参照の fixture メンバ全列挙への変更は混ぜない。外部参照の中に現れる fixture の型や、実際の `targs` の収集まで止めず、別 library のメタデータも省く場合は001で検証先を確認する。
  - `call=` / `ref=` / 型は006の同じ公開参照表現で描画し、推論型・`targs=`・診断を維持する。専用ケースに限って011の明示対象メタデータ節を追加する。比較後の文字列置換で消すのではなく、所有と対象指定を持つ描画時点で分離する。既定出力は維持したまま新経路をテストから検証する。
  - 不変テスト: 公開 API が同じなら stdlib の由来・declSite・内部 flag / symbol ID・未参照宣言を変えても通常部分は同じ。専用側では対象のメタデータ変更だけが対応する節の差分になり、List の変更で List を型として参照するだけの他の専用ケースは変わらない。
  - 感度テスト: fixture 宣言・推論型・callee / overload・型制約・診断の変更は通常部分でも差分になる。ユーザーの synthetic data / enum / accessor / object literal が残ること、`kotlin.Enum.equals` 等の解決先変更を消さないことを確認する。重要 flag の誤設定は対象指定の Golden と004・005の挙動検証で検出する。
  - 完了条件: raw / normalized 双方で上記が green。専用対象が欠ける状態は失敗し、通常の行数を減らすだけでは通らないこと。描画が compiler の symbol / flags / binding を変更せず、空 package 注入や冪等性だけを情報保持の証明にしない。
- [ ] RF-GOLDEN-008: メンテナ確認後、通常 / 対象指定 Golden へ切り替えて §8 と効果を検証する（前提: 003・004・005・007・011・012・013 の全ゲート green）
  - 切り替え前に、省くメタデータと担当ケース、検証移管の網羅、更新件数への影響、`docs/stdlib-pipeline.md` §8 の改訂案をメンテナ確認する。新方針は「実装詳細だけの変化では通常 Golden を更新しない。公開 API / 解決先の意味変更・出力仕様移行時の更新は許容する」とし、決定的なロード順・stdlib diagnostics・diff 検証の要件は緩めない。
  - 対象: `GoldenHarnessAPI` / `GoldenHarnessDump` / Sema golden / 同文書 §8。007を既定にし、Sema suite のみ `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6` で再生成する。入力 `.kt` の分割・意味変更は混ぜず、専用対象メタデータが保存されていることを確認する。
  - 更新モードなしで同 suite と `GoldenHarnessPersistenceTests` / `GoldenHarnessSemaComparisonNormalizationTests` / `GoldenHarnessNormalizationInvariantTests` を再実行する。API・worker・保存 / 比較で専用対象が失われないことを確認し、正規化バイパスを再導入しない。Lexer / Parser / Diagnostics の出力は変更しない。
  - 効果検証: KSP-697 の106ケース（通常53・stdlib名53）を基準に、同等の対象メタデータ変更で通常側が不変、専用側の更新は契約の担当ケースに限定されることを確認する。1〜2ファイルという値を保証せず、変更された独立契約数・担当ファイル数・残る意味上の expr 差分を分けて実測・記録する。
  - 完了条件: RF 必須ゲートと移管テストが green。579ケース（着手時に件数再確認）の宣言・型・解決先・診断の情報を維持し、メタデータ担当の欠落・意図しない重複がないこと。§8 の正式改訂と通常 / 専用の両方向の回帰が揃うまで完了扱いにしない。
- [ ] RF-GOLDEN-009: Golden 表示のための nil declSite 互換処理をコンパイラから切り離す（前提: 008）
  - 対象: `HeaderCollection.predeclareBundledTupleHeaders` / Charset 先行登録 / `shouldRestoreDeclSiteForReusableSyntheticSymbol`、`PairTripleNominalAnchorTests`。まず Pair / Triple の nil declSite 要求を、正しい宣言所有・型解決・必要な flags と Golden の実装非依存性を確認するテストへ置き換える。
  - nil 維持の理由を Golden 都合と実際の compiler / metadata 互換性に分け、前者だけを解消する。`isSourceBackedSymbol`、external call / constructor lowering、metadata export / import の挙動が変わるため、source 化された全 shell に declSite を一律復元しない。`--no-stdlib` の fallback と Duration 等の既存例外を保持し、着手時に影響が広ければ nominal 群別の新IDへ分割する。
  - 完了条件: 型解決・source / artifact / no-stdlib の該当経路が green で、Golden 安定性のために宣言位置を偽装する必要がないこと。実行時に必要な互換処理は専用回帰テストとともに残し、単なる Golden の再更新で挙動差を隠さない。

---

## Stdlib gap audit 2.3.10 実装タスク（KSP-719+）

> 公式 Kotlin/Native 2.3.10 `klib dump-abi`（`official_native_stdlib_abi.txt`）を正典として、KSwiftK バンドル Kotlin ソース（`Sources/CompilerCore/Stdlib/kotlin/`）と比較した機械監査結果から生成。`kotlin.jvm` / `kotlin.internal` / `kotlin.native.internal` / `kotlin.test` / `kotlinx` / `java` / `javax` / wasm・web-only sourceset は除外。
> 1タスク = 原則 1 PR。粒度は（package, receiver）単位または 30 件を超える場合は関数名 prefix ファミリー単位。完全な未実装リストは `docs/stdlib-gap-audit-2.3.10/gap_v2.tsv`（本倉庫へのコピー推奨）を参照。
> 実装時には、既存の `__kk_*` / `kk_*` bridge・合成スタブ・`RuntimeABISpec` 登録があれば同 PR で削除または `__kk_` 降格し、`UPDATE_GOLDEN=1` で golden を更新、`bash Scripts/diff_kotlinc.sh` で kotlinc 2.3.10 との差分を確認すること。

- [ ] KSP-790: kotlin.uint-family の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin` / top-level / family `uint`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/uint.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_n_uint.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_n_uint.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_n_uint.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.uintArrayOf` — fun uintArrayOf(Array): UIntArray  -- `final inline fun kotlin/uintArrayOf(kotlin/UIntArray...): kotlin/UIntArray`
    - `kotlin.uintCompare` — fun uintCompare(Int, Int): Int  -- `final fun kotlin/uintCompare(kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.uintDivide` — fun uintDivide(UInt, UInt): UInt  -- `final fun kotlin/uintDivide(kotlin/UInt, kotlin/UInt): kotlin/UInt`
    - `kotlin.uintRemainder` — fun uintRemainder(UInt, UInt): UInt  -- `final fun kotlin/uintRemainder(kotlin/UInt, kotlin/UInt): kotlin/UInt`
    - `kotlin.uintToDouble` — fun uintToDouble(Int): Double  -- `final fun kotlin/uintToDouble(kotlin/Int): kotlin/Double`
    - `kotlin.uintToFloat` — fun uintToFloat(Int): Float  -- `final inline fun kotlin/uintToFloat(kotlin/Int): kotlin/Float`
    - `kotlin.uintToLong` — fun uintToLong(Int): Long  -- `final inline fun kotlin/uintToLong(kotlin/Int): kotlin/Long`
    - `kotlin.uintToULong` — fun uintToULong(Int): ULong  -- `final inline fun kotlin/uintToULong(kotlin/Int): kotlin/ULong`

- [ ] KSP-791: kotlin.ulong-family の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin` / top-level / family `ulong`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ulong.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_n_ulong.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_n_ulong.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_n_ulong.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ulongArrayOf` — fun ulongArrayOf(Array): ULongArray  -- `final inline fun kotlin/ulongArrayOf(kotlin/ULongArray...): kotlin/ULongArray`
    - `kotlin.ulongCompare` — fun ulongCompare(Long, Long): Int  -- `final fun kotlin/ulongCompare(kotlin/Long, kotlin/Long): kotlin/Int`
    - `kotlin.ulongDivide` — fun ulongDivide(ULong, ULong): ULong  -- `final fun kotlin/ulongDivide(kotlin/ULong, kotlin/ULong): kotlin/ULong`
    - `kotlin.ulongRemainder` — fun ulongRemainder(ULong, ULong): ULong  -- `final fun kotlin/ulongRemainder(kotlin/ULong, kotlin/ULong): kotlin/ULong`
    - `kotlin.ulongToDouble` — fun ulongToDouble(Long): Double  -- `final fun kotlin/ulongToDouble(kotlin/Long): kotlin/Double`
    - `kotlin.ulongToFloat` — fun ulongToFloat(Long): Float  -- `final inline fun kotlin/ulongToFloat(kotlin/Long): kotlin/Float`

- [ ] KSP-803: kotlin.Lazy の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin` / receiver `Lazy`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/Lazy.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_Lazy_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_Lazy_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_Lazy_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.getValue` — fun Lazy.getValue(Any, KProperty): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/Lazy<#A>).kotlin/getValue(kotlin/Any?, kotlin.reflect/KProperty<*>): #A`

- [ ] KSP-807: kotlin.Array top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.Array` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/Array/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_Array_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_Array_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_Array_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.Array.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.Array.<init>` — constructor (Int, Function1)  -- `constructor <init>(kotlin/Int, kotlin/Function1<kotlin/Int, #A>)`

- [x] KSP-811: kotlin.BooleanArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.BooleanArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/BooleanArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_BooleanArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_BooleanArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_BooleanArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.BooleanArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.BooleanArray.<init>` — constructor (Int, Function1)  -- `constructor <init>(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Boolean>)`

- [x] KSP-813: kotlin.Byte.Companion.Companion の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.Byte.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/Byte/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_Byte_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_Byte_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_Byte_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: Kotlin 2.3.10 の `Byte.Companion` 契約に合わせ、4 APIをsource-backed `public val` getterとして実装。ByteはTypeSystem上のprimitiveでsource declarationがないため、Companionのnominal anchorを追加し、Byte専用のSema numeric fallback（誤ったInt型返却）を削除した。直接参照・明示Companion receiver・Byte/Intの型・`Any` boxingと`is Byte`を専用Golden/diffで固定し、Byte同型 `toByte()` のno-op loweringも回帰修正した。Runtime/ABI bridgeは存在しないため変更していない。
  - 検証: focused Sema Golden shard（`UPDATE_GOLDEN=1`）/ `stdlib_kotlin_Byte_Companion_Companion_n.kt` の `diff_kotlinc` / Golden normalization invariant / `check_todo_ids.sh` / `validate_runtime_abi_links.sh` がpass。
  - 実装シンボル一覧:
    - `kotlin.Byte.Companion.MAX_VALUE` — val Companion.MAX_VALUE: Byte  -- `final const val MAX_VALUE`
    - `kotlin.Byte.Companion.MIN_VALUE` — val Companion.MIN_VALUE: Byte  -- `final const val MIN_VALUE`
    - `kotlin.Byte.Companion.SIZE_BITS` — val Companion.SIZE_BITS: Int  -- `final const val SIZE_BITS`
    - `kotlin.Byte.Companion.SIZE_BYTES` — val Companion.SIZE_BYTES: Int  -- `final const val SIZE_BYTES`

- [ ] KSP-814: kotlin.ByteArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.ByteArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ByteArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ByteArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ByteArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ByteArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ByteArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.ByteArray.<init>` — constructor (Int, Function1)  -- `constructor <init>(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Byte>)`

- [ ] KSP-815: kotlin.Char.Companion.Companion の未実装 stdlib API を実装する（15 件）
  - 対象: `kotlin.Char.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/Char/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_Char_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_Char_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_Char_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.Char.Companion.MAX_CODE_POINT` — val Companion.MAX_CODE_POINT: Int  -- `final const val MAX_CODE_POINT`
    - `kotlin.Char.Companion.MAX_HIGH_SURROGATE` — val Companion.MAX_HIGH_SURROGATE: Char  -- `final const val MAX_HIGH_SURROGATE`
    - `kotlin.Char.Companion.MAX_LOW_SURROGATE` — val Companion.MAX_LOW_SURROGATE: Char  -- `final const val MAX_LOW_SURROGATE`
    - `kotlin.Char.Companion.MAX_RADIX` — val Companion.MAX_RADIX: Int  -- `final const val MAX_RADIX`
    - `kotlin.Char.Companion.MAX_SURROGATE` — val Companion.MAX_SURROGATE: Char  -- `final const val MAX_SURROGATE`
    - `kotlin.Char.Companion.MAX_VALUE` — val Companion.MAX_VALUE: Char  -- `final const val MAX_VALUE`
    - `kotlin.Char.Companion.MIN_CODE_POINT` — val Companion.MIN_CODE_POINT: Int  -- `final const val MIN_CODE_POINT`
    - `kotlin.Char.Companion.MIN_HIGH_SURROGATE` — val Companion.MIN_HIGH_SURROGATE: Char  -- `final const val MIN_HIGH_SURROGATE`
    - `kotlin.Char.Companion.MIN_LOW_SURROGATE` — val Companion.MIN_LOW_SURROGATE: Char  -- `final const val MIN_LOW_SURROGATE`
    - `kotlin.Char.Companion.MIN_RADIX` — val Companion.MIN_RADIX: Int  -- `final const val MIN_RADIX`
    - `kotlin.Char.Companion.MIN_SUPPLEMENTARY_CODE_POINT` — val Companion.MIN_SUPPLEMENTARY_CODE_POINT: Int  -- `final const val MIN_SUPPLEMENTARY_CODE_POINT`
    - `kotlin.Char.Companion.MIN_SURROGATE` — val Companion.MIN_SURROGATE: Char  -- `final const val MIN_SURROGATE`
    - `kotlin.Char.Companion.MIN_VALUE` — val Companion.MIN_VALUE: Char  -- `final const val MIN_VALUE`
    - `kotlin.Char.Companion.SIZE_BITS` — val Companion.SIZE_BITS: Int  -- `final const val SIZE_BITS`
    - `kotlin.Char.Companion.SIZE_BYTES` — val Companion.SIZE_BYTES: Int  -- `final const val SIZE_BYTES`

- [ ] KSP-819: kotlin.Comparable.Comparable の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.Comparable` / receiver `Comparable`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/Comparable/Comparable.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_Comparable_Comparable_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_Comparable_Comparable_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_Comparable_Comparable_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.Comparable.compareTo` — fun Comparable.compareTo(): Int  -- `abstract fun compareTo(#A): kotlin/Int`

- [ ] KSP-827: kotlin.DeepRecursiveScope.DeepRecursiveScope の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.DeepRecursiveScope` / receiver `DeepRecursiveScope`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/DeepRecursiveScope/DeepRecursiveScope.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_DeepRecursiveScope_DeepRecursiveScope_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_DeepRecursiveScope_DeepRecursiveScope_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_DeepRecursiveScope_DeepRecursiveScope_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.DeepRecursiveScope.callRecursive` — fun DeepRecursiveScope.callRecursive(): #B  -- `abstract suspend fun callRecursive(#A): #B`

- [ ] KSP-833: kotlin.Double.Companion.Companion の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.Double.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/Double/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_Double_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_Double_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_Double_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.Double.Companion.MAX_VALUE` — val Companion.MAX_VALUE: Double  -- `final const val MAX_VALUE`
    - `kotlin.Double.Companion.MIN_VALUE` — val Companion.MIN_VALUE: Double  -- `final const val MIN_VALUE`
    - `kotlin.Double.Companion.NEGATIVE_INFINITY` — val Companion.NEGATIVE_INFINITY: Double  -- `final const val NEGATIVE_INFINITY`
    - `kotlin.Double.Companion.NaN` — val Companion.NaN: Double  -- `final const val NaN`
    - `kotlin.Double.Companion.POSITIVE_INFINITY` — val Companion.POSITIVE_INFINITY: Double  -- `final const val POSITIVE_INFINITY`
    - `kotlin.Double.Companion.SIZE_BITS` — val Companion.SIZE_BITS: Int  -- `final const val SIZE_BITS`
    - `kotlin.Double.Companion.SIZE_BYTES` — val Companion.SIZE_BYTES: Int  -- `final const val SIZE_BYTES`

- [ ] KSP-834: kotlin.DoubleArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.DoubleArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/DoubleArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_DoubleArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_DoubleArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_DoubleArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.DoubleArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.DoubleArray.<init>` — constructor (Int, Function1)  -- `constructor <init>(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Double>)`

- [x] KSP-847: kotlin.Float.Companion.Companion の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.Float.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/Float/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_Float_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_Float_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_Float_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.Float.Companion.MAX_VALUE` — val Companion.MAX_VALUE: Float  -- `final const val MAX_VALUE`
    - `kotlin.Float.Companion.MIN_VALUE` — val Companion.MIN_VALUE: Float  -- `final const val MIN_VALUE`
    - `kotlin.Float.Companion.NEGATIVE_INFINITY` — val Companion.NEGATIVE_INFINITY: Float  -- `final const val NEGATIVE_INFINITY`
    - `kotlin.Float.Companion.NaN` — val Companion.NaN: Float  -- `final const val NaN`
    - `kotlin.Float.Companion.POSITIVE_INFINITY` — val Companion.POSITIVE_INFINITY: Float  -- `final const val POSITIVE_INFINITY`
    - `kotlin.Float.Companion.SIZE_BITS` — val Companion.SIZE_BITS: Int  -- `final const val SIZE_BITS`
    - `kotlin.Float.Companion.SIZE_BYTES` — val Companion.SIZE_BYTES: Int  -- `final const val SIZE_BYTES`
  - 完了根拠: `Companion.kt` を source-backed で追加し、7 件の Float 型・値、直接参照と明示 Companion receiver、IEEE 754 bit pattern を Sema Golden と diff 回帰で固定。Float 専用の名称ベース fallback と `kk_float_*` Runtime/ABI bridge を削除した。

- [~] KSP-874: kotlin.Pair top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.Pair` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/Pair/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_Pair_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_Pair_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_Pair_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.Pair.<init>` — constructor (, )  -- `constructor <init>(#A, #B)`
  - 実装済み（ゲート保留）: `Sources/CompilerCore/Stdlib/kotlin/Pair/Stdlib.kt` に constructor の source owner を追加。`__kk_pair_new` は collection/sequence が共有する Pair box allocation bridge のため残置。Pair 単体 diff、TODO ID、Runtime ABI link は pass 済みだが、全 Golden / 全 diff_cases は共有実行環境の timeout/SIGTERM で未完了。

- [ ] KSP-927: kotlin.collections.AbstractList-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `AbstractList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_AbstractList.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_AbstractList.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_AbstractList.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractList` — class kotlin.collections.AbstractList  -- `abstract class <#A: out kotlin/Any?> kotlin.collections/AbstractList : kotlin.collections/AbstractCollection<#A>, kotlin.collections/List<#A> {`

- [ ] KSP-933: kotlin.collections.ArrayList-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `ArrayList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_ArrayList.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_ArrayList.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_ArrayList.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.ArrayList` — class kotlin.collections.ArrayList  -- `final class <#A: kotlin/Any?> kotlin.collections/ArrayList : kotlin.collections/AbstractMutableList<#A>, kotlin.collections/MutableList<#A>, kotlin.collections/RandomAccess {`

- [ ] KSP-937: kotlin.collections.Iterable-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections` / top-level / family `Iterable`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/IterableAggregateHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_Iterable.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_Iterable.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_Iterable.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Iterable` — interface kotlin.collections.Iterable  -- `abstract interface <#A: out kotlin/Any?> kotlin.collections/Iterable {`
    - `kotlin.collections.Iterable` — fun Iterable(Function0): Iterable  -- `final inline fun <#A: kotlin/Any?> kotlin.collections/Iterable(crossinline kotlin/Function0<kotlin.collections/Iterator<#A>>): kotlin.collections/Iterable<#A>`

- [ ] KSP-938: kotlin.collections.Iterator-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `Iterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractIterator.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_Iterator.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_Iterator.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_Iterator.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Iterator` — interface kotlin.collections.Iterator  -- `abstract interface <#A: out kotlin/Any?> kotlin.collections/Iterator {`

- [ ] KSP-939: kotlin.collections.List-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections` / top-level / family `List`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ListAccessHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_List.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_List.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_List.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.List` — interface kotlin.collections.List  -- `abstract interface <#A: out kotlin/Any?> kotlin.collections/List : kotlin.collections/Collection<#A> {`
    - `kotlin.collections.List` — fun List(Int, Function1): List  -- `final inline fun <#A: kotlin/Any?> kotlin.collections/List(kotlin/Int, kotlin/Function1<kotlin/Int, #A>): kotlin.collections/List<#A>`

- [ ] KSP-941: kotlin.collections.Map-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `Map`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MapHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_Map.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_Map.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_Map.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Map` — interface kotlin.collections.Map  -- `abstract interface <#A: kotlin/Any?, #B: out kotlin/Any?> kotlin.collections/Map {`

- [ ] KSP-942: kotlin.collections.MutableCollection-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `MutableCollection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMutableCollection.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_MutableCollection.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_MutableCollection.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_MutableCollection.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableCollection` — interface kotlin.collections.MutableCollection  -- `abstract interface <#A: kotlin/Any?> kotlin.collections/MutableCollection : kotlin.collections/Collection<#A>, kotlin.collections/MutableIterable<#A> {`

- [ ] KSP-946: kotlin.collections.MutableMap-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `MutableMap`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableMap.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_MutableMap.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_MutableMap.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_MutableMap.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableMap` — interface kotlin.collections.MutableMap  -- `abstract interface <#A: kotlin/Any?, #B: kotlin/Any?> kotlin.collections/MutableMap : kotlin.collections/Map<#A, #B> {`

- [ ] KSP-947: kotlin.collections.MutableSet-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / top-level / family `MutableSet`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableSet.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_MutableSet.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_MutableSet.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_MutableSet.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableSet` — interface kotlin.collections.MutableSet  -- `abstract interface <#A: kotlin/Any?> kotlin.collections/MutableSet : kotlin.collections/MutableCollection<#A>, kotlin.collections/Set<#A> {`

- [ ] KSP-949: kotlin.collections.array-family の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.collections` / top-level / family `array`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayAggregateHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_array.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_array.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_array.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.arrayListOf` — fun arrayListOf(): ArrayList  -- `final inline fun <#A: kotlin/Any?> kotlin.collections/arrayListOf(): kotlin.collections/ArrayList<#A>`
    - `kotlin.collections.arrayListOf` — fun arrayListOf(Array): ArrayList  -- `final fun <#A: kotlin/Any?> kotlin.collections/arrayListOf(kotlin/Array<out #A>...): kotlin.collections/ArrayList<#A>`
    - `kotlin.collections.arrayOfUninitializedElements` — fun arrayOfUninitializedElements(Int): Array  -- `final inline fun <#A: kotlin/Any?> kotlin.collections/arrayOfUninitializedElements(kotlin/Int): kotlin/Array<#A>`

- [ ] KSP-957: kotlin.collections.on-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.collections` / top-level / family `on`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractCollection.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_on.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_n_on.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_n_on.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.onEach` — fun onEach(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/Iterable<#A>> (#B).kotlin.collections/onEach(kotlin/Function1<#A, kotlin/Unit>): #B`
    - `kotlin.collections.onEach` — fun onEach(Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/Map<out #A, #B>> (#C).kotlin.collections/onEach(kotlin/Function1<kotlin.collections/Map.Entry<#A, #B>, kotlin/Unit>): #C`
    - `kotlin.collections.onEachIndexed` — fun onEachIndexed(Function2): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/Iterable<#A>> (#B).kotlin.collections/onEachIndexed(kotlin/Function2<kotlin/Int, #A, kotlin/Unit>): #B`
    - `kotlin.collections.onEachIndexed` — fun onEachIndexed(Function2): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/Map<out #A, #B>> (#C).kotlin.collections/onEachIndexed(kotlin/Function2<kotlin/Int, kotlin.collections/Map.Entry<#A, #B>, kotlin/Unit>): #C`

- [x] KSP-961: kotlin.collections.Entry の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.collections` / receiver `Entry`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Entry.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Entry_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Entry_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Entry_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.component1` — fun Entry.component1(): #A  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Map.Entry<#A, #B>).kotlin.collections/component1(): #A`
    - `kotlin.collections.component2` — fun Entry.component2(): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Map.Entry<#A, #B>).kotlin.collections/component2(): #B`
    - `kotlin.collections.toPair` — fun Entry.toPair(): Pair  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Map.Entry<#A, #B>).kotlin.collections/toPair(): kotlin/Pair<#A, #B>`
  - 完了根拠（2026-09-04）: Kotlin 2.3.10 の `libraries/stdlib/src/kotlin/collections/Maps.kt` に一致する `@kotlin.internal.InlineOnly` の `component1` / `component2` / `toPair` を `Entry.kt` に source-backed 実装し、Map.Entry receiver の型・順序・Pair 生成契約を保持した。Map.Entry の component1/component2 synthetic alias は bundled declaration index で source-backed extension を優先するよう抑止し、専用 `kk_map_entry_to_pair` runtime export と ABI parity 登録を削除した。`__kk_pair_first` / `__kk_pair_second` は Map.Entry.key/value と Pair の共有 bridge のため維持した。
  - 回帰: 専用 Sema 回帰で3 call binding が package-level bundled source（外部リンクなし）になり nested synthetic alias が残らないこと、Golden で型と call routing、`diff_kotlinc` で実行結果を固定した。

- [ ] KSP-962: kotlin.collections.Grouping の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.collections` / receiver `Grouping`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Grouping.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Grouping_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Grouping_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Grouping_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.aggregateTo` — fun Grouping.aggregateTo(, Function4): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, #C>> (kotlin.collections/Grouping<#A, #B>).kotlin.collections/aggregateTo(#D, kotlin/Function4<#B, #C?, #A, kotlin/Boolean, #C>): #D`
    - `kotlin.collections.eachCountTo` — fun Grouping.eachCountTo(): #C  -- `final fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #B, kotlin/Int>> (kotlin.collections/Grouping<#A, #B>).kotlin.collections/eachCountTo(#C): #C`
    - `kotlin.collections.foldTo` — fun Grouping.foldTo(, , Function2): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, #C>> (kotlin.collections/Grouping<#A, #B>).kotlin.collections/foldTo(#D, #C, kotlin/Function2<#C, #A, #C>): #D`
    - `kotlin.collections.foldTo` — fun Grouping.foldTo(, Function2, Function3): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, #C>> (kotlin.collections/Grouping<#A, #B>).kotlin.collections/foldTo(#D, kotlin/Function2<#B, #A, #C>, kotlin/Function3<#B, #C, #A, #C>): #D`
    - `kotlin.collections.reduceTo` — fun Grouping.reduceTo(, Function3): #D  -- `final inline fun <#A: kotlin/Any?, #B: #A, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #C, #A>> (kotlin.collections/Grouping<#B, #C>).kotlin.collections/reduceTo(#D, kotlin/Function3<#C, #A, #B, #A>): #D`

- [x] KSP-964: kotlin.collections.Iterable.associate-family の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.collections` / receiver `Iterable` / family `associate`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterables.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_associate.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_associate.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_associate.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠（2026-09-04、KSP-964）: `Iterables.kt` に公式 Kotlin 2.3.10 の `Iterable.associate` / `associateBy` / `associateByTo` / `associateTo` / `associateWith` / `associateWithTo` 8 overloadsを source-backed 実装した。対象専用の Runtime bridge、synthetic stub、RuntimeABI、CallTypeChecker/CallLowerer 特例は現行 master に存在せず、既存の List/Sequence ownership は変更していない。
  - 回帰: Sema で静的・ユーザー定義 `Iterable` と既存 `List` の owner/型引数を固定し、diff ケースで custom one-shot Iterable、重複キーの最終値、宛先 map の同一性・既存値保持を Kotlin 2.3.10 と比較した。
  - 未実装シンボル一覧:
    - `kotlin.collections.associate` — fun Iterable.associate(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/associate(kotlin/Function1<#A, kotlin/Pair<#B, #C>>): kotlin.collections/Map<#B, #C>`
    - `kotlin.collections.associateBy` — fun Iterable.associateBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/associateBy(kotlin/Function1<#A, #B>): kotlin.collections/Map<#B, #A>`
    - `kotlin.collections.associateBy` — fun Iterable.associateBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/associateBy(kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): kotlin.collections/Map<#B, #C>`
    - `kotlin.collections.associateByTo` — fun Iterable.associateByTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #B, in #A>> (kotlin.collections/Iterable<#A>).kotlin.collections/associateByTo(#C, kotlin/Function1<#A, #B>): #C`
    - `kotlin.collections.associateByTo` — fun Iterable.associateByTo(, Function1, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, in #C>> (kotlin.collections/Iterable<#A>).kotlin.collections/associateByTo(#D, kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): #D`
    - `kotlin.collections.associateTo` — fun Iterable.associateTo(, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, in #C>> (kotlin.collections/Iterable<#A>).kotlin.collections/associateTo(#D, kotlin/Function1<#A, kotlin/Pair<#B, #C>>): #D`
    - `kotlin.collections.associateWith` — fun Iterable.associateWith(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/associateWith(kotlin/Function1<#A, #B>): kotlin.collections/Map<#A, #B>`
    - `kotlin.collections.associateWithTo` — fun Iterable.associateWithTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, in #B>> (kotlin.collections/Iterable<#A>).kotlin.collections/associateWithTo(#C, kotlin/Function1<#A, #B>): #C`

- [ ] KSP-966: kotlin.collections.Iterable.collection-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections` / receiver `Iterable` / family `collection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterables.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_collection.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_collection.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_collection.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.collectionSizeOrDefault` — fun Iterable.collectionSizeOrDefault(Int): Int  -- `final fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/collectionSizeOrDefault(kotlin/Int): kotlin/Int`
    - `kotlin.collections.collectionSizeOrNull` — fun Iterable.collectionSizeOrNull(): Int  -- `final fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/collectionSizeOrNull(): kotlin/Int?`

- [ ] KSP-967: kotlin.collections.Iterable.contains-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / receiver `Iterable` / family `contains`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterables.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_contains.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_contains.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_contains.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.contains` — fun Iterable.contains(): Boolean  -- `final fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/contains(#A): kotlin/Boolean`

- [ ] KSP-977: kotlin.collections.Iterable.for-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / receiver `Iterable` / family `for`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterators.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_for.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_for.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_for.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.forEach` — fun Iterable.forEach(Function1): Unit  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/forEach(kotlin/Function1<#A, kotlin/Unit>)`

- [ ] KSP-978: kotlin.collections.Iterable.group-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.collections` / receiver `Iterable` / family `group`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterables.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_group.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_group.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_group.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.groupBy` — fun Iterable.groupBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/groupBy(kotlin/Function1<#A, #B>): kotlin.collections/Map<#B, kotlin.collections/List<#A>>`
    - `kotlin.collections.groupBy` — fun Iterable.groupBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/groupBy(kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): kotlin.collections/Map<#B, kotlin.collections/List<#C>>`
    - `kotlin.collections.groupByTo` — fun Iterable.groupByTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #B, kotlin.collections/MutableList<#A>>> (kotlin.collections/Iterable<#A>).kotlin.collections/groupByTo(#C, kotlin/Function1<#A, #B>): #C`
    - `kotlin.collections.groupByTo` — fun Iterable.groupByTo(, Function1, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, kotlin.collections/MutableList<#C>>> (kotlin.collections/Iterable<#A>).kotlin.collections/groupByTo(#D, kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): #D`

- [ ] KSP-980: kotlin.collections.Iterable.join-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections` / receiver `Iterable` / family `join`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterables.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_join.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_join.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_join.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.joinTo` — fun Iterable.joinTo(, CharSequence, CharSequence, CharSequence, Int, CharSequence, Function1): #B  -- `final fun <#A: kotlin/Any?, #B: kotlin.text/Appendable> (kotlin.collections/Iterable<#A>).kotlin.collections/joinTo(#B, kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/Int = ..., kotlin/CharSequence = ..., kotlin/Function1<#A, kotlin/CharSequence>? = ...): #B`
    - `kotlin.collections.joinToString` — fun Iterable.joinToString(CharSequence, CharSequence, CharSequence, Int, CharSequence, Function1): String  -- `final fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/joinToString(kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/Int = ..., kotlin/CharSequence = ..., kotlin/Function1<#A, kotlin/CharSequence>? = ...): kotlin/String`

- [ ] KSP-984: kotlin.collections.Iterable.min-family の未実装 stdlib API を実装する（18 件）
  - 対象: `kotlin.collections` / receiver `Iterable` / family `min`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterables.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_min.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_min.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_min.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.min` — fun Iterable.min(): Double  -- `final fun (kotlin.collections/Iterable<kotlin/Double>).kotlin.collections/min(): kotlin/Double`
    - `kotlin.collections.min` — fun Iterable.min(): Float  -- `final fun (kotlin.collections/Iterable<kotlin/Float>).kotlin.collections/min(): kotlin/Float`
    - `kotlin.collections.min` — fun Iterable.min(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (kotlin.collections/Iterable<#A>).kotlin.collections/min(): #A`
    - `kotlin.collections.minBy` — fun Iterable.minBy(Function1): #A  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.collections/Iterable<#A>).kotlin.collections/minBy(kotlin/Function1<#A, #B>): #A`
    - `kotlin.collections.minByOrNull` — fun Iterable.minByOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.collections/Iterable<#A>).kotlin.collections/minByOrNull(kotlin/Function1<#A, #B>): #A?`
    - `kotlin.collections.minOf` — fun Iterable.minOf(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.collections/Iterable<#A>).kotlin.collections/minOf(kotlin/Function1<#A, #B>): #B`
    - `kotlin.collections.minOf` — fun Iterable.minOf(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/minOf(kotlin/Function1<#A, kotlin/Double>): kotlin/Double`
    - `kotlin.collections.minOf` — fun Iterable.minOf(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/minOf(kotlin/Function1<#A, kotlin/Float>): kotlin/Float`
    - `kotlin.collections.minOfOrNull` — fun Iterable.minOfOrNull(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.collections/Iterable<#A>).kotlin.collections/minOfOrNull(kotlin/Function1<#A, #B>): #B?`
    - `kotlin.collections.minOfOrNull` — fun Iterable.minOfOrNull(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/minOfOrNull(kotlin/Function1<#A, kotlin/Double>): kotlin/Double?`
    - `kotlin.collections.minOfOrNull` — fun Iterable.minOfOrNull(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/minOfOrNull(kotlin/Function1<#A, kotlin/Float>): kotlin/Float?`
    - `kotlin.collections.minOfWith` — fun Iterable.minOfWith(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/minOfWith(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B`
    - `kotlin.collections.minOfWithOrNull` — fun Iterable.minOfWithOrNull(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/minOfWithOrNull(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B?`
    - `kotlin.collections.minOrNull` — fun Iterable.minOrNull(): Double  -- `final fun (kotlin.collections/Iterable<kotlin/Double>).kotlin.collections/minOrNull(): kotlin/Double?`
    - `kotlin.collections.minOrNull` — fun Iterable.minOrNull(): Float  -- `final fun (kotlin.collections/Iterable<kotlin/Float>).kotlin.collections/minOrNull(): kotlin/Float?`
    - `kotlin.collections.minOrNull` — fun Iterable.minOrNull(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (kotlin.collections/Iterable<#A>).kotlin.collections/minOrNull(): #A?`
    - `kotlin.collections.minWith` — fun Iterable.minWith(Comparator): #A  -- `final fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/minWith(kotlin/Comparator<in #A>): #A`
    - `kotlin.collections.minWithOrNull` — fun Iterable.minWithOrNull(Comparator): #A  -- `final fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/minWithOrNull(kotlin/Comparator<in #A>): #A?`

- [ ] KSP-986: kotlin.collections.Iterable.none-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections` / receiver `Iterable` / family `none`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterables.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_none.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_none.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_none.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.none` — fun Iterable.none(): Boolean  -- `final fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/none(): kotlin/Boolean`
    - `kotlin.collections.none` — fun Iterable.none(Function1): Boolean  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/Iterable<#A>).kotlin.collections/none(kotlin/Function1<#A, kotlin/Boolean>): kotlin/Boolean`

- [ ] KSP-1001: kotlin.collections.List の未実装 stdlib API を実装する（28 件）
  - 対象: `kotlin.collections` / receiver `List`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ListSearchHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_List_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_List_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_List_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.component1` — fun List.component1(): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/component1(): #A`
    - `kotlin.collections.component2` — fun List.component2(): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/component2(): #A`
    - `kotlin.collections.component3` — fun List.component3(): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/component3(): #A`
    - `kotlin.collections.component4` — fun List.component4(): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/component4(): #A`
    - `kotlin.collections.component5` — fun List.component5(): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/component5(): #A`
    - `kotlin.collections.elementAt` — fun List.elementAt(Int): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/elementAt(kotlin/Int): #A`
    - `kotlin.collections.elementAtOrElse` — fun List.elementAtOrElse(Int, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/elementAtOrElse(kotlin/Int, kotlin/Function1<kotlin/Int, #A>): #A`
    - `kotlin.collections.elementAtOrNull` — fun List.elementAtOrNull(Int): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/elementAtOrNull(kotlin/Int): #A?`
    - `kotlin.collections.findLast` — fun List.findLast(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/findLast(kotlin/Function1<#A, kotlin/Boolean>): #A?`
    - `kotlin.collections.first` — fun List.first(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/first(): #A`
    - `kotlin.collections.firstOrNull` — fun List.firstOrNull(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/firstOrNull(): #A?`
    - `kotlin.collections.foldRight` — fun List.foldRight(, Function2): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/foldRight(#B, kotlin/Function2<#A, #B, #B>): #B`
    - `kotlin.collections.foldRightIndexed` — fun List.foldRightIndexed(, Function3): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/foldRightIndexed(#B, kotlin/Function3<kotlin/Int, #A, #B, #B>): #B`
    - `kotlin.collections.getOrElse` — fun List.getOrElse(Int, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/getOrElse(kotlin/Int, kotlin/Function1<kotlin/Int, #A>): #A`
    - `kotlin.collections.getOrNull` — fun List.getOrNull(Int): #A  -- `final fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/getOrNull(kotlin/Int): #A?`
    - `kotlin.collections.last` — fun List.last(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/last(): #A`
    - `kotlin.collections.last` — fun List.last(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/last(kotlin/Function1<#A, kotlin/Boolean>): #A`
    - `kotlin.collections.lastIndex` — val List.lastIndex  -- `final val kotlin.collections/lastIndex`
    - `kotlin.collections.lastOrNull` — fun List.lastOrNull(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/lastOrNull(): #A?`
    - `kotlin.collections.lastOrNull` — fun List.lastOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/lastOrNull(kotlin/Function1<#A, kotlin/Boolean>): #A?`
    - `kotlin.collections.reduceRight` — fun List.reduceRight(Function2): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.collections/List<#B>).kotlin.collections/reduceRight(kotlin/Function2<#B, #A, #A>): #A`
    - `kotlin.collections.reduceRightIndexed` — fun List.reduceRightIndexed(Function3): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.collections/List<#B>).kotlin.collections/reduceRightIndexed(kotlin/Function3<kotlin/Int, #B, #A, #A>): #A`
    - `kotlin.collections.reduceRightIndexedOrNull` — fun List.reduceRightIndexedOrNull(Function3): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.collections/List<#B>).kotlin.collections/reduceRightIndexedOrNull(kotlin/Function3<kotlin/Int, #B, #A, #A>): #A?`
    - `kotlin.collections.reduceRightOrNull` — fun List.reduceRightOrNull(Function2): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.collections/List<#B>).kotlin.collections/reduceRightOrNull(kotlin/Function2<#B, #A, #A>): #A?`
    - `kotlin.collections.requireNoNulls` — fun List.requireNoNulls(): List  -- `final fun <#A: kotlin/Any> (kotlin.collections/List<#A?>).kotlin.collections/requireNoNulls(): kotlin.collections/List<#A>`
    - `kotlin.collections.single` — fun List.single(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/single(): #A`
    - `kotlin.collections.singleOrNull` — fun List.singleOrNull(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/singleOrNull(): #A?`
    - `kotlin.collections.slice` — fun List.slice(IntRange): List  -- `final fun <#A: kotlin/Any?> (kotlin.collections/List<#A>).kotlin.collections/slice(kotlin.ranges/IntRange): kotlin.collections/List<#A>`

- [x] KSP-1006: kotlin.collections.Map.filter-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections` / receiver `Map` / family `filter`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MapHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Map_filter.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Map_filter.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Map_filter.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: Kotlin 2.3.10 の `Maps.kt` に合わせ、`MapHOF.kt` に `Map<out K, V>` と `M : MutableMap<in K, in V>` の `filterTo` / `filterNotTo` を source-backed 実装した。Map source-binding 特例にも2シンボルを追加し、Runtime ABI・Map synthetic stub は対象登録がないため変更していない。
  - 回帰: 専用 Sema Golden で source-backed callee・型引数・destination 戻り値を固定し、専用 kotlinc diff / Backend で destination identity、既存値の上書き、挿入順、empty/nullable、predicate 例外時の部分反映を確認する。
  - 未実装シンボル一覧:
    - `kotlin.collections.filterNotTo` — fun Map.filterNotTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, in #B>> (kotlin.collections/Map<out #A, #B>).kotlin.collections/filterNotTo(#C, kotlin/Function1<kotlin.collections/Map.Entry<#A, #B>, kotlin/Boolean>): #C`
    - `kotlin.collections.filterTo` — fun Map.filterTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, in #B>> (kotlin.collections/Map<out #A, #B>).kotlin.collections/filterTo(#C, kotlin/Function1<kotlin.collections/Map.Entry<#A, #B>, kotlin/Boolean>): #C`

- [ ] KSP-1012: kotlin.collections.Map.map-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.collections` / receiver `Map` / family `map`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MapHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Map_map.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Map_map.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Map_map.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.mapKeysTo` — fun Map.mapKeysTo(, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #C, in #B>> (kotlin.collections/Map<out #A, #B>).kotlin.collections/mapKeysTo(#D, kotlin/Function1<kotlin.collections/Map.Entry<#A, #B>, #C>): #D`
    - `kotlin.collections.mapNotNullTo` — fun Map.mapNotNullTo(, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any, #D: kotlin.collections/MutableCollection<in #C>> (kotlin.collections/Map<out #A, #B>).kotlin.collections/mapNotNullTo(#D, kotlin/Function1<kotlin.collections/Map.Entry<#A, #B>, #C?>): #D`
    - `kotlin.collections.mapTo` — fun Map.mapTo(, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableCollection<in #C>> (kotlin.collections/Map<out #A, #B>).kotlin.collections/mapTo(#D, kotlin/Function1<kotlin.collections/Map.Entry<#A, #B>, #C>): #D`
    - `kotlin.collections.mapValuesTo` — fun Map.mapValuesTo(, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #A, in #C>> (kotlin.collections/Map<out #A, #B>).kotlin.collections/mapValuesTo(#D, kotlin/Function1<kotlin.collections/Map.Entry<#A, #B>, #C>): #D`

- [ ] KSP-1015: kotlin.collections.Map.minus-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections` / receiver `Map` / family `minus`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MapHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Map_minus.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Map_minus.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Map_minus.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.minus` — fun Map.minus(Sequence): Map  -- `final fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Map<out #A, #B>).kotlin.collections/minus(kotlin.sequences/Sequence<#A>): kotlin.collections/Map<#A, #B>`
    - `kotlin.collections.minus` — fun Map.minus(Array): Map  -- `final fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Map<out #A, #B>).kotlin.collections/minus(kotlin/Array<out #A>): kotlin.collections/Map<#A, #B>`

- [x] KSP-1016: kotlin.collections.Map.none-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections` / receiver `Map` / family `none`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MapHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Map_none.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Map_none.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Map_none.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.none` — fun Map.none(): Boolean  -- `final fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.collections/Map<out #A, #B>).kotlin.collections/none(): kotlin/Boolean`
  - 完了根拠（2026-09-04監査）: merged PR #6216（merge commit `346c18370d218126ded5fac35fd9e3a5ec5c2bb4`）で `Map<out K, V>.none(): Boolean` を `MapHOF.kt` に source-backed 実装済み。Sema Golden は zero-argument call を `kotlin.collections.none#29`、predicate overload を `#28` に分離し、`kk_map_none` と対応するsynthetic/Runtime ABIは predicate arity 1 の既存経路として保持している。対象Goldenの直接生成比較、PR #6216のKotlin 2.3.10 kotlinc diff、TODO ID検査、Runtime ABI link検証を確認済み。

- [ ] KSP-1026: kotlin.collections.AbstractCollection.AbstractCollection の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.collections.AbstractCollection` / receiver `AbstractCollection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractCollection/AbstractCollection.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractCollection_AbstractCollection_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractCollection_AbstractCollection_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractCollection_AbstractCollection_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractCollection.contains` — fun AbstractCollection.contains(): Boolean  -- `open fun contains(#A): kotlin/Boolean`
    - `kotlin.collections.AbstractCollection.containsAll` — fun AbstractCollection.containsAll(Collection): Boolean  -- `open fun containsAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.AbstractCollection.isEmpty` — fun AbstractCollection.isEmpty(): Boolean  -- `open fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.AbstractCollection.toArray` — fun AbstractCollection.toArray(): Array  -- `open fun toArray(): kotlin/Array<kotlin/Any?>`
    - `kotlin.collections.AbstractCollection.toArray` — fun AbstractCollection.toArray(Array): Array  -- `open fun <#A1: kotlin/Any?> toArray(kotlin/Array<#A1>): kotlin/Array<#A1>`
    - `kotlin.collections.AbstractCollection.toString` — fun AbstractCollection.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1029: kotlin.collections.AbstractList top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.AbstractList` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractList/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractList_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractList_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractList_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractList.<init>` — constructor ()  -- `constructor <init>()`

- [ ] KSP-1030: kotlin.collections.AbstractList.AbstractList の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.collections.AbstractList` / receiver `AbstractList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractList/AbstractList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractList_AbstractList_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractList_AbstractList_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractList_AbstractList_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractList.equals` — fun AbstractList.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.AbstractList.get` — fun AbstractList.get(Int): #A  -- `abstract fun get(kotlin/Int): #A`
    - `kotlin.collections.AbstractList.hashCode` — fun AbstractList.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.collections.AbstractList.indexOf` — fun AbstractList.indexOf(): Int  -- `open fun indexOf(#A): kotlin/Int`
    - `kotlin.collections.AbstractList.iterator` — fun AbstractList.iterator(): Iterator  -- `open fun iterator(): kotlin.collections/Iterator<#A>`
    - `kotlin.collections.AbstractList.lastIndexOf` — fun AbstractList.lastIndexOf(): Int  -- `open fun lastIndexOf(#A): kotlin/Int`
    - `kotlin.collections.AbstractList.listIterator` — fun AbstractList.listIterator(): ListIterator  -- `open fun listIterator(): kotlin.collections/ListIterator<#A>`
    - `kotlin.collections.AbstractList.listIterator` — fun AbstractList.listIterator(Int): ListIterator  -- `open fun listIterator(kotlin/Int): kotlin.collections/ListIterator<#A>`
    - `kotlin.collections.AbstractList.size` — val AbstractList.size: Int  -- `abstract val size`
    - `kotlin.collections.AbstractList.subList` — fun AbstractList.subList(Int, Int): List  -- `open fun subList(kotlin/Int, kotlin/Int): kotlin.collections/List<#A>`

- [ ] KSP-1031: kotlin.collections.AbstractMap top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.AbstractMap` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMap/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractMap_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractMap_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractMap_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractMap.<init>` — constructor ()  -- `constructor <init>()`

- [ ] KSP-1032: kotlin.collections.AbstractMap.AbstractMap の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.collections.AbstractMap` / receiver `AbstractMap`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMap/AbstractMap.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractMap_AbstractMap_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractMap_AbstractMap_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractMap_AbstractMap_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractMap.containsKey` — fun AbstractMap.containsKey(): Boolean  -- `open fun containsKey(#A): kotlin/Boolean`
    - `kotlin.collections.AbstractMap.containsValue` — fun AbstractMap.containsValue(): Boolean  -- `open fun containsValue(#B): kotlin/Boolean`
    - `kotlin.collections.AbstractMap.equals` — fun AbstractMap.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.AbstractMap.get` — fun AbstractMap.get(): #B  -- `open fun get(#A): #B?`
    - `kotlin.collections.AbstractMap.hashCode` — fun AbstractMap.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.collections.AbstractMap.isEmpty` — fun AbstractMap.isEmpty(): Boolean  -- `open fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.AbstractMap.keys` — val AbstractMap.keys: Set  -- `open val keys`
    - `kotlin.collections.AbstractMap.size` — val AbstractMap.size: Int  -- `open val size`
    - `kotlin.collections.AbstractMap.toString` — fun AbstractMap.toString(): String  -- `open fun toString(): kotlin/String`
    - `kotlin.collections.AbstractMap.values` — val AbstractMap.values: Collection  -- `open val values`

- [ ] KSP-1034: kotlin.collections.AbstractMutableCollection.AbstractMutableCollection の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.collections.AbstractMutableCollection` / receiver `AbstractMutableCollection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMutableCollection/AbstractMutableCollection.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractMutableCollection_AbstractMutableCollection_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableCollection_AbstractMutableCollection_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableCollection_AbstractMutableCollection_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractMutableCollection.addAll` — fun AbstractMutableCollection.addAll(Collection): Boolean  -- `open fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableCollection.clear` — fun AbstractMutableCollection.clear(): Unit  -- `open fun clear()`
    - `kotlin.collections.AbstractMutableCollection.remove` — fun AbstractMutableCollection.remove(): Boolean  -- `open fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableCollection.removeAll` — fun AbstractMutableCollection.removeAll(Collection): Boolean  -- `open fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableCollection.retainAll` — fun AbstractMutableCollection.retainAll(Collection): Boolean  -- `open fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`

- [ ] KSP-1036: kotlin.collections.AbstractMutableList.AbstractMutableList の未実装 stdlib API を実装する（19 件）
  - 対象: `kotlin.collections.AbstractMutableList` / receiver `AbstractMutableList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMutableList/AbstractMutableList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractMutableList_AbstractMutableList_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableList_AbstractMutableList_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableList_AbstractMutableList_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractMutableList.add` — fun AbstractMutableList.add(): Boolean  -- `open fun add(#A): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableList.add` — fun AbstractMutableList.add(Int, ): Unit  -- `abstract fun add(kotlin/Int, #A)`
    - `kotlin.collections.AbstractMutableList.addAll` — fun AbstractMutableList.addAll(Int, Collection): Boolean  -- `open fun addAll(kotlin/Int, kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableList.clear` — fun AbstractMutableList.clear(): Unit  -- `open fun clear()`
    - `kotlin.collections.AbstractMutableList.contains` — fun AbstractMutableList.contains(): Boolean  -- `open fun contains(#A): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableList.equals` — fun AbstractMutableList.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableList.hashCode` — fun AbstractMutableList.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.collections.AbstractMutableList.indexOf` — fun AbstractMutableList.indexOf(): Int  -- `open fun indexOf(#A): kotlin/Int`
    - `kotlin.collections.AbstractMutableList.iterator` — fun AbstractMutableList.iterator(): MutableIterator  -- `open fun iterator(): kotlin.collections/MutableIterator<#A>`
    - `kotlin.collections.AbstractMutableList.lastIndexOf` — fun AbstractMutableList.lastIndexOf(): Int  -- `open fun lastIndexOf(#A): kotlin/Int`
    - `kotlin.collections.AbstractMutableList.listIterator` — fun AbstractMutableList.listIterator(): MutableListIterator  -- `open fun listIterator(): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.AbstractMutableList.listIterator` — fun AbstractMutableList.listIterator(Int): MutableListIterator  -- `open fun listIterator(kotlin/Int): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.AbstractMutableList.modCount` — val AbstractMutableList.modCount: Int  -- `final var modCount`
    - `kotlin.collections.AbstractMutableList.removeAll` — fun AbstractMutableList.removeAll(Collection): Boolean  -- `open fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableList.removeAt` — fun AbstractMutableList.removeAt(Int): #A  -- `abstract fun removeAt(kotlin/Int): #A`
    - `kotlin.collections.AbstractMutableList.removeRange` — fun AbstractMutableList.removeRange(Int, Int): Unit  -- `open fun removeRange(kotlin/Int, kotlin/Int)`
    - `kotlin.collections.AbstractMutableList.retainAll` — fun AbstractMutableList.retainAll(Collection): Boolean  -- `open fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableList.set` — fun AbstractMutableList.set(Int, ): #A  -- `abstract fun set(kotlin/Int, #A): #A`
    - `kotlin.collections.AbstractMutableList.subList` — fun AbstractMutableList.subList(Int, Int): MutableList  -- `open fun subList(kotlin/Int, kotlin/Int): kotlin.collections/MutableList<#A>`

- [ ] KSP-1037: kotlin.collections.AbstractMutableMap top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.AbstractMutableMap` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMutableMap/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractMutableMap_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableMap_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableMap_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractMutableMap.<init>` — constructor ()  -- `constructor <init>()`

- [x] KSP-1038: kotlin.collections.AbstractMutableMap.AbstractMutableMap の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.collections.AbstractMutableMap` / receiver `AbstractMutableMap`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMutableMap/AbstractMutableMap.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractMutableMap_AbstractMutableMap_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableMap_AbstractMutableMap_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableMap_AbstractMutableMap_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractMutableMap.clear` — fun AbstractMutableMap.clear(): Unit  -- `open fun clear()`
    - `kotlin.collections.AbstractMutableMap.keys` — val AbstractMutableMap.keys: MutableSet  -- `open val keys`
    - `kotlin.collections.AbstractMutableMap.put` — fun AbstractMutableMap.put(, ): #B  -- `abstract fun put(#A, #B): #B?`
    - `kotlin.collections.AbstractMutableMap.putAll` — fun AbstractMutableMap.putAll(Map): Unit  -- `open fun putAll(kotlin.collections/Map<out #A, #B>)`
    - `kotlin.collections.AbstractMutableMap.remove` — fun AbstractMutableMap.remove(): #B  -- `open fun remove(#A): #B?`
    - `kotlin.collections.AbstractMutableMap.values` — val AbstractMutableMap.values: MutableCollection  -- `open val values`

- [ ] KSP-1040: kotlin.collections.AbstractMutableSet.AbstractMutableSet の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.collections.AbstractMutableSet` / receiver `AbstractMutableSet`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractMutableSet/AbstractMutableSet.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractMutableSet_AbstractMutableSet_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableSet_AbstractMutableSet_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractMutableSet_AbstractMutableSet_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractMutableSet.add` — fun AbstractMutableSet.add(): Boolean  -- `abstract fun add(#A): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableSet.equals` — fun AbstractMutableSet.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.AbstractMutableSet.hashCode` — fun AbstractMutableSet.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`

- [ ] KSP-1041: kotlin.collections.AbstractSet top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.AbstractSet` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractSet/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractSet_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractSet_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractSet_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractSet.<init>` — constructor ()  -- `constructor <init>()`

- [ ] KSP-1042: kotlin.collections.AbstractSet.AbstractSet の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections.AbstractSet` / receiver `AbstractSet`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/AbstractSet/AbstractSet.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_AbstractSet_AbstractSet_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_AbstractSet_AbstractSet_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_AbstractSet_AbstractSet_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.AbstractSet.equals` — fun AbstractSet.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.AbstractSet.hashCode` — fun AbstractSet.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`

- [ ] KSP-1043: kotlin.collections.ArrayDeque top-level の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.collections.ArrayDeque` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayDeque/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_ArrayDeque_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_ArrayDeque_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_ArrayDeque_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.ArrayDeque.<init>` — constructor ()  -- `constructor <init>()`
    - `kotlin.collections.ArrayDeque.<init>` — constructor (Collection)  -- `constructor <init>(kotlin.collections/Collection<#A>)`
    - `kotlin.collections.ArrayDeque.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`

- [x] KSP-1044: kotlin.collections.ArrayDeque.ArrayDeque の未実装 stdlib API を実装する（24 件）
  - 完了根拠: KSP-625 で既に source-backed 化されていた `first` / `firstOrNull` / `get` / `last` / `lastOrNull` / `removeFirst` / `removeFirstOrNull` / `removeLast` / `removeLastOrNull` の9件を維持し、残る15件を `ArrayDeque.kt` に追加した。既存のring-buffer runtime primitive、synthetic stub、Runtime ABI は変更していない。
  - 回帰: 対象24メンバーのSema Golden、`stdlib_kotlin_collections_ArrayDeque_ArrayDeque_n.kt` の kotlinc 差分（`DIFF_REQUIRE_JDK21=0`）、Bundled stdlib実行、共有stdlib artifact経路を検証し、`check_todo_ids.sh` と `validate_runtime_abi_links.sh` もpass。
  - 対象: `kotlin.collections.ArrayDeque` / receiver `ArrayDeque`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayDeque/ArrayDeque.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_ArrayDeque_ArrayDeque_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_ArrayDeque_ArrayDeque_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_ArrayDeque_ArrayDeque_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.ArrayDeque.add` — fun ArrayDeque.add(): Boolean  -- `final fun add(#A): kotlin/Boolean`
    - `kotlin.collections.ArrayDeque.add` — fun ArrayDeque.add(Int, ): Unit  -- `final fun add(kotlin/Int, #A)`
    - `kotlin.collections.ArrayDeque.addAll` — fun ArrayDeque.addAll(Collection): Boolean  -- `final fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayDeque.addAll` — fun ArrayDeque.addAll(Int, Collection): Boolean  -- `final fun addAll(kotlin/Int, kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayDeque.clear` — fun ArrayDeque.clear(): Unit  -- `final fun clear()`
    - `kotlin.collections.ArrayDeque.contains` — fun ArrayDeque.contains(): Boolean  -- `final fun contains(#A): kotlin/Boolean`
    - `kotlin.collections.ArrayDeque.first` — fun ArrayDeque.first(): #A  -- `final fun first(): #A`
    - `kotlin.collections.ArrayDeque.firstOrNull` — fun ArrayDeque.firstOrNull(): #A  -- `final fun firstOrNull(): #A?`
    - `kotlin.collections.ArrayDeque.get` — fun ArrayDeque.get(Int): #A  -- `final fun get(kotlin/Int): #A`
    - `kotlin.collections.ArrayDeque.indexOf` — fun ArrayDeque.indexOf(): Int  -- `final fun indexOf(#A): kotlin/Int`
    - `kotlin.collections.ArrayDeque.last` — fun ArrayDeque.last(): #A  -- `final fun last(): #A`
    - `kotlin.collections.ArrayDeque.lastIndexOf` — fun ArrayDeque.lastIndexOf(): Int  -- `final fun lastIndexOf(#A): kotlin/Int`
    - `kotlin.collections.ArrayDeque.lastOrNull` — fun ArrayDeque.lastOrNull(): #A  -- `final fun lastOrNull(): #A?`
    - `kotlin.collections.ArrayDeque.remove` — fun ArrayDeque.remove(): Boolean  -- `final fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.ArrayDeque.removeAll` — fun ArrayDeque.removeAll(Collection): Boolean  -- `final fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayDeque.removeAt` — fun ArrayDeque.removeAt(Int): #A  -- `final fun removeAt(kotlin/Int): #A`
    - `kotlin.collections.ArrayDeque.removeFirst` — fun ArrayDeque.removeFirst(): #A  -- `final fun removeFirst(): #A`
    - `kotlin.collections.ArrayDeque.removeFirstOrNull` — fun ArrayDeque.removeFirstOrNull(): #A  -- `final fun removeFirstOrNull(): #A?`
    - `kotlin.collections.ArrayDeque.removeLast` — fun ArrayDeque.removeLast(): #A  -- `final fun removeLast(): #A`
    - `kotlin.collections.ArrayDeque.removeLastOrNull` — fun ArrayDeque.removeLastOrNull(): #A  -- `final fun removeLastOrNull(): #A?`
    - `kotlin.collections.ArrayDeque.retainAll` — fun ArrayDeque.retainAll(Collection): Boolean  -- `final fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayDeque.set` — fun ArrayDeque.set(Int, ): #A  -- `final fun set(kotlin/Int, #A): #A`
    - `kotlin.collections.ArrayDeque.toArray` — fun ArrayDeque.toArray(): Array  -- `final fun toArray(): kotlin/Array<kotlin/Any?>`
    - `kotlin.collections.ArrayDeque.toArray` — fun ArrayDeque.toArray(Array): Array  -- `final fun <#A1: kotlin/Any?> toArray(kotlin/Array<#A1>): kotlin/Array<#A1>`

- [ ] KSP-1045: kotlin.collections.ArrayList top-level の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.collections.ArrayList` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayList/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_ArrayList_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_ArrayList_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_ArrayList_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.ArrayList.<init>` — constructor ()  -- `constructor <init>()`
    - `kotlin.collections.ArrayList.<init>` — constructor (Collection)  -- `constructor <init>(kotlin.collections/Collection<#A>)`
    - `kotlin.collections.ArrayList.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`

- [ ] KSP-1046: kotlin.collections.ArrayList.ArrayList の未実装 stdlib API を実装する（25 件）
  - 対象: `kotlin.collections.ArrayList` / receiver `ArrayList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ArrayList/ArrayList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_ArrayList_ArrayList_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_ArrayList_ArrayList_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_ArrayList_ArrayList_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.ArrayList.add` — fun ArrayList.add(): Boolean  -- `final fun add(#A): kotlin/Boolean`
    - `kotlin.collections.ArrayList.add` — fun ArrayList.add(Int, ): Unit  -- `final fun add(kotlin/Int, #A)`
    - `kotlin.collections.ArrayList.addAll` — fun ArrayList.addAll(Collection): Boolean  -- `final fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayList.addAll` — fun ArrayList.addAll(Int, Collection): Boolean  -- `final fun addAll(kotlin/Int, kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayList.build` — fun ArrayList.build(): List  -- `final fun build(): kotlin.collections/List<#A>`
    - `kotlin.collections.ArrayList.clear` — fun ArrayList.clear(): Unit  -- `final fun clear()`
    - `kotlin.collections.ArrayList.ensureCapacity` — fun ArrayList.ensureCapacity(Int): Unit  -- `final fun ensureCapacity(kotlin/Int)`
    - `kotlin.collections.ArrayList.equals` — fun ArrayList.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.ArrayList.get` — fun ArrayList.get(Int): #A  -- `final fun get(kotlin/Int): #A`
    - `kotlin.collections.ArrayList.hashCode` — fun ArrayList.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.collections.ArrayList.indexOf` — fun ArrayList.indexOf(): Int  -- `final fun indexOf(#A): kotlin/Int`
    - `kotlin.collections.ArrayList.isEmpty` — fun ArrayList.isEmpty(): Boolean  -- `final fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.ArrayList.iterator` — fun ArrayList.iterator(): MutableIterator  -- `final fun iterator(): kotlin.collections/MutableIterator<#A>`
    - `kotlin.collections.ArrayList.lastIndexOf` — fun ArrayList.lastIndexOf(): Int  -- `final fun lastIndexOf(#A): kotlin/Int`
    - `kotlin.collections.ArrayList.listIterator` — fun ArrayList.listIterator(): MutableListIterator  -- `final fun listIterator(): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.ArrayList.listIterator` — fun ArrayList.listIterator(Int): MutableListIterator  -- `final fun listIterator(kotlin/Int): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.ArrayList.remove` — fun ArrayList.remove(): Boolean  -- `final fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.ArrayList.removeAll` — fun ArrayList.removeAll(Collection): Boolean  -- `final fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayList.removeAt` — fun ArrayList.removeAt(Int): #A  -- `final fun removeAt(kotlin/Int): #A`
    - `kotlin.collections.ArrayList.retainAll` — fun ArrayList.retainAll(Collection): Boolean  -- `final fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.ArrayList.set` — fun ArrayList.set(Int, ): #A  -- `final fun set(kotlin/Int, #A): #A`
    - `kotlin.collections.ArrayList.size` — val ArrayList.size: Int  -- `final val size`
    - `kotlin.collections.ArrayList.subList` — fun ArrayList.subList(Int, Int): MutableList  -- `final fun subList(kotlin/Int, kotlin/Int): kotlin.collections/MutableList<#A>`
    - `kotlin.collections.ArrayList.toString` — fun ArrayList.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.collections.ArrayList.trimToSize` — fun ArrayList.trimToSize(): Unit  -- `final fun trimToSize()`

- [ ] KSP-1050: kotlin.collections.Collection.Collection の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.collections.Collection` / receiver `Collection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Collection/Collection.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Collection_Collection_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Collection_Collection_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Collection_Collection_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Collection.contains` — fun Collection.contains(): Boolean  -- `abstract fun contains(#A): kotlin/Boolean`
    - `kotlin.collections.Collection.containsAll` — fun Collection.containsAll(Collection): Boolean  -- `abstract fun containsAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.Collection.isEmpty` — fun Collection.isEmpty(): Boolean  -- `abstract fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.Collection.iterator` — fun Collection.iterator(): Iterator  -- `abstract fun iterator(): kotlin.collections/Iterator<#A>`
    - `kotlin.collections.Collection.size` — val Collection.size: Int  -- `abstract val size`

- [ ] KSP-1055: kotlin.collections.HashMap.HashMap の未実装 stdlib API を実装する（16 件）
  - 対象: `kotlin.collections.HashMap` / receiver `HashMap`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/HashMap/HashMap.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_HashMap_HashMap_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_HashMap_HashMap_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_HashMap_HashMap_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.HashMap.build` — fun HashMap.build(): Map  -- `final fun build(): kotlin.collections/Map<#A, #B>`
    - `kotlin.collections.HashMap.clear` — fun HashMap.clear(): Unit  -- `final fun clear()`
    - `kotlin.collections.HashMap.containsKey` — fun HashMap.containsKey(): Boolean  -- `final fun containsKey(#A): kotlin/Boolean`
    - `kotlin.collections.HashMap.containsValue` — fun HashMap.containsValue(): Boolean  -- `final fun containsValue(#B): kotlin/Boolean`
    - `kotlin.collections.HashMap.entries` — val HashMap.entries: MutableSet  -- `final val entries`
    - `kotlin.collections.HashMap.equals` — fun HashMap.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.collections.HashMap.get` — fun HashMap.get(): #B  -- `final fun get(#A): #B?`
    - `kotlin.collections.HashMap.hashCode` — fun HashMap.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.collections.HashMap.isEmpty` — fun HashMap.isEmpty(): Boolean  -- `final fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.HashMap.keys` — val HashMap.keys: MutableSet  -- `final val keys`
    - `kotlin.collections.HashMap.put` — fun HashMap.put(, ): #B  -- `final fun put(#A, #B): #B?`
    - `kotlin.collections.HashMap.putAll` — fun HashMap.putAll(Map): Unit  -- `final fun putAll(kotlin.collections/Map<out #A, #B>)`
    - `kotlin.collections.HashMap.remove` — fun HashMap.remove(): #B  -- `final fun remove(#A): #B?`
    - `kotlin.collections.HashMap.size` — val HashMap.size: Int  -- `final val size`
    - `kotlin.collections.HashMap.toString` — fun HashMap.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.collections.HashMap.values` — val HashMap.values: MutableCollection  -- `final val values`

- [ ] KSP-1056: kotlin.collections.HashSet top-level の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.collections.HashSet` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/HashSet/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_HashSet_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_HashSet_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_HashSet_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.HashSet.<init>` — constructor ()  -- `constructor <init>()`
    - `kotlin.collections.HashSet.<init>` — constructor (Collection)  -- `constructor <init>(kotlin.collections/Collection<#A>)`
    - `kotlin.collections.HashSet.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.collections.HashSet.<init>` — constructor (Int, Float)  -- `constructor <init>(kotlin/Int, kotlin/Float)`

- [ ] KSP-1057: kotlin.collections.HashSet.HashSet の未実装 stdlib API を実装する（12 件）
  - 対象: `kotlin.collections.HashSet` / receiver `HashSet`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/HashSet/HashSet.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_HashSet_HashSet_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_HashSet_HashSet_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_HashSet_HashSet_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.HashSet.add` — fun HashSet.add(): Boolean  -- `final fun add(#A): kotlin/Boolean`
    - `kotlin.collections.HashSet.addAll` — fun HashSet.addAll(Collection): Boolean  -- `final fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.HashSet.build` — fun HashSet.build(): Set  -- `final fun build(): kotlin.collections/Set<#A>`
    - `kotlin.collections.HashSet.clear` — fun HashSet.clear(): Unit  -- `final fun clear()`
    - `kotlin.collections.HashSet.contains` — fun HashSet.contains(): Boolean  -- `final fun contains(#A): kotlin/Boolean`
    - `kotlin.collections.HashSet.getElement` — fun HashSet.getElement(): #A  -- `final fun getElement(#A): #A?`
    - `kotlin.collections.HashSet.isEmpty` — fun HashSet.isEmpty(): Boolean  -- `final fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.HashSet.iterator` — fun HashSet.iterator(): MutableIterator  -- `final fun iterator(): kotlin.collections/MutableIterator<#A>`
    - `kotlin.collections.HashSet.remove` — fun HashSet.remove(): Boolean  -- `final fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.HashSet.removeAll` — fun HashSet.removeAll(Collection): Boolean  -- `final fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.HashSet.retainAll` — fun HashSet.retainAll(Collection): Boolean  -- `final fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.HashSet.size` — val HashSet.size: Int  -- `final val size`

- [ ] KSP-1061: kotlin.collections.Iterable.Iterable の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.Iterable` / receiver `Iterable`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterable/Iterable.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterable_Iterable_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterable_Iterable_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterable_Iterable_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Iterable.iterator` — fun Iterable.iterator(): Iterator  -- `abstract fun iterator(): kotlin.collections/Iterator<#A>`

- [ ] KSP-1062: kotlin.collections.Iterator.Iterator の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections.Iterator` / receiver `Iterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Iterator/Iterator.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Iterator_Iterator_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Iterator_Iterator_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Iterator_Iterator_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Iterator.hasNext` — fun Iterator.hasNext(): Boolean  -- `abstract fun hasNext(): kotlin/Boolean`
    - `kotlin.collections.Iterator.next` — fun Iterator.next(): #A  -- `abstract fun next(): #A`

- [ ] KSP-1063: kotlin.collections.List.List の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.collections.List` / receiver `List`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/List/List.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_List_List_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_List_List_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_List_List_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.List.get` — fun List.get(Int): #A  -- `abstract fun get(kotlin/Int): #A`
    - `kotlin.collections.List.isEmpty` — fun List.isEmpty(): Boolean  -- `abstract fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.List.iterator` — fun List.iterator(): Iterator  -- `abstract fun iterator(): kotlin.collections/Iterator<#A>`
    - `kotlin.collections.List.listIterator` — fun List.listIterator(): ListIterator  -- `abstract fun listIterator(): kotlin.collections/ListIterator<#A>`
    - `kotlin.collections.List.listIterator` — fun List.listIterator(Int): ListIterator  -- `abstract fun listIterator(kotlin/Int): kotlin.collections/ListIterator<#A>`
    - `kotlin.collections.List.size` — val List.size: Int  -- `abstract val size`

- [ ] KSP-1064: kotlin.collections.ListIterator.ListIterator の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.collections.ListIterator` / receiver `ListIterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/ListIterator/ListIterator.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_ListIterator_ListIterator_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_ListIterator_ListIterator_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_ListIterator_ListIterator_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.ListIterator.hasNext` — fun ListIterator.hasNext(): Boolean  -- `abstract fun hasNext(): kotlin/Boolean`
    - `kotlin.collections.ListIterator.hasPrevious` — fun ListIterator.hasPrevious(): Boolean  -- `abstract fun hasPrevious(): kotlin/Boolean`
    - `kotlin.collections.ListIterator.next` — fun ListIterator.next(): #A  -- `abstract fun next(): #A`
    - `kotlin.collections.ListIterator.nextIndex` — fun ListIterator.nextIndex(): Int  -- `abstract fun nextIndex(): kotlin/Int`
    - `kotlin.collections.ListIterator.previous` — fun ListIterator.previous(): #A  -- `abstract fun previous(): #A`
    - `kotlin.collections.ListIterator.previousIndex` — fun ListIterator.previousIndex(): Int  -- `abstract fun previousIndex(): kotlin/Int`

- [ ] KSP-1066: kotlin.collections.Map top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.Map` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Map/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Map_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Map_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Map_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Map.Entry` — interface kotlin.collections.Map.Entry  -- `abstract interface <#A1: out kotlin/Any?, #B1: out kotlin/Any?> Entry {`

- [ ] KSP-1067: kotlin.collections.Map.Map の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.collections.Map` / receiver `Map`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Map/Map.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Map_Map_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Map_Map_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Map_Map_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Map.entries` — val Map.entries: Set  -- `abstract val entries`
    - `kotlin.collections.Map.get` — fun Map.get(): #B  -- `abstract fun get(#A): #B?`
    - `kotlin.collections.Map.isEmpty` — fun Map.isEmpty(): Boolean  -- `abstract fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.Map.keys` — val Map.keys: Set  -- `abstract val keys`
    - `kotlin.collections.Map.size` — val Map.size: Int  -- `abstract val size`
    - `kotlin.collections.Map.values` — val Map.values: Collection  -- `abstract val values`

- [ ] KSP-1068: kotlin.collections.Map.Entry.Entry の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.collections.Map.Entry` / receiver `Entry`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Map/Entry/Entry.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Map_Entry_Entry_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Map_Entry_Entry_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Map_Entry_Entry_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Map.Entry.key` — val Entry.key: #A1  -- `abstract val key`
    - `kotlin.collections.Map.Entry.value` — val Entry.value: #B1  -- `abstract val value`

- [ ] KSP-1069: kotlin.collections.MutableCollection.MutableCollection の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.collections.MutableCollection` / receiver `MutableCollection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableCollection/MutableCollection.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableCollection_MutableCollection_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableCollection_MutableCollection_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableCollection_MutableCollection_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableCollection.add` — fun MutableCollection.add(): Boolean  -- `abstract fun add(#A): kotlin/Boolean`
    - `kotlin.collections.MutableCollection.addAll` — fun MutableCollection.addAll(Collection): Boolean  -- `abstract fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableCollection.clear` — fun MutableCollection.clear(): Unit  -- `abstract fun clear()`
    - `kotlin.collections.MutableCollection.iterator` — fun MutableCollection.iterator(): MutableIterator  -- `abstract fun iterator(): kotlin.collections/MutableIterator<#A>`
    - `kotlin.collections.MutableCollection.remove` — fun MutableCollection.remove(): Boolean  -- `abstract fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.MutableCollection.removeAll` — fun MutableCollection.removeAll(Collection): Boolean  -- `abstract fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableCollection.retainAll` — fun MutableCollection.retainAll(Collection): Boolean  -- `abstract fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`

- [ ] KSP-1070: kotlin.collections.MutableIterable.MutableIterable の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.MutableIterable` / receiver `MutableIterable`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableIterable/MutableIterable.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableIterable_MutableIterable_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableIterable_MutableIterable_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableIterable_MutableIterable_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableIterable.iterator` — fun MutableIterable.iterator(): MutableIterator  -- `abstract fun iterator(): kotlin.collections/MutableIterator<#A>`

- [x] KSP-1071: kotlin.collections.MutableIterator.MutableIterator の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.MutableIterator` / receiver `MutableIterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableIterator/MutableIterator.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableIterator_MutableIterator_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableIterator_MutableIterator_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableIterator_MutableIterator_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠 (2026-09-04): KSP-943 の merged PR #6154（commit `ea4ae69478`）で `Sources/CompilerCore/Stdlib/kotlin/collections/MutableIterator.kt` に `MutableIterator<out T> : Iterator<T>` と public `remove(): Unit` を source-backed 実装済み。既存の `ListSyntheticMemberLinkTests/testMutableIterableSurfaceIsRegistered` が source file、非synthetic、引数なし/Unit の `remove` を検証し、Sema golden と `Scripts/diff_cases/stdlib_kotlin_collections_n_MutableIterator.kt` が custom `remove()` と `MutableIterable` 経路を固定しているため、KSP-1071 の追加実装は不要。
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableIterator.remove` — fun MutableIterator.remove(): Unit  -- `abstract fun remove()`

- [ ] KSP-1072: kotlin.collections.MutableList.MutableList の未実装 stdlib API を実装する（13 件）
  - 対象: `kotlin.collections.MutableList` / receiver `MutableList`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableList/MutableList.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableList_MutableList_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableList_MutableList_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableList_MutableList_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableList.add` — fun MutableList.add(): Boolean  -- `abstract fun add(#A): kotlin/Boolean`
    - `kotlin.collections.MutableList.add` — fun MutableList.add(Int, ): Unit  -- `abstract fun add(kotlin/Int, #A)`
    - `kotlin.collections.MutableList.addAll` — fun MutableList.addAll(Collection): Boolean  -- `abstract fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableList.addAll` — fun MutableList.addAll(Int, Collection): Boolean  -- `abstract fun addAll(kotlin/Int, kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableList.clear` — fun MutableList.clear(): Unit  -- `abstract fun clear()`
    - `kotlin.collections.MutableList.listIterator` — fun MutableList.listIterator(): MutableListIterator  -- `abstract fun listIterator(): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.MutableList.listIterator` — fun MutableList.listIterator(Int): MutableListIterator  -- `abstract fun listIterator(kotlin/Int): kotlin.collections/MutableListIterator<#A>`
    - `kotlin.collections.MutableList.remove` — fun MutableList.remove(): Boolean  -- `abstract fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.MutableList.removeAll` — fun MutableList.removeAll(Collection): Boolean  -- `abstract fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableList.removeAt` — fun MutableList.removeAt(Int): #A  -- `abstract fun removeAt(kotlin/Int): #A`
    - `kotlin.collections.MutableList.retainAll` — fun MutableList.retainAll(Collection): Boolean  -- `abstract fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableList.set` — fun MutableList.set(Int, ): #A  -- `abstract fun set(kotlin/Int, #A): #A`
    - `kotlin.collections.MutableList.subList` — fun MutableList.subList(Int, Int): MutableList  -- `abstract fun subList(kotlin/Int, kotlin/Int): kotlin.collections/MutableList<#A>`

- [x] KSP-1073: kotlin.collections.MutableListIterator.MutableListIterator の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.collections.MutableListIterator` / receiver `MutableListIterator`
  - 完了根拠: `hasNext`/`next` は既存の `listIteratorInheritedDispatchCallee` 系の itable 強制ロジックで元々正しく動作していた（未変更）。`add`/`set` は `MutableListIterator.kt` に実宣言を追加し、`HeaderHelpers+SyntheticListResiduals.swift`（`ensureSyntheticMutableListIteratorStub`）の synthetic fallback を `activeBundledIndex.contains` ガードで抑制。`remove` は同ファイルの `registerRemoveMember()` が `MutableListIterator` に冗長な synthetic 重複を宣言し、実際に itable 配線済みの継承元 `MutableIterator.remove` を member lookup で覆い隠していた（BUG: `.remove()` が静かに no-op、`add`/`set` は kklib メタデータへ synthetic シンボルが round-trip しないため link failure）ため、`mutableIteratorSymbol` が解決できる通常時は synthetic 重複を作らないようガードして修正。Runtime 側は `RuntimeListIteratorBox` に `addAction`/`setAction`（`RuntimeTypes.swift`）を追加し、`kk_list_iterator`/`kk_list_iterator_at`（`RuntimeCollections.swift`）で配線、`registerMutableListIteratorItable`（`RuntimeCollectionHelpers.swift`、itable slot 3、既存の #6560 が触る2関数とは非依存）でネイティブ `RuntimeListIteratorBox` にも `add`/`set` の itable dispatch を登録。
  - 回帰: `Tests/CompilerCoreTests/Sema/ListSyntheticMemberLinkTests.swift`（`testMutableListIteratorSurfaceIsRegistered`/`testCustomMutableListIteratorImplementationResolves` 更新・確認）、`Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_n_MutableListIterator.golden` 再生成（`remove` の解決先が `MutableListIterator.remove` → `MutableIterator.remove` に変化、機械的差分）、新規 `Scripts/diff_cases/mutable_list_iterator_custom_impl_dispatch.kt`（`diff_kotlinc.sh` で real kotlinc と一致確認、ネイティブ `listIterator()` の `set`/`add`/`remove` と直接実装クラス両方をカバー）。

- [ ] KSP-1074: kotlin.collections.MutableMap top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.MutableMap` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableMap/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableMap_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableMap.MutableEntry` — interface kotlin.collections.MutableMap.MutableEntry  -- `abstract interface <#A1: kotlin/Any?, #B1: kotlin/Any?> MutableEntry : kotlin.collections/Map.Entry<#A1, #B1> {`

- [ ] KSP-1075: kotlin.collections.MutableMap.MutableMap の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.collections.MutableMap` / receiver `MutableMap`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableMap/MutableMap.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableMap_MutableMap_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_MutableMap_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_MutableMap_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableMap.clear` — fun MutableMap.clear(): Unit  -- `abstract fun clear()`
    - `kotlin.collections.MutableMap.entries` — val MutableMap.entries: MutableSet  -- `abstract val entries`
    - `kotlin.collections.MutableMap.keys` — val MutableMap.keys: MutableSet  -- `abstract val keys`
    - `kotlin.collections.MutableMap.put` — fun MutableMap.put(, ): #B  -- `abstract fun put(#A, #B): #B?`
    - `kotlin.collections.MutableMap.putAll` — fun MutableMap.putAll(Map): Unit  -- `abstract fun putAll(kotlin.collections/Map<out #A, #B>)`
    - `kotlin.collections.MutableMap.remove` — fun MutableMap.remove(): #B  -- `abstract fun remove(#A): #B?`
    - `kotlin.collections.MutableMap.values` — val MutableMap.values: MutableCollection  -- `abstract val values`

- [ ] KSP-1076: kotlin.collections.MutableMap.MutableEntry.MutableEntry の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.collections.MutableMap.MutableEntry` / receiver `MutableEntry`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableMap/MutableEntry/MutableEntry.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableMap_MutableEntry_MutableEntry_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_MutableEntry_MutableEntry_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableMap_MutableEntry_MutableEntry_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableMap.MutableEntry.setValue` — fun MutableEntry.setValue(): #B1  -- `abstract fun setValue(#B1): #B1`

- [ ] KSP-1077: kotlin.collections.MutableSet.MutableSet の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.collections.MutableSet` / receiver `MutableSet`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/MutableSet/MutableSet.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_MutableSet_MutableSet_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_MutableSet_MutableSet_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_MutableSet_MutableSet_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.MutableSet.add` — fun MutableSet.add(): Boolean  -- `abstract fun add(#A): kotlin/Boolean`
    - `kotlin.collections.MutableSet.addAll` — fun MutableSet.addAll(Collection): Boolean  -- `abstract fun addAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableSet.clear` — fun MutableSet.clear(): Unit  -- `abstract fun clear()`
    - `kotlin.collections.MutableSet.iterator` — fun MutableSet.iterator(): MutableIterator  -- `abstract fun iterator(): kotlin.collections/MutableIterator<#A>`
    - `kotlin.collections.MutableSet.remove` — fun MutableSet.remove(): Boolean  -- `abstract fun remove(#A): kotlin/Boolean`
    - `kotlin.collections.MutableSet.removeAll` — fun MutableSet.removeAll(Collection): Boolean  -- `abstract fun removeAll(kotlin.collections/Collection<#A>): kotlin/Boolean`
    - `kotlin.collections.MutableSet.retainAll` — fun MutableSet.retainAll(Collection): Boolean  -- `abstract fun retainAll(kotlin.collections/Collection<#A>): kotlin/Boolean`

- [x] KSP-1078: kotlin.collections.Set.Set の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.collections.Set` / receiver `Set`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/collections/Set/Set.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_collections_Set_Set_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_collections_Set_Set_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_collections_Set_Set_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.collections.Set.contains` — fun Set.contains(): Boolean  -- `abstract fun contains(#A): kotlin/Boolean`
    - `kotlin.collections.Set.isEmpty` — fun Set.isEmpty(): Boolean  -- `abstract fun isEmpty(): kotlin/Boolean`
    - `kotlin.collections.Set.iterator` — fun Set.iterator(): Iterator  -- `abstract fun iterator(): kotlin.collections/Iterator<#A>`
    - `kotlin.collections.Set.size` — val Set.size: Int  -- `abstract val size`

- [ ] KSP-1083: kotlin.concurrent top-level の未実装 stdlib API を実装する（11 件）
  - 対象: `kotlin.concurrent` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicArray` — class kotlin.concurrent.AtomicArray  -- `final class <#A: kotlin/Any?> kotlin.concurrent/AtomicArray {`
    - `kotlin.concurrent.AtomicArray` — fun AtomicArray(Int, Function1): AtomicArray  -- `final inline fun <#A: reified kotlin/Any?> kotlin.concurrent/AtomicArray(kotlin/Int, kotlin/Function1<kotlin/Int, #A>): kotlin.concurrent/AtomicArray<#A>`
    - `kotlin.concurrent.AtomicInt` — class kotlin.concurrent.AtomicInt  -- `final class kotlin.concurrent/AtomicInt {`
    - `kotlin.concurrent.AtomicIntArray` — class kotlin.concurrent.AtomicIntArray  -- `final class kotlin.concurrent/AtomicIntArray {`
    - `kotlin.concurrent.AtomicIntArray` — fun AtomicIntArray(Int, Function1): AtomicIntArray  -- `final inline fun kotlin.concurrent/AtomicIntArray(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Int>): kotlin.concurrent/AtomicIntArray`
    - `kotlin.concurrent.AtomicLong` — class kotlin.concurrent.AtomicLong  -- `final class kotlin.concurrent/AtomicLong {`
    - `kotlin.concurrent.AtomicLongArray` — class kotlin.concurrent.AtomicLongArray  -- `final class kotlin.concurrent/AtomicLongArray {`
    - `kotlin.concurrent.AtomicLongArray` — fun AtomicLongArray(Int, Function1): AtomicLongArray  -- `final inline fun kotlin.concurrent/AtomicLongArray(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Long>): kotlin.concurrent/AtomicLongArray`
    - `kotlin.concurrent.AtomicNativePtr` — class kotlin.concurrent.AtomicNativePtr  -- `final class kotlin.concurrent/AtomicNativePtr {`
    - `kotlin.concurrent.AtomicReference` — class kotlin.concurrent.AtomicReference  -- `final class <#A: kotlin/Any?> kotlin.concurrent/AtomicReference {`
    - `kotlin.concurrent.Volatile` — class kotlin.concurrent.Volatile  -- `open annotation class kotlin.concurrent/Volatile : kotlin/Annotation {`

- [ ] KSP-1084: kotlin.concurrent.KMutableProperty0 の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.concurrent` / receiver `KMutableProperty0`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/KMutableProperty0.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_KMutableProperty0_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_KMutableProperty0_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_KMutableProperty0_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomicGetField` — fun KMutableProperty0.atomicGetField(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.reflect/KMutableProperty0<#A>).kotlin.concurrent/atomicGetField(): #A`
    - `kotlin.concurrent.atomicSetField` — fun KMutableProperty0.atomicSetField(): Unit  -- `final fun <#A: kotlin/Any?> (kotlin.reflect/KMutableProperty0<#A>).kotlin.concurrent/atomicSetField(#A)`
    - `kotlin.concurrent.compareAndExchangeField` — fun KMutableProperty0.compareAndExchangeField(, ): #A  -- `final fun <#A: kotlin/Any?> (kotlin.reflect/KMutableProperty0<#A>).kotlin.concurrent/compareAndExchangeField(#A, #A): #A`
    - `kotlin.concurrent.compareAndSetField` — fun KMutableProperty0.compareAndSetField(, ): Boolean  -- `final fun <#A: kotlin/Any?> (kotlin.reflect/KMutableProperty0<#A>).kotlin.concurrent/compareAndSetField(#A, #A): kotlin/Boolean`
    - `kotlin.concurrent.getAndAddField` — fun KMutableProperty0.getAndAddField(Byte): Byte  -- `final fun (kotlin.reflect/KMutableProperty0<kotlin/Byte>).kotlin.concurrent/getAndAddField(kotlin/Byte): kotlin/Byte`
    - `kotlin.concurrent.getAndAddField` — fun KMutableProperty0.getAndAddField(Int): Int  -- `final fun (kotlin.reflect/KMutableProperty0<kotlin/Int>).kotlin.concurrent/getAndAddField(kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.getAndAddField` — fun KMutableProperty0.getAndAddField(Long): Long  -- `final fun (kotlin.reflect/KMutableProperty0<kotlin/Long>).kotlin.concurrent/getAndAddField(kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.getAndAddField` — fun KMutableProperty0.getAndAddField(Short): Short  -- `final fun (kotlin.reflect/KMutableProperty0<kotlin/Short>).kotlin.concurrent/getAndAddField(kotlin/Short): kotlin/Short`
    - `kotlin.concurrent.getAndSetField` — fun KMutableProperty0.getAndSetField(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.reflect/KMutableProperty0<#A>).kotlin.concurrent/getAndSetField(#A): #A`

- [ ] KSP-1085: kotlin.concurrent.AtomicArray top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicArray.<init>` — constructor (Array)  -- `constructor <init>(kotlin/Array<#A>)`

- [ ] KSP-1086: kotlin.concurrent.AtomicArray.AtomicArray の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.concurrent.AtomicArray` / receiver `AtomicArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicArray/AtomicArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicArray_AtomicArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicArray_AtomicArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicArray_AtomicArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicArray.compareAndExchange` — fun AtomicArray.compareAndExchange(Int, , ): #A  -- `final fun compareAndExchange(kotlin/Int, #A, #A): #A`
    - `kotlin.concurrent.AtomicArray.compareAndSet` — fun AtomicArray.compareAndSet(Int, , ): Boolean  -- `final fun compareAndSet(kotlin/Int, #A, #A): kotlin/Boolean`
    - `kotlin.concurrent.AtomicArray.get` — fun AtomicArray.get(Int): #A  -- `final fun get(kotlin/Int): #A`
    - `kotlin.concurrent.AtomicArray.getAndSet` — fun AtomicArray.getAndSet(Int, ): #A  -- `final fun getAndSet(kotlin/Int, #A): #A`
    - `kotlin.concurrent.AtomicArray.length` — val AtomicArray.length: Int  -- `final val length`
    - `kotlin.concurrent.AtomicArray.set` — fun AtomicArray.set(Int, ): Unit  -- `final fun set(kotlin/Int, #A)`
    - `kotlin.concurrent.AtomicArray.toString` — fun AtomicArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1087: kotlin.concurrent.AtomicInt top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicInt` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicInt/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicInt_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicInt_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicInt_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicInt.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`

- [ ] KSP-1088: kotlin.concurrent.AtomicInt.AtomicInt の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.concurrent.AtomicInt` / receiver `AtomicInt`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicInt/AtomicInt.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicInt_AtomicInt_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicInt_AtomicInt_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicInt_AtomicInt_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicInt.compareAndExchange` — fun AtomicInt.compareAndExchange(Int, Int): Int  -- `final fun compareAndExchange(kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.AtomicInt.getAndAdd` — fun AtomicInt.getAndAdd(Int): Int  -- `final fun getAndAdd(kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.AtomicInt.getAndDecrement` — fun AtomicInt.getAndDecrement(): Int  -- `final fun getAndDecrement(): kotlin/Int`
    - `kotlin.concurrent.AtomicInt.getAndIncrement` — fun AtomicInt.getAndIncrement(): Int  -- `final fun getAndIncrement(): kotlin/Int`
    - `kotlin.concurrent.AtomicInt.toString` — fun AtomicInt.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.AtomicInt.value` — val AtomicInt.value: Int  -- `final var value`

- [x] KSP-1089: kotlin.concurrent.AtomicIntArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.AtomicIntArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicIntArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicIntArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicIntArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicIntArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: Kotlin 2.3.10 Native の public AtomicIntArray(Int) を kk_atomic_int_array_create に接続する source-backed overload として追加し、@PublishedApi internal AtomicIntArray(IntArray) はコピーを作る bundled Kotlin 実装として追加した。既存の residual member bridges と Runtime ABI は保持し、同名の2引数 initializer factory がある場合の compiler special-case は arity 単位で通常 source overload を優先できるようにした。
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicIntArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.concurrent.AtomicIntArray.<init>` — constructor (IntArray)  -- `constructor <init>(kotlin/IntArray)`

- [ ] KSP-1090: kotlin.concurrent.AtomicIntArray.AtomicIntArray の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.concurrent.AtomicIntArray` / receiver `AtomicIntArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicIntArray/AtomicIntArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicIntArray_AtomicIntArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicIntArray_AtomicIntArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicIntArray_AtomicIntArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicIntArray.compareAndExchange` — fun AtomicIntArray.compareAndExchange(Int, Int, Int): Int  -- `final fun compareAndExchange(kotlin/Int, kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.AtomicIntArray.compareAndSet` — fun AtomicIntArray.compareAndSet(Int, Int, Int): Boolean  -- `final fun compareAndSet(kotlin/Int, kotlin/Int, kotlin/Int): kotlin/Boolean`
    - `kotlin.concurrent.AtomicIntArray.length` — val AtomicIntArray.length: Int  -- `final val length`
    - `kotlin.concurrent.AtomicIntArray.toString` — fun AtomicIntArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1091: kotlin.concurrent.AtomicLong top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicLong` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicLong/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicLong_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLong_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLong_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicLong.<init>` — constructor (Long)  -- `constructor <init>(kotlin/Long)`

- [ ] KSP-1092: kotlin.concurrent.AtomicLong.AtomicLong の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.concurrent.AtomicLong` / receiver `AtomicLong`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicLong/AtomicLong.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicLong_AtomicLong_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLong_AtomicLong_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLong_AtomicLong_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicLong.compareAndExchange` — fun AtomicLong.compareAndExchange(Long, Long): Long  -- `final fun compareAndExchange(kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.AtomicLong.getAndAdd` — fun AtomicLong.getAndAdd(Long): Long  -- `final fun getAndAdd(kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.AtomicLong.getAndDecrement` — fun AtomicLong.getAndDecrement(): Long  -- `final fun getAndDecrement(): kotlin/Long`
    - `kotlin.concurrent.AtomicLong.getAndIncrement` — fun AtomicLong.getAndIncrement(): Long  -- `final fun getAndIncrement(): kotlin/Long`
    - `kotlin.concurrent.AtomicLong.toString` — fun AtomicLong.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.AtomicLong.value` — val AtomicLong.value: Long  -- `final var value`

- [ ] KSP-1093: kotlin.concurrent.AtomicLongArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.AtomicLongArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicLongArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicLongArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLongArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLongArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicLongArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.concurrent.AtomicLongArray.<init>` — constructor (LongArray)  -- `constructor <init>(kotlin/LongArray)`

- [ ] KSP-1094: kotlin.concurrent.AtomicLongArray.AtomicLongArray の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.concurrent.AtomicLongArray` / receiver `AtomicLongArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicLongArray/AtomicLongArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicLongArray_AtomicLongArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLongArray_AtomicLongArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicLongArray_AtomicLongArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicLongArray.compareAndExchange` — fun AtomicLongArray.compareAndExchange(Int, Long, Long): Long  -- `final fun compareAndExchange(kotlin/Int, kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.AtomicLongArray.compareAndSet` — fun AtomicLongArray.compareAndSet(Int, Long, Long): Boolean  -- `final fun compareAndSet(kotlin/Int, kotlin/Long, kotlin/Long): kotlin/Boolean`
    - `kotlin.concurrent.AtomicLongArray.length` — val AtomicLongArray.length: Int  -- `final val length`
    - `kotlin.concurrent.AtomicLongArray.toString` — fun AtomicLongArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1095: kotlin.concurrent.AtomicNativePtr top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicNativePtr` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicNativePtr/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicNativePtr_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicNativePtr_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicNativePtr_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicNativePtr.<init>` — constructor (NativePtr)  -- `constructor <init>(kotlin.native.internal/NativePtr)`

- [ ] KSP-1096: kotlin.concurrent.AtomicNativePtr.AtomicNativePtr の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.concurrent.AtomicNativePtr` / receiver `AtomicNativePtr`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicNativePtr/AtomicNativePtr.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicNativePtr.compareAndExchange` — fun AtomicNativePtr.compareAndExchange(NativePtr, NativePtr): NativePtr  -- `final fun compareAndExchange(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.AtomicNativePtr.compareAndSet` — fun AtomicNativePtr.compareAndSet(NativePtr, NativePtr): Boolean  -- `final fun compareAndSet(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin/Boolean`
    - `kotlin.concurrent.AtomicNativePtr.getAndSet` — fun AtomicNativePtr.getAndSet(NativePtr): NativePtr  -- `final fun getAndSet(kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.AtomicNativePtr.toString` — fun AtomicNativePtr.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.AtomicNativePtr.value` — val AtomicNativePtr.value: NativePtr  -- `final var value`

- [ ] KSP-1097: kotlin.concurrent.AtomicReference top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.AtomicReference` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicReference/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicReference_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicReference_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicReference_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicReference.<init>` — constructor ()  -- `constructor <init>(#A)`

- [ ] KSP-1098: kotlin.concurrent.AtomicReference.AtomicReference の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.concurrent.AtomicReference` / receiver `AtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicReference/AtomicReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_AtomicReference_AtomicReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicReference_AtomicReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicReference_AtomicReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.AtomicReference.compareAndExchange` — fun AtomicReference.compareAndExchange(, ): #A  -- `final fun compareAndExchange(#A, #A): #A`
    - `kotlin.concurrent.AtomicReference.getAndSet` — fun AtomicReference.getAndSet(): #A  -- `final fun getAndSet(#A): #A`
    - `kotlin.concurrent.AtomicReference.toString` — fun AtomicReference.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.AtomicReference.value` — val AtomicReference.value: #A  -- `final var value`

- [ ] KSP-1100: kotlin.concurrent.atomics top-level の未実装 stdlib API を実装する（13 件）
  - 対象: `kotlin.concurrent.atomics` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicArray` — class kotlin.concurrent.atomics.AtomicArray  -- `final class <#A: kotlin/Any?> kotlin.concurrent.atomics/AtomicArray {`
    - `kotlin.concurrent.atomics.AtomicArray` — fun AtomicArray(Int, Function1): AtomicArray  -- `final inline fun <#A: reified kotlin/Any?> kotlin.concurrent.atomics/AtomicArray(kotlin/Int, kotlin/Function1<kotlin/Int, #A>): kotlin.concurrent.atomics/AtomicArray<#A>`
    - `kotlin.concurrent.atomics.AtomicBoolean` — class kotlin.concurrent.atomics.AtomicBoolean  -- `final class kotlin.concurrent.atomics/AtomicBoolean {`
    - `kotlin.concurrent.atomics.AtomicInt` — class kotlin.concurrent.atomics.AtomicInt  -- `final class kotlin.concurrent.atomics/AtomicInt {`
    - `kotlin.concurrent.atomics.AtomicIntArray` — class kotlin.concurrent.atomics.AtomicIntArray  -- `final class kotlin.concurrent.atomics/AtomicIntArray {`
    - `kotlin.concurrent.atomics.AtomicIntArray` — fun AtomicIntArray(Int, Function1): AtomicIntArray  -- `final inline fun kotlin.concurrent.atomics/AtomicIntArray(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Int>): kotlin.concurrent.atomics/AtomicIntArray`
    - `kotlin.concurrent.atomics.AtomicLong` — class kotlin.concurrent.atomics.AtomicLong  -- `final class kotlin.concurrent.atomics/AtomicLong {`
    - `kotlin.concurrent.atomics.AtomicLongArray` — class kotlin.concurrent.atomics.AtomicLongArray  -- `final class kotlin.concurrent.atomics/AtomicLongArray {`
    - `kotlin.concurrent.atomics.AtomicLongArray` — fun AtomicLongArray(Int, Function1): AtomicLongArray  -- `final inline fun kotlin.concurrent.atomics/AtomicLongArray(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Long>): kotlin.concurrent.atomics/AtomicLongArray`
    - `kotlin.concurrent.atomics.AtomicNativePtr` — class kotlin.concurrent.atomics.AtomicNativePtr  -- `final class kotlin.concurrent.atomics/AtomicNativePtr {`
    - `kotlin.concurrent.atomics.AtomicReference` — class kotlin.concurrent.atomics.AtomicReference  -- `final class <#A: kotlin/Any?> kotlin.concurrent.atomics/AtomicReference {`
    - `kotlin.concurrent.atomics.ExperimentalAtomicApi` — class kotlin.concurrent.atomics.ExperimentalAtomicApi  -- `open annotation class kotlin.concurrent.atomics/ExperimentalAtomicApi : kotlin/Annotation {`
    - `kotlin.concurrent.atomics.atomicArrayOfNulls` — fun atomicArrayOfNulls(Int): AtomicArray  -- `final inline fun <#A: reified kotlin/Any?> kotlin.concurrent.atomics/atomicArrayOfNulls(kotlin/Int): kotlin.concurrent.atomics/AtomicArray<#A?>`

- [ ] KSP-1101: kotlin.concurrent.atomics.AtomicArray の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicArrayMigration.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.fetchAndUpdateAt` — fun AtomicArray.fetchAndUpdateAt(Int, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicArray<#A>).kotlin.concurrent.atomics/fetchAndUpdateAt(kotlin/Int, kotlin/Function1<#A, #A>): #A`
    - `kotlin.concurrent.atomics.updateAndFetchAt` — fun AtomicArray.updateAndFetchAt(Int, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicArray<#A>).kotlin.concurrent.atomics/updateAndFetchAt(kotlin/Int, kotlin/Function1<#A, #A>): #A`

- [ ] KSP-1102: kotlin.concurrent.atomics.AtomicInt の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicInt`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicInt.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicInt_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.decrementAndFetch` — fun AtomicInt.decrementAndFetch(): Int  -- `final fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/decrementAndFetch(): kotlin/Int`
    - `kotlin.concurrent.atomics.incrementAndFetch` — fun AtomicInt.incrementAndFetch(): Int  -- `final fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/incrementAndFetch(): kotlin/Int`
    - `kotlin.concurrent.atomics.minusAssign` — fun AtomicInt.minusAssign(Int): Unit  -- `final fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/minusAssign(kotlin/Int)`
    - `kotlin.concurrent.atomics.plusAssign` — fun AtomicInt.plusAssign(Int): Unit  -- `final fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/plusAssign(kotlin/Int)`
    - `kotlin.concurrent.atomics.update` — fun AtomicInt.update(Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/update(kotlin/Function1<kotlin/Int, kotlin/Int>)`
    - `kotlin.concurrent.atomics.updateAndFetch` — fun AtomicInt.updateAndFetch(Function1): Int  -- `final inline fun (kotlin.concurrent.atomics/AtomicInt).kotlin.concurrent.atomics/updateAndFetch(kotlin/Function1<kotlin/Int, kotlin/Int>): kotlin/Int`

- [ ] KSP-1103: kotlin.concurrent.atomics.AtomicIntArray の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicIntArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicArrayMigration.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.updateAndFetchAt` — fun AtomicIntArray.updateAndFetchAt(Int, Function1): Int  -- `final inline fun (kotlin.concurrent.atomics/AtomicIntArray).kotlin.concurrent.atomics/updateAndFetchAt(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Int>): kotlin/Int`
    - `kotlin.concurrent.atomics.updateAt` — fun AtomicIntArray.updateAt(Int, Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicIntArray).kotlin.concurrent.atomics/updateAt(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Int>)`

- [ ] KSP-1104: kotlin.concurrent.atomics.AtomicLong の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicLong`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLong.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLong_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.decrementAndFetch` — fun AtomicLong.decrementAndFetch(): Long  -- `final fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/decrementAndFetch(): kotlin/Long`
    - `kotlin.concurrent.atomics.incrementAndFetch` — fun AtomicLong.incrementAndFetch(): Long  -- `final fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/incrementAndFetch(): kotlin/Long`
    - `kotlin.concurrent.atomics.minusAssign` — fun AtomicLong.minusAssign(Long): Unit  -- `final fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/minusAssign(kotlin/Long)`
    - `kotlin.concurrent.atomics.plusAssign` — fun AtomicLong.plusAssign(Long): Unit  -- `final fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/plusAssign(kotlin/Long)`
    - `kotlin.concurrent.atomics.update` — fun AtomicLong.update(Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/update(kotlin/Function1<kotlin/Long, kotlin/Long>)`
    - `kotlin.concurrent.atomics.updateAndFetch` — fun AtomicLong.updateAndFetch(Function1): Long  -- `final inline fun (kotlin.concurrent.atomics/AtomicLong).kotlin.concurrent.atomics/updateAndFetch(kotlin/Function1<kotlin/Long, kotlin/Long>): kotlin/Long`

- [ ] KSP-1105: kotlin.concurrent.atomics.AtomicLongArray の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicLongArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicArrayMigration.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.updateAndFetchAt` — fun AtomicLongArray.updateAndFetchAt(Int, Function1): Long  -- `final inline fun (kotlin.concurrent.atomics/AtomicLongArray).kotlin.concurrent.atomics/updateAndFetchAt(kotlin/Int, kotlin/Function1<kotlin/Long, kotlin/Long>): kotlin/Long`
    - `kotlin.concurrent.atomics.updateAt` — fun AtomicLongArray.updateAt(Int, Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicLongArray).kotlin.concurrent.atomics/updateAt(kotlin/Int, kotlin/Function1<kotlin/Long, kotlin/Long>)`

- [ ] KSP-1106: kotlin.concurrent.atomics.AtomicNativePtr の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicNativePtr`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicNativePtr.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.fetchAndUpdate` — fun AtomicNativePtr.fetchAndUpdate(Function1): NativePtr  -- `final inline fun (kotlin.concurrent.atomics/AtomicNativePtr).kotlin.concurrent.atomics/fetchAndUpdate(kotlin/Function1<kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr>): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.update` — fun AtomicNativePtr.update(Function1): Unit  -- `final inline fun (kotlin.concurrent.atomics/AtomicNativePtr).kotlin.concurrent.atomics/update(kotlin/Function1<kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr>)`
    - `kotlin.concurrent.atomics.updateAndFetch` — fun AtomicNativePtr.updateAndFetch(Function1): NativePtr  -- `final inline fun (kotlin.concurrent.atomics/AtomicNativePtr).kotlin.concurrent.atomics/updateAndFetch(kotlin/Function1<kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr>): kotlin.native.internal/NativePtr`

- [ ] KSP-1107: kotlin.concurrent.atomics.AtomicReference の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.concurrent.atomics` / receiver `AtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.fetchAndUpdate` — fun AtomicReference.fetchAndUpdate(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicReference<#A>).kotlin.concurrent.atomics/fetchAndUpdate(kotlin/Function1<#A, #A>): #A`
    - `kotlin.concurrent.atomics.update` — fun AtomicReference.update(Function1): Unit  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicReference<#A>).kotlin.concurrent.atomics/update(kotlin/Function1<#A, #A>)`
    - `kotlin.concurrent.atomics.updateAndFetch` — fun AtomicReference.updateAndFetch(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.concurrent.atomics/AtomicReference<#A>).kotlin.concurrent.atomics/updateAndFetch(kotlin/Function1<#A, #A>): #A`

- [ ] KSP-1108: kotlin.concurrent.atomics.AtomicArray top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.atomics.AtomicArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicArray.<init>` — constructor (Array)  -- `constructor <init>(kotlin/Array<#A>)`

- [ ] KSP-1109: kotlin.concurrent.atomics.AtomicArray.AtomicArray の未実装 stdlib API を実装する（13 件）
  - 対象: `kotlin.concurrent.atomics.AtomicArray` / receiver `AtomicArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicArray/AtomicArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicArray_AtomicArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_AtomicArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicArray_AtomicArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicArray.compareAndExchange` — fun AtomicArray.compareAndExchange(Int, , ): #A  -- `final fun compareAndExchange(kotlin/Int, #A, #A): #A`
    - `kotlin.concurrent.atomics.AtomicArray.compareAndExchangeAt` — fun AtomicArray.compareAndExchangeAt(Int, , ): #A  -- `final fun compareAndExchangeAt(kotlin/Int, #A, #A): #A`
    - `kotlin.concurrent.atomics.AtomicArray.compareAndSet` — fun AtomicArray.compareAndSet(Int, , ): Boolean  -- `final fun compareAndSet(kotlin/Int, #A, #A): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicArray.compareAndSetAt` — fun AtomicArray.compareAndSetAt(Int, , ): Boolean  -- `final fun compareAndSetAt(kotlin/Int, #A, #A): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicArray.exchangeAt` — fun AtomicArray.exchangeAt(Int, ): #A  -- `final fun exchangeAt(kotlin/Int, #A): #A`
    - `kotlin.concurrent.atomics.AtomicArray.get` — fun AtomicArray.get(Int): #A  -- `final fun get(kotlin/Int): #A`
    - `kotlin.concurrent.atomics.AtomicArray.getAndSet` — fun AtomicArray.getAndSet(Int, ): #A  -- `final fun getAndSet(kotlin/Int, #A): #A`
    - `kotlin.concurrent.atomics.AtomicArray.length` — val AtomicArray.length: Int  -- `final val length`
    - `kotlin.concurrent.atomics.AtomicArray.loadAt` — fun AtomicArray.loadAt(Int): #A  -- `final fun loadAt(kotlin/Int): #A`
    - `kotlin.concurrent.atomics.AtomicArray.set` — fun AtomicArray.set(Int, ): Unit  -- `final fun set(kotlin/Int, #A)`
    - `kotlin.concurrent.atomics.AtomicArray.size` — val AtomicArray.size: Int  -- `final val size`
    - `kotlin.concurrent.atomics.AtomicArray.storeAt` — fun AtomicArray.storeAt(Int, ): Unit  -- `final fun storeAt(kotlin/Int, #A)`
    - `kotlin.concurrent.atomics.AtomicArray.toString` — fun AtomicArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1110: kotlin.concurrent.atomics.AtomicBoolean top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.atomics.AtomicBoolean` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicBoolean/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicBoolean_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicBoolean_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicBoolean_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicBoolean.<init>` — constructor (Boolean)  -- `constructor <init>(kotlin/Boolean)`

- [ ] KSP-1111: kotlin.concurrent.atomics.AtomicBoolean.AtomicBoolean の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.concurrent.atomics.AtomicBoolean` / receiver `AtomicBoolean`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicBoolean/AtomicBoolean.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicBoolean_AtomicBoolean_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicBoolean_AtomicBoolean_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicBoolean_AtomicBoolean_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicBoolean.compareAndExchange` — fun AtomicBoolean.compareAndExchange(Boolean, Boolean): Boolean  -- `final fun compareAndExchange(kotlin/Boolean, kotlin/Boolean): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicBoolean.exchange` — fun AtomicBoolean.exchange(Boolean): Boolean  -- `final fun exchange(kotlin/Boolean): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicBoolean.load` — fun AtomicBoolean.load(): Boolean  -- `final fun load(): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicBoolean.store` — fun AtomicBoolean.store(Boolean): Unit  -- `final fun store(kotlin/Boolean)`
    - `kotlin.concurrent.atomics.AtomicBoolean.toString` — fun AtomicBoolean.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1112: kotlin.concurrent.atomics.AtomicInt top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.atomics.AtomicInt` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicInt/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicInt_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicInt.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`

- [ ] KSP-1113: kotlin.concurrent.atomics.AtomicInt.AtomicInt の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.concurrent.atomics.AtomicInt` / receiver `AtomicInt`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicInt/AtomicInt.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicInt_AtomicInt_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_AtomicInt_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicInt_AtomicInt_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicInt.addAndFetch` — fun AtomicInt.addAndFetch(Int): Int  -- `final fun addAndFetch(kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.compareAndExchange` — fun AtomicInt.compareAndExchange(Int, Int): Int  -- `final fun compareAndExchange(kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.exchange` — fun AtomicInt.exchange(Int): Int  -- `final fun exchange(kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.getAndAdd` — fun AtomicInt.getAndAdd(Int): Int  -- `final fun getAndAdd(kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.getAndDecrement` — fun AtomicInt.getAndDecrement(): Int  -- `final fun getAndDecrement(): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.getAndIncrement` — fun AtomicInt.getAndIncrement(): Int  -- `final fun getAndIncrement(): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.load` — fun AtomicInt.load(): Int  -- `final fun load(): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicInt.store` — fun AtomicInt.store(Int): Unit  -- `final fun store(kotlin/Int)`
    - `kotlin.concurrent.atomics.AtomicInt.toString` — fun AtomicInt.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.atomics.AtomicInt.value` — val AtomicInt.value: Int  -- `final var value`

- [ ] KSP-1114: kotlin.concurrent.atomics.AtomicIntArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics.AtomicIntArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicIntArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicIntArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.concurrent.atomics.AtomicIntArray.<init>` — constructor (IntArray)  -- `constructor <init>(kotlin/IntArray)`

- [ ] KSP-1115: kotlin.concurrent.atomics.AtomicIntArray.AtomicIntArray の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.concurrent.atomics.AtomicIntArray` / receiver `AtomicIntArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicIntArray/AtomicIntArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicIntArray_AtomicIntArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_AtomicIntArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicIntArray_AtomicIntArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicIntArray.compareAndExchange` — fun AtomicIntArray.compareAndExchange(Int, Int, Int): Int  -- `final fun compareAndExchange(kotlin/Int, kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.concurrent.atomics.AtomicIntArray.compareAndSet` — fun AtomicIntArray.compareAndSet(Int, Int, Int): Boolean  -- `final fun compareAndSet(kotlin/Int, kotlin/Int, kotlin/Int): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicIntArray.length` — val AtomicIntArray.length: Int  -- `final val length`
    - `kotlin.concurrent.atomics.AtomicIntArray.size` — val AtomicIntArray.size: Int  -- `final val size`
    - `kotlin.concurrent.atomics.AtomicIntArray.toString` — fun AtomicIntArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1116: kotlin.concurrent.atomics.AtomicLong top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.atomics.AtomicLong` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLong/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLong_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicLong.<init>` — constructor (Long)  -- `constructor <init>(kotlin/Long)`

- [ ] KSP-1117: kotlin.concurrent.atomics.AtomicLong.AtomicLong の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.concurrent.atomics.AtomicLong` / receiver `AtomicLong`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLong/AtomicLong.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLong_AtomicLong_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_AtomicLong_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLong_AtomicLong_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicLong.addAndFetch` — fun AtomicLong.addAndFetch(Long): Long  -- `final fun addAndFetch(kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.compareAndExchange` — fun AtomicLong.compareAndExchange(Long, Long): Long  -- `final fun compareAndExchange(kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.exchange` — fun AtomicLong.exchange(Long): Long  -- `final fun exchange(kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.getAndAdd` — fun AtomicLong.getAndAdd(Long): Long  -- `final fun getAndAdd(kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.getAndDecrement` — fun AtomicLong.getAndDecrement(): Long  -- `final fun getAndDecrement(): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.getAndIncrement` — fun AtomicLong.getAndIncrement(): Long  -- `final fun getAndIncrement(): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.load` — fun AtomicLong.load(): Long  -- `final fun load(): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLong.store` — fun AtomicLong.store(Long): Unit  -- `final fun store(kotlin/Long)`
    - `kotlin.concurrent.atomics.AtomicLong.toString` — fun AtomicLong.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.atomics.AtomicLong.value` — val AtomicLong.value: Long  -- `final var value`

- [ ] KSP-1118: kotlin.concurrent.atomics.AtomicLongArray top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.concurrent.atomics.AtomicLongArray` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLongArray/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicLongArray.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.concurrent.atomics.AtomicLongArray.<init>` — constructor (LongArray)  -- `constructor <init>(kotlin/LongArray)`

- [ ] KSP-1119: kotlin.concurrent.atomics.AtomicLongArray.AtomicLongArray の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.concurrent.atomics.AtomicLongArray` / receiver `AtomicLongArray`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicLongArray/AtomicLongArray.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicLongArray_AtomicLongArray_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_AtomicLongArray_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicLongArray_AtomicLongArray_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicLongArray.compareAndExchange` — fun AtomicLongArray.compareAndExchange(Int, Long, Long): Long  -- `final fun compareAndExchange(kotlin/Int, kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.concurrent.atomics.AtomicLongArray.compareAndSet` — fun AtomicLongArray.compareAndSet(Int, Long, Long): Boolean  -- `final fun compareAndSet(kotlin/Int, kotlin/Long, kotlin/Long): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicLongArray.length` — val AtomicLongArray.length: Int  -- `final val length`
    - `kotlin.concurrent.atomics.AtomicLongArray.size` — val AtomicLongArray.size: Int  -- `final val size`
    - `kotlin.concurrent.atomics.AtomicLongArray.toString` — fun AtomicLongArray.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1121: kotlin.concurrent.atomics.AtomicNativePtr.AtomicNativePtr の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.concurrent.atomics.AtomicNativePtr` / receiver `AtomicNativePtr`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicNativePtr/AtomicNativePtr.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicNativePtr_AtomicNativePtr_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicNativePtr.compareAndExchange` — fun AtomicNativePtr.compareAndExchange(NativePtr, NativePtr): NativePtr  -- `final fun compareAndExchange(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.AtomicNativePtr.compareAndSet` — fun AtomicNativePtr.compareAndSet(NativePtr, NativePtr): Boolean  -- `final fun compareAndSet(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin/Boolean`
    - `kotlin.concurrent.atomics.AtomicNativePtr.exchange` — fun AtomicNativePtr.exchange(NativePtr): NativePtr  -- `final fun exchange(kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.AtomicNativePtr.getAndSet` — fun AtomicNativePtr.getAndSet(NativePtr): NativePtr  -- `final fun getAndSet(kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.AtomicNativePtr.load` — fun AtomicNativePtr.load(): NativePtr  -- `final fun load(): kotlin.native.internal/NativePtr`
    - `kotlin.concurrent.atomics.AtomicNativePtr.store` — fun AtomicNativePtr.store(NativePtr): Unit  -- `final fun store(kotlin.native.internal/NativePtr)`
    - `kotlin.concurrent.atomics.AtomicNativePtr.toString` — fun AtomicNativePtr.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.atomics.AtomicNativePtr.value` — val AtomicNativePtr.value: NativePtr  -- `final var value`

- [ ] KSP-1122: kotlin.concurrent.atomics.AtomicReference top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.concurrent.atomics.AtomicReference` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicReference/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicReference_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicReference.<init>` — constructor ()  -- `constructor <init>(#A)`

- [ ] KSP-1123: kotlin.concurrent.atomics.AtomicReference.AtomicReference の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.concurrent.atomics.AtomicReference` / receiver `AtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/concurrent/atomics/AtomicReference/AtomicReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_concurrent_atomics_AtomicReference_AtomicReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_AtomicReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_concurrent_atomics_AtomicReference_AtomicReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.concurrent.atomics.AtomicReference.compareAndExchange` — fun AtomicReference.compareAndExchange(, ): #A  -- `final fun compareAndExchange(#A, #A): #A`
    - `kotlin.concurrent.atomics.AtomicReference.exchange` — fun AtomicReference.exchange(): #A  -- `final fun exchange(#A): #A`
    - `kotlin.concurrent.atomics.AtomicReference.getAndSet` — fun AtomicReference.getAndSet(): #A  -- `final fun getAndSet(#A): #A`
    - `kotlin.concurrent.atomics.AtomicReference.load` — fun AtomicReference.load(): #A  -- `final fun load(): #A`
    - `kotlin.concurrent.atomics.AtomicReference.store` — fun AtomicReference.store(): Unit  -- `final fun store(#A)`
    - `kotlin.concurrent.atomics.AtomicReference.toString` — fun AtomicReference.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.concurrent.atomics.AtomicReference.value` — val AtomicReference.value: #A  -- `final var value`

- [ ] KSP-1131: kotlin.coroutines top-level の未実装 stdlib API を実装する（12 件）
  - 対象: `kotlin.coroutines` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.AbstractCoroutineContextElement` — class kotlin.coroutines.AbstractCoroutineContextElement  -- `abstract class kotlin.coroutines/AbstractCoroutineContextElement : kotlin.coroutines/CoroutineContext.Element {`
    - `kotlin.coroutines.AbstractCoroutineContextKey` — class kotlin.coroutines.AbstractCoroutineContextKey  -- `abstract class <#A: kotlin.coroutines/CoroutineContext.Element, #B: #A> kotlin.coroutines/AbstractCoroutineContextKey : kotlin.coroutines/CoroutineContext.Key<#B> {`
    - `kotlin.coroutines.Continuation` — interface kotlin.coroutines.Continuation  -- `abstract interface <#A: in kotlin/Any?> kotlin.coroutines/Continuation {`
    - `kotlin.coroutines.Continuation` — fun Continuation(CoroutineContext, Function1): Continuation  -- `final inline fun <#A: kotlin/Any?> kotlin.coroutines/Continuation(kotlin.coroutines/CoroutineContext, crossinline kotlin/Function1<kotlin/Result<#A>, kotlin/Unit>): kotlin.coroutines/Continuation<#A>`
    - `kotlin.coroutines.ContinuationInterceptor` — interface kotlin.coroutines.ContinuationInterceptor  -- `abstract interface kotlin.coroutines/ContinuationInterceptor : kotlin.coroutines/CoroutineContext.Element {`
    - `kotlin.coroutines.CoroutineContext` — interface kotlin.coroutines.CoroutineContext  -- `abstract interface kotlin.coroutines/CoroutineContext {`
    - `kotlin.coroutines.EmptyCoroutineContext` — object kotlin.coroutines.EmptyCoroutineContext  -- `final object kotlin.coroutines/EmptyCoroutineContext : kotlin.coroutines/CoroutineContext, kotlin.io/Serializable {`
    - `kotlin.coroutines.RestrictsSuspension` — class kotlin.coroutines.RestrictsSuspension  -- `open annotation class kotlin.coroutines/RestrictsSuspension : kotlin/Annotation {`
    - `kotlin.coroutines.SafeContinuation` — class kotlin.coroutines.SafeContinuation  -- `final class <#A: in kotlin/Any?> kotlin.coroutines/SafeContinuation : kotlin.coroutines/Continuation<#A> {`
    - `kotlin.coroutines.SuspendFunction` — interface kotlin.coroutines.SuspendFunction  -- `abstract interface <#A: out kotlin/Any?> kotlin.coroutines/SuspendFunction`
    - `kotlin.coroutines.coroutineContext` — val coroutineContext  -- `final val kotlin.coroutines/coroutineContext`
    - `kotlin.coroutines.suspendCoroutine` — fun suspendCoroutine(Function1): #A  -- `final suspend inline fun <#A: kotlin/Any?> kotlin.coroutines/suspendCoroutine(crossinline kotlin/Function1<kotlin.coroutines/Continuation<#A>, kotlin/Unit>): #A`

- [ ] KSP-1136: kotlin.coroutines.AbstractCoroutineContextElement top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.coroutines.AbstractCoroutineContextElement` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/AbstractCoroutineContextElement/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.AbstractCoroutineContextElement.<init>` — constructor (Key)  -- `constructor <init>(kotlin.coroutines/CoroutineContext.Key<*>)`

- [ ] KSP-1137: kotlin.coroutines.AbstractCoroutineContextElement.AbstractCoroutineContextElement の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.coroutines.AbstractCoroutineContextElement` / receiver `AbstractCoroutineContextElement`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/AbstractCoroutineContextElement/AbstractCoroutineContextElement.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_AbstractCoroutineContextElement_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_AbstractCoroutineContextElement_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_AbstractCoroutineContextElement_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.AbstractCoroutineContextElement.key` — val AbstractCoroutineContextElement.key: Key  -- `open val key`

- [ ] KSP-1138: kotlin.coroutines.AbstractCoroutineContextKey top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.coroutines.AbstractCoroutineContextKey` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/AbstractCoroutineContextKey/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_AbstractCoroutineContextKey_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_AbstractCoroutineContextKey_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_AbstractCoroutineContextKey_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.AbstractCoroutineContextKey.<init>` — constructor (Key, Function1)  -- `constructor <init>(kotlin.coroutines/CoroutineContext.Key<#A>, kotlin/Function1<kotlin.coroutines/CoroutineContext.Element, #B?>)`

- [ ] KSP-1139: kotlin.coroutines.Continuation.Continuation の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.coroutines.Continuation` / receiver `Continuation`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/Continuation/Continuation.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_Continuation_Continuation_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_Continuation_Continuation_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_Continuation_Continuation_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.Continuation.context` — val Continuation.context: CoroutineContext  -- `abstract val context`
    - `kotlin.coroutines.Continuation.resumeWith` — fun Continuation.resumeWith(Result): Unit  -- `abstract fun resumeWith(kotlin/Result<#A>)`

- [ ] KSP-1141: kotlin.coroutines.ContinuationInterceptor.ContinuationInterceptor の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.coroutines.ContinuationInterceptor` / receiver `ContinuationInterceptor`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/ContinuationInterceptor/ContinuationInterceptor.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_ContinuationInterceptor_ContinuationInterceptor_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_ContinuationInterceptor_ContinuationInterceptor_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_ContinuationInterceptor_ContinuationInterceptor_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.ContinuationInterceptor.get` — fun ContinuationInterceptor.get(Key): #A1  -- `open fun <#A1: kotlin.coroutines/CoroutineContext.Element> get(kotlin.coroutines/CoroutineContext.Key<#A1>): #A1?`
    - `kotlin.coroutines.ContinuationInterceptor.interceptContinuation` — fun ContinuationInterceptor.interceptContinuation(Continuation): Continuation  -- `abstract fun <#A1: kotlin/Any?> interceptContinuation(kotlin.coroutines/Continuation<#A1>): kotlin.coroutines/Continuation<#A1>`
    - `kotlin.coroutines.ContinuationInterceptor.minusKey` — fun ContinuationInterceptor.minusKey(Key): CoroutineContext  -- `open fun minusKey(kotlin.coroutines/CoroutineContext.Key<*>): kotlin.coroutines/CoroutineContext`
    - `kotlin.coroutines.ContinuationInterceptor.releaseInterceptedContinuation` — fun ContinuationInterceptor.releaseInterceptedContinuation(Continuation): Unit  -- `open fun releaseInterceptedContinuation(kotlin.coroutines/Continuation<*>)`

- [ ] KSP-1142: kotlin.coroutines.CoroutineContext top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.coroutines.CoroutineContext` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/CoroutineContext/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_CoroutineContext_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.CoroutineContext.Element` — interface kotlin.coroutines.CoroutineContext.Element  -- `abstract interface Element : kotlin.coroutines/CoroutineContext {`
    - `kotlin.coroutines.CoroutineContext.Key` — interface kotlin.coroutines.CoroutineContext.Key  -- `abstract interface <#A1: kotlin.coroutines/CoroutineContext.Element> Key`

- [ ] KSP-1143: kotlin.coroutines.CoroutineContext.CoroutineContext の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.coroutines.CoroutineContext` / receiver `CoroutineContext`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/CoroutineContext/CoroutineContext.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_CoroutineContext_CoroutineContext_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_CoroutineContext_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_CoroutineContext_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.CoroutineContext.fold` — fun CoroutineContext.fold(, Function2): #A1  -- `abstract fun <#A1: kotlin/Any?> fold(#A1, kotlin/Function2<#A1, kotlin.coroutines/CoroutineContext.Element, #A1>): #A1`
    - `kotlin.coroutines.CoroutineContext.get` — fun CoroutineContext.get(Key): #A1  -- `abstract fun <#A1: kotlin.coroutines/CoroutineContext.Element> get(kotlin.coroutines/CoroutineContext.Key<#A1>): #A1?`
    - `kotlin.coroutines.CoroutineContext.minusKey` — fun CoroutineContext.minusKey(Key): CoroutineContext  -- `abstract fun minusKey(kotlin.coroutines/CoroutineContext.Key<*>): kotlin.coroutines/CoroutineContext`
    - `kotlin.coroutines.CoroutineContext.plus` — fun CoroutineContext.plus(CoroutineContext): CoroutineContext  -- `open fun plus(kotlin.coroutines/CoroutineContext): kotlin.coroutines/CoroutineContext`

- [ ] KSP-1144: kotlin.coroutines.CoroutineContext.Element.Element の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.coroutines.CoroutineContext.Element` / receiver `Element`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/CoroutineContext/Element/Element.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_CoroutineContext_Element_Element_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_Element_Element_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_CoroutineContext_Element_Element_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.CoroutineContext.Element.fold` — fun Element.fold(, Function2): #A2  -- `open fun <#A2: kotlin/Any?> fold(#A2, kotlin/Function2<#A2, kotlin.coroutines/CoroutineContext.Element, #A2>): #A2`
    - `kotlin.coroutines.CoroutineContext.Element.get` — fun Element.get(Key): #A2  -- `open fun <#A2: kotlin.coroutines/CoroutineContext.Element> get(kotlin.coroutines/CoroutineContext.Key<#A2>): #A2?`
    - `kotlin.coroutines.CoroutineContext.Element.key` — val Element.key: Key  -- `abstract val key`
    - `kotlin.coroutines.CoroutineContext.Element.minusKey` — fun Element.minusKey(Key): CoroutineContext  -- `open fun minusKey(kotlin.coroutines/CoroutineContext.Key<*>): kotlin.coroutines/CoroutineContext`

- [ ] KSP-1145: kotlin.coroutines.EmptyCoroutineContext.EmptyCoroutineContext の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.coroutines.EmptyCoroutineContext` / receiver `EmptyCoroutineContext`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/EmptyCoroutineContext/EmptyCoroutineContext.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_EmptyCoroutineContext_EmptyCoroutineContext_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_EmptyCoroutineContext_EmptyCoroutineContext_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_EmptyCoroutineContext_EmptyCoroutineContext_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.EmptyCoroutineContext.fold` — fun EmptyCoroutineContext.fold(, Function2): #A1  -- `final fun <#A1: kotlin/Any?> fold(#A1, kotlin/Function2<#A1, kotlin.coroutines/CoroutineContext.Element, #A1>): #A1`
    - `kotlin.coroutines.EmptyCoroutineContext.get` — fun EmptyCoroutineContext.get(Key): #A1  -- `final fun <#A1: kotlin.coroutines/CoroutineContext.Element> get(kotlin.coroutines/CoroutineContext.Key<#A1>): #A1?`
    - `kotlin.coroutines.EmptyCoroutineContext.hashCode` — fun EmptyCoroutineContext.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.coroutines.EmptyCoroutineContext.minusKey` — fun EmptyCoroutineContext.minusKey(Key): CoroutineContext  -- `final fun minusKey(kotlin.coroutines/CoroutineContext.Key<*>): kotlin.coroutines/CoroutineContext`
    - `kotlin.coroutines.EmptyCoroutineContext.plus` — fun EmptyCoroutineContext.plus(CoroutineContext): CoroutineContext  -- `final fun plus(kotlin.coroutines/CoroutineContext): kotlin.coroutines/CoroutineContext`
    - `kotlin.coroutines.EmptyCoroutineContext.toString` — fun EmptyCoroutineContext.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1147: kotlin.coroutines.SafeContinuation top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.coroutines.SafeContinuation` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/SafeContinuation/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_SafeContinuation_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_SafeContinuation_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_SafeContinuation_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.SafeContinuation.<init>` — constructor (Continuation)  -- `constructor <init>(kotlin.coroutines/Continuation<#A>)`

- [ ] KSP-1148: kotlin.coroutines.SafeContinuation.SafeContinuation の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.coroutines.SafeContinuation` / receiver `SafeContinuation`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/SafeContinuation/SafeContinuation.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_SafeContinuation_SafeContinuation_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_SafeContinuation_SafeContinuation_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_SafeContinuation_SafeContinuation_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.SafeContinuation.context` — val SafeContinuation.context: CoroutineContext  -- `final val context`
    - `kotlin.coroutines.SafeContinuation.getOrThrow` — fun SafeContinuation.getOrThrow(): Any  -- `final fun getOrThrow(): kotlin/Any?`
    - `kotlin.coroutines.SafeContinuation.resumeWith` — fun SafeContinuation.resumeWith(Result): Unit  -- `final fun resumeWith(kotlin/Result<#A>)`

- [ ] KSP-1149: kotlin.coroutines.cancellation top-level の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.coroutines.cancellation` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/cancellation/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_cancellation_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_cancellation_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_cancellation_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.cancellation.CancellationException` — class kotlin.coroutines.cancellation.CancellationException  -- `open class kotlin.coroutines.cancellation/CancellationException : kotlin/IllegalStateException {`
    - `kotlin.coroutines.cancellation.CancellationException` — fun CancellationException(Throwable): CancellationException  -- `final inline fun kotlin.coroutines.cancellation/CancellationException(kotlin/Throwable?): kotlin.coroutines.cancellation/CancellationException`
    - `kotlin.coroutines.cancellation.CancellationException` — fun CancellationException(String, Throwable): CancellationException  -- `final inline fun kotlin.coroutines.cancellation/CancellationException(kotlin/String?, kotlin/Throwable?): kotlin.coroutines.cancellation/CancellationException`

- [ ] KSP-1151: kotlin.coroutines.intrinsics top-level の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.coroutines.intrinsics` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/intrinsics/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_intrinsics_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED` — val COROUTINE_SUSPENDED  -- `final val kotlin.coroutines.intrinsics/COROUTINE_SUSPENDED`
    - `kotlin.coroutines.intrinsics.CoroutineSingletons` — enumClass kotlin.coroutines.intrinsics.CoroutineSingletons  -- `final enum class kotlin.coroutines.intrinsics/CoroutineSingletons : kotlin/Enum<kotlin.coroutines.intrinsics/CoroutineSingletons> {`
    - `kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturnFallback` — fun startCoroutineUninterceptedOrReturnFallback(SuspendFunction0, Continuation): Any  -- `final fun <#A: kotlin/Any?> kotlin.coroutines.intrinsics/startCoroutineUninterceptedOrReturnFallback(kotlin.coroutines/SuspendFunction0<#A>, kotlin.coroutines/Continuation<#A>): kotlin/Any?`
    - `kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturnFallback` — fun startCoroutineUninterceptedOrReturnFallback(SuspendFunction1, , Continuation): Any  -- `final fun <#A: kotlin/Any?, #B: kotlin/Any?> kotlin.coroutines.intrinsics/startCoroutineUninterceptedOrReturnFallback(kotlin.coroutines/SuspendFunction1<#A, #B>, #A, kotlin.coroutines/Continuation<#B>): kotlin/Any?`
    - `kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn` — fun suspendCoroutineUninterceptedOrReturn(Function1): #A  -- `final suspend inline fun <#A: kotlin/Any?> kotlin.coroutines.intrinsics/suspendCoroutineUninterceptedOrReturn(crossinline kotlin/Function1<kotlin.coroutines/Continuation<#A>, kotlin/Any?>): #A`
    - `kotlin.coroutines.intrinsics.wrapWithContinuationImpl` — fun wrapWithContinuationImpl(Continuation): Continuation  -- `final fun <#A: kotlin/Any?> kotlin.coroutines.intrinsics/wrapWithContinuationImpl(kotlin.coroutines/Continuation<#A>): kotlin.coroutines/Continuation<#A>`

- [ ] KSP-1153: kotlin.coroutines.intrinsics.SuspendFunction0 の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.coroutines.intrinsics` / receiver `SuspendFunction0`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/intrinsics/SuspendFunction0.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_intrinsics_SuspendFunction0_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_SuspendFunction0_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_SuspendFunction0_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.intrinsics.createCoroutineUnintercepted` — fun SuspendFunction0.createCoroutineUnintercepted(Continuation): Continuation  -- `final fun <#A: kotlin/Any?> (kotlin.coroutines/SuspendFunction0<#A>).kotlin.coroutines.intrinsics/createCoroutineUnintercepted(kotlin.coroutines/Continuation<#A>): kotlin.coroutines/Continuation<kotlin/Unit>`
    - `kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn` — fun SuspendFunction0.startCoroutineUninterceptedOrReturn(Continuation): Any  -- `final inline fun <#A: kotlin/Any?> (kotlin.coroutines/SuspendFunction0<#A>).kotlin.coroutines.intrinsics/startCoroutineUninterceptedOrReturn(kotlin.coroutines/Continuation<#A>): kotlin/Any?`

- [ ] KSP-1154: kotlin.coroutines.intrinsics.SuspendFunction1 の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.coroutines.intrinsics` / receiver `SuspendFunction1`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/intrinsics/SuspendFunction1.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_intrinsics_SuspendFunction1_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_SuspendFunction1_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_SuspendFunction1_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.intrinsics.createCoroutineUnintercepted` — fun SuspendFunction1.createCoroutineUnintercepted(, Continuation): Continuation  -- `final fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.coroutines/SuspendFunction1<#A, #B>).kotlin.coroutines.intrinsics/createCoroutineUnintercepted(#A, kotlin.coroutines/Continuation<#B>): kotlin.coroutines/Continuation<kotlin/Unit>`
    - `kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn` — fun SuspendFunction1.startCoroutineUninterceptedOrReturn(, Continuation): Any  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.coroutines/SuspendFunction1<#A, #B>).kotlin.coroutines.intrinsics/startCoroutineUninterceptedOrReturn(#A, kotlin.coroutines/Continuation<#B>): kotlin/Any?`

- [ ] KSP-1155: kotlin.coroutines.intrinsics.CoroutineSingletons.CoroutineSingletons の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.coroutines.intrinsics.CoroutineSingletons` / receiver `CoroutineSingletons`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/coroutines/intrinsics/CoroutineSingletons/CoroutineSingletons.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_coroutines_intrinsics_CoroutineSingletons_CoroutineSingletons_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_CoroutineSingletons_CoroutineSingletons_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_coroutines_intrinsics_CoroutineSingletons_CoroutineSingletons_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.coroutines.intrinsics.CoroutineSingletons.entries` — val CoroutineSingletons.entries: EnumEntries  -- `final val entries`
    - `kotlin.coroutines.intrinsics.CoroutineSingletons.valueOf` — fun CoroutineSingletons.valueOf(String): CoroutineSingletons  -- `final fun valueOf(kotlin/String): kotlin.coroutines.intrinsics/CoroutineSingletons`
    - `kotlin.coroutines.intrinsics.CoroutineSingletons.values` — fun CoroutineSingletons.values(): Array  -- `final fun values(): kotlin/Array<kotlin.coroutines.intrinsics/CoroutineSingletons>`

- [ ] KSP-1191: kotlin.native top-level の未実装 stdlib API を実装する（27 件）
  - 対象: `kotlin.native` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.BitSet` — class kotlin.native.BitSet  -- `final class kotlin.native/BitSet {`
    - `kotlin.native.CName` — class kotlin.native.CName  -- `open annotation class kotlin.native/CName : kotlin/Annotation {`
    - `kotlin.native.CpuArchitecture` — enumClass kotlin.native.CpuArchitecture  -- `final enum class kotlin.native/CpuArchitecture : kotlin/Enum<kotlin.native/CpuArchitecture> {`
    - `kotlin.native.EagerInitialization` — class kotlin.native.EagerInitialization  -- `open annotation class kotlin.native/EagerInitialization : kotlin/Annotation {`
    - `kotlin.native.FreezingIsDeprecated` — class kotlin.native.FreezingIsDeprecated  -- `open annotation class kotlin.native/FreezingIsDeprecated : kotlin/Annotation {`
    - `kotlin.native.HiddenFromObjC` — class kotlin.native.HiddenFromObjC  -- `open annotation class kotlin.native/HiddenFromObjC : kotlin/Annotation {`
    - `kotlin.native.HidesFromObjC` — class kotlin.native.HidesFromObjC  -- `open annotation class kotlin.native/HidesFromObjC : kotlin/Annotation {`
    - `kotlin.native.ImmutableBlob` — class kotlin.native.ImmutableBlob  -- `final class kotlin.native/ImmutableBlob {`
    - `kotlin.native.IncorrectDereferenceException` — class kotlin.native.IncorrectDereferenceException  -- `final class kotlin.native/IncorrectDereferenceException : kotlin/RuntimeException {`
    - `kotlin.native.MemoryModel` — enumClass kotlin.native.MemoryModel  -- `final enum class kotlin.native/MemoryModel : kotlin/Enum<kotlin.native/MemoryModel> {`
    - `kotlin.native.NoInline` — class kotlin.native.NoInline  -- `open annotation class kotlin.native/NoInline : kotlin/Annotation {`
    - `kotlin.native.ObjCName` — class kotlin.native.ObjCName  -- `open annotation class kotlin.native/ObjCName : kotlin/Annotation {`
    - `kotlin.native.ObsoleteNativeApi` — class kotlin.native.ObsoleteNativeApi  -- `open annotation class kotlin.native/ObsoleteNativeApi : kotlin/Annotation {`
    - `kotlin.native.OsFamily` — enumClass kotlin.native.OsFamily  -- `final enum class kotlin.native/OsFamily : kotlin/Enum<kotlin.native/OsFamily> {`
    - `kotlin.native.Platform` — object kotlin.native.Platform  -- `final object kotlin.native/Platform {`
    - `kotlin.native.RefinesInSwift` — class kotlin.native.RefinesInSwift  -- `open annotation class kotlin.native/RefinesInSwift : kotlin/Annotation {`
    - `kotlin.native.ShouldRefineInSwift` — class kotlin.native.ShouldRefineInSwift  -- `open annotation class kotlin.native/ShouldRefineInSwift : kotlin/Annotation {`
    - `kotlin.native.SymbolName` — class kotlin.native.SymbolName  -- `open annotation class kotlin.native/SymbolName : kotlin/Annotation {`
    - `kotlin.native.getUnhandledExceptionHook` — fun getUnhandledExceptionHook(): Function1  -- `final fun kotlin.native/getUnhandledExceptionHook(): kotlin/Function1<kotlin/Throwable, kotlin/Unit>?`
    - `kotlin.native.immutableBlobOf` — fun immutableBlobOf(Array): ImmutableBlob  -- `final fun kotlin.native/immutableBlobOf(kotlin/ShortArray...): kotlin.native/ImmutableBlob`
    - `kotlin.native.initRuntimeIfNeeded` — fun initRuntimeIfNeeded(): Unit  -- `final fun kotlin.native/initRuntimeIfNeeded()`
    - `kotlin.native.isExperimentalMM` — fun isExperimentalMM(): Boolean  -- `final fun kotlin.native/isExperimentalMM(): kotlin/Boolean`
    - `kotlin.native.processUnhandledException` — fun processUnhandledException(Throwable): Unit  -- `final fun kotlin.native/processUnhandledException(kotlin/Throwable)`
    - `kotlin.native.setUnhandledExceptionHook` — fun setUnhandledExceptionHook(Function1): Function1  -- `final fun kotlin.native/setUnhandledExceptionHook(kotlin/Function1<kotlin/Throwable, kotlin/Unit>?): kotlin/Function1<kotlin/Throwable, kotlin/Unit>?`
    - `kotlin.native.terminateWithUnhandledException` — fun terminateWithUnhandledException(Throwable): Nothing  -- `final fun kotlin.native/terminateWithUnhandledException(kotlin/Throwable): kotlin/Nothing`
    - `kotlin.native.vectorOf` — fun vectorOf(Float, Float, Float, Float): Vector128  -- `final fun kotlin.native/vectorOf(kotlin/Float, kotlin/Float, kotlin/Float, kotlin/Float): kotlinx.cinterop/Vector128`
    - `kotlin.native.vectorOf` — fun vectorOf(Int, Int, Int, Int): Vector128  -- `final fun kotlin.native/vectorOf(kotlin/Int, kotlin/Int, kotlin/Int, kotlin/Int): kotlinx.cinterop/Vector128`

- [ ] KSP-1192: kotlin.native.ImmutableBlob の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native` / receiver `ImmutableBlob`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/ImmutableBlob.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_ImmutableBlob_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_ImmutableBlob_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_ImmutableBlob_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.asCPointer` — fun ImmutableBlob.asCPointer(Int): CPointer  -- `final fun (kotlin.native/ImmutableBlob).kotlin.native/asCPointer(kotlin/Int = ...): kotlinx.cinterop/CPointer<kotlinx.cinterop/ByteVarOf<kotlin/Byte>>`
    - `kotlin.native.asUCPointer` — fun ImmutableBlob.asUCPointer(Int): CPointer  -- `final fun (kotlin.native/ImmutableBlob).kotlin.native/asUCPointer(kotlin/Int = ...): kotlinx.cinterop/CPointer<kotlinx.cinterop/UByteVarOf<kotlin/UByte>>`
    - `kotlin.native.toByteArray` — fun ImmutableBlob.toByteArray(Int, Int): ByteArray  -- `final fun (kotlin.native/ImmutableBlob).kotlin.native/toByteArray(kotlin/Int = ..., kotlin/Int = ...): kotlin/ByteArray`
    - `kotlin.native.toUByteArray` — fun ImmutableBlob.toUByteArray(Int, Int): UByteArray  -- `final fun (kotlin.native/ImmutableBlob).kotlin.native/toUByteArray(kotlin/Int = ..., kotlin/Int = ...): kotlin/UByteArray`

- [ ] KSP-1196: kotlin.native.CName top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.CName` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/CName/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_CName_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_CName_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_CName_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.CName.<init>` — constructor (String, String)  -- `constructor <init>(kotlin/String = ..., kotlin/String = ...)`

- [x] KSP-1197: kotlin.native.CName.CName の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.native.CName` / receiver `CName`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/CName/CName.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_CName_CName_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_CName_CName_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_CName_CName_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装済み根拠: `Sources/CompilerCore/Stdlib/kotlin/native/ObjCInterop.kt` の source-backed `CName` 宣言に `val externName: String` と `val shortName: String` が存在する。これは merged PR #5034（KSP-667、commit `334a393e34`）で導入された宣言であり、追加の bridge/stub/ABI/name-string 特例はない。
  - 現行 master の Sema probe で両シンボルが非synthetic `.property`、`String` 型、`CName` 親、source-backed と確認済み。
  - 実装済みシンボル一覧:
    - `kotlin.native.CName.externName` — val CName.externName: String  -- `final val externName`
    - `kotlin.native.CName.shortName` — val CName.shortName: String  -- `final val shortName`

- [ ] KSP-1198: kotlin.native.CpuArchitecture.CpuArchitecture の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.CpuArchitecture` / receiver `CpuArchitecture`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/CpuArchitecture/CpuArchitecture.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_CpuArchitecture_CpuArchitecture_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_CpuArchitecture_CpuArchitecture_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_CpuArchitecture_CpuArchitecture_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.CpuArchitecture.bitness` — val CpuArchitecture.bitness: Int  -- `final val bitness`
    - `kotlin.native.CpuArchitecture.entries` — val CpuArchitecture.entries: EnumEntries  -- `final val entries`
    - `kotlin.native.CpuArchitecture.valueOf` — fun CpuArchitecture.valueOf(String): CpuArchitecture  -- `final fun valueOf(kotlin/String): kotlin.native/CpuArchitecture`
    - `kotlin.native.CpuArchitecture.values` — fun CpuArchitecture.values(): Array  -- `final fun values(): kotlin/Array<kotlin.native/CpuArchitecture>`

- [ ] KSP-1203: kotlin.native.ImmutableBlob.ImmutableBlob の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.native.ImmutableBlob` / receiver `ImmutableBlob`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/ImmutableBlob/ImmutableBlob.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_ImmutableBlob_ImmutableBlob_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_ImmutableBlob_ImmutableBlob_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_ImmutableBlob_ImmutableBlob_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.ImmutableBlob.get` — fun ImmutableBlob.get(Int): Byte  -- `final fun get(kotlin/Int): kotlin/Byte`
    - `kotlin.native.ImmutableBlob.iterator` — fun ImmutableBlob.iterator(): ByteIterator  -- `final fun iterator(): kotlin.collections/ByteIterator`
    - `kotlin.native.ImmutableBlob.size` — val ImmutableBlob.size: Int  -- `final val size`

- [ ] KSP-1215: kotlin.native.SymbolName.SymbolName の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.SymbolName` / receiver `SymbolName`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/SymbolName/SymbolName.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_SymbolName_SymbolName_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_SymbolName_SymbolName_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_SymbolName_SymbolName_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.SymbolName.name` — val SymbolName.name: String  -- `final val name`

- [ ] KSP-1216: kotlin.native.concurrent top-level の未実装 stdlib API を実装する（29 件）
  - 対象: `kotlin.native.concurrent` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicInt` — class kotlin.native.concurrent.AtomicInt  -- `final class kotlin.native.concurrent/AtomicInt {`
    - `kotlin.native.concurrent.AtomicLong` — class kotlin.native.concurrent.AtomicLong  -- `final class kotlin.native.concurrent/AtomicLong {`
    - `kotlin.native.concurrent.AtomicNativePtr` — class kotlin.native.concurrent.AtomicNativePtr  -- `final class kotlin.native.concurrent/AtomicNativePtr {`
    - `kotlin.native.concurrent.AtomicReference` — class kotlin.native.concurrent.AtomicReference  -- `final class <#A: kotlin/Any?> kotlin.native.concurrent/AtomicReference {`
    - `kotlin.native.concurrent.Continuation0` — class kotlin.native.concurrent.Continuation0  -- `final class kotlin.native.concurrent/Continuation0 : kotlin/Function0<kotlin/Unit> {`
    - `kotlin.native.concurrent.Continuation1` — class kotlin.native.concurrent.Continuation1  -- `final class <#A: kotlin/Any?> kotlin.native.concurrent/Continuation1 : kotlin/Function1<#A, kotlin/Unit> {`
    - `kotlin.native.concurrent.Continuation2` — class kotlin.native.concurrent.Continuation2  -- `final class <#A: kotlin/Any?, #B: kotlin/Any?> kotlin.native.concurrent/Continuation2 : kotlin/Function2<#A, #B, kotlin/Unit> {`
    - `kotlin.native.concurrent.DetachedObjectGraph` — class kotlin.native.concurrent.DetachedObjectGraph  -- `final class <#A: kotlin/Any?> kotlin.native.concurrent/DetachedObjectGraph {`
    - `kotlin.native.concurrent.FreezableAtomicReference` — class kotlin.native.concurrent.FreezableAtomicReference  -- `final class <#A: kotlin/Any?> kotlin.native.concurrent/FreezableAtomicReference {`
    - `kotlin.native.concurrent.FreezingException` — class kotlin.native.concurrent.FreezingException  -- `final class kotlin.native.concurrent/FreezingException : kotlin/RuntimeException {`
    - `kotlin.native.concurrent.Future` — class kotlin.native.concurrent.Future  -- `final value class <#A: kotlin/Any?> kotlin.native.concurrent/Future {`
    - `kotlin.native.concurrent.FutureState` — enumClass kotlin.native.concurrent.FutureState  -- `final enum class kotlin.native.concurrent/FutureState : kotlin/Enum<kotlin.native.concurrent/FutureState> {`
    - `kotlin.native.concurrent.InvalidMutabilityException` — class kotlin.native.concurrent.InvalidMutabilityException  -- `final class kotlin.native.concurrent/InvalidMutabilityException : kotlin/RuntimeException {`
    - `kotlin.native.concurrent.MutableData` — class kotlin.native.concurrent.MutableData  -- `final class kotlin.native.concurrent/MutableData {`
    - `kotlin.native.concurrent.ObsoleteWorkersApi` — class kotlin.native.concurrent.ObsoleteWorkersApi  -- `open annotation class kotlin.native.concurrent/ObsoleteWorkersApi : kotlin/Annotation {`
    - `kotlin.native.concurrent.SharedImmutable` — class kotlin.native.concurrent.SharedImmutable  -- `open annotation class kotlin.native.concurrent/SharedImmutable : kotlin/Annotation {`
    - `kotlin.native.concurrent.ThreadLocal` — class kotlin.native.concurrent.ThreadLocal  -- `open annotation class kotlin.native.concurrent/ThreadLocal : kotlin/Annotation {`
    - `kotlin.native.concurrent.TransferMode` — enumClass kotlin.native.concurrent.TransferMode  -- `final enum class kotlin.native.concurrent/TransferMode : kotlin/Enum<kotlin.native.concurrent/TransferMode> {`
    - `kotlin.native.concurrent.Worker` — class kotlin.native.concurrent.Worker  -- `final value class kotlin.native.concurrent/Worker {`
    - `kotlin.native.concurrent.WorkerBoundReference` — class kotlin.native.concurrent.WorkerBoundReference  -- `final class <#A: out kotlin/Any> kotlin.native.concurrent/WorkerBoundReference {`
    - `kotlin.native.concurrent.atomicLazy` — fun atomicLazy(Function0): Lazy  -- `final fun <#A: kotlin/Any?> kotlin.native.concurrent/atomicLazy(kotlin/Function0<#A>): kotlin/Lazy<#A>`
    - `kotlin.native.concurrent.attachObjectGraphInternal` — fun attachObjectGraphInternal(NativePtr): Any  -- `final fun kotlin.native.concurrent/attachObjectGraphInternal(kotlin.native.internal/NativePtr): kotlin/Any?`
    - `kotlin.native.concurrent.consumeFuture` — fun consumeFuture(Int): Any  -- `final fun kotlin.native.concurrent/consumeFuture(kotlin/Int): kotlin/Any?`
    - `kotlin.native.concurrent.detachObjectGraphInternal` — fun detachObjectGraphInternal(Int, Function0): NativePtr  -- `final fun kotlin.native.concurrent/detachObjectGraphInternal(kotlin/Int, kotlin/Function0<kotlin/Any?>): kotlin.native.internal/NativePtr`
    - `kotlin.native.concurrent.executeImpl` — fun executeImpl(Worker, TransferMode, Function0, CPointer): Future  -- `final fun kotlin.native.concurrent/executeImpl(kotlin.native.concurrent/Worker, kotlin.native.concurrent/TransferMode, kotlin/Function0<kotlin/Any?>, kotlinx.cinterop/CPointer<kotlinx.cinterop/CFunction<*>>): kotlin.native.concurrent/Future<kotlin/Any?>`
    - `kotlin.native.concurrent.freeze` — fun freeze(): #A  -- `final fun <#A: kotlin/Any?> (#A).kotlin.native.concurrent/freeze(): #A`
    - `kotlin.native.concurrent.waitForMultipleFutures` — fun waitForMultipleFutures(Collection, Int): Set  -- `final fun <#A: kotlin/Any?> kotlin.native.concurrent/waitForMultipleFutures(kotlin.collections/Collection<kotlin.native.concurrent/Future<#A>>, kotlin/Int): kotlin.collections/Set<kotlin.native.concurrent/Future<#A>>`
    - `kotlin.native.concurrent.waitWorkerTermination` — fun waitWorkerTermination(Worker): Unit  -- `final fun kotlin.native.concurrent/waitWorkerTermination(kotlin.native.concurrent/Worker)`
    - `kotlin.native.concurrent.withWorker` — fun withWorker(String, Boolean, Function1): #A  -- `final inline fun <#A: kotlin/Any?> kotlin.native.concurrent/withWorker(kotlin/String? = ..., kotlin/Boolean = ..., kotlin/Function1<kotlin.native.concurrent/Worker, #A>): #A`

- [ ] KSP-1217: kotlin.native.concurrent.CPointer の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.native.concurrent` / receiver `CPointer`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/CPointer.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_CPointer_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_CPointer_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_CPointer_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.callContinuation0` — fun CPointer.callContinuation0(): Unit  -- `final fun (kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>).kotlin.native.concurrent/callContinuation0()`
    - `kotlin.native.concurrent.callContinuation1` — fun CPointer.callContinuation1(): Unit  -- `final fun <#A: kotlin/Any?> (kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>).kotlin.native.concurrent/callContinuation1()`
    - `kotlin.native.concurrent.callContinuation2` — fun CPointer.callContinuation2(): Unit  -- `final fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>).kotlin.native.concurrent/callContinuation2()`

- [ ] KSP-1218: kotlin.native.concurrent.Collection の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent` / receiver `Collection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Collection.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_Collection_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_Collection_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_Collection_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.waitForMultipleFutures` — fun Collection.waitForMultipleFutures(Int): Set  -- `final fun <#A: kotlin/Any?> (kotlin.collections/Collection<kotlin.native.concurrent/Future<#A>>).kotlin.native.concurrent/waitForMultipleFutures(kotlin/Int): kotlin.collections/Set<kotlin.native.concurrent/Future<#A>>`

- [ ] KSP-1219: kotlin.native.concurrent.DetachedObjectGraph の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent` / receiver `DetachedObjectGraph`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/DetachedObjectGraph.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.attach` — fun DetachedObjectGraph.attach(): #A  -- `final inline fun <#A: reified kotlin/Any?> (kotlin.native.concurrent/DetachedObjectGraph<#A>).kotlin.native.concurrent/attach(): #A`

- [ ] KSP-1220: kotlin.native.concurrent.AtomicInt top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent.AtomicInt` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/AtomicInt/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicInt_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicInt_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicInt_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicInt.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`

- [ ] KSP-1221: kotlin.native.concurrent.AtomicInt.AtomicInt の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.native.concurrent.AtomicInt` / receiver `AtomicInt`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/AtomicInt/AtomicInt.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicInt_AtomicInt_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicInt_AtomicInt_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicInt_AtomicInt_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicInt.compareAndSwap` — fun AtomicInt.compareAndSwap(Int, Int): Int  -- `final fun compareAndSwap(kotlin/Int, kotlin/Int): kotlin/Int`
    - `kotlin.native.concurrent.AtomicInt.decrement` — fun AtomicInt.decrement(): Unit  -- `final fun decrement()`
    - `kotlin.native.concurrent.AtomicInt.getAndAdd` — fun AtomicInt.getAndAdd(Int): Int  -- `final fun getAndAdd(kotlin/Int): kotlin/Int`
    - `kotlin.native.concurrent.AtomicInt.getAndDecrement` — fun AtomicInt.getAndDecrement(): Int  -- `final fun getAndDecrement(): kotlin/Int`
    - `kotlin.native.concurrent.AtomicInt.getAndIncrement` — fun AtomicInt.getAndIncrement(): Int  -- `final fun getAndIncrement(): kotlin/Int`
    - `kotlin.native.concurrent.AtomicInt.increment` — fun AtomicInt.increment(): Unit  -- `final fun increment()`
    - `kotlin.native.concurrent.AtomicInt.toString` — fun AtomicInt.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.AtomicInt.value` — val AtomicInt.value: Int  -- `final var value`

- [ ] KSP-1222: kotlin.native.concurrent.AtomicLong top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent.AtomicLong` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/AtomicLong/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicLong_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicLong_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicLong_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicLong.<init>` — constructor (Long)  -- `constructor <init>(kotlin/Long = ...)`

- [ ] KSP-1223: kotlin.native.concurrent.AtomicLong.AtomicLong の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.native.concurrent.AtomicLong` / receiver `AtomicLong`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/AtomicLong/AtomicLong.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicLong_AtomicLong_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicLong_AtomicLong_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicLong_AtomicLong_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicLong.addAndGet` — fun AtomicLong.addAndGet(Int): Long  -- `final fun addAndGet(kotlin/Int): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.compareAndSwap` — fun AtomicLong.compareAndSwap(Long, Long): Long  -- `final fun compareAndSwap(kotlin/Long, kotlin/Long): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.decrement` — fun AtomicLong.decrement(): Unit  -- `final fun decrement()`
    - `kotlin.native.concurrent.AtomicLong.getAndAdd` — fun AtomicLong.getAndAdd(Long): Long  -- `final fun getAndAdd(kotlin/Long): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.getAndDecrement` — fun AtomicLong.getAndDecrement(): Long  -- `final fun getAndDecrement(): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.getAndIncrement` — fun AtomicLong.getAndIncrement(): Long  -- `final fun getAndIncrement(): kotlin/Long`
    - `kotlin.native.concurrent.AtomicLong.increment` — fun AtomicLong.increment(): Unit  -- `final fun increment()`
    - `kotlin.native.concurrent.AtomicLong.toString` — fun AtomicLong.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.AtomicLong.value` — val AtomicLong.value: Long  -- `final var value`

- [ ] KSP-1224: kotlin.native.concurrent.AtomicNativePtr top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent.AtomicNativePtr` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/AtomicNativePtr/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicNativePtr_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicNativePtr_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicNativePtr_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicNativePtr.<init>` — constructor (NativePtr)  -- `constructor <init>(kotlin.native.internal/NativePtr)`

- [ ] KSP-1225: kotlin.native.concurrent.AtomicNativePtr.AtomicNativePtr の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.native.concurrent.AtomicNativePtr` / receiver `AtomicNativePtr`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/AtomicNativePtr/AtomicNativePtr.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicNativePtr_AtomicNativePtr_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicNativePtr.compareAndSet` — fun AtomicNativePtr.compareAndSet(NativePtr, NativePtr): Boolean  -- `final fun compareAndSet(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin/Boolean`
    - `kotlin.native.concurrent.AtomicNativePtr.compareAndSwap` — fun AtomicNativePtr.compareAndSwap(NativePtr, NativePtr): NativePtr  -- `final fun compareAndSwap(kotlin.native.internal/NativePtr, kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.native.concurrent.AtomicNativePtr.getAndSet` — fun AtomicNativePtr.getAndSet(NativePtr): NativePtr  -- `final fun getAndSet(kotlin.native.internal/NativePtr): kotlin.native.internal/NativePtr`
    - `kotlin.native.concurrent.AtomicNativePtr.toString` — fun AtomicNativePtr.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.AtomicNativePtr.value` — val AtomicNativePtr.value: NativePtr  -- `final var value`

- [ ] KSP-1226: kotlin.native.concurrent.AtomicReference top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent.AtomicReference` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/AtomicReference/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicReference_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicReference_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicReference_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicReference.<init>` — constructor ()  -- `constructor <init>(#A)`

- [ ] KSP-1227: kotlin.native.concurrent.AtomicReference.AtomicReference の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.concurrent.AtomicReference` / receiver `AtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/AtomicReference/AtomicReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_AtomicReference_AtomicReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicReference_AtomicReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_AtomicReference_AtomicReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.AtomicReference.compareAndSwap` — fun AtomicReference.compareAndSwap(, ): #A  -- `final fun compareAndSwap(#A, #A): #A`
    - `kotlin.native.concurrent.AtomicReference.getAndSet` — fun AtomicReference.getAndSet(): #A  -- `final fun getAndSet(#A): #A`
    - `kotlin.native.concurrent.AtomicReference.toString` — fun AtomicReference.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.AtomicReference.value` — val AtomicReference.value: #A  -- `final var value`

- [ ] KSP-1234: kotlin.native.concurrent.DetachedObjectGraph top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.native.concurrent.DetachedObjectGraph` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/DetachedObjectGraph/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.DetachedObjectGraph.<init>` — constructor (CPointer)  -- `constructor <init>(kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>?)`
    - `kotlin.native.concurrent.DetachedObjectGraph.<init>` — constructor (TransferMode, Function0)  -- `constructor <init>(kotlin.native.concurrent/TransferMode = ..., kotlin/Function0<#A>)`

- [ ] KSP-1235: kotlin.native.concurrent.DetachedObjectGraph.DetachedObjectGraph の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.native.concurrent.DetachedObjectGraph` / receiver `DetachedObjectGraph`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/DetachedObjectGraph/DetachedObjectGraph.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_DetachedObjectGraph_DetachedObjectGraph_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_DetachedObjectGraph_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_DetachedObjectGraph_DetachedObjectGraph_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.DetachedObjectGraph.asCPointer` — fun DetachedObjectGraph.asCPointer(): CPointer  -- `final fun asCPointer(): kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>?`
    - `kotlin.native.concurrent.DetachedObjectGraph.stable` — val DetachedObjectGraph.stable: AtomicNativePtr  -- `final val stable`

- [ ] KSP-1237: kotlin.native.concurrent.FreezableAtomicReference.FreezableAtomicReference の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.concurrent.FreezableAtomicReference` / receiver `FreezableAtomicReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/FreezableAtomicReference/FreezableAtomicReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_FreezableAtomicReference_FreezableAtomicReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_FreezableAtomicReference_FreezableAtomicReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_FreezableAtomicReference_FreezableAtomicReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.FreezableAtomicReference.compareAndSet` — fun FreezableAtomicReference.compareAndSet(, ): Boolean  -- `final fun compareAndSet(#A, #A): kotlin/Boolean`
    - `kotlin.native.concurrent.FreezableAtomicReference.compareAndSwap` — fun FreezableAtomicReference.compareAndSwap(, ): #A  -- `final fun compareAndSwap(#A, #A): #A`
    - `kotlin.native.concurrent.FreezableAtomicReference.toString` — fun FreezableAtomicReference.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.native.concurrent.FreezableAtomicReference.value` — val FreezableAtomicReference.value: #A  -- `final var value`

- [ ] KSP-1240: kotlin.native.concurrent.Future.Future の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.native.concurrent.Future` / receiver `Future`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Future/Future.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_Future_Future_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_Future_Future_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_Future_Future_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.Future.consume` — fun Future.consume(Function1): #A1  -- `final inline fun <#A1: kotlin/Any?> consume(kotlin/Function1<#A, #A1>): #A1`
    - `kotlin.native.concurrent.Future.equals` — fun Future.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.native.concurrent.Future.hashCode` — fun Future.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.native.concurrent.Future.id` — val Future.id: Int  -- `final val id`
    - `kotlin.native.concurrent.Future.result` — val Future.result: #A  -- `final val result`
    - `kotlin.native.concurrent.Future.state` — val Future.state: FutureState  -- `final val state`
    - `kotlin.native.concurrent.Future.toString` — fun Future.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1243: kotlin.native.concurrent.MutableData top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent.MutableData` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/MutableData/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_MutableData_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_MutableData_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_MutableData_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.MutableData.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int = ...)`

- [ ] KSP-1244: kotlin.native.concurrent.MutableData.MutableData の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.native.concurrent.MutableData` / receiver `MutableData`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/MutableData/MutableData.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_MutableData_MutableData_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_MutableData_MutableData_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_MutableData_MutableData_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.MutableData.append` — fun MutableData.append(MutableData): Unit  -- `final fun append(kotlin.native.concurrent/MutableData)`
    - `kotlin.native.concurrent.MutableData.append` — fun MutableData.append(CPointer, Int): Unit  -- `final fun append(kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>?, kotlin/Int)`
    - `kotlin.native.concurrent.MutableData.append` — fun MutableData.append(ByteArray, Int, Int): Unit  -- `final fun append(kotlin/ByteArray, kotlin/Int = ..., kotlin/Int = ...)`
    - `kotlin.native.concurrent.MutableData.copyInto` — fun MutableData.copyInto(ByteArray, Int, Int, Int): Unit  -- `final fun copyInto(kotlin/ByteArray, kotlin/Int, kotlin/Int, kotlin/Int)`
    - `kotlin.native.concurrent.MutableData.get` — fun MutableData.get(Int): Byte  -- `final fun get(kotlin/Int): kotlin/Byte`
    - `kotlin.native.concurrent.MutableData.reset` — fun MutableData.reset(): Unit  -- `final fun reset()`
    - `kotlin.native.concurrent.MutableData.size` — val MutableData.size: Int  -- `final val size`
    - `kotlin.native.concurrent.MutableData.withBufferLocked` — fun MutableData.withBufferLocked(Function2): #A1  -- `final fun <#A1: kotlin/Any?> withBufferLocked(kotlin/Function2<kotlin/ByteArray, kotlin/Int, #A1>): #A1`
    - `kotlin.native.concurrent.MutableData.withPointerLocked` — fun MutableData.withPointerLocked(Function2): #A1  -- `final fun <#A1: kotlin/Any?> withPointerLocked(kotlin/Function2<kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>, kotlin/Int, #A1>): #A1`

- [ ] KSP-1250: kotlin.native.concurrent.Worker.Worker の未実装 stdlib API を実装する（12 件）
  - 対象: `kotlin.native.concurrent.Worker` / receiver `Worker`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Worker/Worker.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_Worker_Worker_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_Worker_Worker_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_Worker_Worker_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.Worker.asCPointer` — fun Worker.asCPointer(): CPointer  -- `final fun asCPointer(): kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>?`
    - `kotlin.native.concurrent.Worker.equals` — fun Worker.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.native.concurrent.Worker.execute` — fun Worker.execute(TransferMode, Function0, Function1): Future  -- `final fun <#A1: kotlin/Any?, #B1: kotlin/Any?> execute(kotlin.native.concurrent/TransferMode, kotlin/Function0<#A1>, kotlin/Function1<#A1, #B1>): kotlin.native.concurrent/Future<#B1>`
    - `kotlin.native.concurrent.Worker.executeAfter` — fun Worker.executeAfter(Long, Function0): Unit  -- `final fun executeAfter(kotlin/Long = ..., kotlin/Function0<kotlin/Unit>)`
    - `kotlin.native.concurrent.Worker.hashCode` — fun Worker.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.native.concurrent.Worker.id` — val Worker.id: Int  -- `final val id`
    - `kotlin.native.concurrent.Worker.name` — val Worker.name: String  -- `final val name`
    - `kotlin.native.concurrent.Worker.park` — fun Worker.park(Long, Boolean): Boolean  -- `final fun park(kotlin/Long, kotlin/Boolean = ...): kotlin/Boolean`
    - `kotlin.native.concurrent.Worker.platformThreadId` — val Worker.platformThreadId: ULong  -- `final val platformThreadId`
    - `kotlin.native.concurrent.Worker.processQueue` — fun Worker.processQueue(): Boolean  -- `final fun processQueue(): kotlin/Boolean`
    - `kotlin.native.concurrent.Worker.requestTermination` — fun Worker.requestTermination(Boolean): Future  -- `final fun requestTermination(kotlin/Boolean = ...): kotlin.native.concurrent/Future<kotlin/Unit>`
    - `kotlin.native.concurrent.Worker.toString` — fun Worker.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1251: kotlin.native.concurrent.Worker.Companion.Companion の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.concurrent.Worker.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/Worker/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_Worker_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_Worker_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_Worker_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.Worker.Companion.activeWorkers` — val Companion.activeWorkers: List  -- `final val activeWorkers`
    - `kotlin.native.concurrent.Worker.Companion.current` — val Companion.current: Worker  -- `final val current`
    - `kotlin.native.concurrent.Worker.Companion.fromCPointer` — fun Companion.fromCPointer(CPointer): Worker  -- `final fun fromCPointer(kotlinx.cinterop/CPointer<out kotlinx.cinterop/CPointed>?): kotlin.native.concurrent/Worker`
    - `kotlin.native.concurrent.Worker.Companion.start` — fun Companion.start(Boolean, String): Worker  -- `final fun start(kotlin/Boolean = ..., kotlin/String? = ...): kotlin.native.concurrent/Worker`

- [ ] KSP-1252: kotlin.native.concurrent.WorkerBoundReference top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.concurrent.WorkerBoundReference` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/WorkerBoundReference/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_WorkerBoundReference_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_WorkerBoundReference_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_WorkerBoundReference_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.WorkerBoundReference.<init>` — constructor ()  -- `constructor <init>(#A)`

- [ ] KSP-1253: kotlin.native.concurrent.WorkerBoundReference.WorkerBoundReference の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.native.concurrent.WorkerBoundReference` / receiver `WorkerBoundReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/concurrent/WorkerBoundReference/WorkerBoundReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_concurrent_WorkerBoundReference_WorkerBoundReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_concurrent_WorkerBoundReference_WorkerBoundReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_WorkerBoundReference_WorkerBoundReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.concurrent.WorkerBoundReference.value` — val WorkerBoundReference.value: #A  -- `final val value`
    - `kotlin.native.concurrent.WorkerBoundReference.valueOrNull` — val WorkerBoundReference.valueOrNull: #A  -- `final val valueOrNull`
    - `kotlin.native.concurrent.WorkerBoundReference.worker` — val WorkerBoundReference.worker: Worker  -- `final val worker`

- [ ] KSP-1255: kotlin.native.ref.WeakReference top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.ref.WeakReference` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/ref/WeakReference/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_ref_WeakReference_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_ref_WeakReference_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_ref_WeakReference_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.ref.WeakReference.<init>` — constructor ()  -- `constructor <init>(#A)`

- [ ] KSP-1256: kotlin.native.ref.WeakReference.WeakReference の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.ref.WeakReference` / receiver `WeakReference`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/ref/WeakReference/WeakReference.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_ref_WeakReference_WeakReference_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_ref_WeakReference_WeakReference_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_ref_WeakReference_WeakReference_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.ref.WeakReference.clear` — fun WeakReference.clear(): Unit  -- `final fun clear()`
    - `kotlin.native.ref.WeakReference.get` — fun WeakReference.get(): #A  -- `final fun get(): #A?`
    - `kotlin.native.ref.WeakReference.pointer` — val WeakReference.pointer: WeakReferenceImpl  -- `final var pointer`
    - `kotlin.native.ref.WeakReference.value` — val WeakReference.value: #A  -- `final val value`

- [ ] KSP-1257: kotlin.native.ref.WeakReferenceImpl top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.ref.WeakReferenceImpl` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/ref/WeakReferenceImpl/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_ref_WeakReferenceImpl_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_ref_WeakReferenceImpl_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_ref_WeakReferenceImpl_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.ref.WeakReferenceImpl.<init>` — constructor ()  -- `constructor <init>()`

- [x] KSP-1258: kotlin.native.ref.WeakReferenceImpl.WeakReferenceImpl の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.ref.WeakReferenceImpl` / receiver `WeakReferenceImpl`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/ref/WeakReferenceImpl/WeakReferenceImpl.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_ref_WeakReferenceImpl_WeakReferenceImpl_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_ref_WeakReferenceImpl_WeakReferenceImpl_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_ref_WeakReferenceImpl_WeakReferenceImpl_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: Kotlin 2.3.10 公式 `kotlin/native/ref/WeakPrivate.kt` の `@PublishedApi internal abstract class WeakReferenceImpl` と `abstract fun get(): Any?` が、現行 `Sources/CompilerCore/Stdlib/kotlin/native/ref/Stdlib.kt` に source-backed で実装済み。これは merged PR #6340 の commit `209516e01e` で導入され、専用の synthetic/Runtime ABI bridge は存在しない。`WeakReferenceImplSourceMigrationTests` が source path、internal/abstract class、引数なし receiver member、`Any?` 戻り値、非 synthetic、外部 link なし、重複なしを固定する。
  - 未実装シンボル一覧:
    - `kotlin.native.ref.WeakReferenceImpl.get` — fun WeakReferenceImpl.get(): Any  -- `abstract fun get(): kotlin/Any?`

- [ ] KSP-1259: kotlin.native.runtime top-level の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.native.runtime` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.Debugging` — object kotlin.native.runtime.Debugging  -- `final object kotlin.native.runtime/Debugging {`
    - `kotlin.native.runtime.GC` — object kotlin.native.runtime.GC  -- `final object kotlin.native.runtime/GC {`
    - `kotlin.native.runtime.GCInfo` — class kotlin.native.runtime.GCInfo  -- `final class kotlin.native.runtime/GCInfo {`
    - `kotlin.native.runtime.MemoryUsage` — class kotlin.native.runtime.MemoryUsage  -- `final class kotlin.native.runtime/MemoryUsage {`
    - `kotlin.native.runtime.NativeRuntimeApi` — class kotlin.native.runtime.NativeRuntimeApi  -- `open annotation class kotlin.native.runtime/NativeRuntimeApi : kotlin/Annotation {`
    - `kotlin.native.runtime.RootSetStatistics` — class kotlin.native.runtime.RootSetStatistics  -- `final class kotlin.native.runtime/RootSetStatistics {`
    - `kotlin.native.runtime.SweepStatistics` — class kotlin.native.runtime.SweepStatistics  -- `final class kotlin.native.runtime/SweepStatistics {`

- [ ] KSP-1260: kotlin.native.runtime.Debugging.Debugging の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.native.runtime.Debugging` / receiver `Debugging`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/Debugging/Debugging.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_Debugging_Debugging_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_Debugging_Debugging_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_Debugging_Debugging_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.Debugging.dumpMemory` — fun Debugging.dumpMemory(Long): Boolean  -- `final fun dumpMemory(kotlin/Long): kotlin/Boolean`
    - `kotlin.native.runtime.Debugging.forceCheckedShutdown` — val Debugging.forceCheckedShutdown: Boolean  -- `final var forceCheckedShutdown`
    - `kotlin.native.runtime.Debugging.isThreadStateRunnable` — val Debugging.isThreadStateRunnable: Boolean  -- `final val isThreadStateRunnable`

- [ ] KSP-1262: kotlin.native.runtime.GC.GC の未実装 stdlib API を実装する（22 件）
  - 対象: `kotlin.native.runtime.GC` / receiver `GC`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/GC/GC.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_GC_GC_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_GC_GC_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_GC_GC_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.GC.autotune` — val GC.autotune: Boolean  -- `final var autotune`
    - `kotlin.native.runtime.GC.collect` — fun GC.collect(): Unit  -- `final fun collect()`
    - `kotlin.native.runtime.GC.collectCyclesThreshold` — val GC.collectCyclesThreshold: Long  -- `final var collectCyclesThreshold`
    - `kotlin.native.runtime.GC.collectCyclic` — fun GC.collectCyclic(): Unit  -- `final fun collectCyclic()`
    - `kotlin.native.runtime.GC.cyclicCollectorEnabled` — val GC.cyclicCollectorEnabled: Boolean  -- `final var cyclicCollectorEnabled`
    - `kotlin.native.runtime.GC.detectCycles` — fun GC.detectCycles(): Array  -- `final fun detectCycles(): kotlin/Array<kotlin/Any>?`
    - `kotlin.native.runtime.GC.findCycle` — fun GC.findCycle(Any): Array  -- `final fun findCycle(kotlin/Any): kotlin/Array<kotlin/Any>?`
    - `kotlin.native.runtime.GC.heapTriggerCoefficient` — val GC.heapTriggerCoefficient: Double  -- `final var heapTriggerCoefficient`
    - `kotlin.native.runtime.GC.lastGCInfo` — val GC.lastGCInfo: GCInfo  -- `final val lastGCInfo`
    - `kotlin.native.runtime.GC.maxHeapBytes` — val GC.maxHeapBytes: Long  -- `final var maxHeapBytes`
    - `kotlin.native.runtime.GC.minHeapBytes` — val GC.minHeapBytes: Long  -- `final var minHeapBytes`
    - `kotlin.native.runtime.GC.pauseOnTargetHeapOverflow` — val GC.pauseOnTargetHeapOverflow: Boolean  -- `final var pauseOnTargetHeapOverflow`
    - `kotlin.native.runtime.GC.regularGCInterval` — val GC.regularGCInterval: Duration  -- `final var regularGCInterval`
    - `kotlin.native.runtime.GC.resume` — fun GC.resume(): Unit  -- `final fun resume()`
    - `kotlin.native.runtime.GC.schedule` — fun GC.schedule(): Unit  -- `final fun schedule()`
    - `kotlin.native.runtime.GC.start` — fun GC.start(): Unit  -- `final fun start()`
    - `kotlin.native.runtime.GC.stop` — fun GC.stop(): Unit  -- `final fun stop()`
    - `kotlin.native.runtime.GC.suspend` — fun GC.suspend(): Unit  -- `final fun suspend()`
    - `kotlin.native.runtime.GC.targetHeapBytes` — val GC.targetHeapBytes: Long  -- `final var targetHeapBytes`
    - `kotlin.native.runtime.GC.targetHeapUtilization` — val GC.targetHeapUtilization: Double  -- `final var targetHeapUtilization`
    - `kotlin.native.runtime.GC.threshold` — val GC.threshold: Int  -- `final var threshold`
    - `kotlin.native.runtime.GC.thresholdAllocations` — val GC.thresholdAllocations: Long  -- `final var thresholdAllocations`

- [ ] KSP-1263: kotlin.native.runtime.GC.MainThreadFinalizerProcessor.MainThreadFinalizerProcessor の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.runtime.GC.MainThreadFinalizerProcessor` / receiver `MainThreadFinalizerProcessor`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/GC/MainThreadFinalizerProcessor/MainThreadFinalizerProcessor.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_GC_MainThreadFinalizerProcessor_MainThreadFinalizerProcessor_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_GC_MainThreadFinalizerProcessor_MainThreadFinalizerProcessor_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_GC_MainThreadFinalizerProcessor_MainThreadFinalizerProcessor_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.GC.MainThreadFinalizerProcessor.available` — val MainThreadFinalizerProcessor.available: Boolean  -- `final val available`
    - `kotlin.native.runtime.GC.MainThreadFinalizerProcessor.batchSize` — val MainThreadFinalizerProcessor.batchSize: ULong  -- `final var batchSize`
    - `kotlin.native.runtime.GC.MainThreadFinalizerProcessor.maxTimeInTask` — val MainThreadFinalizerProcessor.maxTimeInTask: Duration  -- `final var maxTimeInTask`
    - `kotlin.native.runtime.GC.MainThreadFinalizerProcessor.minTimeBetweenTasks` — val MainThreadFinalizerProcessor.minTimeBetweenTasks: Duration  -- `final var minTimeBetweenTasks`

- [ ] KSP-1264: kotlin.native.runtime.GCInfo top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.runtime.GCInfo` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/GCInfo/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_GCInfo_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_GCInfo_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_GCInfo_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.GCInfo.<init>` — constructor (Long, Long, Long, Long, Long, Long, Long, Long, Long, Long, RootSetStatistics, Long, Map, Map, Map)  -- `constructor <init>(kotlin/Long, kotlin/Long, kotlin/Long, kotlin/Long, kotlin/Long, kotlin/Long, kotlin/Long?, kotlin/Long?, kotlin/Long?, kotlin/Long?, kotlin.native.runtime/RootSetStatistics, kotlin/Long, kotlin.collections/Map<kotlin/String, kotlin.native.runtime/SweepStatistics>, kotlin.collections/Map<kotlin/String, kotlin.native.runtime/MemoryUsage>, kotlin.collections/Map<kotlin/String, kotlin.native.runtime/MemoryUsage>)`

- [ ] KSP-1265: kotlin.native.runtime.GCInfo.GCInfo の未実装 stdlib API を実装する（15 件）
  - 対象: `kotlin.native.runtime.GCInfo` / receiver `GCInfo`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/GCInfo/GCInfo.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_GCInfo_GCInfo_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_GCInfo_GCInfo_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_GCInfo_GCInfo_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.GCInfo.endTimeNs` — val GCInfo.endTimeNs: Long  -- `final val endTimeNs`
    - `kotlin.native.runtime.GCInfo.epoch` — val GCInfo.epoch: Long  -- `final val epoch`
    - `kotlin.native.runtime.GCInfo.firstPauseEndTimeNs` — val GCInfo.firstPauseEndTimeNs: Long  -- `final val firstPauseEndTimeNs`
    - `kotlin.native.runtime.GCInfo.firstPauseRequestTimeNs` — val GCInfo.firstPauseRequestTimeNs: Long  -- `final val firstPauseRequestTimeNs`
    - `kotlin.native.runtime.GCInfo.firstPauseStartTimeNs` — val GCInfo.firstPauseStartTimeNs: Long  -- `final val firstPauseStartTimeNs`
    - `kotlin.native.runtime.GCInfo.markedCount` — val GCInfo.markedCount: Long  -- `final val markedCount`
    - `kotlin.native.runtime.GCInfo.memoryUsageAfter` — val GCInfo.memoryUsageAfter: Map  -- `final val memoryUsageAfter`
    - `kotlin.native.runtime.GCInfo.memoryUsageBefore` — val GCInfo.memoryUsageBefore: Map  -- `final val memoryUsageBefore`
    - `kotlin.native.runtime.GCInfo.postGcCleanupTimeNs` — val GCInfo.postGcCleanupTimeNs: Long  -- `final val postGcCleanupTimeNs`
    - `kotlin.native.runtime.GCInfo.rootSet` — val GCInfo.rootSet: RootSetStatistics  -- `final val rootSet`
    - `kotlin.native.runtime.GCInfo.secondPauseEndTimeNs` — val GCInfo.secondPauseEndTimeNs: Long  -- `final val secondPauseEndTimeNs`
    - `kotlin.native.runtime.GCInfo.secondPauseRequestTimeNs` — val GCInfo.secondPauseRequestTimeNs: Long  -- `final val secondPauseRequestTimeNs`
    - `kotlin.native.runtime.GCInfo.secondPauseStartTimeNs` — val GCInfo.secondPauseStartTimeNs: Long  -- `final val secondPauseStartTimeNs`
    - `kotlin.native.runtime.GCInfo.startTimeNs` — val GCInfo.startTimeNs: Long  -- `final val startTimeNs`
    - `kotlin.native.runtime.GCInfo.sweepStatistics` — val GCInfo.sweepStatistics: Map  -- `final val sweepStatistics`

- [ ] KSP-1267: kotlin.native.runtime.MemoryUsage.MemoryUsage の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.runtime.MemoryUsage` / receiver `MemoryUsage`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/MemoryUsage/MemoryUsage.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_MemoryUsage_MemoryUsage_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_MemoryUsage_MemoryUsage_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_MemoryUsage_MemoryUsage_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.MemoryUsage.totalObjectsSizeBytes` — val MemoryUsage.totalObjectsSizeBytes: Long  -- `final val totalObjectsSizeBytes`

- [ ] KSP-1269: kotlin.native.runtime.RootSetStatistics top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.runtime.RootSetStatistics` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/RootSetStatistics/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_RootSetStatistics_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_RootSetStatistics_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_RootSetStatistics_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.RootSetStatistics.<init>` — constructor (Long, Long, Long, Long)  -- `constructor <init>(kotlin/Long, kotlin/Long, kotlin/Long, kotlin/Long)`

- [ ] KSP-1270: kotlin.native.runtime.RootSetStatistics.RootSetStatistics の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.native.runtime.RootSetStatistics` / receiver `RootSetStatistics`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/RootSetStatistics/RootSetStatistics.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_RootSetStatistics_RootSetStatistics_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_RootSetStatistics_RootSetStatistics_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_RootSetStatistics_RootSetStatistics_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.RootSetStatistics.globalReferences` — val RootSetStatistics.globalReferences: Long  -- `final val globalReferences`
    - `kotlin.native.runtime.RootSetStatistics.stableReferences` — val RootSetStatistics.stableReferences: Long  -- `final val stableReferences`
    - `kotlin.native.runtime.RootSetStatistics.stackReferences` — val RootSetStatistics.stackReferences: Long  -- `final val stackReferences`
    - `kotlin.native.runtime.RootSetStatistics.threadLocalReferences` — val RootSetStatistics.threadLocalReferences: Long  -- `final val threadLocalReferences`

- [x] KSP-1271: kotlin.native.runtime.SweepStatistics top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.native.runtime.SweepStatistics` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/SweepStatistics/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_SweepStatistics_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_SweepStatistics_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_SweepStatistics_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.SweepStatistics.<init>` — constructor (Long, Long)  -- `constructor <init>(kotlin/Long, kotlin/Long)`
  - 完了根拠: Kotlin 2.3.10 公式 `GCInfo.kt` と同じ `@NativeRuntimeApi` / `@SinceKotlin("1.9")` 付き constructor を bundled Kotlin source に移し、`NativeRefRuntimeSemaTests.testSweepStatisticsConstructorIsSourceBacked` で source-backed constructor と既存 synthetic property surface の分離を検証した。KSP-1272 の `sweptCount` / `keptCount` receiver properties、GC/GCInfo/MemoryUsage/RootSetStatistics/Debugging、Runtime/ABI bridge は変更していない。

- [ ] KSP-1272: kotlin.native.runtime.SweepStatistics.SweepStatistics の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.native.runtime.SweepStatistics` / receiver `SweepStatistics`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/native/runtime/SweepStatistics/SweepStatistics.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_native_runtime_SweepStatistics_SweepStatistics_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_native_runtime_SweepStatistics_SweepStatistics_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_runtime_SweepStatistics_SweepStatistics_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.native.runtime.SweepStatistics.keptCount` — val SweepStatistics.keptCount: Long  -- `final val keptCount`
    - `kotlin.native.runtime.SweepStatistics.sweptCount` — val SweepStatistics.sweptCount: Long  -- `final val sweptCount`

- [ ] KSP-1274: kotlin.properties.Delegates.Delegates の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.properties.Delegates` / receiver `Delegates`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/properties/Delegates/Delegates.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_properties_Delegates_Delegates_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_properties_Delegates_Delegates_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_properties_Delegates_Delegates_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.properties.Delegates.notNull` — fun Delegates.notNull(): ReadWriteProperty  -- `final fun <#A1: kotlin/Any> notNull(): kotlin.properties/ReadWriteProperty<kotlin/Any?, #A1>`
    - `kotlin.properties.Delegates.observable` — fun Delegates.observable(, Function3): ReadWriteProperty  -- `final inline fun <#A1: kotlin/Any?> observable(#A1, crossinline kotlin/Function3<kotlin.reflect/KProperty<*>, #A1, #A1, kotlin/Unit>): kotlin.properties/ReadWriteProperty<kotlin/Any?, #A1>`
    - `kotlin.properties.Delegates.vetoable` — fun Delegates.vetoable(, Function3): ReadWriteProperty  -- `final inline fun <#A1: kotlin/Any?> vetoable(#A1, crossinline kotlin/Function3<kotlin.reflect/KProperty<*>, #A1, #A1, kotlin/Boolean>): kotlin.properties/ReadWriteProperty<kotlin/Any?, #A1>`

- [ ] KSP-1275: kotlin.properties.ObservableProperty top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.properties.ObservableProperty` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/properties/ObservableProperty/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_properties_ObservableProperty_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_properties_ObservableProperty_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_properties_ObservableProperty_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.properties.ObservableProperty.<init>` — constructor ()  -- `constructor <init>(#A)`

- [ ] KSP-1276: kotlin.properties.ObservableProperty.ObservableProperty の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.properties.ObservableProperty` / receiver `ObservableProperty`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/properties/ObservableProperty/ObservableProperty.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_properties_ObservableProperty_ObservableProperty_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_properties_ObservableProperty_ObservableProperty_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_properties_ObservableProperty_ObservableProperty_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.properties.ObservableProperty.afterChange` — fun ObservableProperty.afterChange(KProperty, , ): Unit  -- `open fun afterChange(kotlin.reflect/KProperty<*>, #A, #A)`
    - `kotlin.properties.ObservableProperty.beforeChange` — fun ObservableProperty.beforeChange(KProperty, , ): Boolean  -- `open fun beforeChange(kotlin.reflect/KProperty<*>, #A, #A): kotlin/Boolean`
    - `kotlin.properties.ObservableProperty.getValue` — fun ObservableProperty.getValue(Any, KProperty): #A  -- `open fun getValue(kotlin/Any?, kotlin.reflect/KProperty<*>): #A`
    - `kotlin.properties.ObservableProperty.setValue` — fun ObservableProperty.setValue(Any, KProperty, ): Unit  -- `open fun setValue(kotlin/Any?, kotlin.reflect/KProperty<*>, #A)`
    - `kotlin.properties.ObservableProperty.toString` — fun ObservableProperty.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1281: kotlin.ranges top-level の未実装 stdlib API を実装する（21 件）
  - 対象: `kotlin.ranges` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.CharProgression` — class kotlin.ranges.CharProgression  -- `open class kotlin.ranges/CharProgression : kotlin.collections/Iterable<kotlin/Char> {`
    - `kotlin.ranges.CharRange` — class kotlin.ranges.CharRange  -- `final class kotlin.ranges/CharRange : kotlin.ranges/CharProgression, kotlin.ranges/ClosedRange<kotlin/Char>, kotlin.ranges/OpenEndRange<kotlin/Char> {`
    - `kotlin.ranges.IntProgression` — class kotlin.ranges.IntProgression  -- `open class kotlin.ranges/IntProgression : kotlin.collections/Iterable<kotlin/Int> {`
    - `kotlin.ranges.IntRange` — class kotlin.ranges.IntRange  -- `final class kotlin.ranges/IntRange : kotlin.ranges/ClosedRange<kotlin/Int>, kotlin.ranges/IntProgression, kotlin.ranges/OpenEndRange<kotlin/Int> {`
    - `kotlin.ranges.LongProgression` — class kotlin.ranges.LongProgression  -- `open class kotlin.ranges/LongProgression : kotlin.collections/Iterable<kotlin/Long> {`
    - `kotlin.ranges.LongRange` — class kotlin.ranges.LongRange  -- `final class kotlin.ranges/LongRange : kotlin.ranges/ClosedRange<kotlin/Long>, kotlin.ranges/LongProgression, kotlin.ranges/OpenEndRange<kotlin/Long> {`
    - `kotlin.ranges.UIntProgression` — class kotlin.ranges.UIntProgression  -- `open class kotlin.ranges/UIntProgression : kotlin.collections/Iterable<kotlin/UInt> {`
    - `kotlin.ranges.UIntRange` — class kotlin.ranges.UIntRange  -- `final class kotlin.ranges/UIntRange : kotlin.ranges/ClosedRange<kotlin/UInt>, kotlin.ranges/OpenEndRange<kotlin/UInt>, kotlin.ranges/UIntProgression {`
    - `kotlin.ranges.ULongProgression` — class kotlin.ranges.ULongProgression  -- `open class kotlin.ranges/ULongProgression : kotlin.collections/Iterable<kotlin/ULong> {`
    - `kotlin.ranges.ULongRange` — class kotlin.ranges.ULongRange  -- `final class kotlin.ranges/ULongRange : kotlin.ranges/ClosedRange<kotlin/ULong>, kotlin.ranges/OpenEndRange<kotlin/ULong>, kotlin.ranges/ULongProgression {`
    - `kotlin.ranges.coerceAtLeast` — fun coerceAtLeast(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceAtLeast(#A): #A`
    - `kotlin.ranges.coerceAtMost` — fun coerceAtMost(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceAtMost(#A): #A`
    - `kotlin.ranges.coerceIn` — fun coerceIn(ClosedFloatingPointRange): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceIn(kotlin.ranges/ClosedFloatingPointRange<#A>): #A`
    - `kotlin.ranges.coerceIn` — fun coerceIn(ClosedRange): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceIn(kotlin.ranges/ClosedRange<#A>): #A`
    - `kotlin.ranges.coerceIn` — fun coerceIn(, ): #A  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/coerceIn(#A?, #A?): #A`
    - `kotlin.ranges.contains` — fun contains(): Boolean  -- `final inline fun <#A: kotlin/Any, #B: kotlin.collections/Iterable<#A> & kotlin.ranges/ClosedRange<#A>> (#B).kotlin.ranges/contains(#A?): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun contains(): Boolean  -- `final inline fun <#A: kotlin/Any, #B: kotlin.collections/Iterable<#A> & kotlin.ranges/OpenEndRange<#A>> (#B).kotlin.ranges/contains(#A?): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun contains(): Boolean  -- `final inline fun <#A: kotlin/Comparable<#A>, #B: kotlin.collections/Iterable<#A> & kotlin.ranges/ClosedRange<#A>> (#B).kotlin.ranges/contains(#A?): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun contains(): Boolean  -- `final inline fun <#A: kotlin/Comparable<#A>, #B: kotlin.collections/Iterable<#A> & kotlin.ranges/OpenEndRange<#A>> (#B).kotlin.ranges/contains(#A?): kotlin/Boolean`
    - `kotlin.ranges.rangeTo` — fun rangeTo(): ClosedRange  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/rangeTo(#A): kotlin.ranges/ClosedRange<#A>`
    - `kotlin.ranges.rangeUntil` — fun rangeUntil(): OpenEndRange  -- `final fun <#A: kotlin/Comparable<#A>> (#A).kotlin.ranges/rangeUntil(#A): kotlin.ranges/OpenEndRange<#A>`

- [ ] KSP-1283: kotlin.ranges.ClosedRange の未実装 stdlib API を実装する（30 件）
  - 対象: `kotlin.ranges` / receiver `ClosedRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ClosedRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ClosedRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ClosedRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ClosedRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Byte>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Double>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Float>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Int>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Short): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Long>).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Byte): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Double): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Double): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Float): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Float): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Int): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ClosedRange.contains(Long): Boolean  -- `final fun (kotlin.ranges/ClosedRange<kotlin/Short>).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`

- [ ] KSP-1284: kotlin.ranges.IntProgression の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.ranges` / receiver `IntProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.first` — fun IntProgression.first(): Int  -- `final fun (kotlin.ranges/IntProgression).kotlin.ranges/first(): kotlin/Int`
    - `kotlin.ranges.last` — fun IntProgression.last(): Int  -- `final fun (kotlin.ranges/IntProgression).kotlin.ranges/last(): kotlin/Int`

- [ ] KSP-1285: kotlin.ranges.IntRange の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.ranges` / receiver `IntRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.contains` — fun IntRange.contains(Byte): Boolean  -- `final inline fun (kotlin.ranges/IntRange).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun IntRange.contains(Long): Boolean  -- `final inline fun (kotlin.ranges/IntRange).kotlin.ranges/contains(kotlin/Long): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun IntRange.contains(Short): Boolean  -- `final inline fun (kotlin.ranges/IntRange).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`

- [ ] KSP-1286: kotlin.ranges.LongProgression の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges` / receiver `LongProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.first` — fun LongProgression.first(): Long  -- `final fun (kotlin.ranges/LongProgression).kotlin.ranges/first(): kotlin/Long`
    - `kotlin.ranges.firstOrNull` — fun LongProgression.firstOrNull(): Long  -- `final fun (kotlin.ranges/LongProgression).kotlin.ranges/firstOrNull(): kotlin/Long?`
    - `kotlin.ranges.last` — fun LongProgression.last(): Long  -- `final fun (kotlin.ranges/LongProgression).kotlin.ranges/last(): kotlin/Long`
    - `kotlin.ranges.lastOrNull` — fun LongProgression.lastOrNull(): Long  -- `final fun (kotlin.ranges/LongProgression).kotlin.ranges/lastOrNull(): kotlin/Long?`

- [ ] KSP-1287: kotlin.ranges.LongRange の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.ranges` / receiver `LongRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.contains` — fun LongRange.contains(Byte): Boolean  -- `final inline fun (kotlin.ranges/LongRange).kotlin.ranges/contains(kotlin/Byte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun LongRange.contains(Int): Boolean  -- `final inline fun (kotlin.ranges/LongRange).kotlin.ranges/contains(kotlin/Int): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun LongRange.contains(Short): Boolean  -- `final inline fun (kotlin.ranges/LongRange).kotlin.ranges/contains(kotlin/Short): kotlin/Boolean`

- [ ] KSP-1289: kotlin.ranges.UIntProgression の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges` / receiver `UIntProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.first` — fun UIntProgression.first(): UInt  -- `final fun (kotlin.ranges/UIntProgression).kotlin.ranges/first(): kotlin/UInt`
    - `kotlin.ranges.firstOrNull` — fun UIntProgression.firstOrNull(): UInt  -- `final fun (kotlin.ranges/UIntProgression).kotlin.ranges/firstOrNull(): kotlin/UInt?`
    - `kotlin.ranges.last` — fun UIntProgression.last(): UInt  -- `final fun (kotlin.ranges/UIntProgression).kotlin.ranges/last(): kotlin/UInt`
    - `kotlin.ranges.lastOrNull` — fun UIntProgression.lastOrNull(): UInt  -- `final fun (kotlin.ranges/UIntProgression).kotlin.ranges/lastOrNull(): kotlin/UInt?`

- [ ] KSP-1290: kotlin.ranges.UIntRange の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.ranges` / receiver `UIntRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.contains` — fun UIntRange.contains(UByte): Boolean  -- `final fun (kotlin.ranges/UIntRange).kotlin.ranges/contains(kotlin/UByte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun UIntRange.contains(ULong): Boolean  -- `final fun (kotlin.ranges/UIntRange).kotlin.ranges/contains(kotlin/ULong): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun UIntRange.contains(UShort): Boolean  -- `final fun (kotlin.ranges/UIntRange).kotlin.ranges/contains(kotlin/UShort): kotlin/Boolean`

- [ ] KSP-1291: kotlin.ranges.ULongProgression の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges` / receiver `ULongProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.first` — fun ULongProgression.first(): ULong  -- `final fun (kotlin.ranges/ULongProgression).kotlin.ranges/first(): kotlin/ULong`
    - `kotlin.ranges.firstOrNull` — fun ULongProgression.firstOrNull(): ULong  -- `final fun (kotlin.ranges/ULongProgression).kotlin.ranges/firstOrNull(): kotlin/ULong?`
    - `kotlin.ranges.last` — fun ULongProgression.last(): ULong  -- `final fun (kotlin.ranges/ULongProgression).kotlin.ranges/last(): kotlin/ULong`
    - `kotlin.ranges.lastOrNull` — fun ULongProgression.lastOrNull(): ULong  -- `final fun (kotlin.ranges/ULongProgression).kotlin.ranges/lastOrNull(): kotlin/ULong?`

- [ ] KSP-1292: kotlin.ranges.ULongRange の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.ranges` / receiver `ULongRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.contains` — fun ULongRange.contains(UByte): Boolean  -- `final fun (kotlin.ranges/ULongRange).kotlin.ranges/contains(kotlin/UByte): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ULongRange.contains(UInt): Boolean  -- `final fun (kotlin.ranges/ULongRange).kotlin.ranges/contains(kotlin/UInt): kotlin/Boolean`
    - `kotlin.ranges.contains` — fun ULongRange.contains(UShort): Boolean  -- `final fun (kotlin.ranges/ULongRange).kotlin.ranges/contains(kotlin/UShort): kotlin/Boolean`

- [ ] KSP-1293: kotlin.ranges.CharProgression top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.CharProgression` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/CharProgression/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_CharProgression_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_CharProgression_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_CharProgression_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.CharProgression.Companion` — object kotlin.ranges.CharProgression.Companion  -- `final object Companion {`

- [ ] KSP-1294: kotlin.ranges.CharProgression.CharProgression の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.ranges.CharProgression` / receiver `CharProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/CharProgression/CharProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_CharProgression_CharProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_CharProgression_CharProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_CharProgression_CharProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.CharProgression.equals` — fun CharProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.CharProgression.first` — val CharProgression.first: Char  -- `final val first`
    - `kotlin.ranges.CharProgression.hashCode` — fun CharProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.CharProgression.iterator` — fun CharProgression.iterator(): CharIterator  -- `open fun iterator(): kotlin.collections/CharIterator`
    - `kotlin.ranges.CharProgression.last` — val CharProgression.last: Char  -- `final val last`
    - `kotlin.ranges.CharProgression.step` — val CharProgression.step: Int  -- `final val step`
    - `kotlin.ranges.CharProgression.toString` — fun CharProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1296: kotlin.ranges.CharRange.CharRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.CharRange` / receiver `CharRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/CharRange/CharRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_CharRange_CharRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_CharRange_CharRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_CharRange_CharRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.CharRange.endExclusive` — val CharRange.endExclusive: Char  -- `final val endExclusive`
    - `kotlin.ranges.CharRange.endInclusive` — val CharRange.endInclusive: Char  -- `final val endInclusive`
    - `kotlin.ranges.CharRange.equals` — fun CharRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.CharRange.hashCode` — fun CharRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.CharRange.start` — val CharRange.start: Char  -- `final val start`
    - `kotlin.ranges.CharRange.toString` — fun CharRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1298: kotlin.ranges.ClosedFloatingPointRange.ClosedFloatingPointRange の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.ranges.ClosedFloatingPointRange` / receiver `ClosedFloatingPointRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ClosedFloatingPointRange/ClosedFloatingPointRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ClosedFloatingPointRange_ClosedFloatingPointRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ClosedFloatingPointRange_ClosedFloatingPointRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ClosedFloatingPointRange_ClosedFloatingPointRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ClosedFloatingPointRange.contains` — fun ClosedFloatingPointRange.contains(): Boolean  -- `open fun contains(#A): kotlin/Boolean`
    - `kotlin.ranges.ClosedFloatingPointRange.isEmpty` — fun ClosedFloatingPointRange.isEmpty(): Boolean  -- `open fun isEmpty(): kotlin/Boolean`
    - `kotlin.ranges.ClosedFloatingPointRange.lessThanOrEquals` — fun ClosedFloatingPointRange.lessThanOrEquals(, ): Boolean  -- `abstract fun lessThanOrEquals(#A, #A): kotlin/Boolean`

- [ ] KSP-1299: kotlin.ranges.ClosedRange.ClosedRange の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges.ClosedRange` / receiver `ClosedRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ClosedRange/ClosedRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ClosedRange_ClosedRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ClosedRange_ClosedRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ClosedRange_ClosedRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ClosedRange.contains` — fun ClosedRange.contains(): Boolean  -- `open fun contains(#A): kotlin/Boolean`
    - `kotlin.ranges.ClosedRange.endInclusive` — val ClosedRange.endInclusive: #A  -- `abstract val endInclusive`
    - `kotlin.ranges.ClosedRange.isEmpty` — fun ClosedRange.isEmpty(): Boolean  -- `open fun isEmpty(): kotlin/Boolean`
    - `kotlin.ranges.ClosedRange.start` — val ClosedRange.start: #A  -- `abstract val start`

- [ ] KSP-1301: kotlin.ranges.IntProgression.IntProgression の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.ranges.IntProgression` / receiver `IntProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/IntProgression/IntProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntProgression_IntProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntProgression_IntProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntProgression_IntProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.IntProgression.equals` — fun IntProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.IntProgression.first` — val IntProgression.first: Int  -- `final val first`
    - `kotlin.ranges.IntProgression.hashCode` — fun IntProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.IntProgression.iterator` — fun IntProgression.iterator(): IntIterator  -- `open fun iterator(): kotlin.collections/IntIterator`
    - `kotlin.ranges.IntProgression.last` — val IntProgression.last: Int  -- `final val last`
    - `kotlin.ranges.IntProgression.step` — val IntProgression.step: Int  -- `final val step`
    - `kotlin.ranges.IntProgression.toString` — fun IntProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1302: kotlin.ranges.IntRange top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.ranges.IntRange` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/IntRange/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntRange_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.IntRange.<init>` — constructor (Int, Int)  -- `constructor <init>(kotlin/Int, kotlin/Int)`
    - `kotlin.ranges.IntRange.Companion` — object kotlin.ranges.IntRange.Companion  -- `final object Companion {`

- [ ] KSP-1303: kotlin.ranges.IntRange.IntRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.IntRange` / receiver `IntRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/IntRange/IntRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntRange_IntRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_IntRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_IntRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.IntRange.endExclusive` — val IntRange.endExclusive: Int  -- `final val endExclusive`
    - `kotlin.ranges.IntRange.endInclusive` — val IntRange.endInclusive: Int  -- `final val endInclusive`
    - `kotlin.ranges.IntRange.equals` — fun IntRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.IntRange.hashCode` — fun IntRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.IntRange.start` — val IntRange.start: Int  -- `final val start`
    - `kotlin.ranges.IntRange.toString` — fun IntRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1304: kotlin.ranges.IntRange.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.IntRange.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/IntRange/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_IntRange_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_IntRange_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.IntRange.Companion.EMPTY` — val Companion.EMPTY: IntRange  -- `final val EMPTY`

- [ ] KSP-1305: kotlin.ranges.LongProgression top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.LongProgression` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongProgression/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongProgression.Companion` — object kotlin.ranges.LongProgression.Companion  -- `final object Companion {`

- [ ] KSP-1306: kotlin.ranges.LongProgression.LongProgression の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.ranges.LongProgression` / receiver `LongProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongProgression/LongProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_LongProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_LongProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_LongProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongProgression.equals` — fun LongProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.LongProgression.first` — val LongProgression.first: Long  -- `final val first`
    - `kotlin.ranges.LongProgression.hashCode` — fun LongProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.LongProgression.iterator` — fun LongProgression.iterator(): LongIterator  -- `open fun iterator(): kotlin.collections/LongIterator`
    - `kotlin.ranges.LongProgression.last` — val LongProgression.last: Long  -- `final val last`
    - `kotlin.ranges.LongProgression.step` — val LongProgression.step: Long  -- `final val step`
    - `kotlin.ranges.LongProgression.toString` — fun LongProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1307: kotlin.ranges.LongProgression.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.LongProgression.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongProgression/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongProgression_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongProgression_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongProgression.Companion.fromClosedRange` — fun Companion.fromClosedRange(Long, Long, Long): LongProgression  -- `final fun fromClosedRange(kotlin/Long, kotlin/Long, kotlin/Long): kotlin.ranges/LongProgression`

- [ ] KSP-1308: kotlin.ranges.LongRange top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.ranges.LongRange` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongRange/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongRange_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongRange.<init>` — constructor (Long, Long)  -- `constructor <init>(kotlin/Long, kotlin/Long)`
    - `kotlin.ranges.LongRange.Companion` — object kotlin.ranges.LongRange.Companion  -- `final object Companion {`

- [ ] KSP-1309: kotlin.ranges.LongRange.LongRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.LongRange` / receiver `LongRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongRange/LongRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongRange_LongRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_LongRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_LongRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongRange.endExclusive` — val LongRange.endExclusive: Long  -- `final val endExclusive`
    - `kotlin.ranges.LongRange.endInclusive` — val LongRange.endInclusive: Long  -- `final val endInclusive`
    - `kotlin.ranges.LongRange.equals` — fun LongRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.LongRange.hashCode` — fun LongRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.LongRange.start` — val LongRange.start: Long  -- `final val start`
    - `kotlin.ranges.LongRange.toString` — fun LongRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1310: kotlin.ranges.LongRange.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.LongRange.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/LongRange/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_LongRange_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_LongRange_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.LongRange.Companion.EMPTY` — val Companion.EMPTY: LongRange  -- `final val EMPTY`

- [ ] KSP-1311: kotlin.ranges.OpenEndRange.OpenEndRange の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.ranges.OpenEndRange` / receiver `OpenEndRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/OpenEndRange/OpenEndRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_OpenEndRange_OpenEndRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_OpenEndRange_OpenEndRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_OpenEndRange_OpenEndRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.OpenEndRange.contains` — fun OpenEndRange.contains(): Boolean  -- `open fun contains(#A): kotlin/Boolean`
    - `kotlin.ranges.OpenEndRange.endExclusive` — val OpenEndRange.endExclusive: #A  -- `abstract val endExclusive`
    - `kotlin.ranges.OpenEndRange.isEmpty` — fun OpenEndRange.isEmpty(): Boolean  -- `open fun isEmpty(): kotlin/Boolean`
    - `kotlin.ranges.OpenEndRange.start` — val OpenEndRange.start: #A  -- `abstract val start`

- [ ] KSP-1312: kotlin.ranges.UIntProgression top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.UIntProgression` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntProgression/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntProgression_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntProgression.Companion` — object kotlin.ranges.UIntProgression.Companion  -- `final object Companion {`

- [ ] KSP-1313: kotlin.ranges.UIntProgression.UIntProgression の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.UIntProgression` / receiver `UIntProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntProgression/UIntProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntProgression_UIntProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_UIntProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntProgression_UIntProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntProgression.equals` — fun UIntProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.UIntProgression.first` — val UIntProgression.first: UInt  -- `final val first`
    - `kotlin.ranges.UIntProgression.hashCode` — fun UIntProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.UIntProgression.last` — val UIntProgression.last: UInt  -- `final val last`
    - `kotlin.ranges.UIntProgression.step` — val UIntProgression.step: Int  -- `final val step`
    - `kotlin.ranges.UIntProgression.toString` — fun UIntProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1314: kotlin.ranges.UIntRange top-level の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.ranges.UIntRange` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntRange/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntRange_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntRange.<init>` — constructor (UInt, UInt)  -- `constructor <init>(kotlin/UInt, kotlin/UInt)`
    - `kotlin.ranges.UIntRange.Companion` — object kotlin.ranges.UIntRange.Companion  -- `final object Companion {`

- [ ] KSP-1315: kotlin.ranges.UIntRange.UIntRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.UIntRange` / receiver `UIntRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntRange/UIntRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntRange_UIntRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_UIntRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_UIntRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntRange.endExclusive` — val UIntRange.endExclusive: UInt  -- `final val endExclusive`
    - `kotlin.ranges.UIntRange.endInclusive` — val UIntRange.endInclusive: UInt  -- `final val endInclusive`
    - `kotlin.ranges.UIntRange.equals` — fun UIntRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.UIntRange.hashCode` — fun UIntRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.UIntRange.start` — val UIntRange.start: UInt  -- `final val start`
    - `kotlin.ranges.UIntRange.toString` — fun UIntRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1316: kotlin.ranges.UIntRange.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.UIntRange.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/UIntRange/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_UIntRange_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_UIntRange_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.UIntRange.Companion.EMPTY` — val Companion.EMPTY: UIntRange  -- `final val EMPTY`

- [ ] KSP-1317: kotlin.ranges.ULongProgression top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.ULongProgression` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongProgression/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongProgression_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongProgression.Companion` — object kotlin.ranges.ULongProgression.Companion  -- `final object Companion {`

- [ ] KSP-1318: kotlin.ranges.ULongProgression.ULongProgression の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.ULongProgression` / receiver `ULongProgression`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongProgression/ULongProgression.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongProgression_ULongProgression_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_ULongProgression_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_ULongProgression_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongProgression.equals` — fun ULongProgression.equals(Any): Boolean  -- `open fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.ULongProgression.first` — val ULongProgression.first: ULong  -- `final val first`
    - `kotlin.ranges.ULongProgression.hashCode` — fun ULongProgression.hashCode(): Int  -- `open fun hashCode(): kotlin/Int`
    - `kotlin.ranges.ULongProgression.last` — val ULongProgression.last: ULong  -- `final val last`
    - `kotlin.ranges.ULongProgression.step` — val ULongProgression.step: Long  -- `final val step`
    - `kotlin.ranges.ULongProgression.toString` — fun ULongProgression.toString(): String  -- `open fun toString(): kotlin/String`

- [ ] KSP-1319: kotlin.ranges.ULongProgression.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.ULongProgression.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongProgression/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongProgression_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongProgression_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongProgression.Companion.fromClosedRange` — fun Companion.fromClosedRange(ULong, ULong, Long): ULongProgression  -- `final fun fromClosedRange(kotlin/ULong, kotlin/ULong, kotlin/Long): kotlin.ranges/ULongProgression`

- [ ] KSP-1321: kotlin.ranges.ULongRange.ULongRange の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.ranges.ULongRange` / receiver `ULongRange`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongRange/ULongRange.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongRange_ULongRange_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_ULongRange_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_ULongRange_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongRange.endExclusive` — val ULongRange.endExclusive: ULong  -- `final val endExclusive`
    - `kotlin.ranges.ULongRange.endInclusive` — val ULongRange.endInclusive: ULong  -- `final val endInclusive`
    - `kotlin.ranges.ULongRange.equals` — fun ULongRange.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.ranges.ULongRange.hashCode` — fun ULongRange.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.ranges.ULongRange.start` — val ULongRange.start: ULong  -- `final val start`
    - `kotlin.ranges.ULongRange.toString` — fun ULongRange.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1322: kotlin.ranges.ULongRange.Companion.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.ranges.ULongRange.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/ranges/ULongRange/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_ranges_ULongRange_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_ranges_ULongRange_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.ranges.ULongRange.Companion.EMPTY` — val Companion.EMPTY: ULongRange  -- `final val EMPTY`

- [ ] KSP-1323: kotlin.reflect top-level の未実装 stdlib API を実装する（15 件）
  - 対象: `kotlin.reflect` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.AssociatedObjectKey` — class kotlin.reflect.AssociatedObjectKey  -- `open annotation class kotlin.reflect/AssociatedObjectKey : kotlin/Annotation {`
    - `kotlin.reflect.ExperimentalAssociatedObjects` — class kotlin.reflect.ExperimentalAssociatedObjects  -- `open annotation class kotlin.reflect/ExperimentalAssociatedObjects : kotlin/Annotation {`
    - `kotlin.reflect.KAnnotatedElement` — interface kotlin.reflect.KAnnotatedElement  -- `abstract interface kotlin.reflect/KAnnotatedElement`
    - `kotlin.reflect.KCallable` — interface kotlin.reflect.KCallable  -- `abstract interface <#A: out kotlin/Any?> kotlin.reflect/KCallable : kotlin.reflect/KAnnotatedElement {`
    - `kotlin.reflect.KClass` — interface kotlin.reflect.KClass  -- `abstract interface <#A: kotlin/Any> kotlin.reflect/KClass : kotlin.reflect/KAnnotatedElement, kotlin.reflect/KClassifier, kotlin.reflect/KDeclarationContainer {`
    - `kotlin.reflect.KClassifier` — interface kotlin.reflect.KClassifier  -- `abstract interface kotlin.reflect/KClassifier`
    - `kotlin.reflect.KDeclarationContainer` — interface kotlin.reflect.KDeclarationContainer  -- `abstract interface kotlin.reflect/KDeclarationContainer`
    - `kotlin.reflect.KFunction` — interface kotlin.reflect.KFunction  -- `abstract interface <#A: out kotlin/Any?> kotlin.reflect/KFunction : kotlin.reflect/KCallable<#A>, kotlin/Function<#A>`
    - `kotlin.reflect.KMutableProperty` — interface kotlin.reflect.KMutableProperty  -- `abstract interface <#A: kotlin/Any?> kotlin.reflect/KMutableProperty : kotlin.reflect/KProperty<#A>`
    - `kotlin.reflect.KProperty` — interface kotlin.reflect.KProperty  -- `abstract interface <#A: out kotlin/Any?> kotlin.reflect/KProperty : kotlin.reflect/KCallable<#A>`
    - `kotlin.reflect.KType` — interface kotlin.reflect.KType  -- `abstract interface kotlin.reflect/KType {`
    - `kotlin.reflect.KTypeParameter` — interface kotlin.reflect.KTypeParameter  -- `abstract interface kotlin.reflect/KTypeParameter : kotlin.reflect/KClassifier {`
    - `kotlin.reflect.KTypeProjection` — class kotlin.reflect.KTypeProjection  -- `final class kotlin.reflect/KTypeProjection {`
    - `kotlin.reflect.KVariance` — enumClass kotlin.reflect.KVariance  -- `final enum class kotlin.reflect/KVariance : kotlin/Enum<kotlin.reflect/KVariance> {`
    - `kotlin.reflect.typeOf` — fun typeOf(): KType  -- `final inline fun <#A: reified kotlin/Any?> kotlin.reflect/typeOf(): kotlin.reflect/KType`

- [ ] KSP-1324: kotlin.reflect.KClass の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.reflect` / receiver `KClass`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KClass_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KClass_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KClass_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.cast` — fun KClass.cast(Any): #A  -- `final fun <#A: kotlin/Any> (kotlin.reflect/KClass<#A>).kotlin.reflect/cast(kotlin/Any?): #A`
    - `kotlin.reflect.findAssociatedObject` — fun KClass.findAssociatedObject(): Any  -- `final inline fun <#A: reified kotlin/Annotation> (kotlin.reflect/KClass<*>).kotlin.reflect/findAssociatedObject(): kotlin/Any?`
    - `kotlin.reflect.safeCast` — fun KClass.safeCast(Any): #A  -- `final fun <#A: kotlin/Any> (kotlin.reflect/KClass<#A>).kotlin.reflect/safeCast(kotlin/Any?): #A?`

- [x] KSP-1327: kotlin.reflect.KCallable.KCallable の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.reflect.KCallable` / receiver `KCallable`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KCallable/KCallable.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KCallable_KCallable_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KCallable_KCallable_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KCallable_KCallable_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 完了根拠: `KCallable.kt` を source-backed declaration として追加し、`name: String` と Native 契約の `returnType: KType` を定義。KFunction/KProperty 継承と safe-call を含む Sema/KIR routing を shared `__kk_kcallable_get_return_type` に接続し、runtime reflection box と callable reference metadata を実体の `RuntimeKTypeBox` に変換した。
  - 回帰: `ReflectKCallableTests`、`stdlib_kotlin_reflect_KCallable_KCallable_n` の Sema Golden/diff、`RuntimeReflectionTypeMetadataTests`、既存 `CallableRefTypeIdentityTests`、Runtime ABI link validation を通過。
  - 未実装シンボル一覧:
    - `kotlin.reflect.KCallable.name` — val KCallable.name: String  -- `abstract val name`
    - `kotlin.reflect.KCallable.returnType` — val KCallable.returnType: KType  -- `abstract val returnType`

- [x] KSP-1328: kotlin.reflect.KClass.KClass の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.reflect.KClass` / receiver `KClass`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KClass/KClass.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KClass_KClass_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KClass_KClass_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KClass_KClass_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.KClass.equals` — fun KClass.equals(Any): Boolean  -- `abstract fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.reflect.KClass.hashCode` — fun KClass.hashCode(): Int  -- `abstract fun hashCode(): kotlin/Int`

- [x] KSP-1332: kotlin.reflect.KType.KType の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.reflect.KType` / receiver `KType`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KType/KType.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KType_KType_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KType_KType_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KType_KType_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.KType.arguments` — val KType.arguments: List  -- `abstract val arguments`
    - `kotlin.reflect.KType.classifier` — val KType.classifier: KClassifier  -- `abstract val classifier`
    - `kotlin.reflect.KType.isMarkedNullable` — val KType.isMarkedNullable: Boolean  -- `abstract val isMarkedNullable`

- [ ] KSP-1333: kotlin.reflect.KTypeParameter.KTypeParameter の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.reflect.KTypeParameter` / receiver `KTypeParameter`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KTypeParameter/KTypeParameter.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KTypeParameter_KTypeParameter_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KTypeParameter_KTypeParameter_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KTypeParameter_KTypeParameter_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.KTypeParameter.isReified` — val KTypeParameter.isReified: Boolean  -- `abstract val isReified`
    - `kotlin.reflect.KTypeParameter.name` — val KTypeParameter.name: String  -- `abstract val name`
    - `kotlin.reflect.KTypeParameter.upperBounds` — val KTypeParameter.upperBounds: List  -- `abstract val upperBounds`
    - `kotlin.reflect.KTypeParameter.variance` — val KTypeParameter.variance: KVariance  -- `abstract val variance`

- [ ] KSP-1335: kotlin.reflect.KTypeProjection.KTypeProjection の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.reflect.KTypeProjection` / receiver `KTypeProjection`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KTypeProjection/KTypeProjection.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KTypeProjection_KTypeProjection_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KTypeProjection_KTypeProjection_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KTypeProjection_KTypeProjection_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.KTypeProjection.component1` — fun KTypeProjection.component1(): KVariance  -- `final fun component1(): kotlin.reflect/KVariance?`
    - `kotlin.reflect.KTypeProjection.component2` — fun KTypeProjection.component2(): KType  -- `final fun component2(): kotlin.reflect/KType?`
    - `kotlin.reflect.KTypeProjection.copy` — fun KTypeProjection.copy(KVariance, KType): KTypeProjection  -- `final fun copy(kotlin.reflect/KVariance? = ..., kotlin.reflect/KType? = ...): kotlin.reflect/KTypeProjection`
    - `kotlin.reflect.KTypeProjection.equals` — fun KTypeProjection.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.reflect.KTypeProjection.hashCode` — fun KTypeProjection.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.reflect.KTypeProjection.toString` — fun KTypeProjection.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.reflect.KTypeProjection.type` — val KTypeProjection.type: KType  -- `final val type`
    - `kotlin.reflect.KTypeProjection.variance` — val KTypeProjection.variance: KVariance  -- `final val variance`

- [ ] KSP-1336: kotlin.reflect.KTypeProjection.Companion.Companion の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.reflect.KTypeProjection.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/reflect/KTypeProjection/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_reflect_KTypeProjection_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_reflect_KTypeProjection_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_reflect_KTypeProjection_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.reflect.KTypeProjection.Companion.STAR` — val Companion.STAR: KTypeProjection  -- `final val STAR`
    - `kotlin.reflect.KTypeProjection.Companion.contravariant` — fun Companion.contravariant(KType): KTypeProjection  -- `final fun contravariant(kotlin.reflect/KType): kotlin.reflect/KTypeProjection`
    - `kotlin.reflect.KTypeProjection.Companion.covariant` — fun Companion.covariant(KType): KTypeProjection  -- `final fun covariant(kotlin.reflect/KType): kotlin.reflect/KTypeProjection`
    - `kotlin.reflect.KTypeProjection.Companion.invariant` — fun Companion.invariant(KType): KTypeProjection  -- `final fun invariant(kotlin.reflect/KType): kotlin.reflect/KTypeProjection`
    - `kotlin.reflect.KTypeProjection.Companion.star` — val Companion.star: KTypeProjection  -- `final val star`

- [ ] KSP-1338: kotlin.sequences top-level の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.sequences` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.Sequence` — fun Sequence(Function0): Sequence  -- `final inline fun <#A: kotlin/Any?> kotlin.sequences/Sequence(crossinline kotlin/Function0<kotlin.collections/Iterator<#A>>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.SequenceScope` — class kotlin.sequences.SequenceScope  -- `abstract class <#A: in kotlin/Any?> kotlin.sequences/SequenceScope {`
    - `kotlin.sequences.generateSequence` — fun generateSequence(Function0): Sequence  -- `final fun <#A: kotlin/Any> kotlin.sequences/generateSequence(kotlin/Function0<#A?>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.generateSequence` — fun generateSequence(, Function1): Sequence  -- `final fun <#A: kotlin/Any> kotlin.sequences/generateSequence(#A?, kotlin/Function1<#A, #A?>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.generateSequence` — fun generateSequence(Function0, Function1): Sequence  -- `final fun <#A: kotlin/Any> kotlin.sequences/generateSequence(kotlin/Function0<#A?>, kotlin/Function1<#A, #A?>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.iterator` — fun iterator(SuspendFunction1): Iterator  -- `final fun <#A: kotlin/Any?> kotlin.sequences/iterator(kotlin.coroutines/SuspendFunction1<kotlin.sequences/SequenceScope<#A>, kotlin/Unit>): kotlin.collections/Iterator<#A>`
    - `kotlin.sequences.sequence` — fun sequence(SuspendFunction1): Sequence  -- `final fun <#A: kotlin/Any?> kotlin.sequences/sequence(kotlin.coroutines/SuspendFunction1<kotlin.sequences/SequenceScope<#A>, kotlin/Unit>): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.sequenceOf` — fun sequenceOf(): Sequence  -- `final inline fun <#A: kotlin/Any?> kotlin.sequences/sequenceOf(): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.sequenceOf` — fun sequenceOf(): Sequence  -- `final fun <#A: kotlin/Any?> kotlin.sequences/sequenceOf(#A): kotlin.sequences/Sequence<#A>`

- [ ] KSP-1340: kotlin.sequences.Sequence.associate-family の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `associate`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_associate.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_associate.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_associate.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.associate` — fun Sequence.associate(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associate(kotlin/Function1<#A, kotlin/Pair<#B, #C>>): kotlin.collections/Map<#B, #C>`
    - `kotlin.sequences.associateBy` — fun Sequence.associateBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateBy(kotlin/Function1<#A, #B>): kotlin.collections/Map<#B, #A>`
    - `kotlin.sequences.associateBy` — fun Sequence.associateBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateBy(kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): kotlin.collections/Map<#B, #C>`
    - `kotlin.sequences.associateByTo` — fun Sequence.associateByTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #B, in #A>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateByTo(#C, kotlin/Function1<#A, #B>): #C`
    - `kotlin.sequences.associateByTo` — fun Sequence.associateByTo(, Function1, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, in #C>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateByTo(#D, kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): #D`
    - `kotlin.sequences.associateTo` — fun Sequence.associateTo(, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, in #C>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateTo(#D, kotlin/Function1<#A, kotlin/Pair<#B, #C>>): #D`
    - `kotlin.sequences.associateWith` — fun Sequence.associateWith(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateWith(kotlin/Function1<#A, #B>): kotlin.collections/Map<#A, #B>`
    - `kotlin.sequences.associateWithTo` — fun Sequence.associateWithTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/associateWithTo(#C, kotlin/Function1<#A, #B>): #C`

- [ ] KSP-1341: kotlin.sequences.Sequence.element-family の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `element`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_element.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_element.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_element.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.elementAt` — fun Sequence.elementAt(Int): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/elementAt(kotlin/Int): #A`
    - `kotlin.sequences.elementAtOrElse` — fun Sequence.elementAtOrElse(Int, Function1): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/elementAtOrElse(kotlin/Int, kotlin/Function1<kotlin/Int, #A>): #A`
    - `kotlin.sequences.elementAtOrNull` — fun Sequence.elementAtOrNull(Int): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/elementAtOrNull(kotlin/Int): #A?`

- [ ] KSP-1344: kotlin.sequences.Sequence.first-family の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `first`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_first.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_first.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_first.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.first` — fun Sequence.first(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/first(): #A`
    - `kotlin.sequences.first` — fun Sequence.first(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/first(kotlin/Function1<#A, kotlin/Boolean>): #A`
    - `kotlin.sequences.firstNotNullOf` — fun Sequence.firstNotNullOf(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any> (kotlin.sequences/Sequence<#A>).kotlin.sequences/firstNotNullOf(kotlin/Function1<#A, #B?>): #B`
    - `kotlin.sequences.firstNotNullOfOrNull` — fun Sequence.firstNotNullOfOrNull(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any> (kotlin.sequences/Sequence<#A>).kotlin.sequences/firstNotNullOfOrNull(kotlin/Function1<#A, #B?>): #B?`
    - `kotlin.sequences.firstOrNull` — fun Sequence.firstOrNull(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/firstOrNull(): #A?`
    - `kotlin.sequences.firstOrNull` — fun Sequence.firstOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/firstOrNull(kotlin/Function1<#A, kotlin/Boolean>): #A?`

- [ ] KSP-1345: kotlin.sequences.Sequence.flat-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `flat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceTransformHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_flat.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_flat.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_flat.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.flatMapIndexedTo` — fun Sequence.flatMapIndexedTo(, Function2): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/flatMapIndexedTo(#C, kotlin/Function2<kotlin/Int, #A, kotlin.collections/Iterable<#B>>): #C`
    - `kotlin.sequences.flatMapIndexedTo` — fun Sequence.flatMapIndexedTo(, Function2): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/flatMapIndexedTo(#C, kotlin/Function2<kotlin/Int, #A, kotlin.sequences/Sequence<#B>>): #C`
    - `kotlin.sequences.flatMapTo` — fun Sequence.flatMapTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/flatMapTo(#C, kotlin/Function1<#A, kotlin.collections/Iterable<#B>>): #C`
    - `kotlin.sequences.flatMapTo` — fun Sequence.flatMapTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/flatMapTo(#C, kotlin/Function1<#A, kotlin.sequences/Sequence<#B>>): #C`

- [ ] KSP-1346: kotlin.sequences.Sequence.fold-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `fold`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_fold.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_fold.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_fold.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.fold` — fun Sequence.fold(, Function2): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/fold(#B, kotlin/Function2<#B, #A, #B>): #B`
    - `kotlin.sequences.foldIndexed` — fun Sequence.foldIndexed(, Function3): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/foldIndexed(#B, kotlin/Function3<kotlin/Int, #B, #A, #B>): #B`

- [x] KSP-1347: kotlin.sequences.Sequence.for-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `for`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_for.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_for.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_for.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.forEach` — fun Sequence.forEach(Function1): Unit  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/forEach(kotlin/Function1<#A, kotlin/Unit>)`
    - `kotlin.sequences.forEachIndexed` — fun Sequence.forEachIndexed(Function2): Unit  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/forEachIndexed(kotlin/Function2<kotlin/Int, #A, kotlin/Unit>)`
  - 完了根拠: Kotlin 2.3.10準拠の `Sequence<T>.forEach` / `forEachIndexed` を bundled Kotlin source に追加し、順序・空Sequence・indexed引数・例外伝播を source-backed 経路で回帰固定。旧 `kk_sequence_forEach` / `kk_sequence_forEachIndexed` の Sequence stub、Runtime、ABI、lowering 特例を削除した。

- [ ] KSP-1348: kotlin.sequences.Sequence.group-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `group`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_group.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_group.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_group.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.groupBy` — fun Sequence.groupBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/groupBy(kotlin/Function1<#A, #B>): kotlin.collections/Map<#B, kotlin.collections/List<#A>>`
    - `kotlin.sequences.groupBy` — fun Sequence.groupBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/groupBy(kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): kotlin.collections/Map<#B, kotlin.collections/List<#C>>`
    - `kotlin.sequences.groupByTo` — fun Sequence.groupByTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #B, kotlin.collections/MutableList<#A>>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/groupByTo(#C, kotlin/Function1<#A, #B>): #C`
    - `kotlin.sequences.groupByTo` — fun Sequence.groupByTo(, Function1, Function1): #D  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin/Any?, #D: kotlin.collections/MutableMap<in #B, kotlin.collections/MutableList<#C>>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/groupByTo(#D, kotlin/Function1<#A, #B>, kotlin/Function1<#A, #C>): #D`

- [ ] KSP-1350: kotlin.sequences.Sequence.join-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `join`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_join.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_join.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_join.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.joinTo` — fun Sequence.joinTo(, CharSequence, CharSequence, CharSequence, Int, CharSequence, Function1): #B  -- `final fun <#A: kotlin/Any?, #B: kotlin.text/Appendable> (kotlin.sequences/Sequence<#A>).kotlin.sequences/joinTo(#B, kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/Int = ..., kotlin/CharSequence = ..., kotlin/Function1<#A, kotlin/CharSequence>? = ...): #B`
    - `kotlin.sequences.joinToString` — fun Sequence.joinToString(CharSequence, CharSequence, CharSequence, Int, CharSequence, Function1): String  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/joinToString(kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/CharSequence = ..., kotlin/Int = ..., kotlin/CharSequence = ..., kotlin/Function1<#A, kotlin/CharSequence>? = ...): kotlin/String`

- [ ] KSP-1351: kotlin.sequences.Sequence.last-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `last`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_last.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_last.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_last.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.last` — fun Sequence.last(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/last(): #A`
    - `kotlin.sequences.last` — fun Sequence.last(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/last(kotlin/Function1<#A, kotlin/Boolean>): #A`
    - `kotlin.sequences.lastOrNull` — fun Sequence.lastOrNull(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/lastOrNull(): #A?`
    - `kotlin.sequences.lastOrNull` — fun Sequence.lastOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/lastOrNull(kotlin/Function1<#A, kotlin/Boolean>): #A?`

- [ ] KSP-1352: kotlin.sequences.Sequence.map-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `map`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceDestinationHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_map.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_map.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_map.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.mapIndexedNotNullTo` — fun Sequence.mapIndexedNotNullTo(, Function2): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/mapIndexedNotNullTo(#C, kotlin/Function2<kotlin/Int, #A, #B?>): #C`
    - `kotlin.sequences.mapIndexedTo` — fun Sequence.mapIndexedTo(, Function2): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/mapIndexedTo(#C, kotlin/Function2<kotlin/Int, #A, #B>): #C`
    - `kotlin.sequences.mapNotNullTo` — fun Sequence.mapNotNullTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/mapNotNullTo(#C, kotlin/Function1<#A, #B?>): #C`
    - `kotlin.sequences.mapTo` — fun Sequence.mapTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableCollection<in #B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/mapTo(#C, kotlin/Function1<#A, #B>): #C`

- [ ] KSP-1353: kotlin.sequences.Sequence.max-family の未実装 stdlib API を実装する（18 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `max`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_max.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_max.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_max.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.max` — fun Sequence.max(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/max(): kotlin/Double`
    - `kotlin.sequences.max` — fun Sequence.max(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/max(): kotlin/Float`
    - `kotlin.sequences.max` — fun Sequence.max(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/max(): #A`
    - `kotlin.sequences.maxBy` — fun Sequence.maxBy(Function1): #A  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxBy(kotlin/Function1<#A, #B>): #A`
    - `kotlin.sequences.maxByOrNull` — fun Sequence.maxByOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxByOrNull(kotlin/Function1<#A, #B>): #A?`
    - `kotlin.sequences.maxOf` — fun Sequence.maxOf(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOf(kotlin/Function1<#A, #B>): #B`
    - `kotlin.sequences.maxOf` — fun Sequence.maxOf(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOf(kotlin/Function1<#A, kotlin/Double>): kotlin/Double`
    - `kotlin.sequences.maxOf` — fun Sequence.maxOf(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOf(kotlin/Function1<#A, kotlin/Float>): kotlin/Float`
    - `kotlin.sequences.maxOfOrNull` — fun Sequence.maxOfOrNull(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOfOrNull(kotlin/Function1<#A, #B>): #B?`
    - `kotlin.sequences.maxOfOrNull` — fun Sequence.maxOfOrNull(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOfOrNull(kotlin/Function1<#A, kotlin/Double>): kotlin/Double?`
    - `kotlin.sequences.maxOfOrNull` — fun Sequence.maxOfOrNull(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOfOrNull(kotlin/Function1<#A, kotlin/Float>): kotlin/Float?`
    - `kotlin.sequences.maxOfWith` — fun Sequence.maxOfWith(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOfWith(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B`
    - `kotlin.sequences.maxOfWithOrNull` — fun Sequence.maxOfWithOrNull(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOfWithOrNull(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B?`
    - `kotlin.sequences.maxOrNull` — fun Sequence.maxOrNull(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/maxOrNull(): kotlin/Double?`
    - `kotlin.sequences.maxOrNull` — fun Sequence.maxOrNull(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/maxOrNull(): kotlin/Float?`
    - `kotlin.sequences.maxOrNull` — fun Sequence.maxOrNull(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxOrNull(): #A?`
    - `kotlin.sequences.maxWith` — fun Sequence.maxWith(Comparator): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxWith(kotlin/Comparator<in #A>): #A`
    - `kotlin.sequences.maxWithOrNull` — fun Sequence.maxWithOrNull(Comparator): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/maxWithOrNull(kotlin/Comparator<in #A>): #A?`

- [ ] KSP-1354: kotlin.sequences.Sequence.min-family の未実装 stdlib API を実装する（18 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `min`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_min.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_min.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_min.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.min` — fun Sequence.min(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/min(): kotlin/Double`
    - `kotlin.sequences.min` — fun Sequence.min(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/min(): kotlin/Float`
    - `kotlin.sequences.min` — fun Sequence.min(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/min(): #A`
    - `kotlin.sequences.minBy` — fun Sequence.minBy(Function1): #A  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minBy(kotlin/Function1<#A, #B>): #A`
    - `kotlin.sequences.minByOrNull` — fun Sequence.minByOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minByOrNull(kotlin/Function1<#A, #B>): #A?`
    - `kotlin.sequences.minOf` — fun Sequence.minOf(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOf(kotlin/Function1<#A, #B>): #B`
    - `kotlin.sequences.minOf` — fun Sequence.minOf(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOf(kotlin/Function1<#A, kotlin/Double>): kotlin/Double`
    - `kotlin.sequences.minOf` — fun Sequence.minOf(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOf(kotlin/Function1<#A, kotlin/Float>): kotlin/Float`
    - `kotlin.sequences.minOfOrNull` — fun Sequence.minOfOrNull(Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Comparable<#B>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOfOrNull(kotlin/Function1<#A, #B>): #B?`
    - `kotlin.sequences.minOfOrNull` — fun Sequence.minOfOrNull(Function1): Double  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOfOrNull(kotlin/Function1<#A, kotlin/Double>): kotlin/Double?`
    - `kotlin.sequences.minOfOrNull` — fun Sequence.minOfOrNull(Function1): Float  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOfOrNull(kotlin/Function1<#A, kotlin/Float>): kotlin/Float?`
    - `kotlin.sequences.minOfWith` — fun Sequence.minOfWith(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOfWith(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B`
    - `kotlin.sequences.minOfWithOrNull` — fun Sequence.minOfWithOrNull(Comparator, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOfWithOrNull(kotlin/Comparator<in #B>, kotlin/Function1<#A, #B>): #B?`
    - `kotlin.sequences.minOrNull` — fun Sequence.minOrNull(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/minOrNull(): kotlin/Double?`
    - `kotlin.sequences.minOrNull` — fun Sequence.minOrNull(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/minOrNull(): kotlin/Float?`
    - `kotlin.sequences.minOrNull` — fun Sequence.minOrNull(): #A  -- `final fun <#A: kotlin/Comparable<#A>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minOrNull(): #A?`
    - `kotlin.sequences.minWith` — fun Sequence.minWith(Comparator): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minWith(kotlin/Comparator<in #A>): #A`
    - `kotlin.sequences.minWithOrNull` — fun Sequence.minWithOrNull(Comparator): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/minWithOrNull(kotlin/Comparator<in #A>): #A?`

- [ ] KSP-1355: kotlin.sequences.Sequence.reduce-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `reduce`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_reduce.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_reduce.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_reduce.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.reduce` — fun Sequence.reduce(Function2): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.sequences/Sequence<#B>).kotlin.sequences/reduce(kotlin/Function2<#A, #B, #A>): #A`
    - `kotlin.sequences.reduceIndexed` — fun Sequence.reduceIndexed(Function3): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.sequences/Sequence<#B>).kotlin.sequences/reduceIndexed(kotlin/Function3<kotlin/Int, #A, #B, #A>): #A`
    - `kotlin.sequences.reduceIndexedOrNull` — fun Sequence.reduceIndexedOrNull(Function3): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.sequences/Sequence<#B>).kotlin.sequences/reduceIndexedOrNull(kotlin/Function3<kotlin/Int, #A, #B, #A>): #A?`
    - `kotlin.sequences.reduceOrNull` — fun Sequence.reduceOrNull(Function2): #A  -- `final inline fun <#A: kotlin/Any?, #B: #A> (kotlin.sequences/Sequence<#B>).kotlin.sequences/reduceOrNull(kotlin/Function2<#A, #B, #A>): #A?`

- [ ] KSP-1356: kotlin.sequences.Sequence.shuffled-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `shuffled`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_shuffled.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_shuffled.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_shuffled.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.shuffled` — fun Sequence.shuffled(): Sequence  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/shuffled(): kotlin.sequences/Sequence<#A>`
    - `kotlin.sequences.shuffled` — fun Sequence.shuffled(Random): Sequence  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/shuffled(kotlin.random/Random): kotlin.sequences/Sequence<#A>`

- [ ] KSP-1357: kotlin.sequences.Sequence.single-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `single`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_single.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_single.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_single.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.single` — fun Sequence.single(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/single(): #A`
    - `kotlin.sequences.single` — fun Sequence.single(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/single(kotlin/Function1<#A, kotlin/Boolean>): #A`
    - `kotlin.sequences.singleOrNull` — fun Sequence.singleOrNull(): #A  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/singleOrNull(): #A?`
    - `kotlin.sequences.singleOrNull` — fun Sequence.singleOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/singleOrNull(kotlin/Function1<#A, kotlin/Boolean>): #A?`

- [ ] KSP-1359: kotlin.sequences.Sequence.sum-family の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `sum`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_sum.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_sum.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_sum.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.sum` — fun Sequence.sum(): Double  -- `final fun (kotlin.sequences/Sequence<kotlin/Double>).kotlin.sequences/sum(): kotlin/Double`
    - `kotlin.sequences.sum` — fun Sequence.sum(): Float  -- `final fun (kotlin.sequences/Sequence<kotlin/Float>).kotlin.sequences/sum(): kotlin/Float`
    - `kotlin.sequences.sum` — fun Sequence.sum(): Long  -- `final fun (kotlin.sequences/Sequence<kotlin/Long>).kotlin.sequences/sum(): kotlin/Long`
    - `kotlin.sequences.sum` — fun Sequence.sum(): UInt  -- `final fun (kotlin.sequences/Sequence<kotlin/UByte>).kotlin.sequences/sum(): kotlin/UInt`
    - `kotlin.sequences.sum` — fun Sequence.sum(): UInt  -- `final fun (kotlin.sequences/Sequence<kotlin/UInt>).kotlin.sequences/sum(): kotlin/UInt`
    - `kotlin.sequences.sum` — fun Sequence.sum(): ULong  -- `final fun (kotlin.sequences/Sequence<kotlin/ULong>).kotlin.sequences/sum(): kotlin/ULong`
    - `kotlin.sequences.sum` — fun Sequence.sum(): UInt  -- `final fun (kotlin.sequences/Sequence<kotlin/UShort>).kotlin.sequences/sum(): kotlin/UInt`
    - `kotlin.sequences.sumOf` — fun Sequence.sumOf(Function1): Long  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/sumOf(kotlin/Function1<#A, kotlin/Long>): kotlin/Long`
    - `kotlin.sequences.sumOf` — fun Sequence.sumOf(Function1): UInt  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/sumOf(kotlin/Function1<#A, kotlin/UInt>): kotlin/UInt`
    - `kotlin.sequences.sumOf` — fun Sequence.sumOf(Function1): ULong  -- `final inline fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/sumOf(kotlin/Function1<#A, kotlin/ULong>): kotlin/ULong`

- [x] KSP-1360: kotlin.sequences.Sequence.to-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.sequences` / receiver `Sequence` / family `to`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceConversionsAndSetOps.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_Sequence_to.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_to.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_Sequence_to.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 実装シンボル一覧:
    - `kotlin.sequences.toCollection` — fun Sequence.toCollection(): #B  -- `final fun <#A: kotlin/Any?, #B: kotlin.collections/MutableCollection<in #A>> (kotlin.sequences/Sequence<#A>).kotlin.sequences/toCollection(#B): #B`
    - `kotlin.sequences.toHashSet` — fun Sequence.toHashSet(): HashSet  -- `final fun <#A: kotlin/Any?> (kotlin.sequences/Sequence<#A>).kotlin.sequences/toHashSet(): kotlin.collections/HashSet<#A>`
  - 完了根拠 (2026-09-04): `SequenceConversionsAndSetOps.kt` の両 API は KSP-443（PR #5747、commit `5722866682`）で Kotlin 実装が追加済み。`toCollection` は destination に要素を追加して同じ destination を返し、`toHashSet` は `toMutableSet` に委譲する。関連する PR #1334/#1341/#2481/#2482 で Sema・codegen・runtime の表面も検証済みであり、既存の `kk_sequence_*` は runtime bridge として保持する。現行 master で既存の回帰テスト、Kotlin 2.3.10 との diff、Runtime ABI リンク検証を再確認したため、この TODO では実装・bridge/stub の変更および専用の重複テスト追加は行わない。

- [ ] KSP-1361: kotlin.sequences.SequenceScope.SequenceScope の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.sequences.SequenceScope` / receiver `SequenceScope`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/sequences/SequenceScope/SequenceScope.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_sequences_SequenceScope_SequenceScope_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_sequences_SequenceScope_SequenceScope_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_sequences_SequenceScope_SequenceScope_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.sequences.SequenceScope.yield` — fun SequenceScope.yield(): Unit  -- `abstract suspend fun yield(#A)`
    - `kotlin.sequences.SequenceScope.yieldAll` — fun SequenceScope.yieldAll(Iterator): Unit  -- `abstract suspend fun yieldAll(kotlin.collections/Iterator<#A>)`
    - `kotlin.sequences.SequenceScope.yieldAll` — fun SequenceScope.yieldAll(Iterable): Unit  -- `final suspend fun yieldAll(kotlin.collections/Iterable<#A>)`
    - `kotlin.sequences.SequenceScope.yieldAll` — fun SequenceScope.yieldAll(Sequence): Unit  -- `final suspend fun yieldAll(kotlin.sequences/Sequence<#A>)`

- [ ] KSP-1362: kotlin.text top-level の未実装 stdlib API を実装する（20 件）
  - 対象: `kotlin.text` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Appendable` — interface kotlin.text.Appendable  -- `abstract interface kotlin.text/Appendable {`
    - `kotlin.text.CharCategory` — enumClass kotlin.text.CharCategory  -- `final enum class kotlin.text/CharCategory : kotlin/Enum<kotlin.text/CharCategory> {`
    - `kotlin.text.HexFormat` — fun HexFormat(Function1): HexFormat  -- `final inline fun kotlin.text/HexFormat(kotlin/Function1<kotlin.text/HexFormat.Builder, kotlin/Unit>): kotlin.text/HexFormat`
    - `kotlin.text.MatchGroupCollection` — interface kotlin.text.MatchGroupCollection  -- `abstract interface kotlin.text/MatchGroupCollection : kotlin.collections/Collection<kotlin.text/MatchGroup?> {`
    - `kotlin.text.MatchNamedGroupCollection` — interface kotlin.text.MatchNamedGroupCollection  -- `abstract interface kotlin.text/MatchNamedGroupCollection : kotlin.text/MatchGroupCollection {`
    - `kotlin.text.MatchResult` — interface kotlin.text.MatchResult  -- `abstract interface kotlin.text/MatchResult {`
    - `kotlin.text.String` — fun String(CharArray): String  -- `final fun kotlin.text/String(kotlin/CharArray): kotlin/String`
    - `kotlin.text.String` — fun String(CharArray, Int, Int): String  -- `final fun kotlin.text/String(kotlin/CharArray, kotlin/Int, kotlin/Int): kotlin/String`
    - `kotlin.text.Typography` — object kotlin.text.Typography  -- `final object kotlin.text/Typography {`
    - `kotlin.text.append` — fun append(Array): #A  -- `final fun <#A: kotlin.text/Appendable> (#A).kotlin.text/append(kotlin/Array<out kotlin/CharSequence?>...): #A`
    - `kotlin.text.appendRange` — fun appendRange(CharSequence, Int, Int): #A  -- `final fun <#A: kotlin.text/Appendable> (#A).kotlin.text/appendRange(kotlin/CharSequence, kotlin/Int, kotlin/Int): #A`
    - `kotlin.text.buildString` — fun buildString(Function1): String  -- `final inline fun kotlin.text/buildString(kotlin/Function1<kotlin.text/StringBuilder, kotlin/Unit>): kotlin/String`
    - `kotlin.text.buildString` — fun buildString(Int, Function1): String  -- `final inline fun kotlin.text/buildString(kotlin/Int, kotlin/Function1<kotlin.text/StringBuilder, kotlin/Unit>): kotlin/String`
    - `kotlin.text.checkRadix` — fun checkRadix(Int): Int  -- `final fun kotlin.text/checkRadix(kotlin/Int): kotlin/Int`
    - `kotlin.text.ifBlank` — fun ifBlank(Function0): #B  -- `final inline fun <#A: #B & kotlin/CharSequence, #B: kotlin/Any?> (#A).kotlin.text/ifBlank(kotlin/Function0<#B>): #B`
    - `kotlin.text.ifEmpty` — fun ifEmpty(Function0): #B  -- `final inline fun <#A: #B & kotlin/CharSequence, #B: kotlin/Any?> (#A).kotlin.text/ifEmpty(kotlin/Function0<#B>): #B`
    - `kotlin.text.intToString` — fun intToString(Int, Int): String  -- `final fun kotlin.text/intToString(kotlin/Int, kotlin/Int): kotlin/String`
    - `kotlin.text.longToString` — fun longToString(Long, Int): String  -- `final fun kotlin.text/longToString(kotlin/Long, kotlin/Int): kotlin/String`
    - `kotlin.text.onEach` — fun onEach(Function1): #A  -- `final inline fun <#A: kotlin/CharSequence> (#A).kotlin.text/onEach(kotlin/Function1<kotlin/Char, kotlin/Unit>): #A`
    - `kotlin.text.onEachIndexed` — fun onEachIndexed(Function2): #A  -- `final inline fun <#A: kotlin/CharSequence> (#A).kotlin.text/onEachIndexed(kotlin/Function2<kotlin/Int, kotlin/Char, kotlin/Unit>): #A`

- [ ] KSP-1365: kotlin.text.CharSequence.as-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `as`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_as.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_as.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_as.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.asIterable` — fun CharSequence.asIterable(): Iterable  -- `final fun (kotlin/CharSequence).kotlin.text/asIterable(): kotlin.collections/Iterable<kotlin/Char>`
    - `kotlin.text.asSequence` — fun CharSequence.asSequence(): Sequence  -- `final fun (kotlin/CharSequence).kotlin.text/asSequence(): kotlin.sequences/Sequence<kotlin/Char>`

- [ ] KSP-1366: kotlin.text.CharSequence.associate-family の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `associate`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_associate.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_associate.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_associate.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.associate` — fun CharSequence.associate(Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin/CharSequence).kotlin.text/associate(kotlin/Function1<kotlin/Char, kotlin/Pair<#A, #B>>): kotlin.collections/Map<#A, #B>`
    - `kotlin.text.associateBy` — fun CharSequence.associateBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/associateBy(kotlin/Function1<kotlin/Char, #A>): kotlin.collections/Map<#A, kotlin/Char>`
    - `kotlin.text.associateBy` — fun CharSequence.associateBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin/CharSequence).kotlin.text/associateBy(kotlin/Function1<kotlin/Char, #A>, kotlin/Function1<kotlin/Char, #B>): kotlin.collections/Map<#A, #B>`
    - `kotlin.text.associateByTo` — fun CharSequence.associateByTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableMap<in #A, in kotlin/Char>> (kotlin/CharSequence).kotlin.text/associateByTo(#B, kotlin/Function1<kotlin/Char, #A>): #B`
    - `kotlin.text.associateByTo` — fun CharSequence.associateByTo(, Function1, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, in #B>> (kotlin/CharSequence).kotlin.text/associateByTo(#C, kotlin/Function1<kotlin/Char, #A>, kotlin/Function1<kotlin/Char, #B>): #C`
    - `kotlin.text.associateTo` — fun CharSequence.associateTo(, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, in #B>> (kotlin/CharSequence).kotlin.text/associateTo(#C, kotlin/Function1<kotlin/Char, kotlin/Pair<#A, #B>>): #C`
    - `kotlin.text.associateWith` — fun CharSequence.associateWith(Function1): Map  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/associateWith(kotlin/Function1<kotlin/Char, #A>): kotlin.collections/Map<kotlin/Char, #A>`
    - `kotlin.text.associateWithTo` — fun CharSequence.associateWithTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableMap<in kotlin/Char, in #A>> (kotlin/CharSequence).kotlin.text/associateWithTo(#B, kotlin/Function1<kotlin/Char, #A>): #B`

- [ ] KSP-1367: kotlin.text.CharSequence.chunked-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `chunked`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringWindowChunkTransform.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_chunked.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_chunked.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_chunked.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.chunked` — fun CharSequence.chunked(Int, Function1): List  -- `final fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/chunked(kotlin/Int, kotlin/Function1<kotlin/CharSequence, #A>): kotlin.collections/List<#A>`

- [ ] KSP-1368: kotlin.text.CharSequence.common-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `common`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_common.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_common.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_common.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.commonPrefixWith` — fun CharSequence.commonPrefixWith(CharSequence, Boolean): String  -- `final fun (kotlin/CharSequence).kotlin.text/commonPrefixWith(kotlin/CharSequence, kotlin/Boolean = ...): kotlin/String`
    - `kotlin.text.commonSuffixWith` — fun CharSequence.commonSuffixWith(CharSequence, Boolean): String  -- `final fun (kotlin/CharSequence).kotlin.text/commonSuffixWith(kotlin/CharSequence, kotlin/Boolean = ...): kotlin/String`

- [ ] KSP-1369: kotlin.text.CharSequence.contains-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `contains`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringIndexOf.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_contains.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_contains.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_contains.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.contains` — fun CharSequence.contains(Regex): Boolean  -- `final inline fun (kotlin/CharSequence).kotlin.text/contains(kotlin.text/Regex): kotlin/Boolean`
    - `kotlin.text.contains` — fun CharSequence.contains(Char, Boolean): Boolean  -- `final fun (kotlin/CharSequence).kotlin.text/contains(kotlin/Char, kotlin/Boolean = ...): kotlin/Boolean`

- [ ] KSP-1370: kotlin.text.CharSequence.count-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `count`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_count.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_count.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_count.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.count` — fun CharSequence.count(): Int  -- `final inline fun (kotlin/CharSequence).kotlin.text/count(): kotlin/Int`

- [ ] KSP-1371: kotlin.text.CharSequence.drop-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `drop`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_drop.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_drop.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_drop.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.drop` — fun CharSequence.drop(Int): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/drop(kotlin/Int): kotlin/CharSequence`
    - `kotlin.text.dropLast` — fun CharSequence.dropLast(Int): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/dropLast(kotlin/Int): kotlin/CharSequence`
    - `kotlin.text.dropLastWhile` — fun CharSequence.dropLastWhile(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/dropLastWhile(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`
    - `kotlin.text.dropWhile` — fun CharSequence.dropWhile(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/dropWhile(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`

- [ ] KSP-1372: kotlin.text.CharSequence.element-family の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `element`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_element.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_element.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_element.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.elementAt` — fun CharSequence.elementAt(Int): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/elementAt(kotlin/Int): kotlin/Char`
    - `kotlin.text.elementAtOrElse` — fun CharSequence.elementAtOrElse(Int, Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/elementAtOrElse(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Char>): kotlin/Char`
    - `kotlin.text.elementAtOrNull` — fun CharSequence.elementAtOrNull(Int): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/elementAtOrNull(kotlin/Int): kotlin/Char?`

- [ ] KSP-1374: kotlin.text.CharSequence.first-family の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `first`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_first.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_first.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_first.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.first` — fun CharSequence.first(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/first(): kotlin/Char`
    - `kotlin.text.first` — fun CharSequence.first(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/first(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char`
    - `kotlin.text.firstNotNullOf` — fun CharSequence.firstNotNullOf(Function1): #A  -- `final inline fun <#A: kotlin/Any> (kotlin/CharSequence).kotlin.text/firstNotNullOf(kotlin/Function1<kotlin/Char, #A?>): #A`
    - `kotlin.text.firstNotNullOfOrNull` — fun CharSequence.firstNotNullOfOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Any> (kotlin/CharSequence).kotlin.text/firstNotNullOfOrNull(kotlin/Function1<kotlin/Char, #A?>): #A?`
    - `kotlin.text.firstOrNull` — fun CharSequence.firstOrNull(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/firstOrNull(): kotlin/Char?`
    - `kotlin.text.firstOrNull` — fun CharSequence.firstOrNull(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/firstOrNull(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char?`

- [ ] KSP-1375: kotlin.text.CharSequence.flat-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `flat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_flat.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_flat.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_flat.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.flatMap` — fun CharSequence.flatMap(Function1): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/flatMap(kotlin/Function1<kotlin/Char, kotlin.collections/Iterable<#A>>): kotlin.collections/List<#A>`
    - `kotlin.text.flatMapIndexed` — fun CharSequence.flatMapIndexed(Function2): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/flatMapIndexed(kotlin/Function2<kotlin/Int, kotlin/Char, kotlin.collections/Iterable<#A>>): kotlin.collections/List<#A>`
    - `kotlin.text.flatMapIndexedTo` — fun CharSequence.flatMapIndexedTo(, Function2): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/flatMapIndexedTo(#B, kotlin/Function2<kotlin/Int, kotlin/Char, kotlin.collections/Iterable<#A>>): #B`
    - `kotlin.text.flatMapTo` — fun CharSequence.flatMapTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/flatMapTo(#B, kotlin/Function1<kotlin/Char, kotlin.collections/Iterable<#A>>): #B`

- [ ] KSP-1376: kotlin.text.CharSequence.fold-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `fold`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_fold.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_fold.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_fold.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.fold` — fun CharSequence.fold(, Function2): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/fold(#A, kotlin/Function2<#A, kotlin/Char, #A>): #A`
    - `kotlin.text.foldIndexed` — fun CharSequence.foldIndexed(, Function3): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/foldIndexed(#A, kotlin/Function3<kotlin/Int, #A, kotlin/Char, #A>): #A`
    - `kotlin.text.foldRight` — fun CharSequence.foldRight(, Function2): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/foldRight(#A, kotlin/Function2<kotlin/Char, #A, #A>): #A`
    - `kotlin.text.foldRightIndexed` — fun CharSequence.foldRightIndexed(, Function3): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/foldRightIndexed(#A, kotlin/Function3<kotlin/Int, kotlin/Char, #A, #A>): #A`

- [ ] KSP-1377: kotlin.text.CharSequence.for-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `for`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_for.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_for.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_for.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.forEach` — fun CharSequence.forEach(Function1): Unit  -- `final inline fun (kotlin/CharSequence).kotlin.text/forEach(kotlin/Function1<kotlin/Char, kotlin/Unit>)`
    - `kotlin.text.forEachIndexed` — fun CharSequence.forEachIndexed(Function2): Unit  -- `final inline fun (kotlin/CharSequence).kotlin.text/forEachIndexed(kotlin/Function2<kotlin/Int, kotlin/Char, kotlin/Unit>)`

- [ ] KSP-1378: kotlin.text.CharSequence.get-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `get`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_get.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_get.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_get.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.getOrElse` — fun CharSequence.getOrElse(Int, Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/getOrElse(kotlin/Int, kotlin/Function1<kotlin/Int, kotlin/Char>): kotlin/Char`
    - `kotlin.text.getOrNull` — fun CharSequence.getOrNull(Int): Char  -- `final fun (kotlin/CharSequence).kotlin.text/getOrNull(kotlin/Int): kotlin/Char?`

- [ ] KSP-1379: kotlin.text.CharSequence.group-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `group`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_group.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_group.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_group.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.groupBy` — fun CharSequence.groupBy(Function1): Map  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/groupBy(kotlin/Function1<kotlin/Char, #A>): kotlin.collections/Map<#A, kotlin.collections/List<kotlin/Char>>`
    - `kotlin.text.groupBy` — fun CharSequence.groupBy(Function1, Function1): Map  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?> (kotlin/CharSequence).kotlin.text/groupBy(kotlin/Function1<kotlin/Char, #A>, kotlin/Function1<kotlin/Char, #B>): kotlin.collections/Map<#A, kotlin.collections/List<#B>>`
    - `kotlin.text.groupByTo` — fun CharSequence.groupByTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableMap<in #A, kotlin.collections/MutableList<kotlin/Char>>> (kotlin/CharSequence).kotlin.text/groupByTo(#B, kotlin/Function1<kotlin/Char, #A>): #B`
    - `kotlin.text.groupByTo` — fun CharSequence.groupByTo(, Function1, Function1): #C  -- `final inline fun <#A: kotlin/Any?, #B: kotlin/Any?, #C: kotlin.collections/MutableMap<in #A, kotlin.collections/MutableList<#B>>> (kotlin/CharSequence).kotlin.text/groupByTo(#C, kotlin/Function1<kotlin/Char, #A>, kotlin/Function1<kotlin/Char, #B>): #C`

- [ ] KSP-1380: kotlin.text.CharSequence.grouping-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `grouping`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_grouping.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_grouping.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_grouping.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.groupingBy` — fun CharSequence.groupingBy(Function1): Grouping  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/groupingBy(crossinline kotlin/Function1<kotlin/Char, #A>): kotlin.collections/Grouping<kotlin/Char, #A>`

- [ ] KSP-1381: kotlin.text.CharSequence.has-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `has`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_has.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_has.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_has.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.hasSurrogatePairAt` — fun CharSequence.hasSurrogatePairAt(Int): Boolean  -- `final fun (kotlin/CharSequence).kotlin.text/hasSurrogatePairAt(kotlin/Int): kotlin/Boolean`

- [ ] KSP-1382: kotlin.text.CharSequence.indices-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `indices`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_indices.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_indices.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_indices.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.indices` — val CharSequence.indices  -- `final val kotlin.text/indices`

- [ ] KSP-1383: kotlin.text.CharSequence.iterator-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `iterator`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_iterator.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_iterator.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_iterator.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.iterator` — fun CharSequence.iterator(): CharIterator  -- `final fun (kotlin/CharSequence).kotlin.text/iterator(): kotlin.collections/CharIterator`

- [ ] KSP-1384: kotlin.text.CharSequence.last-family の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `last`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringIndexOf.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_last.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_last.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_last.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.last` — fun CharSequence.last(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/last(): kotlin/Char`
    - `kotlin.text.last` — fun CharSequence.last(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/last(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char`
    - `kotlin.text.lastIndex` — val CharSequence.lastIndex  -- `final val kotlin.text/lastIndex`
    - `kotlin.text.lastOrNull` — fun CharSequence.lastOrNull(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/lastOrNull(): kotlin/Char?`
    - `kotlin.text.lastOrNull` — fun CharSequence.lastOrNull(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/lastOrNull(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char?`

- [ ] KSP-1385: kotlin.text.CharSequence.map-family の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `map`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_map.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_map.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_map.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.mapIndexedNotNull` — fun CharSequence.mapIndexedNotNull(Function2): List  -- `final inline fun <#A: kotlin/Any> (kotlin/CharSequence).kotlin.text/mapIndexedNotNull(kotlin/Function2<kotlin/Int, kotlin/Char, #A?>): kotlin.collections/List<#A>`
    - `kotlin.text.mapIndexedNotNullTo` — fun CharSequence.mapIndexedNotNullTo(, Function2): #B  -- `final inline fun <#A: kotlin/Any, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/mapIndexedNotNullTo(#B, kotlin/Function2<kotlin/Int, kotlin/Char, #A?>): #B`
    - `kotlin.text.mapIndexedTo` — fun CharSequence.mapIndexedTo(, Function2): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/mapIndexedTo(#B, kotlin/Function2<kotlin/Int, kotlin/Char, #A>): #B`
    - `kotlin.text.mapNotNullTo` — fun CharSequence.mapNotNullTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/mapNotNullTo(#B, kotlin/Function1<kotlin/Char, #A?>): #B`
    - `kotlin.text.mapTo` — fun CharSequence.mapTo(, Function1): #B  -- `final inline fun <#A: kotlin/Any?, #B: kotlin.collections/MutableCollection<in #A>> (kotlin/CharSequence).kotlin.text/mapTo(#B, kotlin/Function1<kotlin/Char, #A>): #B`

- [ ] KSP-1386: kotlin.text.CharSequence.matches-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `matches`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_matches.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_matches.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_matches.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.matches` — fun CharSequence.matches(Regex): Boolean  -- `final inline fun (kotlin/CharSequence).kotlin.text/matches(kotlin.text/Regex): kotlin/Boolean`

- [ ] KSP-1387: kotlin.text.CharSequence.max-family の未実装 stdlib API を実装する（14 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `max`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_max.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_max.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_max.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.max` — fun CharSequence.max(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/max(): kotlin/Char`
    - `kotlin.text.maxBy` — fun CharSequence.maxBy(Function1): Char  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/maxBy(kotlin/Function1<kotlin/Char, #A>): kotlin/Char`
    - `kotlin.text.maxByOrNull` — fun CharSequence.maxByOrNull(Function1): Char  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/maxByOrNull(kotlin/Function1<kotlin/Char, #A>): kotlin/Char?`
    - `kotlin.text.maxOf` — fun CharSequence.maxOf(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/maxOf(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double`
    - `kotlin.text.maxOf` — fun CharSequence.maxOf(Function1): Float  -- `final inline fun (kotlin/CharSequence).kotlin.text/maxOf(kotlin/Function1<kotlin/Char, kotlin/Float>): kotlin/Float`
    - `kotlin.text.maxOf` — fun CharSequence.maxOf(Function1): #A  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/maxOf(kotlin/Function1<kotlin/Char, #A>): #A`
    - `kotlin.text.maxOfOrNull` — fun CharSequence.maxOfOrNull(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/maxOfOrNull(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double?`
    - `kotlin.text.maxOfOrNull` — fun CharSequence.maxOfOrNull(Function1): Float  -- `final inline fun (kotlin/CharSequence).kotlin.text/maxOfOrNull(kotlin/Function1<kotlin/Char, kotlin/Float>): kotlin/Float?`
    - `kotlin.text.maxOfOrNull` — fun CharSequence.maxOfOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/maxOfOrNull(kotlin/Function1<kotlin/Char, #A>): #A?`
    - `kotlin.text.maxOfWith` — fun CharSequence.maxOfWith(Comparator, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/maxOfWith(kotlin/Comparator<in #A>, kotlin/Function1<kotlin/Char, #A>): #A`
    - `kotlin.text.maxOfWithOrNull` — fun CharSequence.maxOfWithOrNull(Comparator, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/maxOfWithOrNull(kotlin/Comparator<in #A>, kotlin/Function1<kotlin/Char, #A>): #A?`
    - `kotlin.text.maxOrNull` — fun CharSequence.maxOrNull(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/maxOrNull(): kotlin/Char?`
    - `kotlin.text.maxWith` — fun CharSequence.maxWith(Comparator): Char  -- `final fun (kotlin/CharSequence).kotlin.text/maxWith(kotlin/Comparator<in kotlin/Char>): kotlin/Char`
    - `kotlin.text.maxWithOrNull` — fun CharSequence.maxWithOrNull(Comparator): Char  -- `final fun (kotlin/CharSequence).kotlin.text/maxWithOrNull(kotlin/Comparator<in kotlin/Char>): kotlin/Char?`

- [ ] KSP-1388: kotlin.text.CharSequence.min-family の未実装 stdlib API を実装する（14 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `min`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_min.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_min.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_min.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.min` — fun CharSequence.min(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/min(): kotlin/Char`
    - `kotlin.text.minBy` — fun CharSequence.minBy(Function1): Char  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/minBy(kotlin/Function1<kotlin/Char, #A>): kotlin/Char`
    - `kotlin.text.minByOrNull` — fun CharSequence.minByOrNull(Function1): Char  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/minByOrNull(kotlin/Function1<kotlin/Char, #A>): kotlin/Char?`
    - `kotlin.text.minOf` — fun CharSequence.minOf(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/minOf(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double`
    - `kotlin.text.minOf` — fun CharSequence.minOf(Function1): Float  -- `final inline fun (kotlin/CharSequence).kotlin.text/minOf(kotlin/Function1<kotlin/Char, kotlin/Float>): kotlin/Float`
    - `kotlin.text.minOf` — fun CharSequence.minOf(Function1): #A  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/minOf(kotlin/Function1<kotlin/Char, #A>): #A`
    - `kotlin.text.minOfOrNull` — fun CharSequence.minOfOrNull(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/minOfOrNull(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double?`
    - `kotlin.text.minOfOrNull` — fun CharSequence.minOfOrNull(Function1): Float  -- `final inline fun (kotlin/CharSequence).kotlin.text/minOfOrNull(kotlin/Function1<kotlin/Char, kotlin/Float>): kotlin/Float?`
    - `kotlin.text.minOfOrNull` — fun CharSequence.minOfOrNull(Function1): #A  -- `final inline fun <#A: kotlin/Comparable<#A>> (kotlin/CharSequence).kotlin.text/minOfOrNull(kotlin/Function1<kotlin/Char, #A>): #A?`
    - `kotlin.text.minOfWith` — fun CharSequence.minOfWith(Comparator, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/minOfWith(kotlin/Comparator<in #A>, kotlin/Function1<kotlin/Char, #A>): #A`
    - `kotlin.text.minOfWithOrNull` — fun CharSequence.minOfWithOrNull(Comparator, Function1): #A  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/minOfWithOrNull(kotlin/Comparator<in #A>, kotlin/Function1<kotlin/Char, #A>): #A?`
    - `kotlin.text.minOrNull` — fun CharSequence.minOrNull(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/minOrNull(): kotlin/Char?`
    - `kotlin.text.minWith` — fun CharSequence.minWith(Comparator): Char  -- `final fun (kotlin/CharSequence).kotlin.text/minWith(kotlin/Comparator<in kotlin/Char>): kotlin/Char`
    - `kotlin.text.minWithOrNull` — fun CharSequence.minWithOrNull(Comparator): Char  -- `final fun (kotlin/CharSequence).kotlin.text/minWithOrNull(kotlin/Comparator<in kotlin/Char>): kotlin/Char?`

- [ ] KSP-1389: kotlin.text.CharSequence.none-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `none`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_none.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_none.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_none.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.none` — fun CharSequence.none(): Boolean  -- `final fun (kotlin/CharSequence).kotlin.text/none(): kotlin/Boolean`

- [ ] KSP-1390: kotlin.text.CharSequence.pad-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `pad`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_pad.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_pad.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_pad.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.padEnd` — fun CharSequence.padEnd(Int, Char): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/padEnd(kotlin/Int, kotlin/Char = ...): kotlin/CharSequence`
    - `kotlin.text.padStart` — fun CharSequence.padStart(Int, Char): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/padStart(kotlin/Int, kotlin/Char = ...): kotlin/CharSequence`

- [ ] KSP-1391: kotlin.text.CharSequence.random-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `random`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_random.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_random.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_random.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.random` — fun CharSequence.random(): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/random(): kotlin/Char`
    - `kotlin.text.random` — fun CharSequence.random(Random): Char  -- `final fun (kotlin/CharSequence).kotlin.text/random(kotlin.random/Random): kotlin/Char`
    - `kotlin.text.randomOrNull` — fun CharSequence.randomOrNull(): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/randomOrNull(): kotlin/Char?`
    - `kotlin.text.randomOrNull` — fun CharSequence.randomOrNull(Random): Char  -- `final fun (kotlin/CharSequence).kotlin.text/randomOrNull(kotlin.random/Random): kotlin/Char?`

- [ ] KSP-1392: kotlin.text.CharSequence.region-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `region`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_region.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_region.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_region.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.regionMatches` — fun CharSequence.regionMatches(Int, CharSequence, Int, Int, Boolean): Boolean  -- `final fun (kotlin/CharSequence).kotlin.text/regionMatches(kotlin/Int, kotlin/CharSequence, kotlin/Int, kotlin/Int, kotlin/Boolean = ...): kotlin/Boolean`

- [ ] KSP-1393: kotlin.text.CharSequence.remove-family の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `remove`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringPrefixSuffix.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_remove.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_remove.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_remove.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.removePrefix` — fun CharSequence.removePrefix(CharSequence): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/removePrefix(kotlin/CharSequence): kotlin/CharSequence`
    - `kotlin.text.removeRange` — fun CharSequence.removeRange(IntRange): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/removeRange(kotlin.ranges/IntRange): kotlin/CharSequence`
    - `kotlin.text.removeRange` — fun CharSequence.removeRange(Int, Int): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/removeRange(kotlin/Int, kotlin/Int): kotlin/CharSequence`
    - `kotlin.text.removeSuffix` — fun CharSequence.removeSuffix(CharSequence): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/removeSuffix(kotlin/CharSequence): kotlin/CharSequence`
    - `kotlin.text.removeSurrounding` — fun CharSequence.removeSurrounding(CharSequence): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/removeSurrounding(kotlin/CharSequence): kotlin/CharSequence`
    - `kotlin.text.removeSurrounding` — fun CharSequence.removeSurrounding(CharSequence, CharSequence): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/removeSurrounding(kotlin/CharSequence, kotlin/CharSequence): kotlin/CharSequence`

- [ ] KSP-1394: kotlin.text.CharSequence.repeat-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `repeat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_repeat.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_repeat.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_repeat.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.repeat` — fun CharSequence.repeat(Int): String  -- `final fun (kotlin/CharSequence).kotlin.text/repeat(kotlin/Int): kotlin/String`

- [ ] KSP-1395: kotlin.text.CharSequence.replace-family の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `replace`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_replace.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_replace.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_replace.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.replace` — fun CharSequence.replace(Regex, String): String  -- `final inline fun (kotlin/CharSequence).kotlin.text/replace(kotlin.text/Regex, kotlin/String): kotlin/String`
    - `kotlin.text.replace` — fun CharSequence.replace(Regex, Function1): String  -- `final inline fun (kotlin/CharSequence).kotlin.text/replace(kotlin.text/Regex, noinline kotlin/Function1<kotlin.text/MatchResult, kotlin/CharSequence>): kotlin/String`
    - `kotlin.text.replaceFirst` — fun CharSequence.replaceFirst(Regex, String): String  -- `final inline fun (kotlin/CharSequence).kotlin.text/replaceFirst(kotlin.text/Regex, kotlin/String): kotlin/String`
    - `kotlin.text.replaceRange` — fun CharSequence.replaceRange(IntRange, CharSequence): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/replaceRange(kotlin.ranges/IntRange, kotlin/CharSequence): kotlin/CharSequence`
    - `kotlin.text.replaceRange` — fun CharSequence.replaceRange(Int, Int, CharSequence): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/replaceRange(kotlin/Int, kotlin/Int, kotlin/CharSequence): kotlin/CharSequence`

- [ ] KSP-1396: kotlin.text.CharSequence.reversed-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `reversed`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_reversed.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_reversed.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_reversed.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.reversed` — fun CharSequence.reversed(): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/reversed(): kotlin/CharSequence`

- [ ] KSP-1397: kotlin.text.CharSequence.running-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `running`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_running.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_running.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_running.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.runningFold` — fun CharSequence.runningFold(, Function2): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/runningFold(#A, kotlin/Function2<#A, kotlin/Char, #A>): kotlin.collections/List<#A>`
    - `kotlin.text.runningFoldIndexed` — fun CharSequence.runningFoldIndexed(, Function3): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/runningFoldIndexed(#A, kotlin/Function3<kotlin/Int, #A, kotlin/Char, #A>): kotlin.collections/List<#A>`
    - `kotlin.text.runningReduce` — fun CharSequence.runningReduce(Function2): List  -- `final inline fun (kotlin/CharSequence).kotlin.text/runningReduce(kotlin/Function2<kotlin/Char, kotlin/Char, kotlin/Char>): kotlin.collections/List<kotlin/Char>`
    - `kotlin.text.runningReduceIndexed` — fun CharSequence.runningReduceIndexed(Function3): List  -- `final inline fun (kotlin/CharSequence).kotlin.text/runningReduceIndexed(kotlin/Function3<kotlin/Int, kotlin/Char, kotlin/Char, kotlin/Char>): kotlin.collections/List<kotlin/Char>`

- [ ] KSP-1398: kotlin.text.CharSequence.scan-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `scan`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_scan.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_scan.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_scan.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.scan` — fun CharSequence.scan(, Function2): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/scan(#A, kotlin/Function2<#A, kotlin/Char, #A>): kotlin.collections/List<#A>`
    - `kotlin.text.scanIndexed` — fun CharSequence.scanIndexed(, Function3): List  -- `final inline fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/scanIndexed(#A, kotlin/Function3<kotlin/Int, #A, kotlin/Char, #A>): kotlin.collections/List<#A>`

- [ ] KSP-1399: kotlin.text.CharSequence.single-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `single`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_single.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_single.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_single.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.single` — fun CharSequence.single(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/single(): kotlin/Char`
    - `kotlin.text.single` — fun CharSequence.single(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/single(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char`
    - `kotlin.text.singleOrNull` — fun CharSequence.singleOrNull(): Char  -- `final fun (kotlin/CharSequence).kotlin.text/singleOrNull(): kotlin/Char?`
    - `kotlin.text.singleOrNull` — fun CharSequence.singleOrNull(Function1): Char  -- `final inline fun (kotlin/CharSequence).kotlin.text/singleOrNull(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/Char?`

- [ ] KSP-1400: kotlin.text.CharSequence.slice-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `slice`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_slice.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_slice.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_slice.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.slice` — fun CharSequence.slice(Iterable): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/slice(kotlin.collections/Iterable<kotlin/Int>): kotlin/CharSequence`
    - `kotlin.text.slice` — fun CharSequence.slice(IntRange): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/slice(kotlin.ranges/IntRange): kotlin/CharSequence`

- [ ] KSP-1401: kotlin.text.CharSequence.split-family の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `split`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_split.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_split.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_split.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.split` — fun CharSequence.split(Regex, Int): List  -- `final inline fun (kotlin/CharSequence).kotlin.text/split(kotlin.text/Regex, kotlin/Int = ...): kotlin.collections/List<kotlin/String>`
    - `kotlin.text.split` — fun CharSequence.split(Array, Boolean, Int): List  -- `final fun (kotlin/CharSequence).kotlin.text/split(kotlin/Array<out kotlin/String>..., kotlin/Boolean = ..., kotlin/Int = ...): kotlin.collections/List<kotlin/String>`
    - `kotlin.text.split` — fun CharSequence.split(Array, Boolean, Int): List  -- `final fun (kotlin/CharSequence).kotlin.text/split(kotlin/CharArray..., kotlin/Boolean = ..., kotlin/Int = ...): kotlin.collections/List<kotlin/String>`
    - `kotlin.text.splitToSequence` — fun CharSequence.splitToSequence(Regex, Int): Sequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/splitToSequence(kotlin.text/Regex, kotlin/Int = ...): kotlin.sequences/Sequence<kotlin/String>`
    - `kotlin.text.splitToSequence` — fun CharSequence.splitToSequence(Array, Boolean, Int): Sequence  -- `final fun (kotlin/CharSequence).kotlin.text/splitToSequence(kotlin/Array<out kotlin/String>..., kotlin/Boolean = ..., kotlin/Int = ...): kotlin.sequences/Sequence<kotlin/String>`
    - `kotlin.text.splitToSequence` — fun CharSequence.splitToSequence(Array, Boolean, Int): Sequence  -- `final fun (kotlin/CharSequence).kotlin.text/splitToSequence(kotlin/CharArray..., kotlin/Boolean = ..., kotlin/Int = ...): kotlin.sequences/Sequence<kotlin/String>`

- [ ] KSP-1402: kotlin.text.CharSequence.sub-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `sub`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringSubstringSlice.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_sub.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_sub.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_sub.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.subSequence` — fun CharSequence.subSequence(IntRange): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/subSequence(kotlin.ranges/IntRange): kotlin/CharSequence`

- [ ] KSP-1403: kotlin.text.CharSequence.substring-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `substring`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_substring.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_substring.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_substring.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.substring` — fun CharSequence.substring(IntRange): String  -- `final fun (kotlin/CharSequence).kotlin.text/substring(kotlin.ranges/IntRange): kotlin/String`
    - `kotlin.text.substring` — fun CharSequence.substring(Int, Int): String  -- `final inline fun (kotlin/CharSequence).kotlin.text/substring(kotlin/Int, kotlin/Int = ...): kotlin/String`

- [ ] KSP-1404: kotlin.text.CharSequence.sum-family の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `sum`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_sum.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_sum.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_sum.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): Double  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/Double>): kotlin/Double`
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): Int  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/Int>): kotlin/Int`
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): Long  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/Long>): kotlin/Long`
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): UInt  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/UInt>): kotlin/UInt`
    - `kotlin.text.sumOf` — fun CharSequence.sumOf(Function1): ULong  -- `final inline fun (kotlin/CharSequence).kotlin.text/sumOf(kotlin/Function1<kotlin/Char, kotlin/ULong>): kotlin/ULong`

- [ ] KSP-1405: kotlin.text.CharSequence.take-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `take`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_take.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_take.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_take.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.take` — fun CharSequence.take(Int): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/take(kotlin/Int): kotlin/CharSequence`
    - `kotlin.text.takeLast` — fun CharSequence.takeLast(Int): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/takeLast(kotlin/Int): kotlin/CharSequence`
    - `kotlin.text.takeLastWhile` — fun CharSequence.takeLastWhile(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/takeLastWhile(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`
    - `kotlin.text.takeWhile` — fun CharSequence.takeWhile(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/takeWhile(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`

- [ ] KSP-1406: kotlin.text.CharSequence.to-family の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `to`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_to.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_to.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_to.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.toCollection` — fun CharSequence.toCollection(): #A  -- `final fun <#A: kotlin.collections/MutableCollection<in kotlin/Char>> (kotlin/CharSequence).kotlin.text/toCollection(#A): #A`
    - `kotlin.text.toHashSet` — fun CharSequence.toHashSet(): HashSet  -- `final fun (kotlin/CharSequence).kotlin.text/toHashSet(): kotlin.collections/HashSet<kotlin/Char>`
    - `kotlin.text.toList` — fun CharSequence.toList(): List  -- `final fun (kotlin/CharSequence).kotlin.text/toList(): kotlin.collections/List<kotlin/Char>`
    - `kotlin.text.toMutableList` — fun CharSequence.toMutableList(): MutableList  -- `final fun (kotlin/CharSequence).kotlin.text/toMutableList(): kotlin.collections/MutableList<kotlin/Char>`
    - `kotlin.text.toSet` — fun CharSequence.toSet(): Set  -- `final fun (kotlin/CharSequence).kotlin.text/toSet(): kotlin.collections/Set<kotlin/Char>`

- [ ] KSP-1407: kotlin.text.CharSequence.trim-family の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `trim`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_trim.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_trim.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_trim.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.trim` — fun CharSequence.trim(): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trim(): kotlin/CharSequence`
    - `kotlin.text.trim` — fun CharSequence.trim(Array): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trim(kotlin/CharArray...): kotlin/CharSequence`
    - `kotlin.text.trim` — fun CharSequence.trim(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/trim(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`
    - `kotlin.text.trimEnd` — fun CharSequence.trimEnd(): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trimEnd(): kotlin/CharSequence`
    - `kotlin.text.trimEnd` — fun CharSequence.trimEnd(Array): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trimEnd(kotlin/CharArray...): kotlin/CharSequence`
    - `kotlin.text.trimEnd` — fun CharSequence.trimEnd(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/trimEnd(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`
    - `kotlin.text.trimStart` — fun CharSequence.trimStart(): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trimStart(): kotlin/CharSequence`
    - `kotlin.text.trimStart` — fun CharSequence.trimStart(Array): CharSequence  -- `final fun (kotlin/CharSequence).kotlin.text/trimStart(kotlin/CharArray...): kotlin/CharSequence`
    - `kotlin.text.trimStart` — fun CharSequence.trimStart(Function1): CharSequence  -- `final inline fun (kotlin/CharSequence).kotlin.text/trimStart(kotlin/Function1<kotlin/Char, kotlin/Boolean>): kotlin/CharSequence`

- [ ] KSP-1408: kotlin.text.CharSequence.windowed-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `windowed`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringWindowChunkTransform.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_windowed.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_windowed.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_windowed.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.windowed` — fun CharSequence.windowed(Int, Int, Boolean, Function1): List  -- `final fun <#A: kotlin/Any?> (kotlin/CharSequence).kotlin.text/windowed(kotlin/Int, kotlin/Int = ..., kotlin/Boolean = ..., kotlin/Function1<kotlin/CharSequence, #A>): kotlin.collections/List<#A>`

- [ ] KSP-1409: kotlin.text.CharSequence.with-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `CharSequence` / family `with`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringHOF.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_CharSequence_with.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_CharSequence_with.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_CharSequence_with.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.withIndex` — fun CharSequence.withIndex(): Iterable  -- `final fun (kotlin/CharSequence).kotlin.text/withIndex(): kotlin.collections/Iterable<kotlin.collections/IndexedValue<kotlin/Char>>`

- [ ] KSP-1410: kotlin.text.Companion の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/CharSurrogate.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.CASE_INSENSITIVE_ORDER` — val Companion.CASE_INSENSITIVE_ORDER  -- `final val kotlin.text/CASE_INSENSITIVE_ORDER`

- [ ] KSP-1411: kotlin.text.StringBuilder.append-family の未実装 stdlib API を実装する（16 件）
  - 対象: `kotlin.text` / receiver `StringBuilder` / family `append`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_append.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_append.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_append.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.append` — fun StringBuilder.append(Any): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/append(kotlin/Any?): kotlin.text/StringBuilder`
    - `kotlin.text.append` — fun StringBuilder.append(Byte): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/append(kotlin/Byte): kotlin.text/StringBuilder`
    - `kotlin.text.append` — fun StringBuilder.append(Short): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/append(kotlin/Short): kotlin.text/StringBuilder`
    - `kotlin.text.append` — fun StringBuilder.append(CharArray, Int, Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/append(kotlin/CharArray, kotlin/Int, kotlin/Int): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Boolean): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Boolean): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Byte): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Byte): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Char): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Char): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(CharArray): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/CharArray): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(CharSequence): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/CharSequence?): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Double): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Double): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Float): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Float): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Int): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Long): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Long): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(Short): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/Short): kotlin.text/StringBuilder`
    - `kotlin.text.appendLine` — fun StringBuilder.appendLine(String): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendLine(kotlin/String?): kotlin.text/StringBuilder`
    - `kotlin.text.appendRange` — fun StringBuilder.appendRange(CharArray, Int, Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/appendRange(kotlin/CharArray, kotlin/Int, kotlin/Int): kotlin.text/StringBuilder`

- [ ] KSP-1412: kotlin.text.StringBuilder.appendln-family の未実装 stdlib API を実装する（10 件）
  - 対象: `kotlin.text` / receiver `StringBuilder` / family `appendln`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_appendln.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_appendln.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_appendln.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.appendln` — fun StringBuilder.appendln(): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Any): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Any?): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Boolean): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Boolean): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Byte): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Byte): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Double): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Double): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Float): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Float): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Int): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Int): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Long): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Long): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(Short): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/Short): kotlin.text/StringBuilder`
    - `kotlin.text.appendln` — fun StringBuilder.appendln(String): StringBuilder  -- `final fun (kotlin.text/StringBuilder).kotlin.text/appendln(kotlin/String): kotlin.text/StringBuilder`

- [ ] KSP-1413: kotlin.text.StringBuilder.insert-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text` / receiver `StringBuilder` / family `insert`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_insert.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_insert.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_insert.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.insert` — fun StringBuilder.insert(Int, Byte): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/insert(kotlin/Int, kotlin/Byte): kotlin.text/StringBuilder`
    - `kotlin.text.insert` — fun StringBuilder.insert(Int, Short): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/insert(kotlin/Int, kotlin/Short): kotlin.text/StringBuilder`
    - `kotlin.text.insert` — fun StringBuilder.insert(Int, CharSequence, Int, Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/insert(kotlin/Int, kotlin/CharSequence?, kotlin/Int, kotlin/Int): kotlin.text/StringBuilder`
    - `kotlin.text.insertRange` — fun StringBuilder.insertRange(Int, CharArray, Int, Int): StringBuilder  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/insertRange(kotlin/Int, kotlin/CharArray, kotlin/Int, kotlin/Int): kotlin.text/StringBuilder`

- [ ] KSP-1414: kotlin.text.StringBuilder.to-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text` / receiver `StringBuilder` / family `to`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_to.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_to.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_to.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.toCharArray` — fun StringBuilder.toCharArray(CharArray, Int, Int, Int): Unit  -- `final inline fun (kotlin.text/StringBuilder).kotlin.text/toCharArray(kotlin/CharArray, kotlin/Int = ..., kotlin/Int = ..., kotlin/Int = ...)`

- [ ] KSP-1419: kotlin.text.HexFormat top-level の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text.HexFormat` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.Builder` — class kotlin.text.HexFormat.Builder  -- `final class Builder {`
    - `kotlin.text.HexFormat.BytesHexFormat` — class kotlin.text.HexFormat.BytesHexFormat  -- `final class BytesHexFormat {`
    - `kotlin.text.HexFormat.Companion` — object kotlin.text.HexFormat.Companion  -- `final object Companion {`
    - `kotlin.text.HexFormat.NumberHexFormat` — class kotlin.text.HexFormat.NumberHexFormat  -- `final class NumberHexFormat {`

- [ ] KSP-1420: kotlin.text.HexFormat.HexFormat の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text.HexFormat` / receiver `HexFormat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/HexFormat.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_HexFormat_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_HexFormat_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_HexFormat_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.bytes` — val HexFormat.bytes: BytesHexFormat  -- `final val bytes`
    - `kotlin.text.HexFormat.number` — val HexFormat.number: NumberHexFormat  -- `final val number`
    - `kotlin.text.HexFormat.toString` — fun HexFormat.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.text.HexFormat.upperCase` — val HexFormat.upperCase: Boolean  -- `final val upperCase`

- [ ] KSP-1422: kotlin.text.HexFormat.Builder.Builder の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.text.HexFormat.Builder` / receiver `Builder`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/Builder/Builder.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_Builder_Builder_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_Builder_Builder_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_Builder_Builder_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.Builder.build` — fun Builder.build(): HexFormat  -- `final fun build(): kotlin.text/HexFormat`
    - `kotlin.text.HexFormat.Builder.bytes` — val Builder.bytes: Builder  -- `final val bytes`
    - `kotlin.text.HexFormat.Builder.bytes` — fun Builder.bytes(Function1): Unit  -- `final inline fun bytes(kotlin/Function1<kotlin.text/HexFormat.BytesHexFormat.Builder, kotlin/Unit>)`
    - `kotlin.text.HexFormat.Builder.number` — val Builder.number: Builder  -- `final val number`
    - `kotlin.text.HexFormat.Builder.number` — fun Builder.number(Function1): Unit  -- `final inline fun number(kotlin/Function1<kotlin.text/HexFormat.NumberHexFormat.Builder, kotlin/Unit>)`
    - `kotlin.text.HexFormat.Builder.upperCase` — val Builder.upperCase: Boolean  -- `final var upperCase`

- [ ] KSP-1423: kotlin.text.HexFormat.BytesHexFormat top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.HexFormat.BytesHexFormat` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/BytesHexFormat/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_BytesHexFormat_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.BytesHexFormat.Builder` — class kotlin.text.HexFormat.BytesHexFormat.Builder  -- `final class Builder {`

- [ ] KSP-1424: kotlin.text.HexFormat.BytesHexFormat.BytesHexFormat の未実装 stdlib API を実装する（7 件）
  - 対象: `kotlin.text.HexFormat.BytesHexFormat` / receiver `BytesHexFormat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/BytesHexFormat/BytesHexFormat.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_BytesHexFormat_BytesHexFormat_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_BytesHexFormat_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_BytesHexFormat_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.BytesHexFormat.bytePrefix` — val BytesHexFormat.bytePrefix: String  -- `final val bytePrefix`
    - `kotlin.text.HexFormat.BytesHexFormat.byteSeparator` — val BytesHexFormat.byteSeparator: String  -- `final val byteSeparator`
    - `kotlin.text.HexFormat.BytesHexFormat.byteSuffix` — val BytesHexFormat.byteSuffix: String  -- `final val byteSuffix`
    - `kotlin.text.HexFormat.BytesHexFormat.bytesPerGroup` — val BytesHexFormat.bytesPerGroup: Int  -- `final val bytesPerGroup`
    - `kotlin.text.HexFormat.BytesHexFormat.bytesPerLine` — val BytesHexFormat.bytesPerLine: Int  -- `final val bytesPerLine`
    - `kotlin.text.HexFormat.BytesHexFormat.groupSeparator` — val BytesHexFormat.groupSeparator: String  -- `final val groupSeparator`
    - `kotlin.text.HexFormat.BytesHexFormat.toString` — fun BytesHexFormat.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1425: kotlin.text.HexFormat.BytesHexFormat.Builder.Builder の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.text.HexFormat.BytesHexFormat.Builder` / receiver `Builder`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/BytesHexFormat/Builder/Builder.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_BytesHexFormat_Builder_Builder_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_Builder_Builder_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_BytesHexFormat_Builder_Builder_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.bytePrefix` — val Builder.bytePrefix: String  -- `final var bytePrefix`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.byteSeparator` — val Builder.byteSeparator: String  -- `final var byteSeparator`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.byteSuffix` — val Builder.byteSuffix: String  -- `final var byteSuffix`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.bytesPerGroup` — val Builder.bytesPerGroup: Int  -- `final var bytesPerGroup`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.bytesPerLine` — val Builder.bytesPerLine: Int  -- `final var bytesPerLine`
    - `kotlin.text.HexFormat.BytesHexFormat.Builder.groupSeparator` — val Builder.groupSeparator: String  -- `final var groupSeparator`

- [ ] KSP-1427: kotlin.text.HexFormat.NumberHexFormat top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.HexFormat.NumberHexFormat` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/NumberHexFormat/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_NumberHexFormat_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.NumberHexFormat.Builder` — class kotlin.text.HexFormat.NumberHexFormat.Builder  -- `final class Builder {`

- [ ] KSP-1428: kotlin.text.HexFormat.NumberHexFormat.NumberHexFormat の未実装 stdlib API を実装する（5 件）
  - 対象: `kotlin.text.HexFormat.NumberHexFormat` / receiver `NumberHexFormat`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/NumberHexFormat/NumberHexFormat.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_NumberHexFormat_NumberHexFormat_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_NumberHexFormat_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_NumberHexFormat_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.NumberHexFormat.minLength` — val NumberHexFormat.minLength: Int  -- `final val minLength`
    - `kotlin.text.HexFormat.NumberHexFormat.prefix` — val NumberHexFormat.prefix: String  -- `final val prefix`
    - `kotlin.text.HexFormat.NumberHexFormat.removeLeadingZeros` — val NumberHexFormat.removeLeadingZeros: Boolean  -- `final val removeLeadingZeros`
    - `kotlin.text.HexFormat.NumberHexFormat.suffix` — val NumberHexFormat.suffix: String  -- `final val suffix`
    - `kotlin.text.HexFormat.NumberHexFormat.toString` — fun NumberHexFormat.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1429: kotlin.text.HexFormat.NumberHexFormat.Builder.Builder の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text.HexFormat.NumberHexFormat.Builder` / receiver `Builder`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/HexFormat/NumberHexFormat/Builder/Builder.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_HexFormat_NumberHexFormat_Builder_Builder_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_Builder_Builder_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_HexFormat_NumberHexFormat_Builder_Builder_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.HexFormat.NumberHexFormat.Builder.minLength` — val Builder.minLength: Int  -- `final var minLength`
    - `kotlin.text.HexFormat.NumberHexFormat.Builder.prefix` — val Builder.prefix: String  -- `final var prefix`
    - `kotlin.text.HexFormat.NumberHexFormat.Builder.removeLeadingZeros` — val Builder.removeLeadingZeros: Boolean  -- `final var removeLeadingZeros`
    - `kotlin.text.HexFormat.NumberHexFormat.Builder.suffix` — val Builder.suffix: String  -- `final var suffix`

- [ ] KSP-1431: kotlin.text.MatchGroup.MatchGroup の未実装 stdlib API を実装する（8 件）
  - 対象: `kotlin.text.MatchGroup` / receiver `MatchGroup`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/MatchGroup/MatchGroup.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_MatchGroup_MatchGroup_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_MatchGroup_MatchGroup_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_MatchGroup_MatchGroup_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.MatchGroup.component1` — fun MatchGroup.component1(): String  -- `final fun component1(): kotlin/String`
    - `kotlin.text.MatchGroup.component2` — fun MatchGroup.component2(): IntRange  -- `final fun component2(): kotlin.ranges/IntRange`
    - `kotlin.text.MatchGroup.copy` — fun MatchGroup.copy(String, IntRange): MatchGroup  -- `final fun copy(kotlin/String = ..., kotlin.ranges/IntRange = ...): kotlin.text/MatchGroup`
    - `kotlin.text.MatchGroup.equals` — fun MatchGroup.equals(Any): Boolean  -- `final fun equals(kotlin/Any?): kotlin/Boolean`
    - `kotlin.text.MatchGroup.hashCode` — fun MatchGroup.hashCode(): Int  -- `final fun hashCode(): kotlin/Int`
    - `kotlin.text.MatchGroup.range` — val MatchGroup.range: IntRange  -- `final val range`
    - `kotlin.text.MatchGroup.toString` — fun MatchGroup.toString(): String  -- `final fun toString(): kotlin/String`
    - `kotlin.text.MatchGroup.value` — val MatchGroup.value: String  -- `final val value`

- [ ] KSP-1433: kotlin.text.MatchResult top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.MatchResult` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/MatchResult/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_MatchResult_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_MatchResult_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_MatchResult_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.MatchResult.Destructured` — class kotlin.text.MatchResult.Destructured  -- `final class Destructured {`

- [ ] KSP-1436: kotlin.text.Regex.Regex の未実装 stdlib API を実装する（13 件）
  - 対象: `kotlin.text.Regex` / receiver `Regex`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Regex/Regex.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Regex_Regex_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Regex_Regex_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Regex_Regex_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Regex.containsMatchIn` — fun Regex.containsMatchIn(CharSequence): Boolean  -- `final fun containsMatchIn(kotlin/CharSequence): kotlin/Boolean`
    - `kotlin.text.Regex.find` — fun Regex.find(CharSequence, Int): MatchResult  -- `final fun find(kotlin/CharSequence, kotlin/Int = ...): kotlin.text/MatchResult?`
    - `kotlin.text.Regex.findAll` — fun Regex.findAll(CharSequence, Int): Sequence  -- `final fun findAll(kotlin/CharSequence, kotlin/Int = ...): kotlin.sequences/Sequence<kotlin.text/MatchResult>`
    - `kotlin.text.Regex.matchAt` — fun Regex.matchAt(CharSequence, Int): MatchResult  -- `final fun matchAt(kotlin/CharSequence, kotlin/Int): kotlin.text/MatchResult?`
    - `kotlin.text.Regex.matchEntire` — fun Regex.matchEntire(CharSequence): MatchResult  -- `final fun matchEntire(kotlin/CharSequence): kotlin.text/MatchResult?`
    - `kotlin.text.Regex.matches` — fun Regex.matches(CharSequence): Boolean  -- `final fun matches(kotlin/CharSequence): kotlin/Boolean`
    - `kotlin.text.Regex.matchesAt` — fun Regex.matchesAt(CharSequence, Int): Boolean  -- `final fun matchesAt(kotlin/CharSequence, kotlin/Int): kotlin/Boolean`
    - `kotlin.text.Regex.replace` — fun Regex.replace(CharSequence, Function1): String  -- `final fun replace(kotlin/CharSequence, kotlin/Function1<kotlin.text/MatchResult, kotlin/CharSequence>): kotlin/String`
    - `kotlin.text.Regex.replace` — fun Regex.replace(CharSequence, String): String  -- `final fun replace(kotlin/CharSequence, kotlin/String): kotlin/String`
    - `kotlin.text.Regex.replaceFirst` — fun Regex.replaceFirst(CharSequence, String): String  -- `final fun replaceFirst(kotlin/CharSequence, kotlin/String): kotlin/String`
    - `kotlin.text.Regex.split` — fun Regex.split(CharSequence, Int): List  -- `final fun split(kotlin/CharSequence, kotlin/Int = ...): kotlin.collections/List<kotlin/String>`
    - `kotlin.text.Regex.splitToSequence` — fun Regex.splitToSequence(CharSequence, Int): Sequence  -- `final fun splitToSequence(kotlin/CharSequence, kotlin/Int = ...): kotlin.sequences/Sequence<kotlin/String>`
    - `kotlin.text.Regex.toString` — fun Regex.toString(): String  -- `final fun toString(): kotlin/String`

- [ ] KSP-1439: kotlin.text.StringBuilder top-level の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text.StringBuilder` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/StringBuilder/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_StringBuilder_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_StringBuilder_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.StringBuilder.<init>` — constructor ()  -- `constructor <init>()`
    - `kotlin.text.StringBuilder.<init>` — constructor (CharSequence)  -- `constructor <init>(kotlin/CharSequence)`
    - `kotlin.text.StringBuilder.<init>` — constructor (Int)  -- `constructor <init>(kotlin/Int)`
    - `kotlin.text.StringBuilder.<init>` — constructor (String)  -- `constructor <init>(kotlin/String)`

- [ ] KSP-1442: kotlin.text.Typography.Typography.amp-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `amp`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/amp.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_amp.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_amp.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_amp.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.amp` — val Typography.amp: Char  -- `final const val amp`

- [ ] KSP-1443: kotlin.text.Typography.Typography.bullet-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `bullet`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/bullet.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_bullet.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_bullet.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_bullet.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.bullet` — val Typography.bullet: Char  -- `final const val bullet`

- [ ] KSP-1444: kotlin.text.Typography.Typography.cent-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `cent`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/cent.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_cent.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_cent.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_cent.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.cent` — val Typography.cent: Char  -- `final const val cent`

- [ ] KSP-1445: kotlin.text.Typography.Typography.copyright-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `copyright`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/copyright.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_copyright.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_copyright.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_copyright.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.copyright` — val Typography.copyright: Char  -- `final const val copyright`

- [ ] KSP-1446: kotlin.text.Typography.Typography.dagger-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `dagger`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/dagger.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_dagger.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_dagger.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_dagger.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.dagger` — val Typography.dagger: Char  -- `final const val dagger`

- [ ] KSP-1447: kotlin.text.Typography.Typography.degree-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `degree`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/degree.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_degree.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_degree.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_degree.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.degree` — val Typography.degree: Char  -- `final const val degree`

- [ ] KSP-1449: kotlin.text.Typography.Typography.double-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `double`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/double.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_double.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_double.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_double.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.doubleDagger` — val Typography.doubleDagger: Char  -- `final const val doubleDagger`
    - `kotlin.text.Typography.doublePrime` — val Typography.doublePrime: Char  -- `final const val doublePrime`

- [ ] KSP-1452: kotlin.text.Typography.Typography.greater-family の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `greater`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/greater.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_greater.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_greater.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_greater.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.greater` — val Typography.greater: Char  -- `final const val greater`
    - `kotlin.text.Typography.greaterOrEqual` — val Typography.greaterOrEqual: Char  -- `final const val greaterOrEqual`

- [ ] KSP-1457: kotlin.text.Typography.Typography.mdash-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `mdash`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/mdash.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_mdash.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_mdash.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_mdash.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.mdash` — val Typography.mdash: Char  -- `final const val mdash`

- [ ] KSP-1458: kotlin.text.Typography.Typography.middle-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `middle`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/middle.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_middle.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_middle.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_middle.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.middleDot` — val Typography.middleDot: Char  -- `final const val middleDot`

- [ ] KSP-1459: kotlin.text.Typography.Typography.nbsp-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `nbsp`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/nbsp.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_nbsp.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_nbsp.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_nbsp.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.nbsp` — val Typography.nbsp: Char  -- `final const val nbsp`

- [ ] KSP-1460: kotlin.text.Typography.Typography.ndash-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `ndash`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/ndash.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_ndash.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_ndash.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_ndash.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.ndash` — val Typography.ndash: Char  -- `final const val ndash`

- [ ] KSP-1461: kotlin.text.Typography.Typography.not-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `not`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/not.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_not.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_not.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_not.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.notEqual` — val Typography.notEqual: Char  -- `final const val notEqual`

- [ ] KSP-1462: kotlin.text.Typography.Typography.paragraph-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `paragraph`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/paragraph.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_paragraph.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_paragraph.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_paragraph.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.paragraph` — val Typography.paragraph: Char  -- `final const val paragraph`

- [ ] KSP-1463: kotlin.text.Typography.Typography.plus-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `plus`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/plus.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_plus.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_plus.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_plus.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.plusMinus` — val Typography.plusMinus: Char  -- `final const val plusMinus`

- [ ] KSP-1464: kotlin.text.Typography.Typography.pound-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `pound`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/pound.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_pound.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_pound.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_pound.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.pound` — val Typography.pound: Char  -- `final const val pound`

- [ ] KSP-1465: kotlin.text.Typography.Typography.prime-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `prime`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/prime.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_prime.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_prime.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_prime.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.prime` — val Typography.prime: Char  -- `final const val prime`

- [ ] KSP-1466: kotlin.text.Typography.Typography.quote-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `quote`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/quote.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_quote.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_quote.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_quote.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.quote` — val Typography.quote: Char  -- `final const val quote`

- [ ] KSP-1467: kotlin.text.Typography.Typography.registered-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `registered`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/registered.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_registered.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_registered.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_registered.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.registered` — val Typography.registered: Char  -- `final const val registered`

- [ ] KSP-1468: kotlin.text.Typography.Typography.right-family の未実装 stdlib API を実装する（4 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `right`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/right.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_right.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_right.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_right.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.rightDoubleQuote` — val Typography.rightDoubleQuote: Char  -- `final const val rightDoubleQuote`
    - `kotlin.text.Typography.rightGuillemet` — val Typography.rightGuillemet: Char  -- `final const val rightGuillemet`
    - `kotlin.text.Typography.rightGuillemete` — val Typography.rightGuillemete: Char  -- `final const val rightGuillemete`
    - `kotlin.text.Typography.rightSingleQuote` — val Typography.rightSingleQuote: Char  -- `final const val rightSingleQuote`

- [ ] KSP-1469: kotlin.text.Typography.Typography.section-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `section`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/section.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_section.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_section.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_section.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.section` — val Typography.section: Char  -- `final const val section`

- [ ] KSP-1470: kotlin.text.Typography.Typography.times-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `times`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/times.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_times.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_times.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_times.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.times` — val Typography.times: Char  -- `final const val times`

- [ ] KSP-1471: kotlin.text.Typography.Typography.tm-family の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.text.Typography` / receiver `Typography` / family `tm`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/text/Typography/tm.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_text_Typography_Typography_tm.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_tm.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_text_Typography_Typography_tm.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.text.Typography.tm` — val Typography.tm: Char  -- `final const val tm`

- [ ] KSP-1472: kotlin.time top-level の未実装 stdlib API を実装する（9 件）
  - 対象: `kotlin.time` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.AbstractDoubleTimeSource` — class kotlin.time.AbstractDoubleTimeSource  -- `abstract class kotlin.time/AbstractDoubleTimeSource : kotlin.time/TimeSource.WithComparableMarks {`
    - `kotlin.time.AbstractLongTimeSource` — class kotlin.time.AbstractLongTimeSource  -- `abstract class kotlin.time/AbstractLongTimeSource : kotlin.time/TimeSource.WithComparableMarks {`
    - `kotlin.time.Clock` — interface kotlin.time.Clock  -- `abstract interface kotlin.time/Clock {`
    - `kotlin.time.ComparableTimeMark` — interface kotlin.time.ComparableTimeMark  -- `abstract interface kotlin.time/ComparableTimeMark : kotlin.time/TimeMark, kotlin/Comparable<kotlin.time/ComparableTimeMark> {`
    - `kotlin.time.ExperimentalTime` — class kotlin.time.ExperimentalTime  -- `open annotation class kotlin.time/ExperimentalTime : kotlin/Annotation {`
    - `kotlin.time.Instant` — class kotlin.time.Instant  -- `final class kotlin.time/Instant : kotlin.io/Serializable, kotlin/Comparable<kotlin.time/Instant> {`
    - `kotlin.time.TestTimeSource` — class kotlin.time.TestTimeSource  -- `final class kotlin.time/TestTimeSource : kotlin.time/AbstractLongTimeSource {`
    - `kotlin.time.TimeMark` — interface kotlin.time.TimeMark  -- `abstract interface kotlin.time/TimeMark {`
    - `kotlin.time.TimedValue` — class kotlin.time.TimedValue  -- `final class <#A: kotlin/Any?> kotlin.time/TimedValue {`

- [ ] KSP-1474: kotlin.time.Monotonic の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.time` / receiver `Monotonic`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/TimeSource.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_Monotonic_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_Monotonic_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_Monotonic_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.measureTime` — fun Monotonic.measureTime(Function0): Duration  -- `final inline fun (kotlin.time/TimeSource.Monotonic).kotlin.time/measureTime(kotlin/Function0<kotlin/Unit>): kotlin.time/Duration`
    - `kotlin.time.measureTimedValue` — fun Monotonic.measureTimedValue(Function0): TimedValue  -- `final inline fun <#A: kotlin/Any?> (kotlin.time/TimeSource.Monotonic).kotlin.time/measureTimedValue(kotlin/Function0<#A>): kotlin.time/TimedValue<#A>`

- [ ] KSP-1475: kotlin.time.TimeSource の未実装 stdlib API を実装する（2 件）
  - 対象: `kotlin.time` / receiver `TimeSource`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/TimeSource.kt`
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_TimeSource_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_TimeSource_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_TimeSource_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.measureTime` — fun TimeSource.measureTime(Function0): Duration  -- `final inline fun (kotlin.time/TimeSource).kotlin.time/measureTime(kotlin/Function0<kotlin/Unit>): kotlin.time/Duration`
    - `kotlin.time.measureTimedValue` — fun TimeSource.measureTimedValue(Function0): TimedValue  -- `final inline fun <#A: kotlin/Any?> (kotlin.time/TimeSource).kotlin.time/measureTimedValue(kotlin/Function0<#A>): kotlin.time/TimedValue<#A>`

- [ ] KSP-1477: kotlin.time.AbstractDoubleTimeSource.AbstractDoubleTimeSource の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.time.AbstractDoubleTimeSource` / receiver `AbstractDoubleTimeSource`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/AbstractDoubleTimeSource/AbstractDoubleTimeSource.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_AbstractDoubleTimeSource_AbstractDoubleTimeSource_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_AbstractDoubleTimeSource_AbstractDoubleTimeSource_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_AbstractDoubleTimeSource_AbstractDoubleTimeSource_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.AbstractDoubleTimeSource.markNow` — fun AbstractDoubleTimeSource.markNow(): ComparableTimeMark  -- `open fun markNow(): kotlin.time/ComparableTimeMark`
    - `kotlin.time.AbstractDoubleTimeSource.read` — fun AbstractDoubleTimeSource.read(): Double  -- `abstract fun read(): kotlin/Double`
    - `kotlin.time.AbstractDoubleTimeSource.unit` — val AbstractDoubleTimeSource.unit: DurationUnit  -- `final val unit`

- [ ] KSP-1478: kotlin.time.AbstractLongTimeSource top-level の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.time.AbstractLongTimeSource` / top-level
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/AbstractLongTimeSource/Stdlib.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_AbstractLongTimeSource_n_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_AbstractLongTimeSource_n_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_AbstractLongTimeSource_n_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.AbstractLongTimeSource.<init>` — constructor (DurationUnit)  -- `constructor <init>(kotlin.time/DurationUnit)`

- [ ] KSP-1479: kotlin.time.AbstractLongTimeSource.AbstractLongTimeSource の未実装 stdlib API を実装する（3 件）
  - 対象: `kotlin.time.AbstractLongTimeSource` / receiver `AbstractLongTimeSource`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/AbstractLongTimeSource/AbstractLongTimeSource.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_AbstractLongTimeSource_AbstractLongTimeSource_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_AbstractLongTimeSource_AbstractLongTimeSource_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_AbstractLongTimeSource_AbstractLongTimeSource_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.AbstractLongTimeSource.markNow` — fun AbstractLongTimeSource.markNow(): ComparableTimeMark  -- `open fun markNow(): kotlin.time/ComparableTimeMark`
    - `kotlin.time.AbstractLongTimeSource.read` — fun AbstractLongTimeSource.read(): Long  -- `abstract fun read(): kotlin/Long`
    - `kotlin.time.AbstractLongTimeSource.unit` — val AbstractLongTimeSource.unit: DurationUnit  -- `final val unit`

- [ ] KSP-1481: kotlin.time.Clock.Clock の未実装 stdlib API を実装する（1 件）
  - 対象: `kotlin.time.Clock` / receiver `Clock`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/Clock/Clock.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_Clock_Clock_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_Clock_Clock_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_Clock_Clock_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.Clock.now` — fun Clock.now(): Instant  -- `abstract fun now(): kotlin.time/Instant`

- [ ] KSP-1484: kotlin.time.Duration.Duration の未実装 stdlib API を実装する（14 件）
  - 対象: `kotlin.time.Duration` / receiver `Duration`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/Duration/Duration.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_Duration_Duration_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_Duration_Duration_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_Duration_Duration_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.Duration.div` — fun Duration.div(Double): Duration  -- `final fun div(kotlin/Double): kotlin.time/Duration`
    - `kotlin.time.Duration.hoursComponent` — val Duration.hoursComponent: Int  -- `final val hoursComponent`
    - `kotlin.time.Duration.minutesComponent` — val Duration.minutesComponent: Int  -- `final val minutesComponent`
    - `kotlin.time.Duration.nanosecondsComponent` — val Duration.nanosecondsComponent: Int  -- `final val nanosecondsComponent`
    - `kotlin.time.Duration.secondsComponent` — val Duration.secondsComponent: Int  -- `final val secondsComponent`
    - `kotlin.time.Duration.times` — fun Duration.times(Double): Duration  -- `final fun times(kotlin/Double): kotlin.time/Duration`
    - `kotlin.time.Duration.toComponents` — fun Duration.toComponents(Function2): #A1  -- `final inline fun <#A1: kotlin/Any?> toComponents(kotlin/Function2<kotlin/Long, kotlin/Int, #A1>): #A1`
    - `kotlin.time.Duration.toComponents` — fun Duration.toComponents(Function3): #A1  -- `final inline fun <#A1: kotlin/Any?> toComponents(kotlin/Function3<kotlin/Long, kotlin/Int, kotlin/Int, #A1>): #A1`
    - `kotlin.time.Duration.toComponents` — fun Duration.toComponents(Function4): #A1  -- `final inline fun <#A1: kotlin/Any?> toComponents(kotlin/Function4<kotlin/Long, kotlin/Int, kotlin/Int, kotlin/Int, #A1>): #A1`
    - `kotlin.time.Duration.toComponents` — fun Duration.toComponents(Function5): #A1  -- `final inline fun <#A1: kotlin/Any?> toComponents(kotlin/Function5<kotlin/Long, kotlin/Int, kotlin/Int, kotlin/Int, kotlin/Int, #A1>): #A1`
    - `kotlin.time.Duration.toDouble` — fun Duration.toDouble(DurationUnit): Double  -- `final fun toDouble(kotlin.time/DurationUnit): kotlin/Double`
    - `kotlin.time.Duration.toInt` — fun Duration.toInt(DurationUnit): Int  -- `final fun toInt(kotlin.time/DurationUnit): kotlin/Int`
    - `kotlin.time.Duration.toLong` — fun Duration.toLong(DurationUnit): Long  -- `final fun toLong(kotlin.time/DurationUnit): kotlin/Long`
    - `kotlin.time.Duration.toString` — fun Duration.toString(DurationUnit, Int): String  -- `final fun toString(kotlin.time/DurationUnit, kotlin/Int = ...): kotlin/String`

- [ ] KSP-1485: kotlin.time.Duration.Companion.Companion の未実装 stdlib API を実装する（22 件）
  - 対象: `kotlin.time.Duration.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/Duration/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_Duration_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_Duration_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_Duration_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.Duration.Companion.convert` — fun Companion.convert(Double, DurationUnit, DurationUnit): Double  -- `final fun convert(kotlin/Double, kotlin.time/DurationUnit, kotlin.time/DurationUnit): kotlin/Double`
    - `kotlin.time.Duration.Companion.days` — val Companion.days: Duration  -- `final val days`
    - `kotlin.time.Duration.Companion.days` — val Companion.days: Duration  -- `final val days`
    - `kotlin.time.Duration.Companion.days` — val Companion.days: Duration  -- `final val days`
    - `kotlin.time.Duration.Companion.hours` — val Companion.hours: Duration  -- `final val hours`
    - `kotlin.time.Duration.Companion.hours` — val Companion.hours: Duration  -- `final val hours`
    - `kotlin.time.Duration.Companion.hours` — val Companion.hours: Duration  -- `final val hours`
    - `kotlin.time.Duration.Companion.microseconds` — val Companion.microseconds: Duration  -- `final val microseconds`
    - `kotlin.time.Duration.Companion.microseconds` — val Companion.microseconds: Duration  -- `final val microseconds`
    - `kotlin.time.Duration.Companion.microseconds` — val Companion.microseconds: Duration  -- `final val microseconds`
    - `kotlin.time.Duration.Companion.milliseconds` — val Companion.milliseconds: Duration  -- `final val milliseconds`
    - `kotlin.time.Duration.Companion.milliseconds` — val Companion.milliseconds: Duration  -- `final val milliseconds`
    - `kotlin.time.Duration.Companion.milliseconds` — val Companion.milliseconds: Duration  -- `final val milliseconds`
    - `kotlin.time.Duration.Companion.minutes` — val Companion.minutes: Duration  -- `final val minutes`
    - `kotlin.time.Duration.Companion.minutes` — val Companion.minutes: Duration  -- `final val minutes`
    - `kotlin.time.Duration.Companion.minutes` — val Companion.minutes: Duration  -- `final val minutes`
    - `kotlin.time.Duration.Companion.nanoseconds` — val Companion.nanoseconds: Duration  -- `final val nanoseconds`
    - `kotlin.time.Duration.Companion.nanoseconds` — val Companion.nanoseconds: Duration  -- `final val nanoseconds`
    - `kotlin.time.Duration.Companion.nanoseconds` — val Companion.nanoseconds: Duration  -- `final val nanoseconds`
    - `kotlin.time.Duration.Companion.seconds` — val Companion.seconds: Duration  -- `final val seconds`
    - `kotlin.time.Duration.Companion.seconds` — val Companion.seconds: Duration  -- `final val seconds`
    - `kotlin.time.Duration.Companion.seconds` — val Companion.seconds: Duration  -- `final val seconds`

- [ ] KSP-1490: kotlin.time.Instant.Companion.Companion の未実装 stdlib API を実装する（6 件）
  - 対象: `kotlin.time.Instant.Companion` / receiver `Companion`
  - 実装先 .kt: `Sources/CompilerCore/Stdlib/kotlin/time/Instant/Companion/Companion.kt`（該当ファイルが無ければ新規作成）
  - bridge/stub 整理: 対象シンボルの `__kk_*` / `kk_*` Runtime 関数、`HeaderHelpers+Synthetic*Stubs.swift` 登録、`RuntimeABISpec` エントリ、`CallTypeChecker+*` / `CallLowerer+*` の name-string 特例があれば同 PR で削除。無ければ新規 Kotlin 実装のみ。
  - golden テスト: `Tests/CompilerCoreTests/GoldenCases/Sema/stdlib_kotlin_time_Instant_Companion_Companion_n.kt` を追加し、`UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` で更新。差分が機械的であることを確認。
  - diff ケース: `Scripts/diff_cases/stdlib_kotlin_time_Instant_Companion_Companion_n.kt` を追加し、`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_time_Instant_Companion_Companion_n.kt` green（JDK17 環境では `DIFF_REQUIRE_JDK21=0` を付与）。
  - 完了ゲート: `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green / `bash Scripts/check_todo_ids.sh` pass / `bash Scripts/validate_runtime_abi_links.sh`（存在すれば）
  - 未実装シンボル一覧:
    - `kotlin.time.Instant.Companion.DISTANT_FUTURE` — val Companion.DISTANT_FUTURE: Instant  -- `final val DISTANT_FUTURE`
    - `kotlin.time.Instant.Companion.DISTANT_PAST` — val Companion.DISTANT_PAST: Instant  -- `final val DISTANT_PAST`
    - `kotlin.time.Instant.Companion.fromEpochSeconds` — fun Companion.fromEpochSeconds(Long, Int): Instant  -- `final fun fromEpochSeconds(kotlin/Long, kotlin/Int): kotlin.time/Instant`
    - `kotlin.time.Instant.Companion.fromEpochSeconds` — fun Companion.fromEpochSeconds(Long, Long): Instant  -- `final fun fromEpochSeconds(kotlin/Long, kotlin/Long = ...): kotlin.time/Instant`
    - `kotlin.time.Instant.Companion.parse` — fun Companion.parse(CharSequence): Instant  -- `final fun parse(kotlin/CharSequence): kotlin.time/Instant`
    - `kotlin.time.Instant.Companion.parseOrNull` — fun Companion.parseOrNull(CharSequence): Instant  -- `final fun parseOrNull(kotlin/CharSequence): kotlin.time/Instant?`

## Runtime follow-up

## 戦略アーキテクチャ改善 実行計画（ARCH: 2026-08-22 構造レビュー）

> 出典: 2026-08-22 の全サブシステム構造レビュー（Sema / KIR / Lowering / Backend / Runtime / Driver / LSP / テスト基盤の精査 + 実測）。主要実測値: release kswiftc で hello.kt が **デフォルト 4.27s → `--stdlib-library`(.kklib) 1.40s → `--no-stdlib` 0.41s**（コンパイル時間の ~2/3 が bundled stdlib 2.6万行の毎回再処理）。実行時は `for (i in 1..1000000)` が 1,236ms = **1.24µs/iter ≒ ランタイム C 呼び出し 2 回 × ~620ns**（NSLock + Set ハンドル検証 + 動的キャスト、しかも -Onone ビルド）。
> 参照プラクティス: rustc（事前コンパイル stdlib / rmeta 遅延読込 / lang items）、Kotlin K2（フェーズ化・IDE 遅延解決）、Roslyn（WellKnownMember）、Swift SIL（raw/canonical + verifier）、MLIR（パス境界検証）、rust-analyzer（durability・エラー耐性）、Kotlin/Native（コンパイラ統合ランタイム・並行 mark-sweep）。
> **共通ゲート G を全タスクに適用**（+ 該当時 U）。粒度ルール: 1タスク = 1 PR。性能タスクは変更前後のベンチ値（`Scripts/benchmark_stdlib_hof.sh` / `-Xfrontend time-phases`）を PR 本文に記載する。既存台帳との関係: 名前文字列特例の解体は RF4 系（`docs/rf4-name-special-case-inventory.md`）・KSP 移行と同期して進め、本セクションでは重複起票しない。
> 優先順は Tier 順。**ARCH-001/002 は他の全性能系判断（stdlib-pipeline §13-3 の「Swift 残留の実測条件」）の基準値を変えるため最優先**。完了後に `docs/refactoring-metrics.md` のベンチ基準値を取り直すこと。

### ARCH Tier 1: 即効（相互独立・並列可）

- [ ] ARCH-002: LLVM 中間最適化パイプラインを配線する。現状 `optLevel` は `createTargetMachine`（命令選択・レジスタ割付）と DWARF `isOptimized` にしか流れず、new PassManager 系シンボル（`LLVMRunPasses` / `LLVMCreatePassBuilderOptions`）は `LLVMCAPIBindings+Loading.swift` の dlsym 表に存在しない — **`-O2` 指定でも mem2reg / SROA / GVN / inlining / LICM が一度も走らない**（バックエンドが逆 mem2reg 退避で作るスタックスロットが出荷バイナリに残る）。dlsym 表に 2 シンボルを追加し、`NativeEmitter` の emit 前に `default<O1|O2|O3>` を実行（`-O0` は現状維持でデバッグ体験を守る）。完了条件: `-O0`/`-O2` 両構成で `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` green + ベンチ前後値記載 + G。
- [ ] ARCH-003: CI に `-O2` の diff レーンを追加する（最適化起因ミスコンパイルの常設検出器）。前提: ARCH-002。完了条件: `.github/workflows/ci.yml` にレーン追加 + green 実績を完了メモに記載。
- [ ] ARCH-006: LSP が毎 didChange で bundled stdlib 221 ファイルを Lex→Parse→AST→全量型検査している問題を解消する。`Analyzer.analyze`（LSPServer 内で唯一の `CompilerOptions` 構築点）が `emit: .object` のため `shouldUseDefaultStdlib` ガードに弾かれ、常にソース注入経路に落ちている。stdlib artifact（ARCH-005 の成果物、なければ起動時 1 回のビルド）を明示指定する。完了条件: didChange 1 回あたりの解析時間の前後値を PR 本文に記載 + LSPServerTests に「解析結果に bundled 由来 FileID の再 Lex が発生しない」ことを固定するテスト + G。前提: ARCH-005（または `stdlibLibraryPath` 明示注入のみで先行実施可）。
- [ ] ARCH-011: 述語系 ABI の boxed Bool 返却を生値に変える。`kk_set_contains` / `kk_set_is_empty` 等が結果を `kk_box_bool` で包んで返し、**1 回の contains ごとに解放されない Swift オブジェクトを 1 個リーク**している。呼び出し側 lowering と合わせて i1/i64 生値返却へ。`RuntimeABISpec` 更新 + parity テストを同一 PR で。完了条件: `rg 'kk_box_bool' Sources/Runtime/RuntimeSetAndMap.swift` が 0 件 + RuntimeTests + G。

### ARCH Tier 2a: ランタイム統合（Kotlin/Native 型モデルへの段階接近）

> 背景: Runtime には設計済みの K/N 型モデル（`KTypeInfo` / `kk_alloc` / `KKObjHeader` / frame map / mark-sweep GC）と、実際に動く「Swift ARC box + インスタンスごと辞書 vtable + グローバル NSLock」の**二重設計**が同居し、前者は codegen 未配線で全て到達不能、後者は box 解放経路がなく恒久リークする。GC は起動トリガーが存在せず一度も走らない。

- [ ] ARCH-013: 静的に型が確定するプリミティブ boxing/unboxing をインライン emit 化する。`kk_box_int` は「NSLock 2 回 + Set 照合 + Swift class 割付 + `passRetained`（解放なし）」、`kk_unbox_int` は「NSLock + Set 照合 + 動的キャスト」。型が静的確定する境界（ABILoweringPass の boxing boundary）で、タグ付き即値表現またはインライン割付コードに置換する。設計は ARCH-015 の決定に従属。完了条件: boxing ヘビーな diff ケースのベンチ前後値記載 + RuntimeTests + G。前提: ARCH-015。
- [ ] ARCH-014: ルート 0 件の frame push/pop 税を停止する。`NativeEmitter+FunctionEmission` が全 Kotlin 関数のプロローグで `kk_register_frame_map(fid, 0)` + `kk_push_frame(fid, 0)`、全出口で `kk_pop_frame()` を emit するが、frame map ポインタは**定数 0** のため、ランタイム側は毎関数呼び出しで「グローバルロック 3 回 + 辞書削除 + 配列 append」を行いルート 0 件を登録している（`FrameMapDescriptorC` を構築する codegen は存在しない）。emit を停止し、GC 実体化（ARCH-016）時に TLS シャドウスタックとして正規に再導入する方針を `docs/` に記録する。完了条件: `rg 'kk_push_frame' Sources/CompilerBackend/` が 0 件 + 関数呼び出しヘビーなベンチ前後値記載 + RuntimeTests + G。
- [ ] ARCH-016: box/オブジェクトの解放経路を導入する（恒久リークの解消）。現状 `RuntimeIntBox`/`RuntimeStringBox`/`RuntimeListBox`/`RuntimeMapBox`/`RuntimeObjectBox` は `Unmanaged.passRetained` 後に release する者が存在せず、`objectPointers` 登録とともにプロセス生涯リークする（`RuntimeGC` のコメント自身が「解放は box を release する者の責任」と明言）。mark-sweep は対象ヒープ（`heapObjects`)が常に空で一度も起動しない。到達可能性ベースの回収または明示解放経路を設計・実装し、割付ループの RSS が有界になることを固定する。完了条件: 割付ループ（例: `while` 内 `list.add` / boxing）の RSS 有界性テスト + RuntimeTests + G。前提: ARCH-015。

### ARCH Tier 2b: KIR 品質基盤（SIL/MLIR 流の検証導入）

- [ ] ARCH-018: `KIRVerifier` 第 1 弾を導入する。検査項目: ①関数内ラベル一意 + 全 `jump` 先定義済み（`KIRLabelRelocation.swift` 冒頭コメントが自己記録する「ラベル衝突 → LLVM クラッシュ」クラスの即時検出）、②読まれるレジスタは代入済み、③ `instructionLocations.count == body.count`、④ `call` の callee が `RuntimeABISpec` または KIR 内関数に解決可能。デバッグビルド + CI で全 Lowering パス後に実行、release では off。完了条件: verifier が CI で有効 + 既存 golden/diff green + 意図的に壊した KIR で検出することを固定するユニットテスト + G。
- [ ] ARCH-019: `replaceBody` を位置配列同時更新型のシグネチャに変更する。現状 Lowering 内 28 箇所の `replaceBody` のうち `replaceInstructionLocations` を伴うのは 2 箇所のみで、バックエンドの長さ不一致ガードにより**該当関数の行レベルデバッグ情報が黙って全損**している。`replaceBody(body:locations:)` に一本化し、旧 API を廃止して型で防ぐ。完了条件: `rg 'func replaceBody' Sources/CompilerCore/KIR/` が新シグネチャのみ + Lowering 通過後も `instructionLocations.count == body.count` が全関数で成立（ARCH-018 の検査③を enforcing に昇格）+ G。前提: ARCH-018 推奨。
- [ ] ARCH-020: `KIRStage` 段階マーカー（raw / desugared / abiLowered 等）を導入し、各 Lowering パスが要求・生成段階を宣言する。現状パス順序制約はソースコメントのみ（例: Tailrec→NormalizeBlocks、ValueClassUnboxing→PropertyLowering、IntegerNarrowing→ABILowering）で機械化されていない。SIL の `sil_stage raw/canonical` 相当。完了条件: 順序違反をデバッグビルドで即検出するテスト + G。前提: ARCH-018。

### ARCH Tier 2c: Sema の名前ディスパッチ出口戦略（RF4/KSP と同期）

- [ ] ARCH-021: well-known シンボル表を導入する。現状 stdlib 特例判定は「TypeCheck 内の文字列リテラル switch 386 ケース + インライン `Set<String>` 名前表（collectionHOFNames 等 ~120 名）+ `interner.resolve == "…"` 比較」に散在し、ユーザ定義 `map`/`delay` 等との衝突ガードがサイトごと ad-hoc（`hasNonStdlibCollectionFactoryShadow` 等）。Roslyn `WellKnownMember` / rustc lang items に倣い、①bundled Kotlin 宣言側に `@KsIntrinsic("kotlin.collections.map")` 的注釈（既存 `@KsSymbolName` 機構を流用）または FQName 表を導入、②Sema 起動時に「well-known 名 → SymbolID」を 1 箇所で解決、③特例分岐を SymbolID 比較へ置換する**基盤**を作る（全面置換は RF4 台帳の消化として KSP 移行と同期し、本タスクは基盤 + 代表 2〜3 特例の置換まで）。完了条件: 基盤 + 置換済み特例の rg チェック（旧文字列比較 0 件）+ シャドーイング回帰テスト（ユーザ定義同名関数が特例に吸われない）+ G。
- [ ] ARCH-022: `Scripts/loc_report.sh` に名前ディスパッチの実態メトリクスを追加する。現行の `interner_resolve_literal_comparison_count`（TypeCheck 79 件）は氷山の一角で、文字列 switch 386 ケースとインライン名前表を数えていない。「TypeCheck 内文字列リテラル case 数」「インライン `Set<String>` 名前表エントリ数」を追加し、ARCH-021/RF4 の進捗を非悪化ゲートに乗せる。完了条件: loc_report 出力に新メトリクス + `docs/refactoring-metrics.md` に基準値追記。

### ARCH Tier 2d: テスト・CI の 4 穴埋め

- [ ] ARCH-023: diff_cases を種にした変異 fuzzer と crash corpus を導入する。現状 fuzzing はゼロで、SIGSEGV/SIGBUS 級のフロントエンド・ランタイムバグが diff triage の**副産物として偶然**見つかり続けている。1,038 ケースへのトークン置換・削除・入替変異 + 「クラッシュしない・ICE は `KSWIFTK-ICE-*` 診断で終了する」オラクルから開始し、夜間 CI（`quarterly-audits.yml` 同様の cron）+ 最小化ケースの `Tests/CrashCorpus/` 恒久保存。参照: Csmith(481 バグ)/YARPGen(220+ バグ)の differential fuzzing 実績。完了条件: 夜間ワークフロー追加 + corpus 再生テストが CI で green + 初回運転で見つかったバグの起票実績。
- [ ] ARCH-026: ベンチマークの CI ゲート化。`Scripts/benchmark_stdlib_hof.sh` は現在 CI から一度も呼ばれず、stdlib-pipeline **§13-2/§13-3（性能理由の Swift 残留・ブリッジ追加には実測必須）が執行不能**になっている。実行ベンチ + コンパイル時間ベンチ（hello / 中規模合成 / stdlib-only、`-Xfrontend time-phases` の TSV 化）を CI ジョブにし、基準 TSV をリポジトリ管理、閾値超過（例: ±10%）で fail。PR サマリに差分表示（rustc-perf の最小構成）。完了条件: CI ジョブ green + 基準 TSV コミット + 意図的回帰で fail することの確認記録。
- [ ] ARCH-027: macOS CI レーンを最低 1 本追加する。現状 CI は ubuntu のみで、`docs/spec.md` が宣言する一次プラットフォーム macOS を何も検証していない（diff スクリプトに macOS 専用の配慮が既に複数あるのに、である）。最小構成: build + SmokeTests + LinkPhase 系。完了条件: macos runner ジョブ green。
- [ ] ARCH-028: bundled stdlib 注入コストの計測定義を修正する。`Scripts/measure_bundled_stdlib_injection.sh` と `docs/refactoring-metrics.md` の「+100ms トリガー」は **Lex+Parse の bundled 小計（36ms）だけ**を注入コストと定義しており、実測 ~3.9s/release（Sema/KIR/Lowering/Codegen の stdlib 再処理）が計測基準の盲点に落ちている — 現定義では本当に問題なコストに対して構造的に発火し得ない。定義を「`--no-stdlib` との全フェーズ差分」へ変更し、`docs/refactoring-metrics.md` と stdlib-pipeline.md §7 の基準値・トリガー値を更新する。完了条件: スクリプト + 両 doc 更新 + 新定義での実測値記録。
- [ ] ARCH-029: `.kklib` metadata の遅延読込。ARCH-005 後は `metadata.bin` の eager 全量デシリアライズ + 合成スタブ登録で **Sema 664ms/回（release 実測）が全コンパイルの新たな支配項**になる。rustc rmeta / K2 stub 方式に倣い、metadata.bin を「FQName → オフセット索引 + 本体」の 2 部構成にして名前解決要求時にデシリアライズする。完了条件: `.kklib` 経路 hello.kt の Sema フェーズ前後値記載（目標 1/3 以下）+ `Lib*Metadata*Tests` green + G。前提: ARCH-005。

### ARCH Tier 3: 診断 UX と小粒フォローアップ

- [ ] ARCH-031: `Diagnostic.secondaryRanges` を実配線する。フィールドは存在するが**全 13 構築サイトが空配列を渡し、レンダラも読まない**。型不一致（期待型の由来位置）とオーバーロード曖昧（候補宣言位置）の 2 診断から詰め、テキスト/JSON 両レンダラで表示する。完了条件: 該当診断の golden 更新 + `rg 'secondaryRanges: \[\]' Sources/CompilerCore` の件数減少を PR 本文に記載 + G。
- [ ] ARCH-032: `DiagnosticCodeAction` に TextEdit ペイロードを追加し LSP quick-fix を成立させる。現状 codeActions は title+kind のみで**適用可能な編集を持たない**ラベル。`edits: [(range, newText)]` を追加し、LSPServer の codeAction ハンドラへ貫通、代表 2 診断（未使用 import 削除・`@Suppress` 追加等）で実装。完了条件: LSPServerTests で edit 適用結果を固定 + G。
