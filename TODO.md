# Kotlin Compiler Remaining Tasks

最終更新: 2026-04-28

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
- [x] STDLIB-COL-MAP-002: `Map.withDefault(defaultValue)` を追加する
- [ ] STDLIB-022: range / progression / unsigned range の網羅性を上げる
- [x] STDLIB-RANGE-IFACE-001: `kotlin.ranges.ClosedRange<T>` interface surface を追加する
- [x] STDLIB-RANGE-IFACE-002: `kotlin.ranges.ClosedFloatingPointRange<T>` interface surface を追加する
- [x] STDLIB-RANGE-IFACE-003: `kotlin.ranges.OpenEndRange<T>` interface surface を追加する
- [x] STDLIB-RANGE-CHAR-001: `kotlin.ranges.CharProgression` / `CharRange` type surface を追加する
- [x] STDLIB-RANGE-OPEN-001: `kotlin.ranges.rangeUntil` operator surface を `OpenEndRange` 戻り値で追加する
- [x] STDLIB-RANGE-RANDOM-001: `CharRange` / `IntRange` / `LongRange` / `UIntRange` / `ULongRange`.`random()` overload 群を追加する
- [x] STDLIB-RANGE-RANDOM-002: `CharRange` / `IntRange` / `LongRange` / `UIntRange` / `ULongRange`.`random(random: Random)` overload 群を追加する
- [x] STDLIB-RANGE-UNTIL-001: `Byte` / `Short` / `Int` / `Long` と `UByte` / `UShort` / `UInt` / `ULong` の `until(to)` infix surface を追加する
- [x] STDLIB-RANGE-RANDOM-003: `CharRange` / `IntRange` / `LongRange` / `UIntRange` / `ULongRange`.`randomOrNull()` / `randomOrNull(random: Random)` overload 群を追加する
- [x] STDLIB-RANGE-UNTIL-002: `Byte` / `Short` / `Int` / `Long` 間の mixed-width `until(to)` overload 行列を追加する
- [x] STDLIB-RANGE-COERCE-001: `Byte` / `Short` / `UByte` / `UShort` / `UInt` / `ULong` の `coerceAtLeast` / `coerceAtMost` / `coerceIn` overload 群を追加する

