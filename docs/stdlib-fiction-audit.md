# stdlib 架空シンボル監査 (Fiction Audit)

KSwiftK の合成 stdlib サーフェスを **Kotlin 2.3.10 公式 stdlib 公開 API** と突き合わせ、
「Kotlin にも JDK にも実在しない（架空の）クラス/メソッド」を特定・除去するための監査記録。

## 監査方法

1. **参照元 (source of truth)**
   - JetBrains/kotlin `v2.3.10` タグの公開 API ダンプ
     `libraries/tools/binary-compatibility-validator/reference-public-api/kotlin-stdlib-runtime-merged.txt`
     （= kotlin-stdlib の全公開宣言を機械可読形式で列挙）。
   - プラットフォーム可用性の確認には [kotlinlang.org/api/core/kotlin-stdlib](https://kotlinlang.org/api/core/kotlin-stdlib/) を併用。
   - 注意: この `.api` ダンプは JVM ランタイムのもので、`Int`/`String`/`List` のような
     **コンパイラ組み込み型 / JVM マップ型は含まれない**。これらを架空と誤判定しないよう、
     既知の実在組み込み型は除外リストで補正した。

2. **登録サーフェスの抽出**
   - 監査用テスト `FictionAuditDumpTests`（`DUMP_SURFACE=1`）で、合成スタブ登録後の
     `SymbolTable` シンボル（FQName / 種別）をダンプ。初回監査時点の追跡 baseline は **6888**。

3. **差分と分類**
   - 登録サーフェス ∖ 公式 API を計算し、`kotlin.native/js/wasm/cinterop` など
     JVM ダンプが網羅しないパッケージを除外したうえで残差を人手検証。

## サーフェスの内訳（初回 baseline: 合成シンボル数・パッケージルート別）

- `kotlin.*`: 5354
- `java.*`: 526（`java.io` 124 / `java.net` 102 / `java.util` 86 / `java.security` 75 / `java.nio` 71 / `java.math` 25 / `java.text` 22 / `java.lang` 22 / `java.time` 3）
- `kotlinx.*`: 405（`kotlinx.cinterop` 213 / `kotlinx.coroutines` 139 / `kotlinx.serialization` 52）
- `javax.*`: 38

## 2026-07-06 再監査 (RF-STUB-007)

実行コマンド:

```bash
DUMP_SURFACE=1 bash Scripts/swift_test.sh --filter FictionAuditDumpTests -Xswiftc -swift-version -Xswiftc 6
```

結果:

| 時点 | 追跡対象 | 合計 | baseline 差分 |
|---|---|---:|---:|
| 2026-07-02 初回監査 | 登録サーフェス baseline | 6888 | - |
| 2026-07-06 RF-STUB-007 | `.synthetic` フラグ付き残留サーフェス | 5951 | -937 (-13.6%) |

現行 `.synthetic` フラグ付き root 内訳:

- `kotlin.*`: 5142
- `kotlinx.*`: 461
- `java.*`: 347
- `CancellationException`: 1

参考値として、同じ `DUMP_SURFACE=1` 実行時の `SymbolTable.allSymbols()` 総数は **7371**。
これは bundled Kotlin source 由来のローカル/for 生成シンボル（`__local_*`, `__for_*`）や
ユーザー入力側の `noop` なども含むため、以後の削減推移メトリクスには使わない。

RF-STUB-004〜006 は登録構造の整理であり、API 除去そのものではない。以後は phase 完了ごとに
上表の `.synthetic` フラグ付き残留サーフェス値を更新し、実削減がある場合は該当 bucket と削除根拠を
このファイルへ追記する。

## 2026-07-25 CLEANUP-STUB-102（cinterop 未配線外殻削除）

実行コマンド:

```bash
DUMP_SURFACE=1 bash Scripts/swift_test.sh --filter FictionAuditDumpTests -Xswiftc -swift-version -Xswiftc 6
```

結果:

| 時点 | 追跡対象 | 合計 | 前回からの差分 |
|---|---|---:|---:|
| 2026-07-06 RF-STUB-007 | `.synthetic` フラグ付き残留サーフェス | 5951 | - |
| 2026-07-25 CLEANUP-STUB-102 | `.synthetic` フラグ付き残留サーフェス | 5099 | -852 (-14.3%) |

現行 `.synthetic` フラグ付き root 内訳:

- `kotlin.*`: 4434
- `kotlinx.*`: 294
- `java.*`: 370
- `CancellationException`: 1

参考値として、同じ `DUMP_SURFACE=1` 実行時の `SymbolTable.allSymbols()` 総数は **8599**。

主な削減内容:

- `kotlinx.cinterop` パッケージから externalLinkName 未設定の未配線 synthetic 関数外殻
  （`CPointer.get/set/pointed/value/reinterpret`, `CPointer.plus`, `CPointer.asStableRef`,
  `Arena`/`MemScope`/`NativePlacement`/`nativeHeap` 系 `alloc`/`place`, `StableRef`,
  `CValues`/`CValue`/`CValuesRef` 系アクセサ, `CEnum`/`CVariable` 系プロパティ,
  `zeroValue`/`typeOf`/Vector128 系など）を削除。
- 併せて `HeaderHelpers+SyntheticNativeInteropHelpers.swift` から
  `registerSyntheticCPointerGetFunction`/`setFunction`/`pointedProperty`/`plusFunction`/
  `varTypeAlias`/`CPointedReadFunction` などの未使用ビルダーと、
  `registerSyntheticNativeExtensionProperty`/`NativeTopLevelProperty`/`NativePlacementAllocArrayFunction`
  を削除。
- 残留する実働 cinterop ブリッジは `kk_cpointer_toLong`, `kk_byteArray_toCValues`,
  `kk_pin_object`/`kk_pinned_get`/`kk_unpin_object`, `kk_uByteArray_toCValues`/
  `kk_uIntArray_toCValues`/`kk_uLongArray_toCValues`, `kk_cpointer_toKStringFromUtf32`/
  `kk_cpointer_toKStringFromUtf16` のみ。

## 重要な判断: `java.*` / `kotlinx.*` は「架空」ではない

当初の計画では `java.*`/`javax.*` を一律「架空クラス」として削除予定だったが、調査の結果
**これらは意図的かつ kotlinc と整合検証された JVM 互換 interop** であることが判明した:

- `Scripts/diff_kotlinc.sh` の回帰は **kotlinc(JVM) でコンパイル・実行した出力**と KSwiftK の
  出力を比較する。`url_basic` / `stream_basic` / `i18n_common_edge_cases` / `files_utility` /
  `platform_time_conversion` / `http_client_basic` など多数の `java.*` ケースが
  **非スキップ（= kotlinc と一致することを期待）** で存在する。
- kotlinc 非互換な部分は明示的に `// SKIP-DIFF` でマークされている
  （例: `http_client_advanced`, `resource_bundle`, `number_format`）。
- `kotlinx.coroutines` は diff ハーネスが実 jar (`kotlinx-coroutines-core-jvm`) を取得して検証。
- `kotlinx.cinterop` は Kotlin/Native の実在 interop。

JDK / kotlinx ライブラリのクラスは「Kotlin stdlib ではない」ものの **実在 (real)** であり、
ユーザー要件の「架空 (実在しない) クラス/メソッド」には該当しない。よって **一律削除は行わず保持**する。
（もし JVM/kotlinx interop 自体を撤去したい場合は別タスクとして要相談。）

`java.nio.file.Files` は Java SE の実在する JDK API であり、架空シンボルではない。ただし
CLEANUP-STUB-110 は JVM interop 全体の一律削除ではなく、明示された target-out cleanup として
この Files utility surface のみを全層から除去した。`java.io.File` の FileIO surface と、Path が
共有する `java.nio.file.attribute.FileTime` / `toMillis`、`RuntimeFileTimeBox` は対象外として保持した。

## 真に架空（実在しない）と確認したシンボル → 除去/修正対象

| シンボル | 種別 | 根拠 | 対応 |
|---|---|---|---|
| `kotlin.Cache` (`put`/`get`/`size`, `kk_cache_*`) | class | Kotlin にも JDK にも存在しない完全な造語 | 全層除去 |
| `kotlin.collections.LinkedList` | class | kotlin.collections に `LinkedList` は無い（`ArrayDeque` のみ）。diff ケースも `// SKIP-DIFF` | 全層除去 |
| `List<E>.toTypeArray()` | member | 正しくは `toTypedArray()`。実在名が未登録で架空名のみ使用可 | `toTypedArray` へ改名（実施済み） |

### 除去済み（コミット）

- `kotlin.Cache`（`kk_cache_*` ランタイム・ABI・テスト・登録・stale golden 一式）。
- `kotlin.collections.LinkedList`（合成クラス・`CompilerKnownNames`・`CallTypeChecker` 特別処理・SKIP-DIFF ケース・golden・専用テスト）。
- `List<E>.toTypeArray` → `toTypedArray`（メンバ登録名・フォールバック重複ハンドラ・lookup table・テスト）。

### 検証のうえ「除去しない」と判断したもの

- `kotlin.concurrent.Lock` / `kotlin.concurrent.ReentrantReadWriteLock`（`HeaderHelpers+SyntheticAtomicStubs.swift`）:
  パッケージ配置は不正確（実型は `java.util.concurrent.locks.*`）だが、`kotlin.concurrent.Lock` は
  実在 API の `withLock` を型検査・ランタイム接続するための実装受け皿であり機能を伴うため対象外とした。
  `kotlin.concurrent.ReentrantReadWriteLock` および `java.util.concurrent.locks.ReentrantReadWriteLock` / `kotlin.concurrent.read`
  は実在する ReadWriteLock API の受け皿だったが、使用箇所がテストのみで製品経路から到達不能であったため
  CLEANUP-STUB-120 で削除した。
- `kotlin.random.SecureRandom` 等も同様に、実在の `java.security` interop（kotlinc 検証ケースあり）の
  受け皿であり、機能を伴うため対象外。

### 誤検出として除外した（実在する）主な候補

`*.Companion` / `Base64.Default|Mime|Pem|UrlSafe` / `Clock.System` 等のネスト object、
`kotlin.AutoCloseable` / `kotlin.io.Closeable` / `kotlin.text.Appendable` /
`kotlin.concurrent.atomics.Atomic*`（2.1+ 実在）/ `kotlin.collections.LinkedHashSet`（typealias）など。

## 検証

- `swift build` 成功（ベースライン）。
- 除去後は `bash Scripts/swift_test.sh` 全テスト + `UPDATE_GOLDEN=1 ... matchesGolden` で
  ゴールデン再生成（フルダンプ golden は 5 件）+ `bash Scripts/diff_kotlinc.sh` スポット確認。

## 2026-08-14 CLEANUP-STUB-123（`java.net.URI` synthetic surface 削除）

実行コマンド:

```bash
DUMP_SURFACE=1 SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --skip-build --filter FictionAuditDumpTests
```

変更後の実測値:

| 時点 | 追跡対象 | 合計 | root 内訳 |
|---|---|---:|---|
| 2026-08-14 CLEANUP-STUB-123 | `.synthetic` フラグ付き残留サーフェス | 3386 | `kotlin=2630`, `java=291`, `kotlinx=186`, `CancellationException=1`（その他の内部生成 root を含む） |

この値は CLEANUP-STUB-102 以降の master 上の削減を含むため、前回記録の 5099 との差分を URI 単独の削減量としては扱わない。
今回の対象では `java.net.URI` の synthetic shell、公開 URI exports、Path/URL の URI 変換を除去し、HTTP request builder 内部の URI handoff は保持した。

## 2026-08-14 CLEANUP-STUB-109（`kotlin.io.FileWalkDirection` synthetic surface 削除）

実行コマンド:

```bash
DUMP_SURFACE=1 SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --skip-build --filter FictionAuditDumpTests
```

変更前後の実測値:

| 時点 | 追跡対象 | 合計 | root 内訳 |
|---|---|---:|---|
| 変更前 | `.synthetic` フラグ付き残留サーフェス | 3105 | `kotlin=2607`, `java=304`, `kotlinx=193`, `CancellationException=1` |
| 2026-08-14 CLEANUP-STUB-109 | `.synthetic` フラグ付き残留サーフェス | 3102 | `kotlin=2604`, `java=304`, `kotlinx=193`, `CancellationException=1` |

`kotlin.io.FileWalkDirection` の enum と `TOP_DOWN`/`BOTTOM_UP` の synthetic symbol 3件を削除した。File IO/FileTreeWalk の別 surface は対象外として保持した。

## 2026-08-14 CLEANUP-STUB-124（`java.net.URL` synthetic surface 削除）

実行コマンド:

```bash
DUMP_SURFACE=1 SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --skip-build --filter FictionAuditDumpTests
```

変更後の実測値:

| 時点 | 追跡対象 | 合計 | root 内訳 |
|---|---|---:|---|
| 2026-08-14 CLEANUP-STUB-124 | `.synthetic` フラグ付き残留サーフェス | 3397 | `kotlin=2566`, `java=271`, `kotlinx=187`, `CancellationException=1`（その他の内部生成 root を含む） |

この値は CLEANUP-STUB-123 後の master 上の削減を含むため、前回記録との差分を URL 単独の削減量としては扱わない。
今回の対象では `java.net.URL` の synthetic shell、公開 URL exports、URL runtime/ABI exports を除去し、HTTP request builder 内部の URI handoff は保持した。

## 2026-08-19 CLEANUP-STUB-127/128（Kotlin/JS `JsAny` / `JsNumber` synthetic surface 削除）

実行コマンド:

```bash
DUMP_SURFACE=1 SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --skip-build --filter FictionAuditDumpTests
```

標準の Swift Testing dump が成功し、`makeCompilationContext` / `runSema` pipeline の実測値を取得した。

変更後の実測値:

| 時点 | 追跡対象 | 合計 | root 内訳 |
|---|---|---:|---|
| 2026-08-19 CLEANUP-STUB-127/128 | `.synthetic` フラグ付き残留サーフェス | 2898 | `kotlin=2063`, `java=266`, `kotlinx=191`, `CancellationException=1`（その他の内部生成 root を含む） |

参考値として、同じ実行時の `SymbolTable.allSymbols()` 総数は **14500**。
`kotlin.js.JsAny` / `JsNumber` の synthetic Sema 登録、stale RuntimeABI spec、ABI parity の spec-only allowlist を除去した。
実 Runtime export は存在しないため Runtime 本体は変更していない。`Tests` / `Scripts/diff_cases` に `JsAny` の参照はなく、別問題の `js_annotations.kt` は保持している。

## 2026-09-03 CLEANUP-STUB-110（`java.nio.file.Files` synthetic surface 削除）

実行コマンド:

```bash
DUMP_SURFACE=1 SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter FictionAuditDumpTests -Xswiftc -swift-version -Xswiftc 6
```

変更後の実測値:

| 時点 | 追跡対象 | 合計 | root 内訳 |
|---|---|---:|---|
| 2026-09-03 CLEANUP-STUB-110 | `.synthetic` フラグ付き残留サーフェス | 2529 | `kotlin=1746`, `java=214`, `kotlinx=191`, `CancellationException=1`（その他の内部生成 root を含む） |

`Files` synthetic registration、16 個の `__kk_files_*` runtime export/ABI parity、専用 diff case を削除した。
`FileTime` は Path metadata API が共有するため、`RuntimeFileTimeBox` / `__kk_fileTime_toMillis` と
`FileTime.toMillis` の Path 側登録を保持した。`java.io.File` の `file_isDirectory_test.kt` は
CLEANUP-STUB-107 の surface であり、誤って削除していない。
