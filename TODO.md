# Kotlin Compiler Remaining Tasks

最終更新: 2026-05-28

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

### Phase 2: コレクション・Sequence・Range
- [~] STDLIB-022: range / progression / unsigned range の網羅性を上げる（LongRange `firstOrNull` / `lastOrNull` runtime 済み）

#### kotlin.collections 関数の実装（D-Z）
- [ ] STDLIB-COL-FN-073: `firstNotNullOfOrNull` 関数の実装
- [ ] STDLIB-COL-FN-074: `firstOrNull` 関数の実装
- [ ] STDLIB-COL-FN-075: `flatMap` 関数の実装

### Phase 3: I/O・パス・時間・並行（common）
- [~] STDLIB-GAP-PH3: `kotlin.io`（common） / `kotlin.time` / `kotlin.concurrent` / `kotlin.concurrent.atomics` の未対応を潰す
- [ ] STDLIB-030: `kotlin.io` common 範囲の file / buffered / `use` を仕様単位で締める

#### kotlin.concurrent 関数の実装
- [ ] STDLIB-CONC-FN-004: `fixedRateTimer` 関数の実装（各オーバーロード）
- [ ] STDLIB-CONC-FN-005: `schedule` 関数の実装
- [ ] STDLIB-CONC-FN-006: `scheduleAtFixedRate` 関数の実装（各オーバーロード）
- [ ] STDLIB-CONC-FN-008: `timer` 関数の実装（各オーバーロード）

#### kotlin.io 型の実装
- [ ] STDLIB-IO-TYPE-004: `FileTreeWalk` クラスの実装
- [ ] STDLIB-IO-TYPE-007: `OnErrorAction` enum の実装

#### kotlin.io プロパティの実装
- [ ] STDLIB-IO-PROP-003: `invariantSeparatorsPath` 拡張プロパティの実装
- [ ] STDLIB-IO-PROP-004: `isRooted` 拡張プロパティの実装

#### kotlin.io 関数の実装
- [ ] STDLIB-IO-FN-001: `appendBytes` 関数の実装
- [ ] STDLIB-IO-FN-007: `bufferedReader` 関数の実装（InputStream版）
- [ ] STDLIB-IO-FN-012: `copyRecursively` 関数の実装
- [ ] STDLIB-IO-FN-014: `copyTo` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-016: `forEachBlock` 関数の実装
- [ ] STDLIB-IO-FN-017: `forEachLine` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-020: `inputStream` 関数の実装（ByteArray版）
- [ ] STDLIB-IO-FN-024: `normalize` 関数の実装
- [ ] STDLIB-IO-FN-029: `readBytes` 関数の実装（InputStream版）
- [ ] STDLIB-IO-FN-033: `readText` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-030: `readBytes` 関数の実装（URL版）
- [ ] STDLIB-IO-FN-038: `toRelativeString` 関数の実装
- [ ] STDLIB-IO-FN-040: `useLines` 関数の実装（Reader版）

#### kotlin.io.path 関数の実装
- [ ] STDLIB-IO-PATH-FN-011: `createSymbolicLinkPointingTo` 関数の実装
- [ ] STDLIB-IO-PATH-FN-018: `fileVisitor` 関数の実装
- [ ] STDLIB-IO-PATH-FN-019: `forEachDirectoryEntry` 関数の実装
- [ ] STDLIB-IO-PATH-FN-023: `getOwner` 関数の実装
- [ ] STDLIB-IO-PATH-FN-026: `moveTo` 関数の実装
- [ ] STDLIB-IO-PATH-FN-030: `readAttributes` 関数の実装
- [ ] STDLIB-IO-PATH-FN-028: `outputStream` 関数の実装
- [ ] STDLIB-IO-PATH-FN-032: `setAttribute` 関数の実装
- [ ] STDLIB-IO-PATH-FN-037: `useDirectoryEntries` 関数の実装
- [ ] STDLIB-IO-PATH-FN-038: `useLines` 関数の実装
- [ ] STDLIB-IO-PATH-FN-040: `writeLines` 関数の実装（Iterable版）
- [ ] STDLIB-IO-PATH-FN-042: `writer` 関数の実装

