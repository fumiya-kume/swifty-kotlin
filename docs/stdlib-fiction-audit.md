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
   - 一時テスト `FictionAuditDumpTests`（`DUMP_SURFACE=1`）で、合成スタブ登録後の
     `SymbolTable` 全シンボル（FQName / 種別）をダンプ。総数 **6888**。

3. **差分と分類**
   - 登録サーフェス ∖ 公式 API を計算し、`kotlin.native/js/wasm/cinterop` など
     JVM ダンプが網羅しないパッケージを除外したうえで残差を人手検証。

## サーフェスの内訳（合成シンボル数・パッケージルート別）

- `kotlin.*`: 5354
- `java.*`: 526（`java.io` 124 / `java.net` 102 / `java.util` 86 / `java.security` 75 / `java.nio` 71 / `java.math` 25 / `java.text` 22 / `java.lang` 22 / `java.time` 3）
- `kotlinx.*`: 405（`kotlinx.cinterop` 213 / `kotlinx.coroutines` 139 / `kotlinx.serialization` 52）
- `javax.*`: 38

## 重要な判断: `java.*` / `kotlinx.*` は「架空」ではない

当初の計画では `java.*`/`javax.*` を一律「架空クラス」として削除予定だったが、調査の結果
**これらは意図的かつ kotlinc と整合検証された JVM 互換 interop** であることが判明した:

- `Scripts/diff_kotlinc.sh` の回帰は **kotlinc(JVM) でコンパイル・実行した出力**と KSwiftK の
  出力を比較する。`url_basic` / `stream_basic` / `locale_basic` / `files_utility` /
  `platform_time_conversion` / `http_client_basic` など多数の `java.*` ケースが
  **非スキップ（= kotlinc と一致することを期待）** で存在する。
- kotlinc 非互換な部分は明示的に `// SKIP-DIFF` でマークされている
  （例: `http_client_advanced`, `resource_bundle`, `number_format`）。
- `kotlinx.coroutines` は diff ハーネスが実 jar (`kotlinx-coroutines-core-jvm`) を取得して検証。
- `kotlinx.cinterop` は Kotlin/Native の実在 interop。

JDK / kotlinx ライブラリのクラスは「Kotlin stdlib ではない」ものの **実在 (real)** であり、
ユーザー要件の「架空 (実在しない) クラス/メソッド」には該当しない。よって **一律削除は行わず保持**する。
（もし JVM/kotlinx interop 自体を撤去したい場合は別タスクとして要相談。）

## 真に架空（実在しない）と確認したシンボル → 除去/修正対象

| シンボル | 種別 | 根拠 | 対応 |
|---|---|---|---|
| `kotlin.Cache` (`put`/`get`/`size`, `kk_cache_*`) | class | Kotlin にも JDK にも存在しない完全な造語 | 全層除去 |
| `kotlin.collections.LinkedList` | class | kotlin.collections に `LinkedList` は無い（`ArrayDeque` のみ）。diff ケースも `// SKIP-DIFF` | 全層除去 |
| `List<E>.toTypeArray()` | member | 正しくは `toTypedArray()`。実在名が未登録で架空名のみ使用可 | `toTypedArray` へ改名 |
| `kotlin.concurrent.Lock` / `kotlin.concurrent.ReentrantReadWriteLock` | class | 実在するのは `java.util.concurrent.locks.*` と `kotlin.concurrent` の拡張関数のみ。同名クラスは kotlin.concurrent に無い | 検証のうえ除去 |

### 誤検出として除外した（実在する）主な候補

`*.Companion` / `Base64.Default|Mime|Pem|UrlSafe` / `Clock.System` 等のネスト object、
`kotlin.AutoCloseable` / `kotlin.io.Closeable` / `kotlin.text.Appendable` /
`kotlin.concurrent.atomics.Atomic*`（2.1+ 実在）/ `kotlin.collections.LinkedHashSet`（typealias）など。

## 検証

- `swift build` 成功（ベースライン）。
- 除去後は `bash Scripts/swift_test.sh` 全テスト + `UPDATE_GOLDEN=1 ... matchesGolden` で
  ゴールデン再生成（フルダンプ golden は 5 件）+ `bash Scripts/diff_kotlinc.sh` スポット確認。
