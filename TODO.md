# Kotlin Compiler Remaining Tasks

最終更新: 2026-04-19

---

## 使い方（簡略）
- `[ ]` は未完了、`[~]` は部分完了（本文に残タスクを記載）
- `kotlin.*` の common / Kotlin/Native 相当を主対象とする
- JVM/JS/JVM専用・`kotlinx`・プラグイン系は「ターゲット外バックログ」へ
- 参照は必要最小に留め、詳細は都度 task 本文に反映する

### 主要参照
- Kotlin stdlib 2.3.10 API: https://kotlinlang.org/api/core/kotlin-stdlib/
- Kotlin release process: https://kotlinlang.org/docs/releases.html
- Runtime/API 差分は `Scripts/diff_kotlinc.sh` と `RuntimeABISpec` / ABI テストを起点に確認

## Kotlin stdlib（common / Kotlin/Native 相当）

### スコープパッケージ
- `kotlin`
- `kotlin.annotation`
- `kotlin.collections` / `kotlin.sequences`
- `kotlin.comparisons`
- `kotlin.ranges`
- `kotlin.text`（+ `Char`）
- `kotlin.io`（common のみ）
- `kotlin.io.encoding`（Base64 / HexFormat）
- `kotlin.math` / `kotlin.random`
- `kotlin.concurrent` / `kotlin.concurrent.atomics`
- `kotlin.reflect`
- `kotlin.time`
- `kotlin.properties`
- `kotlin.coroutines` / `kotlin.coroutines.cancellation` / `kotlin.coroutines.intrinsics`
- `kotlin.enums`
- `kotlin.system`
- `kotlin.uuid`
- `kotlin.native` / `kotlin.native.concurrent` / `kotlin.native.ref` / `kotlin.native.runtime`
- `kotlin.contracts`
- `kotlin.experimental`

### Phase 1: プリミティブ・演算子・配列・String コア
- [ ] STDLIB-GAP-PH1: ギャップ表の `kotlin` / `kotlin.text` / `Array` 周辺の未対応を潰す
- [ ] STDLIB-004: `Array` / primitive array の生成・変換・境界挙動を整理する
- [ ] STDLIB-005: `kotlin.text` の文字列変換・分割・置換の端ケースを揃える

### Phase 2: コレクション・Sequence・Range
- [ ] STDLIB-GAP-PH2: `kotlin.collections` / `kotlin.sequences` / `kotlin.ranges` の未対応を潰す
- [ ] STDLIB-020: `Sequence` の lazy 性と builder 系 API の評価順を固定
- [ ] STDLIB-021: mutable collection 変換 API と destination variant の差分を潰す
- [ ] STDLIB-022: range / progression / unsigned range の網羅性を上げる

### Phase 3: I/O・パス・時間・並行（common）
- [ ] STDLIB-GAP-PH3: `kotlin.io`（common） / `kotlin.time` / `kotlin.concurrent` / `kotlin.concurrent.atomics` の未対応を潰す
- [ ] STDLIB-030: `kotlin.io` common 範囲の file / buffered / `use` を仕様単位で締める
- [ ] STDLIB-032: `kotlin.time` の stable / experimental 境界を明文化
- [ ] STDLIB-033: `kotlin.concurrent` / `kotlin.concurrent.atomics` / Native concurrent の parity を上げる