#### kotlin.reflect 型の実装
- [ ] STDLIB-REFLECT-TYPE-009: `KMutableProperty` インターフェースの実装
- [ ] STDLIB-REFLECT-TYPE-010: `KMutableProperty0` インターフェースの実装
- [ ] STDLIB-REFLECT-TYPE-013: `KParameter` インターフェースの実装
- [ ] STDLIB-REFLECT-TYPE-015: `KProperty0` インターフェースの実装

#### kotlin.sequences 関数の実装
- [ ] STDLIB-SEQ-FN-005: `associate` 関数の実装
- [ ] STDLIB-SEQ-FN-009: `associateWith` 関数の実装
- [ ] STDLIB-SEQ-FN-044: `forEach` 関数の実装
- [ ] STDLIB-SEQ-FN-046: `groupBy` 関数の実装
- [ ] STDLIB-SEQ-FN-047: `groupByTo` 関数の実装
- [ ] STDLIB-SEQ-FN-087: `plus` 関数の実装

#### kotlin.system 関数の実装
- [ ] STDLIB-SYSTEM-FN-001: `exitProcess` 関数の実装
- [ ] STDLIB-SYSTEM-FN-003: `getTimeMillis` 関数の実装
- [ ] STDLIB-SYSTEM-FN-005: `measureNanoTime` 関数の実装
- [ ] STDLIB-SYSTEM-FN-006: `measureTimeMicros` 関数の実装
- [ ] STDLIB-SYSTEM-FN-004: `getTimeNanos` 関数の実装
- [ ] STDLIB-SYSTEM-FN-007: `measureTimeMillis` 関数の実装

#### kotlin.text 型の実装
- [ ] STDLIB-TEXT-TYPE-008: `MatchGroupCollection` インターフェースの実装
- [ ] STDLIB-TEXT-TYPE-010: `MatchResult` インターフェースの実装

#### kotlin.text プロパティの実装
- [ ] STDLIB-TEXT-PROP-001: `CASE_INSENSITIVE_ORDER` プロパティの実装
- [ ] STDLIB-TEXT-PROP-002: `category` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-003: `directionality` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-008: `isIdentifierIgnorable` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-009: `isJavaIdentifierPart` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-010: `isJavaIdentifierStart` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-015: `isSurrogate` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-016: `isTitleCase` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-017: `isUnicodeIdentifierPart` 拡張プロパティの実装