### Phase 3: I/O・パス・時間・並行（common）
- [~] STDLIB-GAP-PH3: `kotlin.io`（common） / `kotlin.time` / `kotlin.concurrent` / `kotlin.concurrent.atomics` の未対応を潰す
- [ ] STDLIB-030: `kotlin.io` common 範囲の file / buffered / `use` を仕様単位で締める
- [x] STDLIB-IO-ENC-001: `kotlin.io.encoding.Base64.Default` / `UrlSafe` / `Mime` / `PemMime` を追加する
- [x] STDLIB-IO-ENC-002: `Base64.encode(ByteArray)` / `decode(String)` を追加する
- [x] STDLIB-IO-ENC-003: `Base64.encodeToByteArray(ByteArray)` / `decodeFromByteArray(ByteArray)` を追加する
- [x] STDLIB-IO-ENC-004: `Base64.withPadding(PaddingOption)` と MIME / URL-safe variant の挙動を追加する
- [ ] STDLIB-032: `kotlin.time` の stable / experimental 境界を明文化
- [x] STDLIB-TIME-STABLE-001: `Duration.ZERO` / `Duration.INFINITE` constants を追加する
- [x] STDLIB-TIME-STABLE-002: `Duration.toIsoString()` / `Duration.parse()` / `Duration.parseOrNull()` を追加する
- [x] STDLIB-TIME-STABLE-003: `Duration.parseIsoString()` / `Duration.parseIsoStringOrNull()` を追加する
- [x] STDLIB-TIME-STABLE-004: `Duration.toComponents { ... }` overload 群を追加する
- [x] STDLIB-TIME-STABLE-005: `Double.seconds` など `Double` receiver の `Duration` extension properties を追加する
- [x] STDLIB-TIME-STABLE-006: `Duration / Duration -> Double` を追加する
- [x] STDLIB-TIME-STABLE-007: `Duration.inWholeDays` property を追加する
- [ ] STDLIB-033: `kotlin.concurrent` / `kotlin.concurrent.atomics` / Native concurrent の parity を上げる
- [ ] STDLIB-ATOMIC-001: `kotlin.concurrent.atomics.AtomicNativePtr` surface を追加する
- [ ] STDLIB-ATOMIC-002: `atomicArrayOfNulls<T>(size)` を追加する
- [ ] STDLIB-ATOMIC-003: `AtomicInt.fetchAndDecrement()` / `AtomicLong.fetchAndDecrement()` を追加する
- [ ] STDLIB-ATOMIC-004: `AtomicIntArray.fetchAndDecrementAt(index)` / `AtomicLongArray.fetchAndDecrementAt(index)` を追加する
- [ ] STDLIB-ATOMIC-005: `AtomicIntArray.fetchAndIncrementAt(index)` / `AtomicLongArray.fetchAndIncrementAt(index)` を追加する
- [ ] STDLIB-ATOMIC-006: `AtomicReference.fetchAndUpdate(function)` を追加する
- [ ] STDLIB-ATOMIC-007: `AtomicArray.fetchAndUpdateAt(index, function)` を追加する
- [ ] STDLIB-ATOMIC-008: `AtomicArray.updateAt(index, function)` を追加する
- [ ] STDLIB-ATOMIC-009: `AtomicReference.updateAndFetch(function)` を追加する
- [ ] STDLIB-ATOMIC-010: `AtomicArray.updateAndFetchAt(index, function)` を追加する
- [x] STDLIB-PROP-001: `kotlin.properties.ObservableProperty<V>` abstract class を追加し、`beforeChange` / `afterChange` hook を `Delegates.observable` / `vetoable` と結び付ける
- [x] STDLIB-PROP-002: `kotlin.properties.PropertyDelegateProvider<T, D>` fun interface を追加し、provider 型付けと `provideDelegate` ベースの delegate factory surface を揃える

