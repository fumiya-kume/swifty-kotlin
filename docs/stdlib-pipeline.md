# Stdlib ソースパイプライン設計 (RF-STDLIB-001)

Kotlin ソースで stdlib を実装するための設計メモ。TODO.md の Phase RF2（Stdlib ソースパイプライン基盤）
および M1–M17（モジュール別移行）の共通指針とする。

関連: [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) / [`docs/stdlib-fiction-audit.md`](stdlib-fiction-audit.md) /
[`docs/runtime-abi-external-link-validation-gaps.md`](runtime-abi-external-link-validation-gaps.md)

## 1. 目的とゴール

**ゴール**: stdlib の純ロジック（イテレーション・変換・比較・整形等）を Kotlin ソースとして実装し、
コンパイラ（Swift）側は「言語コア + ランタイムブリッジ」だけを持つ状態にする。

- `HeaderHelpers+Synthetic*`（規模は `Scripts/loc_report.sh` の `header_helpers_synthetic_total_lines` が正。
  2026-07-06 時点で 121 ファイル / 約8.2万行）を、(a) 削除・(b) Kotlin 移行・(c) 真の組込残留の
  3分類（§9）に沿って縮減する
- 挙動の正は **kotlinc 2.3.10**。`Scripts/diff_kotlinc.sh` を回帰 oracle とする
- ランタイム ABI 表面を「ユーザーコードから直接呼ばれる `kk_*`」から
  「stdlib Kotlin 層だけが呼ぶ `__kk_*` ブリッジ」へ縮小する

**非ゴール**:

- GC・メモリ管理・boxing・coroutine 機構・型メタデータ・プラットフォーム I/O の Kotlin 化（Swift ランタイムに残留）
- klib 相当のバイナリ配布形式の設計（§7 の測定結果が閾値を超えるまで着手しない）

## 2. 現状 (as-is)

stdlib 実装は 3 系統に分散している。

| 系統 | 場所 | 規模 | 状態 |
|---|---|---|---|
| 合成スタブ (Swift) | `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift` | 121 ファイル / ~8.2万行 (2026-07-06) | 主力。Sema 時に宣言登録し `kk_*` へ直結 |
| バンドル Kotlin ソース | `Sources/CompilerCore/Stdlib/kotlin/**/*.kt` | 25 ファイル / ~2,500 行 (2026-07-06) | `LoadSourcesPhase` が `__bundled_*.kt` として注入（RF-STDLIB-002 済） |
| インライン Kotlin 文字列 | `Sources/CompilerCore/Driver/BundledKotlinStdlib.swift` | ~550 行 | residual。§6 で廃止対象 |

補足:

- 除外リスト機構（`BundledStdlib.excludedBundledStdlibFiles`）は「.kt は存在するが未配線」の
  暫定措置として存在していたが、エントリが 0 件になった時点で KSP-505 が機構ごと撤廃した。
  `Stdlib/kotlin/**/*.kt` 配下に置いた `.kt` は現在すべて無条件で配線される
- ルート `Stdlib/kotlin/` に死蔵 .kt が残っている（RF-HYG-003/004 参照）。§6 の単一ツリーへ統合する
- ランタイムは `@_cdecl` 関数 ~2,900 個（2026-07-06 実測。`grep -rhoE '@_cdecl\("kk_[a-zA-Z0-9_]+"\)' Sources/Runtime --include='*.swift' | sort -u | wc -l`）、署名は `RuntimeABISpec`（specVersion 管理）で宣言

## 3. あるべき姿 (to-be): 3層モデル

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: 純 Kotlin 層（stdlib の大半）                     │
│   HOF・String 操作・コレクションロジック・Range・Comparator 等│
│   Sources/CompilerCore/Stdlib/kotlin/**/*.kt              │
├─────────────────────────────────────────────────────────┤
│ Layer 2: ブリッジ宣言層（Kotlin で宣言・実体はランタイム）      │
│   @KsSymbolName("__kk_...") internal external fun ...     │
├─────────────────────────────────────────────────────────┤
│ Layer 3: Swift ランタイム層（最小コア）                      │
│   GC・alloc・boxing・coroutine 機構・型メタデータ・OS I/O     │
│   Sources/Runtime/ + RuntimeABISpec                       │
└─────────────────────────────────────────────────────────┘
```

責務の線引き（TODO.md「移行方針」を具体化）:

- **Kotlin のみ**: 他の stdlib API とブリッジ関数の組み合わせで書ける純ロジック全部
- **ブリッジ委譲**: OS/ハードウェアアクセス、メモリ表現に触る操作（文字列の生バイト、配列の生領域）、
  性能上ネイティブ実装が必須なホットパス（実測で判断）
- **Swift 残留（(c) 群）**: `Any`/プリミティブ型/`Nothing` など言語コアの組込宣言、GC・coroutine 機構

## 4. 読み込みフェーズ

`LoadSourcesPhase`（実装済・RF-STDLIB-002）の仕様を確定する。

1. ユーザー入力 (`ctx.options.inputs`) の検証後、`injectBundledStdlib` が
   `Bundle.module/Stdlib/**/*.kt` を列挙し、**相対パスの辞書順**で `sourceManager` に登録する
2. 登録パスは `__bundled_{modulePath}.kt` 形式。ユーザー入力と診断上区別でき、
   fileID 順序が決定的になる（golden 安定性の前提。§8）
3. `Sources/KSwiftKCLI/CLIParser.swift` の `--no-stdlib` で `CompilerOptions.includeStdlib` を false にし、注入全体を opt-out できる（コンパイラ自身のデバッグ用）
4. ~~`excludedBundledStdlibFiles` は縦切り移行（§10）の完了ごとにエントリを削除し、最終的に撤廃する~~ **完了（KSP-505）**: エントリが 0 件になったため機構ごと撤廃済み

**不変条件**: bundled ソースはユーザーソースより先に fileID を確保する。
ユーザーコードの有無で stdlib 側のシンボル ID・診断順序が変わってはならない。

## 5. 宣言の優先規則 (RF-STDLIB-003)

移行期間中は「Kotlin ソース由来の宣言」と「合成スタブ」が同一 API に対して共存しうる。
規則は一箇所（合成スタブ登録のエントリポイント）で実装する:

1. **Kotlin ソース > 合成スタブ**。bundled ソースに同シグネチャの宣言が存在する場合、
   合成スタブ登録をスキップする
2. スキップ判定は「レシーバ型 FQName + メンバ名 + アリティ」単位。オーバーロード集合の一部だけ
   Kotlin 化された状態を許容する（ただし縦切り PR では原則オーバーロード集合ごと移行する）
3. 双方が登録されてしまう二重定義はバグとして **warning 診断**（`KSWIFTK-SEMA-` 系コード採番）で検知する
4. スタブの存置は「Kotlin 版が配線されるまで」。配線 PR と同一 PR でスタブを削除する（§10）。
   長期共存させるフォールバックは作らない

`CallTypeChecker` / `CallLowerer` の名前文字列ベース特殊処理（RF4 系）も同じ優先規則に従う:
Kotlin ソースに実体がある呼び出しは通常の関数解決・KIR 展開に乗せ、専用 lowering を経由させない。

## 6. ソース配置とブリッジ宣言規約

### 配置

- **単一ツリー**: `Sources/CompilerCore/Stdlib/kotlin/`（`Bundle.module` で読める唯一の場所）。
  ルート `Stdlib/kotlin/` の死蔵ファイルは移行時にここへ統合し、ルート側は削除する
- **パッケージ構造は kotlin-stdlib 本家準拠**: `kotlin/text/`, `kotlin/collections/`,
  `kotlin/sequences/`, `kotlin/ranges/`, `kotlin/comparisons/`, ...
- **ファイル名も本家へ収斂させる**: 新規・移行時は本家のファイル名（例: `text/Strings.kt`,
  `collections/Collections.kt`）に寄せる。既存の機能スライス名（`ListFilterHOF.kt` 等)は
  当該モジュールの M フェーズ完了時に統合・リネームする
- `BundledKotlinStdlib.swift` のインライン文字列 4 本は対応する .kt ファイルへ移設し、廃止する

### ブリッジ宣言（external + 注釈）

ランタイム依存点は Kotlin ソース内で宣言する。Kotlin/Native の `@SymbolName` に倣い、
KSwiftK 内部注釈 `@KsSymbolName` を導入する:

```kotlin
package kotlin.text

@KsSymbolName("__kk_string_from_utf8")
internal external fun __stringFromUtf8(bytes: ByteArray, offset: Int, length: Int): String

public fun ByteArray.decodeToString(): String = __stringFromUtf8(this, 0, size)
```

規約:

- 注釈は `kotlin.internal` パッケージに置き、**stdlib ソース外（ユーザーコード）での使用はエラー**とする
- ブリッジ関数は `internal external fun`。シンボル名は `__kk_` prefix、宣言側 Kotlin 関数名は
  `__` prefix（ユーザー補完・公開 API 面に出さない）
- パーサは `external` 修飾子を受理済み（`KotlinParser+Utilities.swift`）。Sema は
  `@KsSymbolName` を externalLinkName として記録し、KIR/Codegen は既存の外部呼び出し経路をそのまま使う
- **ABI 突合を機械化する**: 「stdlib ソース中の全 `@KsSymbolName` 値が `RuntimeABISpec` に宣言され、
  型署名が一致する」ことをテストで enforcing にする。これにより
  `runtime-abi-external-link-validation-gaps.md` の検証ギャップは注釈⇔Spec の突合に一本化される

### `kk_*` → `__kk_*` の縮小

- 既存 `kk_*` 関数は、対応 API の Kotlin 移行時に (i) Kotlin 実装に置換して**削除**、または
  (ii) ブリッジとして**`__kk_*` へ改名・降格**（stdlib 内部からのみ参照）のどちらかにする
- `RuntimeABISpec` は最終的に「ブリッジ + 言語コア（GC/boxing/coroutine/メタデータ）」のみを宣言する。
  specVersion は縮小のたびに更新する

### ライセンス表記（本家移植部品）

`Sources/CompilerCore/Stdlib/kotlin/` 以下のうち、kotlin-stdlib 本家
（`https://github.com/JetBrains/kotlin` の `libraries/stdlib/src/` 以下）から
コード・構造・定数値を移植したファイルは、Apache License, Version 2.0 に基づく
帰属ヘッダをファイル先頭に付ける。

```kotlin
/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/...>.
 */
```