#### kotlin.text 関数の実装
- [ ] STDLIB-TEXT-FN-003: `append` 関数の実装
- [ ] STDLIB-TEXT-FN-005: `appendRange` 関数の実装
- [ ] STDLIB-TEXT-FN-007: `buildStringAppend` 関数の実装
- [ ] STDLIB-TEXT-FN-008: `buildStringBuilder` 関数の実装
- [ ] STDLIB-TEXT-FN-006: `buildString` 関数の実装
- [ ] STDLIB-TEXT-FN-009: `capitalize` 関数の実装
- [ ] STDLIB-TEXT-FN-010: `codePointCount` 関数の実装
- [ ] STDLIB-TEXT-FN-013: `decodeToString` 関数の実装
- [ ] STDLIB-TEXT-FN-014: `encodeToByteArray` 関数の実装
- [ ] STDLIB-TEXT-FN-016: `equals` 関数の実装
- [ ] STDLIB-TEXT-FN-019: `indent` 関数の実装
- [ ] STDLIB-TEXT-FN-021: `indexOfAny` 関数の実装
- [ ] STDLIB-TEXT-FN-022: `indexOfFirst` 関数の実装
- [ ] STDLIB-TEXT-FN-023: `indexOfLast` 関数の実装
- [ ] STDLIB-TEXT-FN-024: `insert` 関数の実装
- [ ] STDLIB-TEXT-FN-025: `insertRange` 関数の実装
- [ ] STDLIB-TEXT-FN-026: `intern` 関数の実装
- [ ] STDLIB-TEXT-FN-027: `isBlank` 関数の実装
- [ ] STDLIB-TEXT-FN-031: `isNullOrEmpty` 関数の実装
- [ ] STDLIB-TEXT-FN-033: `iterator` 関数の実装
- [ ] STDLIB-TEXT-FN-034: `lastIndexOf` 関数の実装
- [ ] STDLIB-TEXT-FN-035: `lastIndexOfAny` 関数の実装
- [ ] STDLIB-TEXT-FN-038: `minus` 関数の実装
- [ ] STDLIB-TEXT-FN-039: `onEach` 関数の実装
- [ ] STDLIB-TEXT-FN-040: `onEachIndexed` 関数の実装
- [ ] STDLIB-TEXT-FN-042: `padStart` 関数の実装
- [ ] STDLIB-TEXT-FN-043: `plus` 関数の実装
- [ ] STDLIB-TEXT-FN-044: `random` 関数の実装
- [ ] STDLIB-TEXT-FN-045: `randomOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-046: `reduce` 関数の実装
- [ ] STDLIB-TEXT-FN-047: `reduceIndexed` 関数の実装
- [ ] STDLIB-TEXT-FN-048: `reduceIndexedOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-049: `reduceOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-051: `removeRange` 関数の実装
- [ ] STDLIB-TEXT-FN-053: `removeSurrounding` 関数の実装
- [ ] STDLIB-TEXT-FN-055: `replace` 関数の実装
- [ ] STDLIB-TEXT-FN-056: `replaceAfter` 関数の実装
- [ ] STDLIB-TEXT-FN-057: `replaceAfterLast` 関数の実装
- [ ] STDLIB-TEXT-FN-058: `replaceBefore` 関数の実装
- [ ] STDLIB-TEXT-FN-059: `replaceBeforeLast` 関数の実装
- [ ] STDLIB-TEXT-FN-060: `replaceFirst` 関数の実装
- [ ] STDLIB-TEXT-FN-061: `replaceIndent` 関数の実装
- [ ] STDLIB-TEXT-FN-062: `replaceRange` 関数の実装
- [ ] STDLIB-TEXT-FN-065: `setRange` 関数の実装
- [ ] STDLIB-TEXT-FN-067: `singleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-068: `slice` 関数の実装
- [ ] STDLIB-TEXT-FN-070: `splitToSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-071: `startsWith` 関数の実装
- [ ] STDLIB-TEXT-FN-072: `subSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-074: `substringAfter` 関数の実装
- [ ] STDLIB-TEXT-FN-075: `substringAfterLast` 関数の実装
- [ ] STDLIB-TEXT-FN-077: `substringBeforeLast` 関数の実装
- [ ] STDLIB-TEXT-FN-079: `takeIf` 関数の実装
- [ ] STDLIB-TEXT-FN-081: `takeLastWhile` 関数の実装
- [ ] STDLIB-TEXT-FN-082: `takeWhile` 関数の実装
- [ ] STDLIB-TEXT-FN-083: `toBigDecimal` 関数の実装
- [ ] STDLIB-TEXT-FN-084: `toBigDecimalOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-085: `toBigInteger` 関数の実装
- [ ] STDLIB-TEXT-FN-086: `toBigIntegerOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-088: `toBooleanStrict` 関数の実装
- [ ] STDLIB-TEXT-FN-089: `toBooleanStrictOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-091: `toByteOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-092: `toByteArray` 関数の実装
- [ ] STDLIB-TEXT-FN-094: `toCollection` 関数の実装
- [ ] STDLIB-TEXT-FN-095: `toDouble` 関数の実装
- [ ] STDLIB-TEXT-FN-096: `toDoubleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-098: `toFloatOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-101: `toList` 関数の実装
- [ ] STDLIB-TEXT-FN-102: `toLong` 関数の実装
- [ ] STDLIB-TEXT-FN-104: `toMutableList` 関数の実装
- [ ] STDLIB-TEXT-FN-105: `toRegex` 関数の実装
- [ ] STDLIB-TEXT-FN-106: `toShort` 関数の実装
- [ ] STDLIB-TEXT-FN-107: `toShortOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-108: `toSortedSet` 関数の実装
- [ ] STDLIB-TEXT-FN-115: `withIndex` 関数の実装
- [ ] STDLIB-TEXT-FN-116: `zip` 関数の実装

#### kotlin.time 型の実装
- [ ] STDLIB-TIME-TYPE-001: `AbstractDoubleTimeSource` 抽象クラスの実装
- [ ] STDLIB-TIME-TYPE-002: `AbstractLongTimeSource` 抽象クラスの実装
- [ ] STDLIB-TIME-TYPE-003: `Clock` インターフェースの実装
- [ ] STDLIB-TIME-TYPE-005: `Duration` クラスの実装
- [ ] STDLIB-TIME-TYPE-007: `ExperimentalTime` アノテーションの実装
- [ ] STDLIB-TIME-TYPE-009: `TestTimeSource` クラスの実装
- [ ] STDLIB-TIME-TYPE-010: `TimedValue` クラスの実装
- [ ] STDLIB-TIME-TYPE-011: `TimeMark` クラスの実装
- [ ] STDLIB-TIME-TYPE-012: `TimeSource` インターフェースの実装

#### kotlin.time プロパティの実装
- [ ] STDLIB-TIME-PROP-001: `isDistantFuture` 拡張プロパティの実装

#### kotlin.time 関数の実装
- [ ] STDLIB-TIME-FN-001: `asClock` 関数の実装
- [ ] STDLIB-TIME-FN-002: `measureTime` 関数の実装
- [ ] STDLIB-TIME-FN-004: `times` 関数の実装
- [ ] STDLIB-TIME-FN-005: `toDuration` 関数の実装
- [ ] STDLIB-TIME-FN-006: `toDurationUnit` 関数の実装
- [ ] STDLIB-TIME-FN-007: `toJavaDuration` 関数の実装
- [ ] STDLIB-TIME-FN-008: `toJavaInstant` 関数の実装
- [ ] STDLIB-TIME-FN-009: `toJSDate` 関数の実装
- [ ] STDLIB-TIME-FN-010: `toKotlinDuration` 関数の実装
- [ ] STDLIB-TIME-FN-012: `toTimeUnit` 関数の実装

#### kotlin.uuid 型の実装
- [ ] STDLIB-UUID-TYPE-002: `Uuid` クラスの実装

#### kotlin.uuid 関数の実装
- [ ] STDLIB-UUID-FN-001: `getUuid` 関数の実装
- [ ] STDLIB-UUID-FN-002: `putUuid` 関数の実装
- [ ] STDLIB-UUID-FN-003: `toJavaUuid` 関数の実装
- [ ] STDLIB-UUID-FN-004: `toKotlinUuid` 関数の実装

### Phase 4: リフレクション・数値・テキスト・その他 stdlib
- [ ] STDLIB-REFLECT-067: `KClass` / metadata / メンバ introspection の残差を詰める
- [ ] STDLIB-RANDOM-001: `kotlin.random` の対象 API 一覧を固定
- [ ] STDLIB-RANDOM-002: `kotlin.random` の sema / lowering を整える
- [ ] STDLIB-RANDOM-003: `kotlin.random` の runtime / seed / 境界値を固定
- [ ] STDLIB-COMP-001: `kotlin.comparisons` の対象 API 一覧を固定
- [ ] STDLIB-COMP-002: `Comparator` 合成の sema / lowering を整える

#### kotlin.comparisons 関数の実装
- [ ] STDLIB-COMP-FN-002: `compareByDescending` 関数の実装（selector版）
- [ ] STDLIB-COMP-FN-003: `compareValues` 関数の実装
- [ ] STDLIB-COMP-FN-005: `maxOf` 関数の実装（Comparable版、2引数）
- [ ] STDLIB-COMP-FN-007: `maxOf` 関数の実装（Comparable版、vararg）
- [ ] STDLIB-COMP-FN-009: `maxOf` 関数の実装（Byte版、3引数）
- [ ] STDLIB-COMP-FN-010: `maxOf` 関数の実装（Byte版、vararg）
- [ ] STDLIB-COMP-FN-012: `maxOf` 関数の実装（Double版、3引数）
- [ ] STDLIB-COMP-FN-014: `maxOf` 関数の実装（Float版、2引数）
- [ ] STDLIB-COMP-FN-015: `maxOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-017: `maxOf` 関数の実装（Int版、2引数）
- [ ] STDLIB-COMP-FN-018: `maxOf` 関数の実装（Int版、3引数）
- [ ] STDLIB-COMP-FN-020: `maxOf` 関数の実装（Long版、2引数）
- [ ] STDLIB-COMP-FN-022: `maxOf` 関数の実装（Long版、vararg）
- [ ] STDLIB-COMP-FN-024: `maxOf` 関数の実装（Short版、3引数）
- [ ] STDLIB-COMP-FN-028: `maxWithOrNull` 関数の実装
- [ ] STDLIB-COMP-FN-029: `minOf` 関数の実装（Comparable版、2引数）
- [ ] STDLIB-COMP-FN-030: `minOf` 関数の実装（Comparable版、3引数）
- [ ] STDLIB-COMP-FN-032: `minOf` 関数の実装（Byte版、2引数）
- [ ] STDLIB-COMP-FN-034: `minOf` 関数の実装（Byte版、vararg）
- [ ] STDLIB-COMP-FN-035: `minOf` 関数の実装（Double版、2引数）
- [ ] STDLIB-COMP-FN-036: `minOf` 関数の実装（Double版、3引数）
- [ ] STDLIB-COMP-FN-037: `minOf` 関数の実装（Double版、vararg）
- [ ] STDLIB-COMP-FN-038: `minOf` 関数の実装（Float版、2引数）
- [ ] STDLIB-COMP-FN-039: `minOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-040: `minOf` 関数の実装（Float版、vararg）
- [ ] STDLIB-COMP-FN-041: `minOf` 関数の実装（Int版、2引数）
- [ ] STDLIB-COMP-FN-042: `minOf` 関数の実装（Int版、3引数）
- [ ] STDLIB-COMP-FN-043: `minOf` 関数の実装（Int版、vararg）
- [ ] STDLIB-COMP-FN-044: `minOf` 関数の実装（Long版、2引数）
- [ ] STDLIB-COMP-FN-045: `minOf` 関数の実装（Long版、3引数）
- [ ] STDLIB-COMP-FN-046: `minOf` 関数の実装（Long版、vararg）
- [ ] STDLIB-COMP-FN-047: `minOf` 関数の実装（Short版、2引数）
- [ ] STDLIB-COMP-FN-048: `minOf` 関数の実装（Short版、3引数）
- [ ] STDLIB-COMP-FN-049: `minOf` 関数の実装（Short版、vararg）
- [ ] STDLIB-COMP-FN-050: `minOf` 関数の実装（UByte版）
- [ ] STDLIB-COMP-FN-051: `minOf` 関数の実装（UInt版）
- [ ] STDLIB-COMP-FN-052: `minOf` 関数の実装（ULong版）
- [ ] STDLIB-COMP-FN-053: `minOf` 関数の実装（UShort版）
- [ ] STDLIB-COMP-FN-055: `minWith` 関数の実装
- [ ] STDLIB-COMP-FN-059: `nullsFirst` 関数の実装（Comparable版）
- [ ] STDLIB-COMP-FN-061: `nullsLast` 関数の実装（Comparable版）
- [ ] STDLIB-COMP-FN-062: `nullsLast` 関数の実装（Comparator版）
- [ ] STDLIB-ANNO-002: annotation sema / diagnostics を整える
- [~] STDLIB-CORO-001: `kotlin.coroutines.intrinsics` / cancellation — 主要部分実装済み（`suspendCoroutineUninterceptedOrReturn`, `intercepted`, `CancellationException`）。残課題は別チケットへ分割。
- [ ] STDLIB-CORO-003: `kotlin.coroutines` の一部ランタイム経路をセマフォ待機から脱却する。対象: `RuntimeAsyncTask.awaitResult`, `RuntimeJobHandle.join`, `kk_with_context`, Channel send/receive, Sequence builder( `sequence`, `iterator` ) の待機部。
- [ ] STDLIB-NATIVE-PLATFORM-001: `kotlin.native` の platform info 残差を詰める
- [ ] STDLIB-NATIVE-PLATFORM-002: common から見える Native bridge を整理

### Phase 5: 非スコープ/高度領域
- [ ] STDLIB-IO-PATH-FN-074: `Path.visitFileTree(maxDepth, followLinks, builderAction)` を追加する
- [ ] STDLIB-JS-COLLECTIONS-TYPE-003: `kotlin.js.collections.JsReadonlyArray<E>` external interface を追加する
- [ ] STDLIB-JS-COLLECTIONS-TYPE-004: `kotlin.js.collections.JsReadonlyMap<K, V>` external interface を追加する
- [ ] STDLIB-JS-COLLECTIONS-FN-006: `JsReadonlySet<E>.toSet()` を追加する
- [ ] STDLIB-JS-COLLECTIONS-FN-005: `JsReadonlySet<E>.toMutableSet()` を追加する
- [ ] STDLIB-CINTEROP-TYPE-020: `kotlinx.cinterop.CPointerVarOf<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-FN-010: `place(value)` を追加する
- [ ] STDLIB-CINTEROP-FN-009: `pin()` を追加する
- [ ] STDLIB-CINTEROP-FN-011: `CPointer<T>.plus(index)` を追加する
- [ ] STDLIB-CINTEROP-FN-016: `CPointer<T>.set(index, value)` を追加する
- [ ] STDLIB-CINTEROP-FN-017: `Array<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-018: `ByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-024: `UByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-025: `UIntArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-026: `ULongArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-028: `List<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-029: `ByteArray.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-032: `CPointer<UShortVar>.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-034: `CPointer<ShortVar>.toKStringFromUtf16()` を追加する
- [ ] STDLIB-CINTEROP-FN-035: `CPointer<UShortVar>.toKStringFromUtf16()` を追加する
- [ ] STDLIB-CINTEROP-FN-036: `CPointer<IntVar>.toKStringFromUtf32()` を追加する
- [ ] STDLIB-CINTEROP-FN-038: `CPointer<T>?.toLong()` を追加する
- [ ] STDLIB-CINTEROP-FN-039: `typeOf<T>()` を追加する
- [ ] STDLIB-CINTEROP-FN-041: `CValue<T>.useContents(block)` を追加する
- [ ] STDLIB-CINTEROP-FN-042: `T.usePinned(block)` を追加する
- [ ] STDLIB-CINTEROP-FN-043: `vectorOf(Float, Float, Float, Float)` の公式 annotation/signature を既存 stub と整合させる
- [ ] STDLIB-CINTEROP-FN-044: `vectorOf(Int, Int, Int, Int)` の公式 annotation/signature を既存 stub と整合させる
- [ ] STDLIB-CINTEROP-FN-045: `CValue<T>.write(location)` を追加する
- [ ] STDLIB-CINTEROP-FN-046: `writeBits(ptr, offset, size, value)` を追加する
- [ ] STDLIB-CINTEROP-FN-047: `zeroValue<T>()` を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-001: `kotlinx.cinterop.internal.CCall` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-002: `kotlinx.cinterop.internal.CEnumEntryAlias` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-004: `kotlinx.cinterop.internal.CGlobalAccess` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-005: `kotlinx.cinterop.internal.ConstantValue` object を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-006: `kotlinx.cinterop.internal.CStruct` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-FN-001: `convertBlockPtrToKotlinFunction(blockPtr)` を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-FN-002: `detachObjCObject(obj)` を追加する
- [ ] STDLIB-DOM-TYPE-001: `org.w3c.dom.ItemArrayLike<T>` external interface を追加する
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
- [ ] TEST-SEQ-009: `kotlin.sequences` の `findLast` / `partition` に Runtime テストを追加する。`kk_sequence_findLast` / `kk_sequence_partition` は専用ランタイム実装があるのに `Tests/RuntimeTests/RuntimeSequenceTests*.swift` での参照が 0 件。カバー対象: 空シーケンス・単一要素・マッチなし（`findLast` は `null`）・全要素マッチ・`partition` の predicate による 2 分割（`Pair<List, List>`）。`count` は基本ケース（`testCountReturnsElementCount`）のみ存在のため、空シーケンスと `predicate` 版を補完する
- [ ] TEST-SEQ-010: `kotlin.sequences` 既存関数のエッジケースを拡充する。`distinctBy`（空・全要素同一キー・キーセレクタ例外伝播）、`filterIsInstance`（空・全一致・全不一致）、`reduceIndexed` / `reduceRightIndexed`（単一要素で accumulator 未呼出）、および中間操作の遅延評価回数の検証（`RuntimeSequenceTests+BuilderAndAdvanced.swift` の `_lazyTestYieldCounter` 機構を活用）
- [ ] TEST-COMP-011: `kotlin.comparisons` の Comparator 合成を補強する。`naturalOrder` / `reverseOrder` のトランポリンに `runtimeNullSentinelInt` を渡したときの挙動、`compareBy` で全キー等値のとき `0` を返すこと、参照型オブジェクトの厳密な安定ソート（同値要素の原順序保持をインデックスベースで検証）。既存 `RuntimeComparatorTests.swift` は充実しているため上記の隙間に限定する
- [ ] TEST-COL-012: `kotlin.collections` の `Set` 高階関数の Runtime/Codegen テストを追加する。`kk_set_filter` / `filterNot` / `map` / `flatMap` / `all` / `any` / `first` / `last` / `lastOrNull` / `maxOrNull` / `minOrNull` / `sorted` / `sortedDescending` / `singleOrNull` / `count{}`（`kk_set_count_predicate`）/ `forEach` は実装の実体が `RuntimeCollectionHOF.swift` にあるが、Runtime テストも Codegen 統合テストも存在しない（Set 専用テストファイルが皆無）。カバー対象: 空 Set・単一要素・全一致/全不一致・要素順序・`first`/`last` の空 Set で例外。`none` と `mapNotNull` は既存カバー済みのため対象外
- [ ] TEST-COL-013: `kotlin.collections` の `Map` 高階関数 `getOrDefault` / `flatMap` / `mapNotNull` / `maxByOrNull` / `minByOrNull` の Codegen 統合テストを追加する（`RuntimeSetAndMap.swift` 等に実装ありだが実行テストなし）。カバー対象: 空 Map・キー不在時の `getOrDefault` デフォルト返却・全エントリ変換・`maxByOrNull`/`minByOrNull` の空 Map で `null`
- [ ] TEST-COL-014: `kotlin.collections` の `List` 受信者版 `reduceIndexedOrNull` / `scanIndexed` の Codegen 統合テストを追加する。Sequence 受信者版はカバー済みだが List 受信者の実行テストが欠落。カバー対象: 空（`reduceIndexedOrNull` は `null`、`scanIndexed` は initial のみ）・単一要素・accumulator に渡る index の検証
- [ ] TEST-RANGE-015: `kotlin.ranges` の IntRange/LongRange 受信者の HOF 実行テストを追加する。`forEach` / `drop` / `take` / `sorted` / `average` / `mapIndexed` / `mapNotNull` / `filterIndexed` / `findLast` / `reduceIndexed` / `first`(predicate版) / `last`(predicate版) は実装ありだが実行レベルのテストが無い（`KotlinCompilationBasicTests` は KIR コンパイルのみで実行せず、`forEach`/`drop`/`take`/`sorted`/`average` は KIR すら未通過）。`RuntimeRangeHOFTests` の直接 `kk_range_*` 呼び出しか Codegen 統合（`.kt` 実行）で。カバー対象: 空 range・単一要素・降順 progression（step 負）・`average` の整数→Double 変換。IntRange の `mapIndexed` は直接ギャップ（UInt/ULong 版は既存）
- [ ] TEST-TEXT-016: `StringBuilder` の明示 API の実行テストを追加する。`insert` / `delete(start,end)` / `deleteCharAt` / `replace` / `reverse` / `setCharAt` / `capacity` / `ensureCapacity` / `trimToSize` / `get` / `length` は実装ありだが未テスト（カバー済みの `deleteAt` / `deleteRange` / `insertRange` / `setRange` とは別関数）。`append` / `appendLine` / `toString` は文字列補間の lowering で間接カバー済みのため対象外。カバー対象: 境界インデックス・空 builder・`reverse` のサロゲートペア保持・`setCharAt`/`get` の範囲外で例外