### Phase 4: リフレクション・数値・テキスト・その他 stdlib
- [ ] STDLIB-GAP-PH4: `kotlin.math` / `kotlin.random` / `kotlin.reflect` / `kotlin.comparisons` / `kotlin.annotation` / `kotlin.system` / `kotlin.uuid` / `kotlin.native` 周辺の「部分」を潰す
- [ ] STDLIB-REFLECT-067: `KClass` / metadata / メンバ introspection の残差を詰める
- [x] STDLIB-REFLECT-068: `kotlin.reflect.KAnnotatedElement` interface と `annotations` surface を追加する
- [x] STDLIB-REFLECT-069: `kotlin.reflect.KDeclarationContainer` interface surface を追加し、`KClass` との継承関係を整える
- [ ] STDLIB-REFLECT-070: `kotlin.reflect.KProperty2<D, E, V>` interface surface を追加する
- [ ] STDLIB-REFLECT-071: `kotlin.reflect.KMutableProperty2<D, E, V>` interface surface を追加する
- [x] STDLIB-REFLECT-072: `kotlin.reflect.KTypeParameter` interface surface を追加する
- [x] STDLIB-MATH-008: 公開されている非公式 rounding helper 名（`roundUp` など）を整理する
- [ ] STDLIB-RANDOM-001: `kotlin.random` の対象 API 一覧を固定
- [ ] STDLIB-RANDOM-002: `kotlin.random` の sema / lowering を整える
- [ ] STDLIB-RANDOM-003: `kotlin.random` の runtime / seed / 境界値を固定
- [x] STDLIB-RANDOM-004: `Random(seed: Long)` constructor を追加する
- [x] STDLIB-RANDOM-005: `Random.Default` singleton を sema から露出する
- [x] STDLIB-RANDOM-006: `Random.nextBytes(size: Int)` overload を追加する
- [x] STDLIB-RANDOM-007: `Random.nextInt(range: IntRange)` extension を追加する
- [x] STDLIB-RANDOM-008: `Random.nextLong(range: LongRange)` extension を追加する
- [x] STDLIB-RANDOM-009: `Random.nextBytes(array, fromIndex, toIndex)` overload を追加する
- [x] STDLIB-RANDOM-010: `Random.nextBits(bitCount: Int)` member surface を追加する
- [x] STDLIB-RANDOM-011: `Random.nextUBytes(size)` / `nextUBytes(array)` / `nextUBytes(array, fromIndex, toIndex)` を追加する
- [x] STDLIB-RANDOM-012: `Random.nextUInt()` / `nextUInt(until)` / `nextUInt(from, until)` / `nextUInt(range)` を追加する
- [x] STDLIB-RANDOM-013: `Random.nextULong()` / `nextULong(until)` / `nextULong(from, until)` / `nextULong(range)` を追加する
- [ ] STDLIB-COMP-001: `kotlin.comparisons` の対象 API 一覧を固定
- [ ] STDLIB-COMP-002: `Comparator` 合成の sema / lowering を整える
- [ ] STDLIB-COMP-003: `Comparator` runtime と failure path を固定
- [x] STDLIB-COMP-004: `compareBy(comparator, selector)` overload を追加する
- [x] STDLIB-COMP-005: `compareByDescending(comparator, selector)` overload を追加する
- [x] STDLIB-COMP-006: `compareBy(vararg selectors)` の一般 vararg surface を追加する（現状は 1/2/3 selector special-case のみ）
- [x] STDLIB-COMP-007: `compareValuesBy(a, b, comparator, selector)` overload を追加する
- [x] STDLIB-COMP-008: `compareValuesBy(a, b, vararg selectors)` の一般 vararg surface を追加する（現状は 1/2/3 selector special-case のみ）
- [x] STDLIB-COMP-009: `Comparator<T>.thenBy(comparator, selector)` overload を追加する
- [x] STDLIB-COMP-010: `Comparator<T>.thenByDescending(comparator, selector)` overload を追加する
- [x] STDLIB-ENUMS-001: `kotlin.enums.EnumEntries<E>` を正しい package で露出する（現状の `kotlin.collections.EnumEntries` synthetic surface を見直す）
- [x] STDLIB-ENUMS-002: `kotlin.enums.enumEntries<T>()` を正しい package で露出する（現状の `kotlin.enumEntries()` synthetic surface を見直す）
- [x] STDLIB-ANNO-001: `kotlin.annotation` の対象一覧を固定
- [ ] STDLIB-ANNO-002: annotation sema / diagnostics を整える
- [x] STDLIB-KOTLIN-ROOT-001: `SubclassOptInRequired(markerClass: KClass<out Annotation>)` を追加し、subclass opt-in の伝播と misuse diagnostics を実装する
 - [x] STDLIB-ANNO-001: `kotlin.annotation` の対象一覧を固定
 - [x] STDLIB-ANNO-002: annotation sema / diagnostics を整える