- 移植元パスとファイル名を可能な限り明記する。
- 本家からの移植でない KSwiftK 独自実装（MIGRATION コメントで Swift Runtime から
  移行したもの等）にはこのヘッダを付けない。
- リポジトリルートに `NOTICE` を置き、本プロジェクトが kotlin-stdlib 由来のコードを
  含むことを記載する。

## 7. コンパイル時間戦略とキャッシュ

方針: 通常の executable ユーザーコンパイルは事前コンパイル済み `.kklib` を既定経路にし、
`--stdlib-from-source` を明示したデバッグ実行だけが bundled Kotlin source を注入する。
`diff_kotlinc.sh` は shard ごとに stdlib を事前ビルドし、全 candidate compile から共有する。
移行効果は計測で確認し、基準を満たさない場合は CI の切り替えを完了扱いにしない。

`kswiftc` の既定artifact解決は次の順序で行う。

1. `KSWIFTK_STDLIB_LIBRARY`、実行ファイル相対の `KSwiftKStdlib.kklib`、SwiftPM resource bundle
   (`KSwiftK_CompilerCore.bundle/Contents/Resources` または `KSwiftK_CompilerCore.resources`)、または
   `<prefix>/lib/kswiftk/stdlib/KSwiftKStdlib.kklib` を検証する。
2. packaged artifact が見つからない場合は、target・compiler version・bundled source hash
   ごとに標準ユーザーcache（macOS は `~/Library/Caches`、Linux は `~/.cache`）へ
   `stdlib-only` build を一度だけ生成する。生成中はcross-process lockを保持し、完成後にatomic moveする。
3. manifest、metadata、object、inline-KIR、target、stdlib hash の不一致は source injection へ
   暗黙に落とさず、明確な診断で停止する。互換性のある packaged artifact がない場合は cache を再生成する。

既定artifactは `emit == executable` に限定する。`object`、`llvm`、`kir` は source/introspection
境界を保持し、LSPのartifact配線は ARCH-006 で扱う。`--stdlib-from-source` は既定artifactの
発見・生成を無効化し、従来の bundled source 経路を明示的に選択する。

`diff_kotlinc.sh` では、shard 内で `kswiftc --stdlib-only --emit library` によって1 回だけ stdlib を `.kklib` 化し、
各ケースを `--no-stdlib --stdlib-library <artifact>` で共有する。artifact は実行時に `DIFF_ARTIFACT_ROOT`
（デフォルト `.artifacts/diff_kotlinc`）配下に生成され、リポジトリにはコミットしない。これにより
case あたりの stdlib 再コンパイルを回避する。

1. 現状 (~2,300 行) は毎回フロントエンドに乗せる。`PhaseTimer` で
   「bundled stdlib 由来の Lex/Parse/Sema 時間」を分離計測できるようにする（RF-STDLIB-006）
2. 計測ゲート: stdlib 注入によるコンパイル時間の増分が **hello.kt 相当の小入力で +100ms** を超えたら
   キャッシュ着手のトリガーとする（[`docs/refactoring-metrics.md`](refactoring-metrics.md) で正式化済み:
   ベースライン中央値 36.05ms、トリガー = 中央値 ≥ 136.05ms）
3. `diff_kotlinc.sh` では `.kklib` 共有を使い、PoC ケースの candidate compile 合計/中央値を baseline 比 50% 以上、
   full shard wall time を baseline 比 20% 以上削減できない場合は CI 切り替えを完了扱いにしない。
4. キャッシュの段階案（トリガー後に選択）:
   - **案 A: pre-parse キャッシュ** — コンパイラビルド時に bundled .kt をトークン列/AST へ
     シリアライズし同梱（`IncrementalCompilationCache` の仕組みを流用）。実装コスト小
   - **案 B: Sema 済みシンボルテーブルの同梱**（klib 的方向）。効果最大だが
     シリアライズ形式の設計・golden への影響が大きい。stdlib が数万行規模になるまで保留
5. ユーザー側の `IncrementalCompilationCache` に対しては、bundled ソースは
   「コンパイラバージョンにのみ依存する固定入力」として扱い、ユーザー入力の変更で再検証しない

> 補足: 並行メモが提案していた別基準（Smoke 相当の入力で wall-clock 15%未満 or 200ms未満）との
> すり合わせは決着済み。実測に基づき上記 +100ms トリガーを採用した（`docs/refactoring-metrics.md`）。

## 8. golden / diff_kotlinc への影響 (RF-STDLIB-007)

- golden（Lexer/Parser/Sema/Diagnostics）は **ユーザー入力ファイルのみ**を対象とし、
  `__bundled_*` 由来のトークン・AST・診断はダンプに含めない（既にパス名で判別可能）
- ただし Sema golden のシンボル ID は bundled ソースの宣言数に影響される。
  §4 の決定的順序（辞書順・ユーザーより先）を不変条件とし、stdlib 変更時は
  `UPDATE_GOLDEN=1` での一括更新を許容する（更新 diff が機械的であることを PR でレビュー）
- stdlib ソース自身に diagnostics が出る状態はコンパイラのバグとして扱う
  （warning 含めゼロを CI で enforcing にする）
- `diff_kotlinc.sh`: 移行した各 API に対応する diff ケースを `Scripts/diff_cases/` に**必ず追加**する。
  kotlinc と意図的に挙動を変えない限り `// SKIP-DIFF` は使わない

実装ステータス（2026-07-06）:

- `LoadSourcesPhase` は bundled / residual stdlib sources を `__bundled_*` path の辞書順に登録し、
  `Tests/CompilerCoreTests/Driver/BundledStdlibOrderingTests.swift` が「bundled がユーザー入力より先」
  と「bundled 同士が辞書順」を固定している
- Sema golden は `Sources/GoldenHarnessSupport/GoldenHarnessDump.swift` で bundled declSite symbols を
  除外し、`rg '__bundled_' Tests/CompilerCoreTests/GoldenCases` が 0 件になる状態を維持する
- Diagnostics golden / CLI diagnostics は `DiagnosticEngine.render` / `renderJSON` が source location、
  severity、code、message で render 時ソートする
- `Scripts/diff_kotlinc.sh` は `find | sort` の case discovery、interleaved sharding、parallel worker logs の
  input-order replay で report / console output の順序を安定化している

## 9. 合成スタブ 3 分類棚卸し (RF-STUB-001)

分類基準:

| 分類 | 基準 | 出口 |
|---|---|---|
| (a) 削除 | JS/Wasm/JVM 固有など KSwiftK のターゲット外、または架空 API（fiction audit 参照） | CLEANUP-STUB-001〜084 で登録呼び出しごと削除 |
| (b) Kotlin 移行 | 純ロジックで Kotlin + ブリッジで書ける | M1–M17 の縦切りで .kt 化しスタブ削除 |
| (c) 組込残留 | `Any`/プリミティブ/`Nothing`/演算子・言語コア、GC/coroutine 機構と不可分 | RF-STUB-003 の宣言テーブル化で残留 |

全 `HeaderHelpers+Synthetic*` ファイルの (a)/(b)/(c) 分類表（2026-07-02 時点、`DUMP_SURFACE=1` の
fiction audit ダンプを起点に棚卸し）:

| File | Lines | Bucket | Owner / next action |
|---|---:|:---:|---|
| `HeaderHelpers+SyntheticArrayStubs.swift` | 2043 | (c)→(b) | KSP-657 で `arrayOf`/`emptyArray`/`arrayOfNulls` を `Stdlib/kotlin/ArrayIntrinsics.kt` へ b-reclass 済み（第1弾）。primitive-array factory / HOF は後続バッチ。 |
| `HeaderHelpers+SyntheticAtomicArrayStubs.swift` | 622 | (b) | `AtomicMigration.kt` owner; `AtomicIntArray`/`AtomicLongArray`/`AtomicArray<T>` + `atomicArrayOf(Nulls)` factories (KSP-695 split). |
| `HeaderHelpers+SyntheticAtomicNativePtrStubs.swift` | 136 | (b) | `AtomicNativePtr`; built on shared NativeConcurrent helpers, may reclassify independently of the rest of the Atomic family (KSP-695 split). |
| `HeaderHelpers+SyntheticAtomicPackageStubs.swift` | 148 | (b) | `kotlin.concurrent.atomics` package scaffolding: `@ExperimentalAtomicApi`, `MemoryOrder` enum, type aliases (KSP-695 split). |
| `HeaderHelpers+SyntheticAtomicRegistrationHelpers.swift` | 325 | (b) | Shared constructor/member/property registration primitives used across the scalar and array families (KSP-695 split). |
| `HeaderHelpers+SyntheticAtomicScalarStubs.swift` | 306 | (b) | `AtomicInt`/`AtomicLong`/`AtomicBoolean`/`AtomicReference<T>`, plus `java.util.concurrent.atomic.AtomicInteger` — a live, tested direct-construction surface sharing the `kk_atomic_int_create` box and retained Java compatibility members, not a target-out cleanup pocket (KSP-695 split; KSP-696 scalar public wrappers are source-backed). |
| `HeaderHelpers+SyntheticAtomicResidualRegistry.swift` | 295 | (b) | Residual Atomic orchestration after KSP-696 removed `HeaderHelpers+SyntheticAtomicStubs.swift`: arrays, package metadata/type aliases, NativePtr, Java compatibility, and shared synthetic nominal shells remain registered here. |
| `HeaderHelpers+SyntheticBase64Stubs.swift` | 830 | (b) | MIGRATION-ENC owner; Kotlin source exists but public stubs still dispatch directly. |
| `HeaderHelpers+SyntheticBuilderDSLStubs.swift` | 414 | (b) | M3 collection builder source migration. |
| `HeaderHelpers+SyntheticCInteropStubs.swift` | 3065 | (c) | Kotlin/Native interop compiler/runtime surface; table-driven residual candidate. |
| `HeaderHelpers+SyntheticCharStubs.swift` | 889 | (c) | Primitive `Char` shell plus helpers; RF-STUB-003 declarative residual registration started here. |
| `HeaderHelpers+SyntheticClockStubs.swift` | 174 | (c) | KSP-712 reclassified: `Clock.now()` remains a hidden runtime dispatch bridge and `Clock.System` bootstrap anchor; public `Clock.System.now()` is bundled Kotlin source. |
| `HeaderHelpers+SyntheticCloseableStubs.swift` | 277 | (b) | `Closeable`/`use` common surface; move to Kotlin source before deleting. |
| `HeaderHelpers+SyntheticCoercionStubs.swift` | 654 | (b)+(c) | KSP-1531 numeric conversion classification; range/coercion source migration is tracked separately. |
| `HeaderHelpers+SyntheticCollectionFactoryStubs.swift` | 92 | (b) | KSP-627 で typealias 4 + `LinkedHashSet` を `Stdlib/kotlin/collections/CollectionAliases.kt` へ移行済み（旧 `+SyntheticCollectionTypeAliases.swift`、272行）。残るのは factory 関数の bootstrap stub のみ。 |
| `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` | 845 | (c) | KSP-701/KSP-665 の分離先（`HeaderHelpers+SyntheticIterableRegistry.swift` 削除時と `+SyntheticStringTypeHelpers.swift` 削除時の残存 fallback shell が合流）。呼び出し元は `+SyntheticComparableAndCollectionStubs.swift`（KSP-700 対象）の `registerSyntheticCollectionStubs` のみ。`AbstractCollection`/`AbstractMutableCollection`/`MutableIterable` の型登録は bundled Kotlin source を再利用する fallback 専用で対応不要。`Collection`/`MutableCollection`/`Iterable`/`Iterator`/`MutableIterator` の型シェルと `isEmpty`/`contains`/`add`系/`iterator`/`hasNext`/`next` メンバは、List/Set/Iterator の runtime box が itable に自己登録しないため virtual dispatch を bypass する目的の bridge（`Collections.kt` の KSP-435 コメント、本ファイル内 BUG-166 コメント参照）で (c) 残置。`random`/`randomOrNull` は KSP-1509 が降格予定の `kk_list_random`/`kk_list_randomOrNull` と同一ブリッジを共有。次アクション: KSP-1542。 |
| `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift` | 631 | (b) | Core collection/comparable shells; source migration owner, with residual type hooks. |
| `HeaderHelpers+SyntheticComparableHelpers.swift` | 168 | (c) | Helper-only file for residual comparable registration. |
| `HeaderHelpers+SyntheticComparatorStubs.swift` | 1446 | (b) | M5 comparisons/comparator source migration. |
| `HeaderHelpers+SyntheticComparisonStubs.swift` | 157 | (b) | **完了・ファイル削除済み**（KSP-684）。トップレベル `maxWith`/`minWith` は `Stdlib/kotlin/comparisons/Comparisons.kt` へ移行し、残る比較ヘルパーは source-backed または Comparator anchor 側で管理する。 |
| `HeaderHelpers+SyntheticCoroutineRegistry.swift` | 3552 | (c) | RF-STUB-005 consolidated coroutine package, ABI, and helper registry. |
| `HeaderHelpers+SyntheticDeepRecursiveStubs.swift` | 324 | (b) | ~~Public stdlib surface; source migration before removal.~~ **完了・ファイル削除済み**（KSP-612, `Stdlib/kotlin/DeepRecursive.kt`）。 |
| `HeaderHelpers+SyntheticDurationStubs.swift` | 1390 | (b) | M8 duration source migration; bridge-only `__kk_*` declarations may remain private. |
| `HeaderHelpers+SyntheticDynamicStubs.swift` | 101 | (a) | ~~Kotlin/JS `dynamic`; cleanup candidate.~~ **削除済み** (CLEANUP-STUB-106). |
| `HeaderHelpers+SyntheticEnumStubs.swift` | 474 | (c) | Enum compiler surface. |
| `HeaderHelpers+SyntheticExceptionStubs.swift` | 787 | (c) | Core exception shells required by diagnostics/lowering; RF-STUB-003 declarative residual registration started here. |
| `HeaderHelpers+SyntheticExperimentalBitwiseStubs.swift` | 99 | (b) | Experimental bitwise stdlib helpers; source migration owner. |
| `HeaderHelpers+SyntheticExperimentalMarkerStubs.swift` | 367 | (c) | Common opt-in markers stay; split JS/Wasm markers into (a) cleanup first. |
| `HeaderHelpers+SyntheticExperimentalTimeStubs.swift` | 463 | (c) | KSP-712 reclassified: `ExperimentalTime` metadata plus TimeSource/TimeMark nominal anchors and fallback dispatch remain compiler/runtime surfaces; public operations are bundled Kotlin source. |
| `HeaderHelpers+SyntheticFileTreeWalkStubs.swift` | 291 | (a) | JVM file-walk compatibility; cleanup candidate. |
| `HeaderHelpers+SyntheticFileWalkDirectionStubs.swift` | 113 | (a) | ~~JVM file-walk support enum; cleanup with file-walk surface.~~ **削除済み** (CLEANUP-STUB-109, 2026-08-14)。 |
| `HeaderHelpers+SyntheticFilesUtilityStubs.swift` | ~~520~~ | ~~(a)~~ | ~~`java.nio.file` / files utility surface; target-out cleanup.~~ **削除済み** (CLEANUP-STUB-110, 2026-09-03)。`FileTime` の Path 共有部分は保持。 |
| `HeaderHelpers+SyntheticFunctionTypeStubs.swift` | 523 | (c) | Function interfaces are compiler-known. |
| `HeaderHelpers+SyntheticGroupingStubs.swift` | 373 | (b) | M3 grouping/HOF source migration. |
| `HeaderHelpers+SyntheticHexFormatStubs.swift` | 589 | (b) | MIGRATION-ENC owner; source exists but not fully wired. |
| `HeaderHelpers+SyntheticInstantStubs.swift` | 272 | (c) | KSP-712 reclassified: Instant.Companion bootstrap and hidden source bridges remain; Instant public properties, arithmetic, comparison, and factories are bundled Kotlin source, while handle/OS-clock core remains runtime-owned. |
| `HeaderHelpers+SyntheticIterableRegistry.swift` | deleted | (c) | **完了・ファイル削除済み**（KSP-701）。Iterable の `filter`/`reduce*`、既存の plus/minus・sumBy* は bundled Kotlin source を正規実装として利用。Collection/Sequence の fallback shell は `HeaderHelpers+SyntheticCollectionTypeFallbacks.swift` と `HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift` に分離。 |
| `HeaderHelpers+SyntheticIteratorStubs.swift` | 272 | (c) | Iterator and primitive iterator compiler surface; RF-STUB-003 declarative residual registration started here. |
| `HeaderHelpers+SyntheticJsAnyStubs.swift` | 25 | (a) | ~~Kotlin/JS surface; cleanup candidate.~~ **削除済み** (CLEANUP-STUB-127/128, 2026-08-19)。`JsAny` の synthetic 登録と2つの登録経路を除去。 |
| `HeaderHelpers+SyntheticJsArrayExternalClassStubs.swift` | 80 | (a) | Kotlin/JS surface; cleanup candidate. |
| `HeaderHelpers+SyntheticJsArrayStubs.swift` | 71 | (a) | Kotlin/JS surface; cleanup candidate. |
| `HeaderHelpers+SyntheticJsNumberStubs.swift` | 117 | (a) | ~~Kotlin/JS number bridge; cleanup candidate.~~ **削除済み** (CLEANUP-STUB-127/128, 2026-08-19)。`JsNumber` synthetic Sema surface と stale RuntimeABI spec を除去。 |
| `HeaderHelpers+SyntheticJsStringInteropStubs.swift` | 183 | (a) | Kotlin/JS string interop; cleanup candidate. |
| `HeaderHelpers+SyntheticKotlinAnnotationStubs.swift` | 790 | (c) | Core annotation and opt-in metadata surface. |
| `HeaderHelpers+SyntheticKotlinIOExceptionStubs.swift` | 133 | (b) | `kotlin.io` exception shell; source/runtime migration owner. |
| `HeaderHelpers+SyntheticKotlinVersionStubs.swift` | 372 | (b) | Public stdlib value surface; source migration owner. |
| `HeaderHelpers+SyntheticListAggregateMembers.swift` | 1288 | (b) | M3 list aggregate/source migration. |
| `HeaderHelpers+SyntheticListConversionMembers.swift` | 434 | (b) | M3 list conversion/source migration. |
| `HeaderHelpers+SyntheticListIndexedAndArrayDequeStubs.swift` | deleted | (b) | **完了・ファイル削除済み**（KSP-702。`IndexedValue`/`withIndex` は `collections/Iterators.kt`、`ArrayDeque` は KSP-625 で source-backed 化済み）。 |
| `HeaderHelpers+SyntheticListStubs.swift` | 1967 | (b) | M3 list shell and member migration. |
| `HeaderHelpers+SyntheticListTransformMembers.swift` | 797 | (b) | M3 list transform/source migration. |
| `HeaderHelpers+SyntheticLocaleConstructorStubs.swift` | 401 | (a) | ~~`java.util.Locale`/locale interop~~ **完了・ファイル削除済み**（CLEANUP-STUB-112）。`Locale` コンストラクタのみ `+SyntheticStringStubs.swift` に残し、locale 付き String/Char 演算のハンドルとして使う。 |
| `HeaderHelpers+SyntheticMapStubs.swift` | 1255 | (b) | M3 map shell and HOF source migration. |
| `HeaderHelpers+SyntheticMathStubs.swift` | 953 | (b) | Math stdlib source migration, with numeric primitive hooks. |
| `HeaderHelpers+SyntheticMetadataAnnotations.swift` | 15 | (c) | Metadata helper surface. |
| `HeaderHelpers+SyntheticMetaprogAnnotationHelpers.swift` | 953 | (c) | Annotation infrastructure; split JVM-only annotations into (a) before table migration. |
| `HeaderHelpers+SyntheticMutableCollectionArrayAddAll.swift` | 109 | (b) | M3 mutable collection helper source migration. |
| `HeaderHelpers+SyntheticMutableCollectionIterableAddAll.swift` | 104 | (b) | M3 mutable collection helper source migration. |
| `HeaderHelpers+SyntheticMutableCollectionSequenceAddAll.swift` | 101 | (b) | M3/M4 mutable collection helper source migration. |
| `HeaderHelpers+SyntheticMutableListStubs.swift` | 1549 | (b) | M3 mutable list shell and member migration. |
| `HeaderHelpers+SyntheticNativeConcurrentCommon.swift` | 736 | (c) | RF-STUB-004 shared NativeConcurrent helper body. |
| `HeaderHelpers+SyntheticNativeConcurrentRegistry.swift` | 2715 | (c) | RF-STUB-004 consolidated NativeConcurrent registration table and entry point. |
| `HeaderHelpers+SyntheticNativeDataStubs.swift` | 821 | (c) | Native data/runtime support; declarative residual candidate. |
| `HeaderHelpers+SyntheticNativeFunctionAnnotationStubs.swift` | 85 | (a) | `kotlin.js.nativeGetter/nativeSetter/nativeInvoke`; cleanup candidate. |
| `HeaderHelpers+SyntheticNativeInteropHelpers.swift` | 1292 | (c) | Kotlin/Native interop helper surface; table-driven residual candidate. |
| `HeaderHelpers+SyntheticNativeInteropStubs.swift` | 386 | (c) | Kotlin/Native interop annotations/types. |
| `HeaderHelpers+SyntheticNativeRefRuntimeStubs.swift` | 759 | (c) | Native ref runtime support; constructor/member/property surface moved to `SyntheticStubSurfaceSpec+NativeRefRuntime.swift` for RF-STUB-003. |
| `HeaderHelpers+SyntheticOnErrorActionStubs.swift` | 120 | (a) | ~~File-tree walk support; cleanup with file-walk surface.~~ **完了・ファイル削除済み**（CLEANUP-STUB-114, 2026-08-14）。OnErrorAction は synthetic enum / 登録以外に参照がなく、`copyRecursively` の既存 FileIO bridge は保持。 |
| `HeaderHelpers+SyntheticPairTripleStubs.swift` | 409 | (b) | Public `Pair`/`Triple` source migration candidate. |
| `HeaderHelpers+SyntheticPathStubs+GenericFunctionRegistration.swift` | 548 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup with path surface. |
| `HeaderHelpers+SyntheticPathStubs+SymbolRegistration.swift` | 488 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup with path surface. |
| `HeaderHelpers+SyntheticPathStubs.swift` | 2102 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup candidate. |
| `HeaderHelpers+SyntheticBucketedStubRegistry.swift` | 325 | (a/b/c) | RF-STUB-006 bucketed registry for delegate and former ExtendedStdlib calls. |
| `HeaderHelpers+SyntheticPlatformObjectHelpers.swift` | 216 | (a) | Java class/platform object helpers; cleanup unless needed by residual annotations. |
| `HeaderHelpers+SyntheticPlatformTimeConversionStubs.swift` | 260 | (a) | ~~JVM/JS platform time conversion; cleanup candidate.~~ **削除済み** (CLEANUP-STUB-126, 2026-08-18)。JVM `java.time` / `java.util.concurrent.TimeUnit` interop を target-out として除去。 |
| `HeaderHelpers+SyntheticPreconditionStubs.swift` | deleted | (b) | ~~`check`/`require`/`error` source migration.~~ **完了・ファイル削除済み**（KSP-707, 2026-08-18）。`require`/`check`/`error` は `Stdlib/kotlin/Preconditions.kt` の source 実装のみで提供。`require`/`check`/`assert` の smart-cast 用 `ContractNonNullEffect` 付与ロジック（`patchSourceBackedPreconditionContractEffects`）は `HeaderHelpers.swift` へ移設。 |
| `HeaderHelpers+SyntheticPropertyDelegateStubs.swift` | 2564 | (c) | Delegation and reflection scaffolding; declarative residual candidate. |
| `HeaderHelpers+SyntheticRandomStubs.swift` | 1147 | (b) | M7 random source migration; split Java random interop pockets into (a). |
| `HeaderHelpers+SyntheticRangeInterfaceStubs.swift` | 382 | (b) | M6 range interfaces/source migration. |
| `HeaderHelpers+SyntheticRangeProgressionStubs.swift` | 1116 | (b) | M6 range/progression source migration. |
| `HeaderHelpers+SyntheticRangeUntilStubs.swift` | 142 | (b) | M6 `..<`/`rangeUntil` source migration. |
| `HeaderHelpers+SyntheticReadWriteLockStubs.swift` | 216 | (a) | JVM-style lock compatibility; cleanup or move behind explicit platform bridge. |
| `HeaderHelpers+SyntheticRegexStubs.swift` | deleted | (b) | ~~Regex public stdlib source migration candidate.~~ **完了・ファイル削除済み**（KSP-1521, 2026-08-23）。`MatchResult` / `Destructured` の nominal anchor は bundled Kotlin source に統合し、engine bridge は保持。 |
| `HeaderHelpers+SyntheticResultStubs.swift` | 584 | (b) | ~~M13 `Result` source migration~~ **完了・ファイル削除済み**（KSP-304, PR #4566, 2026-07-08）。 |
| `HeaderHelpers+SyntheticScopeFunctionStubs.swift` | deleted | (b) | `run`/`with`/`apply`/`let`/`also`/`takeIf`/`takeUnless` は bundled `kotlin/Standard.kt` へ移行済み。`use`/`usePinned`/`useContents` は compiler residual として別経路に残る。`context`/`contextOf` は KSP-603 で `Stdlib/kotlin/ContextParameters.kt` へ移行済み。 |
| `HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift` | 1463 | (b) | M4 sequence registration helper surface. |
| `HeaderHelpers+SyntheticSequenceTerminalStubs.swift` | deleted | (b) | **完了・ファイル削除済み**（KSP-694）。KSP-441〜446/KSP-308 での Kotlin 化に伴い不要スタブを削除、未移行の純残余（`random`/`randomOrNull`/`forEach`/`forEachIndexed`/`firstNotNullOf`/`firstNotNullOfOrNull`/`takeLast`/`takeLastWhile`/`shuffled`/`reversed`/`filterIsInstance`）は `+SyntheticSequenceResidualStubs.swift`（419行）へ移行。 |
| `HeaderHelpers+SyntheticSequenceResidualStubs.swift` | 419 | (b) | M4 sequence residual stubs (`random`, `randomOrNull`, `forEach`, `forEachIndexed`, `firstNotNullOf`, `firstNotNullOfOrNull`, `takeLast`, `takeLastWhile`, `shuffled`, `reversed`, `filterIsInstance`). |
| `HeaderHelpers+SyntheticSerializationStubs.swift` | 850 | (a) | ~~`kotlinx.serialization` compatibility~~ **完了・ファイル削除済み**（CLEANUP-STUB-121, 2026-08-06）。target-out として Runtime/ABI ともに除去。 |
| `HeaderHelpers+SyntheticSetStubs.swift` | 1068 | (b) | M3 set shell and HOF source migration. |
| `HeaderHelpers+SyntheticStdlibLoopStubs.swift` | 88 | (b) | ~~`repeat` source migration~~ **完了・ファイル削除済み**（KSP-604、`Stdlib/kotlin/Standard.kt`）。 |
| `HeaderHelpers+SyntheticStringBuilderStubs.swift` | 629 | (b) | M2 StringBuilder source migration; source exists. |
| `HeaderHelpers+SyntheticStringRegistrationHelpers.swift` | 475 | (b) | M1 string helper registration. |
| `HeaderHelpers+SyntheticStringStubs.swift` | 4180 | (b) | M1 string source migration; bridge-only `__kk_*` declarations may remain private. |
| `HeaderHelpers+SyntheticStringTypeHelpers.swift` | 299 | (c) | ~~String type scaffolding and helper utilities.~~ **完了・ファイル削除済み**（KSP-665）。残存する collection type fallback は `+SyntheticCollectionTypeFallbacks.swift` に分離。 |
| `HeaderHelpers+SyntheticTODOAndIOStubs.swift` | 3698 | (b) | Mixed TODO, IO, system, duration, collection factories; `HeaderHelpers+SyntheticFileIOStubs.swift` を統合済み。 |
| `HeaderHelpers+SyntheticTestStubs.swift` | 178 | (a) | `kotlin.test` test-only compatibility; cleanup outside production stdlib. |
| `HeaderHelpers+SyntheticThreadLocalStubs.swift` | 215 | (c) | Native/thread-local annotation support. |
| `HeaderHelpers+SyntheticTypedRangeStubs.swift` | 1090 | (b) | M6 typed range source migration. |
| `HeaderHelpers+SyntheticURIStubs.swift` | 178 | (a) | ~~`java.net.URI`; cleanup candidate.~~ **削除済み** (CLEANUP-STUB-123, 2026-08-14)。公開 URI surface と Path/URL の URI 変換を除去し、Network の HTTP request builder handoff は保持。 |
| `HeaderHelpers+SyntheticURLStubs.swift` | 332 | (a) | ~~`java.net.URL`; cleanup candidate.~~ **削除済み** (CLEANUP-STUB-124, 2026-08-14)。公開 URL surface と URL runtime/ABI exports を除去し、Network の HTTP request builder handoff は保持。 |
| `HeaderHelpers+SyntheticUnsignedRangeStubs.swift` | 561 | (b) | M6 unsigned range source migration. |
| `HeaderHelpers+SyntheticUuidStubs.swift` | 888 | (b) | M12 UUID source migration; source exists. |
| `HeaderHelpers+SyntheticW3CDomStubs.swift` | 78 | (a) | Kotlin/JS DOM surface; cleanup candidate. |