### Phase 4: リフレクション・数値・テキスト・その他 stdlib
- [ ] STDLIB-GAP-PH4: `kotlin.math` / `kotlin.random` / `kotlin.reflect` / `kotlin.comparisons` / `kotlin.annotation` / `kotlin.system` / `kotlin.uuid` / `kotlin.native` 周辺の「部分」を潰す
- [ ] STDLIB-REFLECT-067: `KClass` / metadata / メンバ introspection の残差を詰める
- [ ] STDLIB-MATH-001: `kotlin.math` の対象 API 一覧を固定
- [ ] STDLIB-MATH-002: `kotlin.math` の sema / lowering を overload 単位で整える
- [ ] STDLIB-MATH-003: `kotlin.math` の runtime / ABI と境界値を固定
- [ ] STDLIB-RANDOM-001: `kotlin.random` の対象 API 一覧を固定
- [ ] STDLIB-RANDOM-002: `kotlin.random` の sema / lowering を整える
- [ ] STDLIB-RANDOM-003: `kotlin.random` の runtime / seed / 境界値を固定
- [ ] STDLIB-COMP-001: `kotlin.comparisons` の対象 API 一覧を固定
- [ ] STDLIB-COMP-002: `Comparator` 合成の sema / lowering を整える
- [ ] STDLIB-COMP-003: `Comparator` runtime と failure path を固定
- [ ] STDLIB-ANNO-001: `kotlin.annotation` の対象一覧を固定
- [ ] STDLIB-ANNO-002: annotation sema / diagnostics を整える
- [ ] STDLIB-I18N-COMMON-001: `kotlin.text` / common のフォーマット・ロケール
- [ ] STDLIB-TIME-EXP-001: `@ExperimentalTime` 系 API の整理（`Clock` / `TimeMark`）
- [~] STDLIB-CORO-001: `kotlin.coroutines.intrinsics` / cancellation — 主要部分実装済み（`suspendCoroutineUninterceptedOrReturn`, `intercepted`, `CancellationException`）。`startCoroutineUninterceptedOrReturn` / `createCoroutineUnintercepted` の runtime entry point が未実装。
- [ ] STDLIB-NATIVE-REF-001: `kotlin.native.ref` / `kotlin.native.runtime` の API 棚卸しを固定
- [ ] STDLIB-NATIVE-REF-002: `kotlin.native.ref` / `kotlin.native.runtime` の sema 露出を整える
- [ ] STDLIB-NATIVE-REF-003: `kotlin.native.ref` / `kotlin.native.runtime` の runtime / ABI を最小必要実装へ整理
- [ ] STDLIB-SYSTEM-001: `kotlin.system` の対象 API 一覧を固定
- [ ] STDLIB-SYSTEM-002: `kotlin.system` の sema / lowering を整える
- [ ] STDLIB-SYSTEM-003: `kotlin.system` の runtime / 計測系テストを固定
- [ ] STDLIB-UUID-001: `kotlin.uuid` の対象 API 一覧を固定
- [ ] STDLIB-UUID-002: `kotlin.uuid` の sema / lowering を整える
- [ ] STDLIB-UUID-003: `kotlin.uuid` の runtime / canonical form / failure path を固定
- [ ] STDLIB-NATIVE-PLATFORM-001: `kotlin.native` の platform info 残差を詰める
- [ ] STDLIB-NATIVE-PLATFORM-002: common から見える Native bridge を整理
- [ ] STDLIB-NATIVE-CONCURRENT-001: `kotlin.native.concurrent` の対象 API 一覧を固定
- [ ] STDLIB-NATIVE-CONCURRENT-002: `kotlin.native.concurrent` の sema / diagnostics を整える
- [ ] STDLIB-NATIVE-CONCURRENT-003: `kotlin.native.concurrent` の最小 runtime / ABI を実装
- [ ] STDLIB-EXPERIMENTAL-001: `kotlin.experimental` の marker 一覧を固定
- [ ] STDLIB-EXPERIMENTAL-002: `kotlin.experimental` の opt-in / diagnostics を整える

### Phase 5: 非スコープ/高度領域
- [ ] STDLIB-JVM-166: Java プレビュー機能の実装
- [ ] STDLIB-JS-167: JavaScript 固有 API の実装
- [ ] STDLIB-NATIVE-168: Native 固有 API の実装
- [ ] STDLIB-REFL-173: コンパイラプラグイン API 実装
- [ ] STDLIB-REFL-175: アノテーション処理高度機能実装

## ターゲット外バックログ（本体非追跡）
- JDBC / DB コネクション・トランザクション・プール
- JVM 風ロギングフレームワーク互換
- `kotlin.jvm` / `kotlin.js` / `kotlin.wasm*` / `java.nio.file` 系・`kotlin.streams`
- kotlinx-metadata / コンパイラプラグイン API / KSP / KAPT
- kotlinx.coroutines の Flow 拡張（SharedFlow、高度演算子）
- JVM `java.time` / JS `Date` との相互運用
- `Runtime.getRuntime()` 系メモリ API（JVM モデル）
- HTTP・汎用シリアライゼーション
- `java.text` 前提の日時・数値フォーマット

## テスト改善タスク
- [ ] TEST-CORO-003: 高度な Coroutine 機能テスト（29→40）
- [ ] TEST-INT-006: Integration Tests の整理と重複削減
- [ ] TEST-CI-007: CI パイプラインの最適化
- [ ] TEST-REPORT-008: テストレポート形式の改善