- [x] STDLIB-KOTLIN-ROOT-001: `SubclassOptInRequired(markerClass: KClass<out Annotation>)` を追加し、subclass opt-in の伝播と misuse diagnostics を実装する
- [x] STDLIB-KOTLIN-ROOT-002: `ConsistentCopyVisibility` annotation を追加し、data class `copy()` visibility migration の declaration-side diagnostics へ結び付ける
- [x] STDLIB-KOTLIN-ROOT-003: `ExposedCopyVisibility` annotation を追加し、public `copy()` 維持モードの suppression semantics を実装する
- [x] STDLIB-KOTLIN-ROOT-004: `ExperimentalVersionOverloading` marker を追加し、`@OptIn` / `-opt-in` diagnostics と結び付ける
- [x] STDLIB-KOTLIN-ROOT-005: `ContextFunctionTypeParams(count: Int)` type annotation を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-001: `BuilderInference` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-002: `DeprecatedSinceKotlin(warningSince, errorSince, hiddenSince)` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-003: `DslMarker` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-004: `OptionalExpectation` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-005: `ParameterName(name: String)` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-006: `PublishedApi` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-007: `SinceKotlin(version: String)` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-008: `Throws(vararg exceptionClasses: KClass<out Throwable>)` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-009: `ExperimentalContextParameters` opt-in marker を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-010: `IgnorableReturnValue` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-011: `IntroducedAt(version: String)` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-ANNO-012: `MustUseReturnValues` annotation surface を追加する
- [x] STDLIB-KOTLIN-ROOT-VERSION-001: `KotlinVersion` constructor と `major` / `minor` / `patch` properties を追加する
- [x] STDLIB-KOTLIN-ROOT-VERSION-002: `KotlinVersion.CURRENT` と comparison helpers（`compareTo`, `isAtLeast`）を追加する
- [x] STDLIB-KOTLIN-ROOT-EXC-001: `NoWhenBranchMatchedException` class surface を追加する
- [x] STDLIB-KOTLIN-ROOT-EXC-002: `ConcurrentModificationException` class surface を追加する
- [x] STDLIB-KOTLIN-ROOT-EXC-003: Native `ArrayIndexOutOfBoundsException` class surface を追加する
- [x] STDLIB-KOTLIN-ROOT-CLOSE-001: `AutoCloseable(closeAction: () -> Unit)` factory を追加する
- [x] STDLIB-KOTLIN-ROOT-CLOSE-002: `AutoCloseable?.use { ... }` common extension を追加する
- [x] STDLIB-KOTLIN-ROOT-ARRAY-001: `arrayOfNulls<T>(size: Int)` root array factory を追加する
- [x] STDLIB-KOTLIN-ROOT-LAZY-001: `lazyOf(value)` root lazy factory を追加する
- [x] STDLIB-KOTLIN-ROOT-CTX-001: experimental `context(with, block)` helper を追加する
- [x] STDLIB-KOTLIN-ROOT-CTX-002: experimental `context(a, b, ..., block)` overload 群を追加する
- [x] STDLIB-KOTLIN-ROOT-CTX-003: experimental `contextOf<A>()` helper を追加する
- [x] STDLIB-KOTLIN-ROOT-REFLECT-001: `KProperty0<*>.isInitialized` root extension property を追加する
- [x] STDLIB-KOTLIN-ROOT-THROW-001: `Throwable.suppressedExceptions` property を追加する
- [x] STDLIB-KOTLIN-ROOT-THROW-002: `Throwable.printStackTrace()` を追加する
- [x] STDLIB-KOTLIN-ROOT-NUM-001: integer `floorDiv` overload 行列を追加する
- [x] STDLIB-KOTLIN-ROOT-NUM-002: integer/floating `mod` overload 行列を追加する
- [ ] STDLIB-I18N-COMMON-001: `kotlin.text` / common のフォーマット・ロケール
- [x] STDLIB-I18N-COMMON-002: `Char.category` を `CharCategory` enum で露出する（現状は `Int` placeholder）
- [x] STDLIB-I18N-COMMON-003: `String.Companion.format(locale, format, vararg args)` を追加する
- [x] STDLIB-I18N-COMMON-004: `Char.uppercase(Locale)` を追加する
- [x] STDLIB-I18N-COMMON-005: `Char.lowercase(Locale)` を追加する
- [x] STDLIB-I18N-COMMON-006: `String.toIntOrNull(radix: Int)` を追加する
- [x] STDLIB-I18N-COMMON-007: `Char.directionality` を `CharDirectionality` enum で露出する（現状は `Int` placeholder）
- [x] STDLIB-I18N-COMMON-008: `Char.lowercaseChar()` を追加する
- [x] STDLIB-I18N-COMMON-009: `Char.uppercaseChar()` を追加する
- [x] STDLIB-I18N-COMMON-010: `Char.titlecaseChar()` を追加する
- [x] STDLIB-I18N-COMMON-011: `Char.isDefined()` を追加する
- [x] STDLIB-I18N-COMMON-012: Native `Char.isSupplementaryCodePoint()` / `Char.isSurrogatePair()` を追加する
- [x] STDLIB-I18N-COMMON-013: Native `Char.toChars()` / `Char.toCodePoint()` を追加する
- [x] STDLIB-TIME-EXP-001: `@ExperimentalTime` 系 API の整理（`Clock` / `TimeMark`）
- [x] STDLIB-TIME-STABLE-008: `DurationUnit` enum surface を追加する
- [x] STDLIB-TIME-STABLE-009: `Int.toDuration(unit)` / `Long.toDuration(unit)` / `Double.toDuration(unit)` を追加する
- [x] STDLIB-TIME-EXP-002: `AbstractDoubleTimeSource` surface を追加する
- [x] STDLIB-TIME-EXP-003: `AbstractLongTimeSource` surface を追加する
- [x] STDLIB-TIME-EXP-004: `TestTimeSource` surface を追加する
- [x] STDLIB-TIME-EXP-005: `Instant.isDistantPast` / `Instant.isDistantFuture` properties を追加する
- [x] STDLIB-TIME-EXP-006: `TimeSource.asClock()` を追加する
- [~] STDLIB-CORO-001: `kotlin.coroutines.intrinsics` / cancellation — 主要部分実装済み（`suspendCoroutineUninterceptedOrReturn`, `intercepted`, `CancellationException`）。残課題は別チケットへ分割。
- [x] STDLIB-CORO-002: `kotlin.coroutines.intrinsics` の runtime entry point（`startCoroutineUninterceptedOrReturn`, `createCoroutineUnintercepted`）を追加する。対応 C ABI 名: `kk_start_coroutine_unintercepted_or_return`, `kk_create_coroutine_unintercepted`。
- [ ] STDLIB-CORO-003: `kotlin.coroutines` の一部ランタイム経路をセマフォ待機から脱却する。対象: `RuntimeAsyncTask.awaitResult`, `RuntimeJobHandle.join`, `kk_with_context`, Channel send/receive, Sequence builder( `sequence`, `iterator` ) の待機部。
- [ ] STDLIB-NATIVE-PLATFORM-001: `kotlin.native` の platform info 残差を詰める
- [ ] STDLIB-NATIVE-PLATFORM-002: common から見える Native bridge を整理
- [x] STDLIB-NATIVE-PLATFORM-003: `kotlin.native.MemoryModel` enum stub と platform bridge を追加する
- [x] STDLIB-NATIVE-PLATFORM-004: `FreezingIsDeprecated` marker を追加する
- [x] STDLIB-NATIVE-PLATFORM-005: `HiddenFromObjC` annotation を追加する
- [x] STDLIB-NATIVE-PLATFORM-006: `NoInline` annotation を追加する
- [x] STDLIB-NATIVE-PLATFORM-007: `ObsoleteNativeApi` marker を追加する
- [x] STDLIB-NATIVE-PLATFORM-008: `EagerInitialization` annotation を追加する
- [x] STDLIB-NATIVE-PLATFORM-009: `BitSet` surface を追加する
- [x] STDLIB-NATIVE-PLATFORM-010: `ImmutableBlob` type と `immutableBlobOf(...)` factory を追加する
- [x] STDLIB-NATIVE-PLATFORM-011: `Vector128` type と `vectorOf(...)` factory を追加する
- [x] STDLIB-NATIVE-PLATFORM-012: Native `Any.asCPointer()` / `Any.asUCPointer()` を追加する
- [x] STDLIB-NATIVE-PLATFORM-013: Native pointer `getByteAt` / `getShortAt` / `getIntAt` / `getLongAt` accessors を追加する
- [x] STDLIB-NATIVE-PLATFORM-014: Native pointer `getUByteAt` / `getUShortAt` / `getUIntAt` / `getULongAt` accessors を追加する
- [x] STDLIB-NATIVE-PLATFORM-015: Native pointer `getCharAt` / `getFloatAt` / `getDoubleAt` accessors を追加する
- [x] STDLIB-NATIVE-PLATFORM-016: Native pointer `setByteAt` / `setShortAt` / `setIntAt` / `setLongAt` accessors を追加する
- [x] STDLIB-NATIVE-PLATFORM-017: Native pointer `setUByteAt` / `setUShortAt` / `setUIntAt` / `setULongAt` accessors を追加する
- [x] STDLIB-NATIVE-PLATFORM-018: Native pointer `setCharAt` / `setFloatAt` / `setDoubleAt` accessors を追加する
- [x] STDLIB-NATIVE-PLATFORM-019: Native `identityHashCode(obj)` を追加する
- [x] STDLIB-NATIVE-PLATFORM-020: Native `getStackTraceAddresses()` を追加する
- [x] STDLIB-NATIVE-PLATFORM-021: Native unhandled-exception hook APIs（`getUnhandledExceptionHook`, `setUnhandledExceptionHook`, `processUnhandledException`, `terminateWithUnhandledException`）を追加する
- [x] STDLIB-NATIVE-CONCURRENT-001: `kotlin.native.concurrent` の対象 API 一覧を固定
- [x] STDLIB-NATIVE-CONCURRENT-002: `kotlin.native.concurrent` の sema / diagnostics を整える
- [x] STDLIB-NATIVE-CONCURRENT-003: `kotlin.native.concurrent` の最小 runtime / ABI を実装
- [x] STDLIB-NATIVE-CONCURRENT-004: `DetachedObjectGraph<T>` surface を追加する
- [x] STDLIB-NATIVE-CONCURRENT-005: `FreezingException` class surface を追加する
- [x] STDLIB-NATIVE-CONCURRENT-006: `InvalidMutabilityException` class surface を追加する
- [x] STDLIB-NATIVE-CONCURRENT-007: `WorkerBoundReference<T>` surface を追加する
- [x] STDLIB-NATIVE-CONCURRENT-008: `atomicLazy(initializer)` を追加する
- [x] STDLIB-NATIVE-CONCURRENT-009: `Any.ensureNeverFrozen()` を追加する
- [x] STDLIB-NATIVE-CONCURRENT-010: `Continuation0` / `Continuation1` / `Continuation2` type surface を追加する
- [x] STDLIB-NATIVE-CONCURRENT-011: `callContinuation0` / `callContinuation1` / `callContinuation2` を追加する
- [x] STDLIB-NATIVE-CONCURRENT-012: `waitForMultipleFutures(futures)` を追加する
- [x] STDLIB-NATIVE-CONCURRENT-013: `waitWorkerTermination(worker)` を追加する
- [x] STDLIB-NATIVE-CONCURRENT-014: `withWorker(name, block)` を追加する
- [x] STDLIB-NATIVE-CONCURRENT-015: legacy `kotlin.native.concurrent.AtomicInt` / `AtomicLong` / `AtomicNativePtr` surface を追加する
- [x] STDLIB-NATIVE-CONCURRENT-016: `FreezableAtomicReference<T>` surface を追加する
- [x] STDLIB-NATIVE-CONCURRENT-017: `MutableData` surface を追加する
- [x] STDLIB-NATIVE-CONCURRENT-018: `ObsoleteWorkersApi` marker を追加する
- [x] STDLIB-NATIVE-CONCURRENT-019: `Any?.isFrozen` / `<T>.freeze()` surface を追加する
- [x] STDLIB-EXPERIMENTAL-001: `kotlin.experimental` の marker 一覧を固定
- [x] STDLIB-EXPERIMENTAL-002: `kotlin.experimental` の opt-in / diagnostics を整える
- [x] STDLIB-EXPERIMENTAL-003: `kotlin.experimental.ExpectRefinement` annotation を追加し、expect declaration metadata へ露出する

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