KSP-712 time-surface audit confirms that these three files no longer own public
stdlib logic: their remaining registrations are (c) nominal/bootstrap fallback
or hidden runtime/interface-dispatch support. In particular, removing the
`kk_instant_*`/`kk_clock_*`/`kk_time_source_*` names by string match would break
Instant handle access, OS monotonic time, `TimeSource.asClock()` boxes, or
user-implementable `Clock` itables. The public source-backed declarations and
these retained bridges are covered by the KSP-712 focused regressions.

Mixed files are assigned to the bucket that owns most of the file today. The
notes column calls out sub-blocks that should be split before the final delete or
table migration.

#### KSP-1531: primitive numeric conversion classification (2026-08-23)

KSP-1531 fixes the classification boundary only; it does not change compiler,
runtime, or ABI code. The current public numeric-member bridge surface is 70
symbols: 68 ordinary numeric `@_cdecl` symbols plus the two member conversion
bit bridges `kk_int_to_double_bits` and `kk_float_to_double_bits`. The Runtime
and RuntimeABI sets are equal for this 70-symbol surface. The synthetic file has
39 registrations, which collapse to 32 of those public symbols plus the
synthetic-only identity `kk_int_to_int` (also present only as an ABI-parity
entry). Unsigned receiver registrations are reached through the primitive
conversion lowerer and the corresponding Runtime/ABI entries, not through that
synthetic file.

The reason codes are:

- `C-WIDTH`: compiler-owned fixed-width sign/zero extension, truncation, or
  representation-preserving integer conversion. The current KIR has no typed
  numeric-cast instruction, so these cases still appear as runtime calls or
  copies; `(c)` records the future single-instruction compiler owner rather
  than claiming that migration has already happened.
- `C-FP`: compiler-owned ordinary integer-to-Float/Double or Float-to-Double
  numeric conversion. The current Runtime implementation encodes the result
  for the raw-bit KIR/ABI representation, but it does not add Kotlin-specific
  saturation, NaN handling, or rounding policy.
- `B-CHAR`: Kotlin `Char` code-unit semantics, including the UInt16 narrowing
  and code-value conversions.
- `B-FP-SAT`: Kotlin Float/Double NaN, infinity, range clamp, and truncation
  semantics for integral targets.
- `B-FP-ABI`: IEEE payload/bit transport or Float/Double representation and
  boxing boundary for an explicit bit-representation bridge. Ordinary numeric
  FP conversion remains `C-FP`; a short runtime body is not sufficient to make
  a representation bridge `(c)`.

<!-- KSP-1531-SYMBOLS-BEGIN -->
| Receiver | (c) compiler-residual symbols | (b) stdlib-semantics symbols | Reason | Follow-up owner |
|---|---|---|---|---|
| `Int` | `kk_int_to_byte`, `kk_int_to_float`, `kk_int_to_long`, `kk_int_to_short`, `kk_int_to_ubyte`, `kk_int_to_uint`, `kk_int_to_ulong`, `kk_int_to_ushort` | `kk_int_to_char`, `kk_int_to_double_bits` | `C-WIDTH`; `C-FP`; `B-CHAR`; `B-FP-ABI` | KSP-1536 |
| `Long` | `kk_long_to_byte`, `kk_long_to_double`, `kk_long_to_float`, `kk_long_to_int`, `kk_long_to_short`, `kk_long_to_ubyte`, `kk_long_to_uint`, `kk_long_to_ulong`, `kk_long_to_ushort` | `kk_long_to_char` | `C-WIDTH`; `C-FP`; `B-CHAR` | KSP-1537 |
| `UInt` | `kk_uint_to_byte`, `kk_uint_to_double`, `kk_uint_to_float`, `kk_uint_to_int`, `kk_uint_to_long`, `kk_uint_to_short`, `kk_uint_to_ubyte`, `kk_uint_to_ulong`, `kk_uint_to_ushort` | `kk_uint_to_char` | `C-WIDTH`; `C-FP`; `B-CHAR` | KSP-1532 |
| `ULong` | `kk_ulong_to_byte`, `kk_ulong_to_double`, `kk_ulong_to_float`, `kk_ulong_to_int`, `kk_ulong_to_short`, `kk_ulong_to_ubyte`, `kk_ulong_to_ushort` | `kk_ulong_to_char` | `C-WIDTH`; `C-FP`; `B-CHAR` | KSP-1533 |
| `UByte` | `kk_ubyte_to_byte`, `kk_ubyte_to_double`, `kk_ubyte_to_float`, `kk_ubyte_to_int`, `kk_ubyte_to_long`, `kk_ubyte_to_short`, `kk_ubyte_to_uint`, `kk_ubyte_to_ulong`, `kk_ubyte_to_ushort` | `kk_ubyte_to_char` | `C-WIDTH`; `C-FP`; `B-CHAR` | KSP-1534 |
| `UShort` | `kk_ushort_to_byte`, `kk_ushort_to_double`, `kk_ushort_to_float`, `kk_ushort_to_int`, `kk_ushort_to_long`, `kk_ushort_to_short`, `kk_ushort_to_ubyte`, `kk_ushort_to_uint`, `kk_ushort_to_ulong` | `kk_ushort_to_char` | `C-WIDTH`; `C-FP`; `B-CHAR` | KSP-1535 |
| `Float` | — | `kk_float_to_char`, `kk_float_to_int`, `kk_float_to_long`, `kk_float_to_double_bits` | `B-CHAR`; `B-FP-SAT`; `B-FP-ABI` | KSP-1538 |
| `Double` | `kk_double_to_float` | `kk_double_to_char`, `kk_double_to_int`, `kk_double_to_long` | `C-FP`; `B-CHAR`; `B-FP-SAT` | KSP-1538 |
| `Char` | — | `kk_char_to_int`, `kk_char_to_long`, `kk_char_to_uint`, `kk_char_to_ulong` | `B-CHAR` | KSP-1539 |
<!-- KSP-1531-SYMBOLS-END -->

The table is grounded in the current implementations. `RuntimeNumericCoercion`
uses fixed-width truncating or representation-preserving operations for the
integer `(c)` group, while its Char and floating-to-Char paths implement code
unit narrowing, NaN/negative handling, upper clamping, and truncation.
`RuntimeNumericCompat` implements floating-to-integral NaN/infinity clamping
and truncation, and its ordinary Float/Double paths encode and decode IEEE
payloads only for the current raw-bit ABI representation. The explicit
`*_to_double_bits` member bridges are classified separately as `B-FP-ABI`.
The bundled `float.kt` and `double.kt` implementations already own
Float/Double-to-UInt/ULong saturation semantics, so those two source-backed API
pairs have no current `kk_float_to_uint`/`kk_float_to_ulong` or
`kk_double_to_uint`/`kk_double_to_ulong` symbol and are not residual bridge
rows.

`CallTypeChecker+MemberCallInferenceRegularPrimitiveSpecials.swift` recognizes
the ordinary primitive conversion targets, with `toChar` fast-path coverage
limited to signed integer receivers. `CallLowerer+LegacyMemberLikeCalls.swift`
`CallLowerer+SafeMemberCalls.swift`, and the top-level route in `CallLowerer.swift`
contain 68 explicit conversion-symbol cases; `kk_float_to_char` and
`kk_double_to_char` are resolved through the registered normal member-call path.
These lowerers otherwise emit KIR `.call`
or representation-preserving `.copy`; `KIRInstruction` currently has no typed
numeric-cast case. Existing `CoercionRuntimeTests` and
`RuntimeMathEdgeCaseTests` cover the wrap, truncation, Char, NaN, infinity, and
precision boundaries used by this classification.

The following adjacent surfaces are intentionally excluded from the 70-symbol
set: the six Byte/Short receiver-only runtime bridges in
`RuntimeABISpec+RuntimeOnlyBridge.swift`, `kk_float_to_bits`/
`kk_double_to_bits`, operator-promotion helper `kk_int_to_float_bits`, and the
erased `Number` conversion route owned by KSP-1540. `ULong.toUInt()` and
`ULong.toLong()` are representation-preserving lowerer copies and have no
dedicated `kk_ulong_to_uint`/`kk_ulong_to_long` symbol. The synthetic-only
`kk_int_to_int` is an identity registration and is not a migration target.

Enforcing evidence was collected mechanically from the current tree: the
classification marker contains 70 unique symbols; Runtime `@_cdecl` ordinary
conversion symbols plus the two member bit bridges contain the same 70; the
RuntimeABI NumericConversion/BridgeCoverage union contains the same 70; and
the lowerer inventory contains 68 explicit names plus the two normal-call
Char fallbacks. The synthetic inventory contains 39 registrations / 33 unique
external names, with 32 public symbols plus `kk_int_to_int`. TODO ID
uniqueness, `Scripts/check_todo_ids.sh`, `git diff --check`, and docs marker
set checks are part of this PR. Build, full test, Golden, kotlinc diff, and
runtime ABI execution are intentionally not run because this task changes only
`TODO.md` and this documentation table.

### RF-STUB-002 reference cleanup recipe

`CLEANUP-STUB-033/034` already removed the old PlatformAndJS phase file. RF-STUB-006
now routes the central delegate sequence and the remaining former ExtendedStdlib calls
through `HeaderHelpers+SyntheticBucketedStubRegistry.swift`, where entries are tagged
as (a)/(b)/(c) while preserving historical registration order. The remaining (a) work
should follow the same shape:

1. Remove the registration call from `registerSyntheticDelegateStubs` or the
   relevant phase batch.
2. Delete the stub file, or split the file first if only some declarations are
   target-out.
3. Delete matching `RuntimeABISpec` entries and runtime `@_cdecl` implementations
   that are no longer emitted.
4. Delete Swift tests and `.golden` expectations that only prove the removed
   target-out surface.
5. Run focused Sema/runtime tests for the touched surface, then run golden
   regeneration only for affected cases.
6. Update `docs/stdlib-fiction-audit.md` with the new synthetic symbol count
   when a phase-sized cleanup lands.

### Follow-up order

1. Small (a) deletions with direct central calls are complete:
   `SyntheticJsAnyStubs`, `SyntheticJsNumberStubs` (CLEANUP-STUB-127/128).
2. Split mixed files before touching their residual parts:
   `SyntheticExperimentalMarkerStubs`, `SyntheticMetaprogAnnotationHelpers`,
   `SyntheticRandomStubs`, `SyntheticTODOAndIOStubs`.
   `SyntheticAtomicStubs` split complete (KSP-695), and its obsolete entrypoint
   was removed by KSP-696: see the responsibility-specific Atomic rows above.
3. After RF-STDLIB-003, migrate one narrow (b) slice end-to-end and use it as the
   template for the remaining M1-M17 rows.
4. Continue RF-STUB-003 residual table migration only on files classified (c); do not table-drive code
   that is already scheduled for deletion or Kotlin source migration. `SyntheticNativeRefRuntimeSurfaceSpec`
   is the current reference pattern for residual constructor/member/property tables.

### KSP-498: `kotlin.coroutines` / Flow / Channel の (c)/(b) 分類確定

対象は `HeaderHelpers+SyntheticCoroutineRegistry.swift`（上表で (c) 一括計上済み）が橋渡しする Runtime 実装。
1ファイルに (b) 候補と (c) 確定が混在するため、上表のファイル単位より一段細かいシンボル系統単位で分類する。
**本節はコード変更を含まない**（棚卸しと分類の記録のみ）。

#### 対象 Runtime ファイル（2026-07-08 時点で再計測）

| File | Lines | `kk_*` 関数数 | 主な内容 |
|---|---:|---:|---|
| `RuntimeCoroutine.swift` | 3159 | 65 | suspend/continuation、builder (`kxmini_*`)、Job、`coroutineScope`/`supervisorScope` の内部プリミティブ、timing、context の一部 |
| `RuntimeCoroutineContext.swift` | 726 | 18 | `CoroutineContext`、`Dispatchers`、`ExceptionHandler`、`ContinuationInterceptor` |
| `RuntimeCoroutineChannel.swift` | 656 | 10 | `Channel` 全操作 |
| `RuntimeCoroutineFlow.swift` | 1971 | 33 | `Flow`/`SharedFlow`/`StateFlow` |
| `RuntimeAtomic.swift` | 1550 | 91 | `AtomicInt`/`AtomicLong`/`AtomicBoolean`/`AtomicReference`（配列版含む） |
| `RuntimeSync.swift` | 489 | 16 | `Mutex`/`Semaphore`/`ReadWriteLock` |
| `RuntimeGC.swift`（該当関数のみ） | 15（うち対象2） | 2 | coroutine root の GC 登録・解除 |

6ファイル計 233 関数 + `RuntimeGC.swift` の該当2関数でファイル数は 6+1 = **7**（TODO.md の「7 ファイル」に一致）。
関数総数「279」は 2026-07-01 棚卸し時点の値で、その後の dead code 削除（例: `kk_java_atomic_int_asKotlinAtomic`
削除（CLEANUP-STUB-024, #4409）、test-only dead code 削除 #4478）により減少している。以降の数値は本節時点の実測を正とする。

#### スタブ（Sema 宣言）側の現状

TODO.md の「23 スタブファイル」も同じく 2026-07-01 時点の値。2026-07-06 の RF-STUB-005（#4544, commit `8e05a7cd6`）で
`HeaderHelpers+SyntheticCoroutineHelpers.swift`・`HeaderHelpers+SyntheticCoroutinesStubs.swift` 等の分割ファイルが
`HeaderHelpers+SyntheticCoroutineRegistry.swift`（3552 行、上表で (c) 計上済み）へ統合された。`Mutex`/`Semaphore`/
`Channel`/`Flow`/`SharedFlow`/`StateFlow` の宣言は現在すべてこの1ファイルに集約されている。`Atomic` 系宣言は
`HeaderHelpers+SyntheticAtomic*.swift` の責務別ファイル群へ分離され、KSP-696 で旧オーケストレータ
`HeaderHelpers+SyntheticAtomicStubs.swift` は削除された。
**KSP-499 以降が触るスタブファイルはこの2つのみ**（棚卸し時点の分割ファイル群は現存しない）。

#### (c) 残留（`__kk_` 降格のみ）— 118 関数

| 系統 | 代表シンボル | 数 | ファイル |
|---|---|---:|---|
| suspend 機構・continuation | `kk_suspend_coroutine`, `kk_coroutine_suspended`, `kk_coroutine_continuation_{context,factory,new,resume,resume_with,resume_with_exception}`, `kk_coroutine_state_{enter,exit,get_completion,get_spill,get_thrown_exception,set_completion,set_label,set_spill}`, `kk_create_coroutine_unintercepted`, `kk_start_coroutine_unintercepted_or_return`, `kk_continuation_intercepted`, `kk_continuation_interceptor_intercept_continuation`, `kk_exception_handler_{new,create,invoke}`, `kk_is_cancellation_exception` | 24 | Coroutine / Context |
| builder・Job・構造化並行の内部プリミティブ | `kk_kxmini_{launch,launch_with_cont,launch_with_dispatcher,launch_with_dispatcher_and_cont,launch_with_exception_handler,async,async_await,async_with_cont,run_blocking,run_blocking_with_cont,produce_with_cont}`, `kk_produce`, `kk_job_{join,await_completion,cancel,cancel_with_cause,complete,complete_exceptionally,is_active,is_cancelled,is_completed,is_failed}`, `kk_coroutine_scope_*`(8), `kk_supervisor_scope_*`(3), `kk_coroutine_launcher_arg_{get,set}` | 35 | Coroutine |
| Channel | `kk_channel_{send,receive,is_closed_token}` | 3 | Channel（suspension コア。KSP-678 で残り 7 関数は `Stdlib/kotlin/coroutines/channels/Channels.kt` の (b) ブリッジへ移行。`kk_channel_{create,close,is_closed_for_send,is_closed_for_receive,iterator,iterator_hasNext,iterator_next}` は runtime を残しつつ `@KsSymbolName` ブリッジ経由に降格） |
| timing | `kk_kxmini_delay`, `kk_with_timeout`, `kk_with_timeout_or_null`, `kk_coroutine_yield` | 4 | Coroutine |
| 同期プリミティブ（カーネルコア c-soft 残留） | `kk_mutex_lock`, `kk_mutex_unlock`, `kk_semaphore_acquire`, `kk_semaphore_release` | 4 | Sync | KSP-677 再監査で (b) 9 関数を分離（下記）。ReadWriteLock は CLEANUP-STUB-120 で削除。 |
| context | `kk_context_*`(9), `kk_coroutine_name_{create,get}`, `kk_dispatcher_{default,io,main}`, `kk_with_context{,_full}`, `kk_coroutine_{current_context,cancel,cancel_current,check_cancellation}` | 20 | Context / Coroutine |
| Flow ブリッジ（cold Flow の最小核） | `kk_flow_create`, `kk_flow_emit`, `kk_flow_collect` | 3 | Flow |
| sequence / iterator builder | `__kk_sequence_builder_{yield,yieldAll,build,build_coro}`, `__kk_iterator_builder_{build,build_coro,yield,hasNext,next,hasNext_coro,next_coro}` | 11 | Sequence |
| （参考・別系統だが同性質）GC root 登録 | `kk_register_coroutine_root`, `kk_unregister_coroutine_root` | 2 | GC |

##### 同期プリミティブ 再監査記録（KSP-677, 2026-07-24）

当初の棚卸しは Mutex/Semaphore/Lock/ReadWriteLock の同期系 16 関数をすべて (c) に計上していたが、KSP-677 で再監査し
**(b) 9 / c-soft コア 4 / (a) cleanup 候補 1** に分離した。ReadWriteLock の c-soft コア 2 つは後続の CLEANUP-STUB-120 で削除。ラッパー層（factory・accessor・try・`withLock`/`withPermit`）は
純ロジックで、c-soft カーネルプリミティブ（lock/unlock・acquire/release）の合成として Kotlin source で表現できる。

- **(b) Kotlin 移行済み（9）** — `Sources/CompilerCore/Stdlib/kotlinx/coroutines/sync/Sync.kt` および
  `Sources/CompilerCore/Stdlib/kotlin/concurrent/Lock.kt`:
  - Mutex: `Mutex()`（旧 `kk_mutex_create`）, `Mutex.isLocked`（旧 `kk_mutex_isLocked`）, `Mutex.tryLock`（旧 `kk_mutex_tryLock`）, `Mutex.withLock`（旧 `kk_mutex_withLock`）
  - Semaphore: `Semaphore(permits)`（旧 `kk_semaphore_create`）, `Semaphore.availablePermits`（旧 `kk_semaphore_availablePermits`）, `Semaphore.tryAcquire`（旧 `kk_semaphore_tryAcquire`）, `Semaphore.withPermit`（旧 `kk_semaphore_withPermit`）
  - Lock: `Lock.withLock`（旧 `kk_lock_withLock`）
  - factory/accessor/try 系は demoted `__kk_*` bridge へ委譲（`__kk_mutex_create` 等）。`withLock`/`withPermit` は
    canonical generic `suspend fun <T> ...(action: () -> T): T` で lock/unlock・acquire/release を try/finally 合成し、
    専用 runtime entry（`kk_mutex_withLock`/`kk_semaphore_withPermit`）は削除。`Lock.withLock` は general closure ABI の
    `__kk_lock_withLock` bridge（fnPtr + closure env + `outThrown`）へ委譲する。
- **c-soft コア残留（4）**: `kk_mutex_lock`, `kk_mutex_unlock`, `kk_semaphore_acquire`, `kk_semaphore_release`。
  ReadWriteLock は CLEANUP-STUB-120 で削除済み。
- **(a) cleanup 済み**: 未使用重複だった `kk_reentrant_read_write_lock_new`（`HeaderHelpers+SyntheticReadWriteLockStubs.swift` の
  コンストラクタ登録・Runtime 実体・ABI 登録）は CLEANUP-STUB-100 で削除済み。CLEANUP-STUB-120 で `ReentrantReadWriteLock`
  関連の残り（`kk_read_write_lock_create`/`read`/`write` および合成スタブ・ABI 登録・TypeChecker/KIR 特別処理）も削除済み。

移行に伴い generic 高階関数 `fun <T> f(action: () -> T): T` が Unit 本体ラムダから `T` を推論できないコンパイラバグ
（`KSWIFTK-TYPE-0001`/`KSWIFTK-SEMA-0002`）を同 PR で修正した。ただし `launch { }` 本体からキャプチャ付き suspend 呼び出しを
行う経路は coroutine lowering の feature gap（`KSWIFTK-CORO-0003`, BUG-049）が残るため、`Scripts/diff_cases/coroutine_mutex_semaphore.kt`
は引き続き SKIP-DIFF（DEBT-DIFF-003）。

#### (b) 候補と KSP-499 完了結果 — 103 関数 + 新規実装分

| 系統 | 代表シンボル | 数 | ファイル | 備考 |
|---|---|---:|---|---|
| Flow terminal（KSP-499 完了） | `__kk_flow_{to_list,first,single}` | 3 | Flow | `Flow.kt` の suspend source implementation が `collect` bridge を合成する。旧 Runtime entry は内部互換用に降格 |
| Flow terminal（KSP-499 完了） | `__kk_flow_{fold,reduce,count}` | 3 | Flow | bundled Kotlin source に実装し、旧 Runtime entry は `__kk_*` に降格 |
| Flow 合成（KSP-499 完了） | `__kk_flow_{merge,zip,combine,flat_map_concat,flat_map_latest,flat_map_merge}` | 6 | Flow | bundled Kotlin source に実装し、旧 Runtime entry は `__kk_*` に降格 |
| Atomic 全般 | `kk_atomic_{int,long,bool,ref}_*`（scalar + 配列 `*At`） | 91 | Atomic | 詳細は下記 |
| `coroutineScope`/`supervisorScope`（公開ラッパー） | ― | 新規 | ― | 内部は (c) の `kk_coroutine_scope_*`/`kk_supervisor_scope_*` へ委譲する薄い Kotlin 関数にする。primitives 自体は (c) のまま |
| Flow per-element（KSP-499 完了） | `map`/`filter`/`take`/`debounce` | 4 | `Stdlib/kotlinx/coroutines/flow/Flow.kt` | `collect`+`emit` 合成の bundled Kotlin implementation |

KSP-499 の (c)/(b) 境界は `kk_flow_create` / `kk_flow_emit` / `kk_flow_collect` の3 public bridgeに固定した。
`collectLatest`、lifetime、timestamp、および旧 terminal/composition Runtime entry は `__kk_*` internal compatibility bridge として残し、
bundled declaration が存在する operator call を name/provenance intrinsic rewrite が横取りしないことを
`LoweringFlowCodegenTests.testBundledFlowOperatorsWinOverIntrinsicRewrite` で固定した。

現時点の `RuntimeCoroutineFlow.swift` の Flow surface は `@_cdecl` 20件で、public bridge は `kk_flow_create` /
`kk_flow_emit` / `kk_flow_collect` の3件、残る17件（stop/timestamp/collectLatest/lifetime、旧 terminal/composition）は
`__kk_*` internal compatibility bridge である。

**Flow (b) 移行の前提条件（KSP-499 で解決）**: `Sources/CompilerCore/Lowering/CoroutineLoweringPass+Flow.swift`
の `lowerFlowExpressions` は `map`/`filter`/`take`/`transform`/`single`/`takeWhile`/`dropWhile`/`flatMapConcat`/`flatMapMerge`/
`flatMapLatest`/`combine`/`zip`/`merge`/`buffer`/`conflate`/`flowOn`/`debounce`/`sample`/`delayEach`/`catch`/`retry`/`retryWhen`/
`onErrorReturn`/`onErrorResume`/`toList`/`first` の呼び出しを、**Sema が解決した callee symbol を参照せず**、
「レシーバが flow 由来の式かどうか（`flowExprIDs`/`flowGlobalSymbols` による provenance 追跡）」+「呼び出し名の文字列一致」
だけで `kk_flow_*` へ KIR 構造的に書き換える。したがって、これらの名前を持つ Kotlin 実装を bundled stdlib に追加しても
**Lowering 段階で無条件に上書きされ、呼ばれない**（`FlowLoweringNames` 構造体・その初期化コードに列挙された名前が対象）。
Flow terminal/合成を (b) 化するには、このパスを「対象シンボルが `kk_flow_*` 系の合成スタブ由来と確認できる場合のみ」に
絞るか、対象名を初期化リストから外す変更が**同一 PR で必須**（`docs/stdlib-pipeline.md` の他モジュールで確立している
「.kt を書いて stub/cdecl を消せば移行完了」という Template T はここでは通用しない）。着手前に必ずダミー実装の
差し替えテスト（例: `suspend fun <T> Flow<T>.toList(): List<T> = listOf()` を bundle し、実際の `flowOf(1,2,3).toList()`
の戻り値がダミーの空リストになるかを確認）で再検証すること。

上記の未解決判定は着手前の履歴であり、KSP-499 では解決済みである。現在の lowering は、Sema が解決した
source-backed/bundled declaration を保持し、未解決または synthetic bridge の場合だけ `__kk_*` intrinsic に書き換える。
`Flow.kt` の `map`/`filter`/`toList`/`first`/`fold`/`reduce` が name/provenance rewrite に横取りされないことは、
`LoweringFlowCodegenTests.testBundledFlowOperatorsWinOverIntrinsicRewrite` で固定した。

Atomic の内訳:

- **委譲パターン適用済み**: `get`/`set`/`getAndSet`/`incrementAndGet`/`decrementAndGet`/`addAndGet` に加えて、KSP-671/KSP-688 で
  `fetchAndAdd`/`fetchAndIncrement`/`fetchAndDecrement`（reverse 変種）と `compareAndSet`（`AtomicInt`/`AtomicLong`/`AtomicBoolean`/`AtomicReference`）を
  `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicMigration.kt` で Kotlin 化済み。reverse 変種は
  `addAndFetch`/`incrementAndFetch`/`decrementAndFetch` に、`compareAndSet` は `compareAndExchange` に委譲する。
  `AtomicReference` は Kotlin API の契約どおり参照同一性（`===`）で委譲結果を判定する。
  委譲先の `__kk_atomic_{int,long,ref}_{load,store,exchange,incrementAndFetch,decrementAndFetch,addAndFetch,compareAndExchange}` と
  `__kk_atomic_bool_{load,store,exchange,compareAndExchange}` は (c) の内部ブリッジ。`kk_atomic_int_create` と
  `kk_atomic_int_compareAndSet` は `java.util.concurrent.atomic.AtomicInteger` の直接構築サーフェスと共有する互換経路として保持し、
  scalar core の `__kk_*` 降格とは分離する。ただし KSP-672 で member-call / indexed access 解決が
  bundled 拡張を atomic レシーバに限り解決できるようになったため、これらの bundled 委譲ソースは休眠ではなく
  **live**（重複合成スタブは登録スキップされ、`isRuntimeBackedAtomicSyntheticRetainedOverlap` による保持は廃止）。KSP-688 では
  `AtomicBoolean`/`AtomicReference` の `compareAndSet` synthetic stub と `kk_atomic_bool/ref_compareAndSet` 公開経路を削除し、
  `compareAndExchange` の CAS コアだけを残した。KSP-696 では scalar 4型の `compareAndExchange`/lambda 更新系も source-backed 化し、
  旧オーケストレータを削除した。配列 `*At`、NativePtr、package alias、Java互換、hardware CAS/arithmetic coreは残存対象である。
- **残存**: 配列 `*At` の未移行メンバと、上記の互換・共有基盤。`while(true)` CAS loop の `Nothing` 型付けは KSP-CAP-004 で非回帰を確認済み。

#### 未分類・KSP-499 着手前に個別判断が必要な項目 — 18 関数

指示された分類に直接対応がない `RuntimeCoroutineFlow.swift` の残り:

- **SharedFlow/StateFlow（hot flow）**: `kk_mutable_shared_flow_{create,emit,try_emit}`, `kk_mutable_state_flow_{create,emit,try_emit}`,
  `kk_shared_flow_{collect,replay_cache}`, `kk_state_flow_value`, `kk_flow_{share_in,state_in,stopped,release,retain}`（計14関数）。
  replay buffer・購読者管理を伴い Channel に近い可能性があり (c) 寄りと推測するが要検証。
  **KSP-675 で SharedFlow 側は (b) 確定**: `SharedFlow`/`MutableSharedFlow`/`Flow.shareIn` を bundled Kotlin source
  （`Stdlib/kotlinx/coroutines/flow/SharedFlow.kt`）へ移行し、replay buffer と eviction を `MutableList` 上の Kotlin
  状態遷移として表現。`kk_mutable_shared_flow_{create,emit,try_emit}` と `kk_flow_share_in` を削除。
  **KSP-676 で StateFlow 側も (b) 確定**: `StateFlow`/`MutableStateFlow`/`Flow.stateIn` を bundled Kotlin source
  （`Stdlib/kotlinx/coroutines/flow/StateFlow.kt`）へ移行。実装は `MutableList` を使った単一値 replay buffer
  上の Kotlin 状態遷移。`StateFlow` は独立インターフェースとして定義し、`MutableStateFlow` が
  `value` / `replayCache` / `collect` / `tryEmit` / `emit` を実装する。
  `kk_mutable_state_flow_{create,emit,try_emit}` / `kk_state_flow_value` / `kk_flow_state_in` を削除。
  `__kk_flow_stopped` / `__kk_flow_emit_with_timestamp` / `__kk_flow_release` / `__kk_flow_retain` は (c) internal compatibility bridge として残留。
- **Flow builder**: `kk_flow_{as_flow,empty,of}`（計3関数）。`kk_flow_create` + `kk_flow_emit` の合成で (b) 化できる
  可能性が高い。`channelFlow`/`callbackFlow` は KSP-686 で (a)（未実装 API）に分類した。最小実測では real API 形の
  `channelFlow { send(1) }` が `KSWIFTK-SEMA-0023: Unresolved function 'send'`、
  `callbackFlow { trySend(1); close() }` が `trySend`/`close` 未解決で止まり、実装済みの `emit` alias だけが `kk_flow_create`
  経由で動作した（両者とも `1` を出力）。そのため合成 Flow 宣言・Flow/Coroutine lowering 特例・未実装 ABI allowlist を削除し、
  fiction を通常の未解決 API として明示した。real `ProducerScope` 実装は別タスクで設計する。
- `__kk_flow_emit_with_timestamp`（1関数）: 用途未確認。将来の `debounce`/`sample` 系実装が必要とする可能性があるため
  KSP-499 後も internal compatibility bridge として保持

## 10. モジュール移行プレイブック

各 M フェーズ（および RF-STDLIB-004/005 の縦切り）は同一手順で回す。
**完了条件は「.kt 実配線 + 合成スタブ削除 + runtime 関数削除または `__kk_*` 降格」**（RF-STDLIB-008）。

1. 対象 API の diff ケースを `Scripts/diff_cases/` に追加し、現行実装で green を確認する（挙動の固定）
2. `.kt` を書く（配置・命名は §6）。ランタイム依存点は `@KsSymbolName` ブリッジで宣言する。
   `Sources/CompilerCore/Stdlib/kotlin/` 配下に置くだけで自動配線される（除外リスト機構は KSP-505 で撤廃済み）
3. 優先規則（§5）により Kotlin 版が解決されることを確認し、**同一 PR で**対応する
   合成スタブ・`CallTypeChecker`/`CallLowerer` の特殊処理・runtime `@_cdecl` を削除
   （または `__kk_*` へ降格）する
4. 必須ゲート（CLAUDE.md）: `swift_test.sh` 全体 / Golden / `diff_kotlinc.sh` green、
   `loc_report.sh` で `HeaderHelpers+Synthetic*` 行数と `"kk_` リテラル数の減少を確認する
5. TODO.md の該当タスクを更新する

進捗メトリクス = `loc_report.sh` の (i) `HeaderHelpers+Synthetic*` 合計行数、(ii) `"kk_` リテラル数、
(iii) `interner.resolve == "..."` 数。すべて単調減少がゲート。

## 11. 実装順序

| 順 | タスク | 内容 |
|---|---|---|
| 1 | RF-STDLIB-003 | 優先規則 + 二重定義 warning（§5） |
| 2 | RF-STDLIB-004 | 縦切り第1弾 `StringComparison.kt`（プレイブック §10 のテンプレート化） |
| 3 | RF-STDLIB-006/007 | PhaseTimer 計測（§7）+ golden 決定性の正規化（§8） |
| 4 | `@KsSymbolName` 導入 | ブリッジ注釈 + ABI 突合テスト（§6）。最初にブリッジが必要な縦切りと同時でよい |
| 5 | RF-STDLIB-005 | 縦切り第2弾 `StringSplitJoin.kt`（`kk_string_split*` の `__kk_*` 降格を含む） |
| 6 | RF-STUB-001 | 3分類棚卸し表を §9 に追記 → M1–M17 とCLEANUP-STUB を並列展開 |

## 12. 附録: 並行策定分の統合待ち事項

master 側 (#4483) でも同時期に同テーマの設計メモが独立に書かれていた（`docs/stdlib-pipeline.md` の
add/add コンフリクト）。本文（§1–11、§9 の棚卸し表を除く）と重複する記述は失わないよう本文へ統合済みだが、
以下は本文にない追加提案であり、レビューで採否・統合先を決めること。

> 2026-07-10 更新: 本節の各案は TODO.md でタスク化された — SourceManager origin = KSP-INF-008、
> 専用診断コード = KSP-INF-009、二重定義4象限 = KSP-INF-011、インクリメンタルキャッシュ = KSP-INF-002。

- ~~**コンパイル時間の許容閾値が §7 と異なる**~~: **決着済み**。RF-STDLIB-006 の実測
  （`docs/refactoring-metrics.md` の Bundled Stdlib Injection Cost）に基づき §7 の
  「+100ms トリガー」を正式採用した。
- **SourceManager の origin 概念**: ファイルパスの `__bundled_` prefix 判定だけに依存せず、
  `user` / `bundledStdlib` / `residualStdlib` の 3 値 origin を `SourceManager` に持たせる具体案
  （既存の prefix 判定は互換期間として残す）。golden・diagnostics のソートキーを
  「origin → normalized path → source offset → declaration stable key」の 4 段にする案も含む。
- **専用診断コード**: bundled stdlib の読み込み失敗を、ユーザー入力の `KSWIFTK-SOURCE-0002` とは別に
  `KSWIFTK-SOURCE-0101`（リソースディレクトリ不在）/ `KSWIFTK-SOURCE-0102`（読み込み失敗）として
  切り出す具体案。
- **二重定義の扱いの 4 象限（決着）**: `BundledDeclarationIndex` + `BundledSyntheticStubRegistration.shouldSkipRegistration` で一元化。
  1. **bundled stdlib source vs synthetic stub**: bundled source が存在する `(owner, name, arity)` に対する合成スタブは登録をスキップする（KSP-002 宣言優先規則）。ガード漏れは `KSWIFTK-SEMA-0102` で検出・警告する。
  2. **bundled stdlib source vs residual stdlib source**: 両方とも `SourceOrigin.isBundledStdlib` で収集される `BundledDeclarationIndex` の対象。同 key が衝突した場合は bundled source（`__bundled_*.kt`）を優先し、residual source は宣言面のフォールバックとする。
  3. **user source vs bundled stdlib source**: ユーザー入力が bundled source と同名・同 arity・同 receiver owner の拡張を定義した場合、ユーザー定義を優先する。合成スタブ登録前の `symbols.lookup(fqName:)` と `shouldSkipRegistration` の `receiverOwnerFQName` 解決により実現する。
  4. **user source vs synthetic stub**: ユーザー入力が synthetic stub と同じ member を定義した場合、ユーザー定義を優先する。各 `registerSyntheticXxx` は `symbols.lookup(fqName:)` が `nil` の場合のみ登録する。
  - **runtime-backed 互換ブリッジの例外**: `List`/`Iterable`/`Sequence` 等の一部 HOF・検索・sort・端末変換は、Kotlin 化 source があっても `kk_*` ABI 経由で呼ばれる移行期橋渡しとして合成スタブを残す。これらは `BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap` にホワイトリスト化し、`warnSyntheticOverlaps` では警告しない。`joinTo`/`joinToString` の transform overload も、arity では default overload と区別できないため function-typed パラメータ検出で false-positive を抑制する。
- **インクリメンタルキャッシュへの影響**: `IncrementalCompilationCache.computeCurrentFingerprints` に
  bundled/residual stdlib の virtual path + content hash を含める案、`IncrementalBuildConfiguration` へ
  stdlib source manifest hash・opt-out フラグを追加する案、stdlib fingerprint 変更時は当面
  full frontend rebuild に倒す方針。

## 13. 移行ガバナンス（2026-07-10 ギャップ監査で制定）

理想像の明確化: **stdlib は限りなく Pure Kotlin、Swift はコンパイラとしての機能提供に集中する**。
Swift に残ってよいのは (1) 言語コアの組込宣言（Any/Nothing/プリミティブ/演算子/関数型 invoke）、
(2) GC・alloc・boxing・coroutine continuation 機構・型メタデータレジストリ、(3) OS/ハードウェア syscall のみ。
「既に Swift ランタイムに実装があるから」「ロジックが複雑だから」は (c) 残留の理由にならない。

1. **完了 = enforcing**: タスクの完了条件は「enforcing テスト or rg チェックが存在して green」のみ。
   ドキュメント同期・部分検証での完了マークは禁止（教訓: KSP-008 の `--no-stdlib` デッドフラグ、
   KSP-103 のアリティのみ突合）。完了メモには検証コマンドと green 実績を必記する。
2. **ブリッジ入場審査と予算**: `__kk_*` を追加する PR は、理由コード
   （syscall / メモリ表現 / GC・continuation / メタデータ / 性能=実測値添付）+ `RuntimeABISpec` 登録 +
   specVersion 更新 + `__kk_*` 総数メトリクスの悪化理由を必須とする。
3. **性能エスケープハッチは実測必須**: ベンチ数値（KSP-INF-007 の基盤）を添付できない限り、
   性能を理由とした Swift 残留・(c) 分類を認めない。
4. **二重 oracle**: 移行タスクは diff_kotlinc ケースに加え、bundled .kt を実行して期待値比較する
   自己完結テスト（KSP-INF-006）を必須にする（テンプレート T 手順7）。
5. **Capability Matrix**: 言語機能ブロッカーは KSP-CAP-* として独立起票し、各移行タスクは必要 CAP を
   「前提」に宣言する。「〜が駄目なら中断」文言は CAP 参照へ置換する（ブロッカー先行の原則）。
6. **(c) 分類の理由コードと再審査**: (c) には理由コード（言語コア / 機構 / syscall / 性能）を付与し、
   RF-GOV-004 の四半期監査に (c) 再審査を統合する。c-soft（解除条件 = CAP ID）を正式ステータスとする。
   2026-07-10 再監査の結論: 旧 (c) 計上の4〜5割が最終的に (b) へ移動し、約2,800行 + cinterop 未配線外殻が
   削除候補（詳細は TODO.md の KSP-W6 / CLEANUP-STUB-096〜103）。
7. **移行完了の2点確認**（テンプレート T 手順6）: ①.kt 本体が実ロジック（`= this` 等のフェイク禁止 — 実例: `ranges/RangeCoercion.kt`）
   ②Sema/KIR/Lowering に同名の name-string 特例が残っていない。
   「bundled .kt が存在する = 移行済み」と誤読しないこと（除外リスト機構は KSP-505 で撤廃済みのため、配置しただけで無条件に配線される点に注意）。
8. **本家準拠度・逸脱台帳・ライセンス**: .kt は挙動だけでなく構造も本家 kotlin-stdlib 形を目標とする。
   コンパイラ制約による構造逸脱（例: KSP-466 Random の 1 クラス統合 — KSP-CAP-006 が解消条件）は
   本節配下に台帳化し、CAP 解消時に本家形へ戻す。本家からの移植ファイルには Apache 2.0 帰属ヘッダ +
   リポジトリ NOTICE を付ける（KSP-INF-013）。
9. **タスク運用**: 未完了タスクの削除禁止（`[x]` のみ削除可）。本文から参照される ID は必ず解決可能に保つ
   （M1–M17 / CLEANUP-STUB 個別リスト消失の教訓）。作業中に発見した修正可能なバグは、症状を再現する最小ケースと回帰テストを含めて同じPR内で修正する。
   同じPRのスコープや安全な修正方針を超える場合だけ、BUG-NNN として TODO.md に理由付きで追跡する（CLAUDE.md「バグ修正ルール」）。
10. **粒度**: 1 タスク = 1 PR。目安「削除対象 kk_* ≤ 15・単一責務・golden 更新1回」。
    超えると判明したら枝番でなく新番号で分割する。

### 構造逸脱台帳（§13-8）

| ファイル | 逸脱内容 | 本家形 | 解消条件 |
|---|---|---|---|
| `random/Random.kt` | 解消済み（`abstract class Random` + `internal class XorWowRandom` + トップレベル `fun Random(seed)` へ復元、PRNG ビット精度を KSP-685 で固定） | `abstract class Random` + `internal class XorWowRandom` + トップレベル `fun Random(seed)` | KSP-CAP-006（クラスと同名トップレベル関数の共存、解消済み）— KSP-685 完了 |
| `kotlin/Throws.kt` | 解消済み（`public annotation class Throws(public vararg val exceptionClasses: KClass<out Throwable>)` へ復元、合成登録を撤廃） | `annotation class Throws(vararg val exceptionClasses: KClass<out Throwable>)` | KSP-CAP-014（bundled source での `vararg val` プロパティと `KClass` 型参照の生成・検証、解消済み）|
| `uuid/Uuid.kt`（KSP-1502） | `generateV7()` の単調性カウンタを `AtomicLong` + CAS ループでなく plain `var`（`UuidV7MonotonicState`）で実装（スレッド安全性なし） | `private object UuidV7Generator` が `kotlin.concurrent.atomics.AtomicLong`（`@OptIn(ExperimentalAtomicApi::class)`）を CAS ループで使用 | `kotlin.concurrent.atomics.AtomicLong` の `load()`/`compareAndSet()` が実運用で動作検証され次第、本家形へ復元 |
| `uuid/Uuid.kt`（KSP-1502） | `generateV7()`/`generateV7NonMonotonicAt()` の乱数を専用 CSPRNG バイト列でなく既存 `random()`（`__kk_uuid_random` ブリッジ）の出力から抽出して転用 | `ByteArray(10)` を `secureRandomBytes()` で都度生成 | 新規ブリッジ追加が§13-2の入場審査コストに見合うと判断された場合（現状は不要と判断） |
