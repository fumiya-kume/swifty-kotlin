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
- [ ] STDLIB-022: range / progression / unsigned range の網羅性を上げる

#### kotlin.collections 抽象基底クラスの実装

#### kotlin.collections 具象実装クラスの実装

#### kotlin.collections 関数の実装（A-C）
- [x] STDLIB-COL-FN-001: `addAll` 関数の実装（Array版）
- [x] STDLIB-COL-FN-002: `addAll` 関数の実装（Iterable版）
- [x] STDLIB-COL-FN-003: `addAll` 関数の実装（Sequence版）
- [x] STDLIB-COL-FN-006: `all` 関数の実装（Array版）
- [x] STDLIB-COL-FN-007: `all` 関数の実装（Iterable版）
- [x] STDLIB-COL-FN-009: `any` 関数の実装（各オーバーロード）
- [x] STDLIB-COL-FN-018: `associate` 関数の実装
- [x] STDLIB-COL-FN-019: `associateBy` 関数の実装
- [x] STDLIB-COL-FN-021: `associateWith` 関数の実装
- [x] STDLIB-COL-FN-034: `contains` 関数の実装

#### kotlin.collections 関数の実装（D-Z）
- [x] STDLIB-COL-FN-048: `dropLastWhile` 関数の実装
- [x] STDLIB-COL-FN-060: `filterIsInstance` 関数の実装
- [x] STDLIB-COL-FN-071: `first` 関数の実装
- [x] STDLIB-COL-FN-077: `flatMapIndexedTo` 関数の実装
- [x] STDLIB-COL-FN-078: `flatMapTo` 関数の実装
- [x] STDLIB-COL-FN-079: `flatten` 関数の実装
- [x] STDLIB-COL-FN-081: `foldIndexed` 関数の実装
- [x] STDLIB-COL-FN-082: `foldRight` 関数の実装
- [x] STDLIB-COL-FN-083: `foldRightIndexed` 関数の実装
- [x] STDLIB-COL-FN-080: `fold` 関数の実装
- [x] STDLIB-COL-FN-084: `forEach` 関数の実装
- [x] STDLIB-COL-FN-087: `getOrDefault` 関数の実装
- [x] STDLIB-COL-FN-090: `groupBy` 関数の実装
- [x] STDLIB-COL-FN-101: `iterator` 関数の実装
- [x] STDLIB-COL-FN-139: `minOfWith` 関数の実装
- [x] STDLIB-COL-FN-160: `reduce` 関数の実装
- [x] STDLIB-COL-FN-159: `randomOrNull` 関数の実装
- [x] STDLIB-COL-FN-198: `sumByDouble` 関数の実装
- [x] STDLIB-COL-FN-203: `takeWhile` 関数の実装
- [x] STDLIB-COL-FN-212: `toList` 関数の実装
- [x] STDLIB-COL-FN-215: `toMutableList` 関数の実装
- [x] STDLIB-COL-FN-220: `toTypeArray` 関数の実装
- [x] STDLIB-COL-FN-225: `windowed` 関数の実装

### Phase 3: I/O・パス・時間・並行（common）
- [~] STDLIB-GAP-PH3: `kotlin.io`（common） / `kotlin.time` / `kotlin.concurrent` / `kotlin.concurrent.atomics` の未対応を潰す
- [ ] STDLIB-030: `kotlin.io` common 範囲の file / buffered / `use` を仕様単位で締める
- [ ] STDLIB-033: `kotlin.concurrent` / `kotlin.concurrent.atomics` / Native concurrent の parity を上げる

#### kotlin.concurrent 型の実装
- [x] STDLIB-CONC-TYPE-007: `Volatile` アノテーションの実装

#### kotlin.concurrent 関数の実装
- [x] STDLIB-CONC-FN-001: `atomicArrayOf` 関数の実装
- [x] STDLIB-CONC-FN-002: `AtomicIntArray` 関数の実装（factory版）
- [x] STDLIB-CONC-FN-003: `AtomicLongArray` 関数の実装（factory版）
- [ ] STDLIB-CONC-FN-004: `fixedRateTimer` 関数の実装（各オーバーロード）
- [ ] STDLIB-CONC-FN-005: `schedule` 関数の実装
- [ ] STDLIB-CONC-FN-006: `scheduleAtFixedRate` 関数の実装（各オーバーロード）
- [x] STDLIB-CONC-FN-007: `thread` 関数の実装
- [ ] STDLIB-CONC-FN-008: `timer` 関数の実装（各オーバーロード）

#### kotlin.concurrent.atomics 型の実装

#### kotlin.concurrent.atomics 関数の実装
- [x] STDLIB-ATOMIC-NEW-FN-002: `asJavaAtomic` 関数の実装（AtomicInt版）
- [x] STDLIB-ATOMIC-NEW-FN-003: `asJavaAtomic` 関数の実装（AtomicLong版）
- [x] STDLIB-ATOMIC-NEW-FN-004: `asJavaAtomic` 関数の実装（AtomicReference版）
- [x] STDLIB-ATOMIC-NEW-FN-005: `asJavaAtomicArray` 関数の実装（AtomicArray版）
- [x] STDLIB-ATOMIC-NEW-FN-006: `asJavaAtomicArray` 関数の実装（AtomicIntArray版）
- [x] STDLIB-ATOMIC-NEW-FN-007: `asJavaAtomicArray` 関数の実装（AtomicLongArray版）
- [x] STDLIB-ATOMIC-NEW-FN-008: `asKotlinAtomic` 関数の実装（各オーバーロード）
- [ ] STDLIB-ATOMIC-NEW-FN-009: `asKotlinAtomicArray` 関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-012: `AtomicLongArray` 関数の実装（factory版）
- [x] STDLIB-ATOMIC-NEW-FN-013: `fetchAndUpdate` 拡張関数の実装（AtomicArray版）
- [x] STDLIB-ATOMIC-NEW-FN-014: `fetchAndUpdate` 拡張関数の実装（AtomicBoolean版）
- [x] STDLIB-ATOMIC-NEW-FN-015: `fetchAndUpdate` 拡張関数の実装（AtomicIntArray版）
- [ ] STDLIB-ATOMIC-NEW-FN-017: `fetchAndUpdate` 拡張関数の実装（AtomicLongArray版）
- [x] STDLIB-ATOMIC-NEW-FN-018: `fetchAndUpdate` 拡張関数の実装（AtomicLong版）
- [x] STDLIB-ATOMIC-NEW-FN-019: `fetchAndUpdate` 拡張関数の実装（AtomicNativePtr版）
- [x] STDLIB-ATOMIC-NEW-FN-020: `fetchAndUpdate` 拡張関数の実装（AtomicReference版）
- [x] STDLIB-ATOMIC-NEW-FN-021: `fetchAndDecrement` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-022: `fetchAndIncrement` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-023: `getAndUpdate` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-024: `updateAndGet` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-025: `compareAndSet` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-026: `getAndSet` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-027: `incrementAndGet` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-028: `decrementAndGet` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-029: `getAndIncrement` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-030: `getAndDecrement` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-031: `addAndGet` 拡張関数の実装（各オーバーロード）
- [x] STDLIB-ATOMIC-NEW-FN-032: `getAndAdd` 拡張関数の実装（各オーバーロード）

#### kotlin.contracts 型の実装
- [x] STDLIB-CONTRACT-TYPE-001: `CallsInPlace` クラスの実装
- [x] STDLIB-CONTRACT-TYPE-009: `Returns` クラスの実装
- [x] STDLIB-CONTRACT-TYPE-010: `ReturnsNotNull` クラスの実装

#### kotlin.coroutines.cancellation 関数の実装

#### kotlin.io 型の実装
- [ ] STDLIB-IO-TYPE-001: `AccessDeniedException` クラスの実装
- [ ] STDLIB-IO-TYPE-002: `FileAlreadyExistsException` クラスの実装
- [ ] STDLIB-IO-TYPE-003: `FileSystemException` クラスの実装
- [ ] STDLIB-IO-TYPE-004: `FileTreeWalk` クラスの実装
- [ ] STDLIB-IO-TYPE-005: `FileWalkDirection` enum の実装
- [ ] STDLIB-IO-TYPE-006: `NoSuchFileException` クラスの実装
- [ ] STDLIB-IO-TYPE-007: `OnErrorAction` enum の実装

#### kotlin.io プロパティの実装
- [ ] STDLIB-IO-PROP-002: `extension` 拡張プロパティの実装
- [ ] STDLIB-IO-PROP-003: `invariantSeparatorsPath` 拡張プロパティの実装
- [ ] STDLIB-IO-PROP-004: `isRooted` 拡張プロパティの実装
- [ ] STDLIB-IO-PROP-005: `nameWithoutExtension` 拡張プロパティの実装

#### kotlin.io 関数の実装
- [ ] STDLIB-IO-FN-001: `appendBytes` 関数の実装
- [ ] STDLIB-IO-FN-003: `buffered` 関数の実装（InputStream版）
- [ ] STDLIB-IO-FN-004: `buffered` 関数の実装（OutputStream版）
- [ ] STDLIB-IO-FN-005: `buffered` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-006: `buffered` 関数の実装（Writer版）
- [ ] STDLIB-IO-FN-007: `bufferedReader` 関数の実装（InputStream版）
- [ ] STDLIB-IO-FN-009: `bufferedWriter` 関数の実装（OutputStream版）
- [ ] STDLIB-IO-FN-010: `bufferedWriter` 関数の実装（File版）
- [ ] STDLIB-IO-FN-011: `byteInputStream` 関数の実装
- [ ] STDLIB-IO-FN-012: `copyRecursively` 関数の実装
- [ ] STDLIB-IO-FN-013: `copyTo` 関数の実装（InputStream版）
- [ ] STDLIB-IO-FN-014: `copyTo` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-015: `copyTo` 関数の実装（File版）
- [ ] STDLIB-IO-FN-016: `forEachBlock` 関数の実装
- [ ] STDLIB-IO-FN-017: `forEachLine` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-020: `inputStream` 関数の実装（ByteArray版）
- [ ] STDLIB-IO-FN-021: `inputStream` 関数の実装（ByteArray範囲版）
- [ ] STDLIB-IO-FN-022: `iterator` 関数の実装
- [ ] STDLIB-IO-FN-024: `normalize` 関数の実装
- [ ] STDLIB-IO-FN-027: `printWriter` 関数の実装
- [ ] STDLIB-IO-FN-029: `readBytes` 関数の実装（InputStream版）
- [ ] STDLIB-IO-FN-030: `readBytes` 関数の実装（URL版）
- [ ] STDLIB-IO-FN-033: `readText` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-035: `readText` 関数の実装（URL版）
- [ ] STDLIB-IO-FN-036: `resolveSibling` 関数の実装
- [ ] STDLIB-IO-FN-037: `startsWith` 関数の実装
- [ ] STDLIB-IO-FN-038: `toRelativeString` 関数の実装
- [ ] STDLIB-IO-FN-040: `useLines` 関数の実装（Reader版）

#### kotlin.io.encoding 型の実装

#### kotlin.io.encoding 関数の実装
- [ ] STDLIB-IO-ENC-FN-001: `decodingWith` 関数の実装
- [ ] STDLIB-IO-ENC-FN-002: `encodingWith` 関数の実装

#### kotlin.io.path プロパティの実装
- [ ] STDLIB-IO-PATH-PROP-001: `extension` 拡張プロパティの実装
- [ ] STDLIB-IO-PATH-PROP-006: `pathString` 拡張プロパティの実装

#### kotlin.io.path 関数の実装
- [ ] STDLIB-IO-PATH-FN-007: `bufferedReader` 関数の実装
- [ ] STDLIB-IO-PATH-FN-010: `copyToRecursively` 関数の実装
- [ ] STDLIB-IO-PATH-FN-011: `createSymbolicLinkPointingTo` 関数の実装
- [ ] STDLIB-IO-PATH-FN-012: `createTempDirectory` 関数の実装
- [ ] STDLIB-IO-PATH-FN-013: `createTempFile` 関数の実装
- [ ] STDLIB-IO-PATH-FN-018: `fileVisitor` 関数の実装
- [ ] STDLIB-IO-PATH-FN-019: `forEachDirectoryEntry` 関数の実装
- [ ] STDLIB-IO-PATH-FN-020: `forEachLine` 関数の実装
- [ ] STDLIB-IO-PATH-FN-021: `getAttribute` 関数の実装
- [ ] STDLIB-IO-PATH-FN-022: `getLastModifiedTime` 関数の実装
- [ ] STDLIB-IO-PATH-FN-023: `getOwner` 関数の実装
- [ ] STDLIB-IO-PATH-FN-024: `getPosixFilePermissions` 関数の実装
- [ ] STDLIB-IO-PATH-FN-025: `inputStream` 関数の実装
- [ ] STDLIB-IO-PATH-FN-026: `moveTo` 関数の実装
- [ ] STDLIB-IO-PATH-FN-027: `notExists` 関数の実装
- [ ] STDLIB-IO-PATH-FN-028: `outputStream` 関数の実装
- [ ] STDLIB-IO-PATH-FN-030: `readAttributes` 関数の実装
- [ ] STDLIB-IO-PATH-FN-032: `setAttribute` 関数の実装
- [ ] STDLIB-IO-PATH-FN-036: `toPath` 関数の実装
- [ ] STDLIB-IO-PATH-FN-037: `useDirectoryEntries` 関数の実装
- [ ] STDLIB-IO-PATH-FN-038: `useLines` 関数の実装
- [ ] STDLIB-IO-PATH-FN-039: `walk` 関数の実装
- [ ] STDLIB-IO-PATH-FN-040: `writeLines` 関数の実装（Iterable版）
- [ ] STDLIB-IO-PATH-FN-041: `writeLines` 関数の実装（Sequence版）
- [ ] STDLIB-IO-PATH-FN-042: `writer` 関数の実装

#### kotlin.math プロパティの実装

#### kotlin.math 関数の実装

#### kotlin.random 型の実装

#### kotlin.random 関数の実装
- [ ] STDLIB-RANDOM-FN-001: `asJavaRandom` 関数の実装
- [ ] STDLIB-RANDOM-FN-002: `asKotlinRandom` 関数の実装

#### kotlin.ranges 関数の実装
- [x] STDLIB-RANGES-FN-004: `coerceValueIn` 関数の実装

#### kotlin.reflect 型の実装
- [x] STDLIB-REFLECT-TYPE-009: `KMutableProperty` インターフェースの実装
- [ ] STDLIB-REFLECT-TYPE-010: `KMutableProperty0` インターフェースの実装
- [x] STDLIB-REFLECT-TYPE-011: `KMutableProperty1` インターフェースの実装
- [ ] STDLIB-REFLECT-TYPE-013: `KParameter` インターフェースの実装
- [x] STDLIB-REFLECT-TYPE-015: `KProperty0` インターフェースの実装
- [ ] STDLIB-REFLECT-TYPE-016: `KProperty1` インターフェースの実装
- [x] STDLIB-REFLECT-TYPE-022: `KVisibility` enum の実装

#### kotlin.reflect プロパティの実装
- [ ] STDLIB-REFLECT-PROP-001: `javaType` 拡張プロパティの実装

#### kotlin.reflect 関数の実装
- [x] STDLIB-REFLECT-FN-002: `createInstance` 拡張関数の実装

#### kotlin.sequences 型の実装
- [ ] STDLIB-SEQ-TYPE-001: `Sequence` インターフェースの実装
- [ ] STDLIB-SEQ-TYPE-002: `SequenceScope` クラスの実装

#### kotlin.sequences 関数の実装
- [x] STDLIB-SEQ-FN-001: `all` 関数の実装
- [x] STDLIB-SEQ-FN-002: `any` 関数の実装
- [x] STDLIB-SEQ-FN-003: `asIterable` 関数の実装
- [ ] STDLIB-SEQ-FN-004: `asSequence` 関数の実装
- [x] STDLIB-SEQ-FN-005: `associate` 関数の実装
- [x] STDLIB-SEQ-FN-006: `associateBy` 関数の実装
- [ ] STDLIB-SEQ-FN-007: `associateByTo` 関数の実装
- [ ] STDLIB-SEQ-FN-008: `associateTo` 関数の実装
- [ ] STDLIB-SEQ-FN-009: `associateWith` 関数の実装
- [x] STDLIB-SEQ-FN-009: `associateWith` 関数の実装
- [ ] STDLIB-SEQ-FN-010: `associateWithTo` 関数の実装
- [ ] STDLIB-SEQ-FN-011: `averageOf` 関数の実装
- [ ] STDLIB-SEQ-FN-012: `chunked` 関数の実装
- [x] STDLIB-SEQ-FN-013: `constrainOnce` 関数の実装
- [ ] STDLIB-SEQ-FN-014: `contains` 関数の実装
- [ ] STDLIB-SEQ-FN-015: `count` 関数の実装
- [ ] STDLIB-SEQ-FN-016: `distinct` 関数の実装
- [ ] STDLIB-SEQ-FN-017: `distinctBy` 関数の実装
- [ ] STDLIB-SEQ-FN-018: `drop` 関数の実装
- [ ] STDLIB-SEQ-FN-019: `dropWhile` 関数の実装
- [ ] STDLIB-SEQ-FN-020: `elementAt` 関数の実装
- [ ] STDLIB-SEQ-FN-021: `elementAtOrElse` 関数の実装
- [ ] STDLIB-SEQ-FN-022: `elementAtOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-023: `filter` 関数の実装
- [x] STDLIB-SEQ-FN-024: `filterIndexed` 関数の実装
- [ ] STDLIB-SEQ-FN-025: `filterIndexedTo` 関数の実装
- [ ] STDLIB-SEQ-FN-026: `filterIsInstance` 関数の実装
- [ ] STDLIB-SEQ-FN-027: `filterIsInstanceTo` 関数の実装
- [x] STDLIB-SEQ-FN-028: `filterNot` 関数の実装
- [ ] STDLIB-SEQ-FN-029: `filterNotNull` 関数の実装
- [ ] STDLIB-SEQ-FN-030: `filterNotTo` 関数の実装
- [ ] STDLIB-SEQ-FN-031: `filterTo` 関数の実装
- [x] STDLIB-SEQ-FN-032: `find` 関数の実装
- [ ] STDLIB-SEQ-FN-033: `findLast` 関数の実装
- [ ] STDLIB-SEQ-FN-034: `first` 関数の実装
- [ ] STDLIB-SEQ-FN-037: `firstOrNull` 関数の実装
- [x] STDLIB-SEQ-FN-038: `flatMap` 関数の実装
- [x] STDLIB-SEQ-FN-039: `flatMapIndexed` 関数の実装
- [ ] STDLIB-SEQ-FN-040: `flatMapIndexedTo` 関数の実装
- [ ] STDLIB-SEQ-FN-041: `flatMapTo` 関数の実装
- [ ] STDLIB-SEQ-FN-042: `fold` 関数の実装
- [x] STDLIB-SEQ-FN-043: `foldIndexed` 関数の実装
- [ ] STDLIB-SEQ-FN-044: `forEach` 関数の実装
- [ ] STDLIB-SEQ-FN-046: `groupBy` 関数の実装
- [ ] STDLIB-SEQ-FN-047: `groupByTo` 関数の実装
- [x] STDLIB-SEQ-FN-048: `indexOf` 関数の実装
- [ ] STDLIB-SEQ-FN-049: `indexOfFirst` 関数の実装
- [ ] STDLIB-SEQ-FN-050: `indexOfLast` 関数の実装
- [ ] STDLIB-SEQ-FN-051: `intersect` 関数の実装
 - [x] STDLIB-SEQ-FN-052: `joinTo` 関数の実装
 - [x] STDLIB-SEQ-FN-053: `joinToString` 関数の実装
 - [x] STDLIB-SEQ-FN-054: `last` 関数の実装
- [ ] STDLIB-SEQ-FN-055: `lastIndexOf` 関数の実装
- [ ] STDLIB-SEQ-FN-056: `lastOrNull` 関数の実装
- [x] STDLIB-SEQ-FN-057: `map` 関数の実装
- [x] STDLIB-SEQ-FN-058: `mapIndexed` 関数の実装
- [ ] STDLIB-SEQ-FN-059: `mapIndexedNotNull` 関数の実装
- [x] STDLIB-SEQ-FN-060: `mapIndexedNotNullTo` 関数の実装
- [ ] STDLIB-SEQ-FN-061: `mapIndexedTo` 関数の実装
- [ ] STDLIB-SEQ-FN-062: `mapNotNull` 関数の実装
- [x] STDLIB-SEQ-FN-063: `mapNotNullTo` 関数の実装
- [x] STDLIB-SEQ-FN-064: `mapTo` 関数の実装
- [ ] STDLIB-SEQ-FN-065: `max` 関数の実装
- [x] STDLIB-SEQ-FN-066: `maxBy` 関数の実装
- [ ] STDLIB-SEQ-FN-067: `maxByOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-068: `maxOf` 関数の実装
- [x] STDLIB-SEQ-FN-069: `maxOfOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-070: `maxOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-071: `maxWith` 関数の実装
- [x] STDLIB-SEQ-FN-072: `maxWithOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-073: `min` 関数の実装
- [ ] STDLIB-SEQ-FN-074: `minBy` 関数の実装
- [ ] STDLIB-SEQ-FN-075: `minByOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-076: `minOf` 関数の実装
- [ ] STDLIB-SEQ-FN-077: `minOfOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-078: `minOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-079: `minWith` 関数の実装
- [ ] STDLIB-SEQ-FN-080: `minWithOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-081: `minus` 関数の実装
- [x] STDLIB-SEQ-FN-083: `none` 関数の実装
- [x] STDLIB-SEQ-FN-084: `onEach` 関数の実装
- [x] STDLIB-SEQ-FN-085: `onEachIndexed` 関数の実装
- [ ] STDLIB-SEQ-FN-086: `partition` 関数の実装
- [ ] STDLIB-SEQ-FN-087: `plus` 関数の実装
- [x] STDLIB-SEQ-FN-088: `plusElement` 関数の実装
- [ ] STDLIB-SEQ-FN-089: `random` 関数の実装
- [x] STDLIB-SEQ-FN-090: `randomOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-091: `reduce` 関数の実装
- [ ] STDLIB-SEQ-FN-092: `reduceIndexed` 関数の実装
- [ ] STDLIB-SEQ-FN-093: `reduceOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-094: `reduceRight` 関数の実装
- [ ] STDLIB-SEQ-FN-095: `reduceRightIndexed` 関数の実装
- [ ] STDLIB-SEQ-FN-096: `reduceRightIndexedOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-097: `reduceRightOrNull` 関数の実装
- [x] STDLIB-SEQ-FN-098: `requireNoNulls` 関数の実装
- [ ] STDLIB-SEQ-FN-099: `reversed` 関数の実装
- [ ] STDLIB-SEQ-FN-100: `runningFold` 関数の実装
- [x] STDLIB-SEQ-FN-101: `runningFoldIndexed` 関数の実装
- [ ] STDLIB-SEQ-FN-102: `runningReduce` 関数の実装
- [ ] STDLIB-SEQ-FN-103: `runningReduceIndexed` 関数の実装
- [ ] STDLIB-SEQ-FN-104: `scan` 関数の実装
- [x] STDLIB-SEQ-FN-105: `scanIndexed` 関数の実装
- [x] STDLIB-SEQ-FN-106: `shuffled` 関数の実装
- [ ] STDLIB-SEQ-FN-107: `single` 関数の実装
- [x] STDLIB-SEQ-FN-108: `singleOrNull` 関数の実装
- [ ] STDLIB-SEQ-FN-109: `slice` 関数の実装
- [ ] STDLIB-SEQ-FN-110: `sorted` 関数の実装
- [x] STDLIB-SEQ-FN-111: `sortedBy` 関数の実装
- [ ] STDLIB-SEQ-FN-112: `sortedByDescending` 関数の実装
- [ ] STDLIB-SEQ-FN-113: `sortedDescending` 関数の実装
- [ ] STDLIB-SEQ-FN-114: `sortedWith` 関数の実装
- [ ] STDLIB-SEQ-FN-115: `subtract` 関数の実装
- [x] STDLIB-SEQ-FN-116: `sum` 関数の実装
- [x] STDLIB-SEQ-FN-118: `sumOf` 関数の実装
- [ ] STDLIB-SEQ-FN-119: `take` 関数の実装
- [x] STDLIB-SEQ-FN-120: `takeLast` 関数の実装
- [x] STDLIB-SEQ-FN-121: `takeLastWhile` 関数の実装
- [x] STDLIB-SEQ-FN-122: `takeWhile` 関数の実装
- [x] STDLIB-SEQ-FN-123: `toCollection` 関数の実装
- [x] STDLIB-SEQ-FN-124: `toHashSet` 関数の実装
- [x] STDLIB-SEQ-FN-125: `toList` 関数の実装
- [x] STDLIB-SEQ-FN-126: `toMutableList` 関数の実装
- [x] STDLIB-SEQ-FN-127: `toMutableSet` 関数の実装
- [x] STDLIB-SEQ-FN-128: `toSet` 関数の実装
- [x] STDLIB-SEQ-FN-129: `toSortedSet` 関数の実装
- [x] STDLIB-SEQ-FN-130: `union` 関数の実装
- [x] STDLIB-SEQ-FN-131: `windowed` 関数の実装
- [ ] STDLIB-SEQ-FN-132: `withIndex` 関数の実装
- [ ] STDLIB-SEQ-FN-133: `zip` 関数の実装
- [x] STDLIB-SEQ-FN-134: `zipWithNext` 関数の実装

#### kotlin.streams 関数の実装
- [x] STDLIB-STREAMS-FN-001: `asSequence` 関数の実装（各ストリーム型）
- [ ] STDLIB-STREAMS-FN-002: `asStream` 関数の実装
- [ ] STDLIB-STREAMS-FN-003: `toList` 関数の実装（各ストリーム型）

#### kotlin.system 関数の実装
- [ ] STDLIB-SYSTEM-FN-001: `exitProcess` 関数の実装
- [ ] STDLIB-SYSTEM-FN-002: `getTimeMicros` 関数の実装
- [ ] STDLIB-SYSTEM-FN-003: `getTimeMillis` 関数の実装
- [ ] STDLIB-SYSTEM-FN-004: `getTimeNanos` 関数の実装
- [ ] STDLIB-SYSTEM-FN-005: `measureNanoTime` 関数の実装
- [ ] STDLIB-SYSTEM-FN-006: `measureTimeMicros` 関数の実装
- [ ] STDLIB-SYSTEM-FN-007: `measureTimeMillis` 関数の実装

#### kotlin.text 型の実装
- [ ] STDLIB-TEXT-TYPE-001: `Appendable` インターフェースの実装
- [ ] STDLIB-TEXT-TYPE-002: `CharacterCodingException` クラスの実装
- [ ] STDLIB-TEXT-TYPE-003: `CharCategory` enum の実装
- [ ] STDLIB-TEXT-TYPE-004: `CharDirectionality` enum の実装
- [ ] STDLIB-TEXT-TYPE-005: `Charsets` オブジェクトの実装
- [ ] STDLIB-TEXT-TYPE-006: `HexFormat` クラスの実装
- [ ] STDLIB-TEXT-TYPE-007: `MatchGroup` クラスの実装
- [ ] STDLIB-TEXT-TYPE-008: `MatchGroupCollection` インターフェースの実装
- [ ] STDLIB-TEXT-TYPE-009: `MatchNamedGroupCollection` インターフェースの実装
- [ ] STDLIB-TEXT-TYPE-010: `MatchResult` インターフェースの実装
- [ ] STDLIB-TEXT-TYPE-011: `Regex` クラスの実装
- [ ] STDLIB-TEXT-TYPE-012: `RegexOption` enum の実装
- [ ] STDLIB-TEXT-TYPE-013: `StringBuilder` クラスの実装

#### kotlin.text プロパティの実装
- [ ] STDLIB-TEXT-PROP-001: `CASE_INSENSITIVE_ORDER` プロパティの実装
- [ ] STDLIB-TEXT-PROP-002: `category` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-003: `directionality` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-004: `isDefined` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-005: `isDigit` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-006: `isHighSurrogate` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-007: `isISOControl` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-008: `isIdentifierIgnorable` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-009: `isJavaIdentifierPart` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-010: `isJavaIdentifierStart` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-011: `isLetter` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-012: `isLetterOrDigit` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-013: `isLowerCase` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-014: `isLowSurrogate` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-015: `isSurrogate` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-016: `isTitleCase` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-017: `isUnicodeIdentifierPart` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-018: `isUpperCase` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-019: `isWhitespace` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-020: `lowercase` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-021: `titlecase` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-022: `uppercase` 拡張プロパティの実装

#### kotlin.text 関数の実装
- [ ] STDLIB-TEXT-FN-001: `all` 関数の実装
- [ ] STDLIB-TEXT-FN-002: `any` 関数の実装
- [ ] STDLIB-TEXT-FN-003: `append` 関数の実装
- [ ] STDLIB-TEXT-FN-004: `appendLine` 関数の実装
- [ ] STDLIB-TEXT-FN-005: `appendRange` 関数の実装
- [ ] STDLIB-TEXT-FN-006: `buildString` 関数の実装
- [ ] STDLIB-TEXT-FN-007: `buildStringAppend` 関数の実装
- [ ] STDLIB-TEXT-FN-008: `buildStringBuilder` 関数の実装
- [ ] STDLIB-TEXT-FN-009: `capitalize` 関数の実装
- [ ] STDLIB-TEXT-FN-010: `codePointCount` 関数の実装
- [ ] STDLIB-TEXT-FN-011: `concat` 関数の実装
- [ ] STDLIB-TEXT-FN-012: `contains` 関数の実装
- [ ] STDLIB-TEXT-FN-013: `decodeToString` 関数の実装
- [ ] STDLIB-TEXT-FN-014: `encodeToByteArray` 関数の実装
- [ ] STDLIB-TEXT-FN-015: `endsWith` 関数の実装
- [ ] STDLIB-TEXT-FN-016: `equals` 関数の実装
- [ ] STDLIB-TEXT-FN-017: `format` 関数の実装
- [ ] STDLIB-TEXT-FN-018: `get` 関数の実装
- [ ] STDLIB-TEXT-FN-019: `indent` 関数の実装
- [ ] STDLIB-TEXT-FN-020: `indexOf` 関数の実装
- [ ] STDLIB-TEXT-FN-021: `indexOfAny` 関数の実装
- [ ] STDLIB-TEXT-FN-022: `indexOfFirst` 関数の実装
- [ ] STDLIB-TEXT-FN-023: `indexOfLast` 関数の実装
- [ ] STDLIB-TEXT-FN-024: `insert` 関数の実装
- [ ] STDLIB-TEXT-FN-025: `insertRange` 関数の実装
- [ ] STDLIB-TEXT-FN-026: `intern` 関数の実装
- [ ] STDLIB-TEXT-FN-027: `isBlank` 関数の実装
- [ ] STDLIB-TEXT-FN-028: `isEmpty` 関数の実装
- [ ] STDLIB-TEXT-FN-029: `isNotBlank` 関数の実装
- [ ] STDLIB-TEXT-FN-030: `isNotEmpty` 関数の実装
- [ ] STDLIB-TEXT-FN-031: `isNullOrEmpty` 関数の実装
- [ ] STDLIB-TEXT-FN-032: `isNullOrBlank` 関数の実装
- [ ] STDLIB-TEXT-FN-033: `iterator` 関数の実装
- [ ] STDLIB-TEXT-FN-034: `lastIndexOf` 関数の実装
- [ ] STDLIB-TEXT-FN-035: `lastIndexOfAny` 関数の実装
- [ ] STDLIB-TEXT-FN-036: `lineSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-037: `lines` 関数の実装
- [ ] STDLIB-TEXT-FN-038: `minus` 関数の実装
- [ ] STDLIB-TEXT-FN-039: `onEach` 関数の実装
- [ ] STDLIB-TEXT-FN-040: `onEachIndexed` 関数の実装
- [ ] STDLIB-TEXT-FN-041: `padEnd` 関数の実装
- [ ] STDLIB-TEXT-FN-042: `padStart` 関数の実装
- [ ] STDLIB-TEXT-FN-043: `plus` 関数の実装
- [ ] STDLIB-TEXT-FN-044: `random` 関数の実装
- [ ] STDLIB-TEXT-FN-045: `randomOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-046: `reduce` 関数の実装
- [ ] STDLIB-TEXT-FN-047: `reduceIndexed` 関数の実装
- [ ] STDLIB-TEXT-FN-048: `reduceIndexedOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-049: `reduceOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-050: `removePrefix` 関数の実装
- [ ] STDLIB-TEXT-FN-051: `removeRange` 関数の実装
- [ ] STDLIB-TEXT-FN-052: `removeSuffix` 関数の実装
- [ ] STDLIB-TEXT-FN-053: `removeSurrounding` 関数の実装
- [ ] STDLIB-TEXT-FN-054: `repeat` 関数の実装
- [ ] STDLIB-TEXT-FN-055: `replace` 関数の実装
- [ ] STDLIB-TEXT-FN-056: `replaceAfter` 関数の実装
- [ ] STDLIB-TEXT-FN-057: `replaceAfterLast` 関数の実装
- [ ] STDLIB-TEXT-FN-058: `replaceBefore` 関数の実装
- [ ] STDLIB-TEXT-FN-059: `replaceBeforeLast` 関数の実装
- [ ] STDLIB-TEXT-FN-060: `replaceFirst` 関数の実装
- [ ] STDLIB-TEXT-FN-061: `replaceIndent` 関数の実装
- [ ] STDLIB-TEXT-FN-062: `replaceRange` 関数の実装
- [ ] STDLIB-TEXT-FN-063: `reversed` 関数の実装
- [ ] STDLIB-TEXT-FN-064: `set` 関数の実装
- [ ] STDLIB-TEXT-FN-065: `setRange` 関数の実装
- [ ] STDLIB-TEXT-FN-066: `single` 関数の実装
- [ ] STDLIB-TEXT-FN-067: `singleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-068: `slice` 関数の実装
- [ ] STDLIB-TEXT-FN-069: `split` 関数の実装
- [ ] STDLIB-TEXT-FN-070: `splitToSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-071: `startsWith` 関数の実装
- [ ] STDLIB-TEXT-FN-072: `subSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-073: `substring` 関数の実装
- [ ] STDLIB-TEXT-FN-074: `substringAfter` 関数の実装
- [ ] STDLIB-TEXT-FN-075: `substringAfterLast` 関数の実装
- [ ] STDLIB-TEXT-FN-076: `substringBefore` 関数の実装
- [ ] STDLIB-TEXT-FN-077: `substringBeforeLast` 関数の実装
- [ ] STDLIB-TEXT-FN-078: `take` 関数の実装
- [ ] STDLIB-TEXT-FN-079: `takeIf` 関数の実装
- [ ] STDLIB-TEXT-FN-080: `takeLast` 関数の実装
- [ ] STDLIB-TEXT-FN-081: `takeLastWhile` 関数の実装
- [ ] STDLIB-TEXT-FN-082: `takeWhile` 関数の実装
- [ ] STDLIB-TEXT-FN-083: `toBigDecimal` 関数の実装
- [ ] STDLIB-TEXT-FN-084: `toBigDecimalOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-085: `toBigInteger` 関数の実装
- [ ] STDLIB-TEXT-FN-086: `toBigIntegerOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-087: `toBoolean` 関数の実装
- [ ] STDLIB-TEXT-FN-088: `toBooleanStrict` 関数の実装
- [ ] STDLIB-TEXT-FN-089: `toBooleanStrictOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-090: `toByte` 関数の実装
- [ ] STDLIB-TEXT-FN-091: `toByteOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-092: `toByteArray` 関数の実装
- [ ] STDLIB-TEXT-FN-093: `toCharArray` 関数の実装
- [ ] STDLIB-TEXT-FN-094: `toCollection` 関数の実装
- [ ] STDLIB-TEXT-FN-095: `toDouble` 関数の実装
- [ ] STDLIB-TEXT-FN-096: `toDoubleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-097: `toFloat` 関数の実装
- [ ] STDLIB-TEXT-FN-098: `toFloatOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-099: `toInt` 関数の実装
- [ ] STDLIB-TEXT-FN-100: `toIntOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-101: `toList` 関数の実装
- [ ] STDLIB-TEXT-FN-102: `toLong` 関数の実装
- [ ] STDLIB-TEXT-FN-103: `toLongOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-104: `toMutableList` 関数の実装
- [ ] STDLIB-TEXT-FN-105: `toRegex` 関数の実装
- [ ] STDLIB-TEXT-FN-106: `toShort` 関数の実装
- [ ] STDLIB-TEXT-FN-107: `toShortOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-108: `toSortedSet` 関数の実装
- [ ] STDLIB-TEXT-FN-109: `toTypedArray` 関数の実装
- [ ] STDLIB-TEXT-FN-110: `trim` 関数の実装
- [ ] STDLIB-TEXT-FN-111: `trimEnd` 関数の実装
- [ ] STDLIB-TEXT-FN-112: `trimIndent` 関数の実装
- [ ] STDLIB-TEXT-FN-113: `trimMargin` 関数の実装
- [ ] STDLIB-TEXT-FN-114: `trimStart` 関数の実装
- [ ] STDLIB-TEXT-FN-115: `withIndex` 関数の実装
- [ ] STDLIB-TEXT-FN-116: `zip` 関数の実装

#### kotlin.time 型の実装
- [ ] STDLIB-TIME-TYPE-001: `AbstractDoubleTimeSource` 抽象クラスの実装
- [ ] STDLIB-TIME-TYPE-002: `AbstractLongTimeSource` 抽象クラスの実装
- [ ] STDLIB-TIME-TYPE-003: `Clock` インターフェースの実装
- [ ] STDLIB-TIME-TYPE-004: `ComparableTimeMark` クラスの実装
- [ ] STDLIB-TIME-TYPE-005: `Duration` クラスの実装
- [ ] STDLIB-TIME-TYPE-006: `DurationUnit` enum の実装
- [ ] STDLIB-TIME-TYPE-007: `ExperimentalTime` アノテーションの実装
- [ ] STDLIB-TIME-TYPE-008: `Instant` クラスの実装
- [ ] STDLIB-TIME-TYPE-009: `TestTimeSource` クラスの実装
- [ ] STDLIB-TIME-TYPE-010: `TimedValue` クラスの実装
- [ ] STDLIB-TIME-TYPE-011: `TimeMark` クラスの実装
- [ ] STDLIB-TIME-TYPE-012: `TimeSource` インターフェースの実装

#### kotlin.time プロパティの実装
- [ ] STDLIB-TIME-PROP-001: `isDistantFuture` 拡張プロパティの実装
- [ ] STDLIB-TIME-PROP-002: `isDistantPast` 拡張プロパティの実装

#### kotlin.time 関数の実装
- [ ] STDLIB-TIME-FN-001: `asClock` 関数の実装
- [ ] STDLIB-TIME-FN-002: `measureTime` 関数の実装
- [ ] STDLIB-TIME-FN-003: `measureTimedValue` 関数の実装
- [ ] STDLIB-TIME-FN-004: `times` 関数の実装
- [ ] STDLIB-TIME-FN-005: `toDuration` 関数の実装
- [ ] STDLIB-TIME-FN-006: `toDurationUnit` 関数の実装
- [ ] STDLIB-TIME-FN-007: `toJavaDuration` 関数の実装
- [ ] STDLIB-TIME-FN-008: `toJavaInstant` 関数の実装
- [ ] STDLIB-TIME-FN-009: `toJSDate` 関数の実装
- [ ] STDLIB-TIME-FN-010: `toKotlinDuration` 関数の実装
- [ ] STDLIB-TIME-FN-011: `toKotlinInstant` 関数の実装
- [ ] STDLIB-TIME-FN-012: `toTimeUnit` 関数の実装

#### kotlin.uuid 型の実装
- [ ] STDLIB-UUID-TYPE-002: `Uuid` クラスの実装

#### kotlin.uuid 関数の実装
- [ ] STDLIB-UUID-FN-001: `getUuid` 関数の実装
- [ ] STDLIB-UUID-FN-002: `putUuid` 関数の実装
- [ ] STDLIB-UUID-FN-003: `toJavaUuid` 関数の実装
- [ ] STDLIB-UUID-FN-004: `toKotlinUuid` 関数の実装

### Phase 4: リフレクション・数値・テキスト・その他 stdlib
- [ ] STDLIB-GAP-PH4: `kotlin.math` / `kotlin.random` / `kotlin.reflect` / `kotlin.comparisons` / `kotlin.annotation` / `kotlin.system` / `kotlin.uuid` / `kotlin.native` 周辺の「部分」を潰す
- [ ] STDLIB-REFLECT-067: `KClass` / metadata / メンバ introspection の残差を詰める
- [ ] STDLIB-RANDOM-001: `kotlin.random` の対象 API 一覧を固定
- [ ] STDLIB-RANDOM-002: `kotlin.random` の sema / lowering を整える
- [ ] STDLIB-RANDOM-003: `kotlin.random` の runtime / seed / 境界値を固定
- [ ] STDLIB-COMP-001: `kotlin.comparisons` の対象 API 一覧を固定
- [ ] STDLIB-COMP-002: `Comparator` 合成の sema / lowering を整える
- [ ] STDLIB-COMP-003: `Comparator` runtime と failure path を固定

#### kotlin.comparisons 関数の実装
- [ ] STDLIB-COMP-FN-001: `compareBy` 関数の実装（selector版）
- [ ] STDLIB-COMP-FN-002: `compareByDescending` 関数の実装（selector版）
- [ ] STDLIB-COMP-FN-003: `compareValues` 関数の実装
- [ ] STDLIB-COMP-FN-004: `compareValuesBy` 関数の実装（selector版）
- [ ] STDLIB-COMP-FN-005: `maxOf` 関数の実装（Comparable版、2引数）
- [ ] STDLIB-COMP-FN-006: `maxOf` 関数の実装（Comparable版、3引数）
- [ ] STDLIB-COMP-FN-007: `maxOf` 関数の実装（Comparable版、vararg）
- [ ] STDLIB-COMP-FN-008: `maxOf` 関数の実装（Byte版、2引数）
- [ ] STDLIB-COMP-FN-009: `maxOf` 関数の実装（Byte版、3引数）
- [ ] STDLIB-COMP-FN-010: `maxOf` 関数の実装（Byte版、vararg）
- [ ] STDLIB-COMP-FN-011: `maxOf` 関数の実装（Double版、2引数）
- [ ] STDLIB-COMP-FN-012: `maxOf` 関数の実装（Double版、3引数）
- [ ] STDLIB-COMP-FN-013: `maxOf` 関数の実装（Double版、vararg）
- [ ] STDLIB-COMP-FN-014: `maxOf` 関数の実装（Float版、2引数）
- [ ] STDLIB-COMP-FN-015: `maxOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-016: `maxOf` 関数の実装（Float版、vararg）
- [ ] STDLIB-COMP-FN-017: `maxOf` 関数の実装（Int版、2引数）
- [ ] STDLIB-COMP-FN-018: `maxOf` 関数の実装（Int版、3引数）
- [ ] STDLIB-COMP-FN-019: `maxOf` 関数の実装（Int版、vararg）
- [ ] STDLIB-COMP-FN-020: `maxOf` 関数の実装（Long版、2引数）
- [ ] STDLIB-COMP-FN-021: `maxOf` 関数の実装（Long版、3引数）
- [ ] STDLIB-COMP-FN-022: `maxOf` 関数の実装（Long版、vararg）
- [ ] STDLIB-COMP-FN-023: `maxOf` 関数の実装（Short版、2引数）
- [ ] STDLIB-COMP-FN-024: `maxOf` 関数の実装（Short版、3引数）
- [ ] STDLIB-COMP-FN-025: `maxOf` 関数の実装（Short版、vararg）
- [ ] STDLIB-COMP-FN-026: `maxOfOrNull` 関数の実装（各オーバーロード）
- [ ] STDLIB-COMP-FN-027: `maxWith` 関数の実装
- [ ] STDLIB-COMP-FN-028: `maxWithOrNull` 関数の実装
- [ ] STDLIB-COMP-FN-029: `minOf` 関数の実装（Comparable版、2引数）
- [ ] STDLIB-COMP-FN-030: `minOf` 関数の実装（Comparable版、3引数）
- [ ] STDLIB-COMP-FN-031: `minOf` 関数の実装（Comparable版、vararg）
- [ ] STDLIB-COMP-FN-032: `minOf` 関数の実装（Byte版、2引数）
- [ ] STDLIB-COMP-FN-033: `minOf` 関数の実装（Byte版、3引数）
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
- [ ] STDLIB-COMP-FN-054: `minOfOrNull` 関数の実装（各オーバーロード）
- [ ] STDLIB-COMP-FN-055: `minWith` 関数の実装
- [ ] STDLIB-COMP-FN-056: `minWithOrNull` 関数の実装
- [ ] STDLIB-COMP-FN-057: `naturalOrder` 関数の実装
- [ ] STDLIB-COMP-FN-058: `naturalOrderComparator` 関数の実装
- [ ] STDLIB-COMP-FN-059: `nullsFirst` 関数の実装（Comparable版）
- [ ] STDLIB-COMP-FN-060: `nullsFirst` 関数の実装（Comparator版）
- [ ] STDLIB-COMP-FN-061: `nullsLast` 関数の実装（Comparable版）
- [ ] STDLIB-COMP-FN-062: `nullsLast` 関数の実装（Comparator版）
- [ ] STDLIB-COMP-FN-063: `reverseOrder` 関数の実装
- [ ] STDLIB-COMP-FN-064: `reverseOrderComparator` 関数の実装
- [ ] STDLIB-ANNO-002: annotation sema / diagnostics を整える
 - [x] STDLIB-ANNO-001: `kotlin.annotation` の対象一覧を固定
 - [x] STDLIB-ANNO-002: annotation sema / diagnostics を整える
- [~] STDLIB-CORO-001: `kotlin.coroutines.intrinsics` / cancellation — 主要部分実装済み（`suspendCoroutineUninterceptedOrReturn`, `intercepted`, `CancellationException`）。残課題は別チケットへ分割。
- [ ] STDLIB-CORO-003: `kotlin.coroutines` の一部ランタイム経路をセマフォ待機から脱却する。対象: `RuntimeAsyncTask.awaitResult`, `RuntimeJobHandle.join`, `kk_with_context`, Channel send/receive, Sequence builder( `sequence`, `iterator` ) の待機部。
- [ ] STDLIB-NATIVE-PLATFORM-001: `kotlin.native` の platform info 残差を詰める
- [ ] STDLIB-NATIVE-PLATFORM-002: common から見える Native bridge を整理

### Phase 5: 非スコープ/高度領域
- [ ] STDLIB-IO-PATH-PROP-005: `Path.nameWithoutExtension` extension property を追加する
- [ ] STDLIB-IO-PATH-PROP-006: `Path.pathString` extension property を追加する
- [ ] STDLIB-IO-PATH-FN-008: `Path.bufferedWriter(charset, bufferSize, options)` を追加する
- [ ] STDLIB-IO-PATH-FN-010: `Path.copyTo(target, overwrite)` を追加する
- [ ] STDLIB-IO-PATH-FN-011: `Path.copyToRecursively(target, onError, followLinks, overwrite)` を追加する
- [ ] STDLIB-IO-PATH-FN-012: `Path.copyToRecursively(target, onError, followLinks, copyAction)` を追加する
- [ ] STDLIB-IO-PATH-FN-013: `Path.createDirectories(attributes)` を追加する
- [ ] STDLIB-IO-PATH-FN-014: `Path.createDirectory(attributes)` を追加する
- [ ] STDLIB-IO-PATH-FN-015: `Path.createFile(attributes)` を追加する
- [ ] STDLIB-IO-PATH-FN-017: `Path.createParentDirectories(attributes)` を追加する
- [ ] STDLIB-IO-PATH-FN-018: `Path.createSymbolicLinkPointingTo(target, attributes)` を追加する
- [ ] STDLIB-IO-PATH-FN-019: `createTempDirectory(prefix, attributes)` を追加する
- [ ] STDLIB-IO-PATH-FN-020: `createTempDirectory(directory, prefix, attributes)` を追加する
- [ ] STDLIB-IO-PATH-FN-021: `createTempFile(prefix, suffix, attributes)` を追加する
- [ ] STDLIB-IO-PATH-FN-022: `createTempFile(directory, prefix, suffix, attributes)` を追加する
- [ ] STDLIB-IO-PATH-FN-024: `Path.deleteIfExists()` の公式 return/annotation shape を既存 stub と整合させる
- [x] STDLIB-IO-PATH-FN-028: `Path.exists(options)` を既存 no-arg stub から公式 vararg shape へ広げる
- [x] STDLIB-IO-PATH-FN-029: `Path.fileAttributesView<V>(options)` を追加する
- [x] STDLIB-IO-PATH-FN-030: `Path.fileAttributesViewOrNull<V>(options)` を追加する
- [ ] STDLIB-IO-PATH-FN-033: `fileVisitor(builderAction)` を追加する
- [ ] STDLIB-IO-PATH-FN-034: `Path.forEachDirectoryEntry(glob, action)` を追加する
- [x] STDLIB-IO-PATH-FN-035: `Path.forEachLine(charset, action)` を追加する
- [x] STDLIB-IO-PATH-FN-036: `Path.getAttribute(attribute, options)` を追加する
- [ ] STDLIB-IO-PATH-FN-037: `Path.getLastModifiedTime(options)` を追加する
- [x] STDLIB-IO-PATH-FN-038: `Path.getOwner(options)` を追加する
- [x] STDLIB-IO-PATH-FN-039: `Path.getPosixFilePermissions(options)` を追加する
- [ ] STDLIB-IO-PATH-FN-040: `Path.inputStream(options)` を追加する
- [x] STDLIB-IO-PATH-FN-041: `Path.isDirectory(options)` を既存 no-arg stub から公式 vararg shape へ広げる
- [x] STDLIB-IO-PATH-FN-045: `Path.isRegularFile(options)` を既存 no-arg stub から公式 vararg shape へ広げる
- [ ] STDLIB-IO-PATH-FN-049: `Path.listDirectoryEntries(glob)` を既存 no-arg stub から公式 glob shape へ広げる
- [x] STDLIB-IO-PATH-FN-049: `Path.listDirectoryEntries(glob)` を既存 no-arg stub から公式 glob shape へ広げる
- [x] STDLIB-IO-PATH-FN-050: `Path.moveTo(target, options)` を追加する
- [x] STDLIB-IO-PATH-FN-052: `Path.notExists(options)` を追加する
- [x] STDLIB-IO-PATH-FN-053: `Path.outputStream(options)` を追加する
- [ ] STDLIB-IO-PATH-FN-054: `Path(pathString)` の公式 top-level factory shape を既存 stub と整合させる
- [x] STDLIB-IO-PATH-FN-055: `Path(base, subpaths)` top-level factory overload を追加する
- [x] STDLIB-IO-PATH-FN-056: `Path.readAttributes<A>(options)` を追加する
- [ ] STDLIB-IO-PATH-FN-057: `Path.readAttributes(attributes, options)` を追加する
- [ ] STDLIB-IO-PATH-FN-059: `Path.reader(charset, options)` を追加する
- [ ] STDLIB-IO-PATH-FN-066: `Path.setAttribute(attribute, value, options)` を追加する
- [ ] STDLIB-IO-PATH-FN-071: `Path.useDirectoryEntries(glob, block)` を追加する
- [x] STDLIB-IO-PATH-FN-072: `Path.useLines(charset, block)` を追加する
- [ ] STDLIB-IO-PATH-FN-073: `Path.visitFileTree(visitor, maxDepth, followLinks)` を追加する
- [ ] STDLIB-IO-PATH-FN-074: `Path.visitFileTree(maxDepth, followLinks, builderAction)` を追加する
- [x] STDLIB-IO-PATH-FN-075: `Path.walk(options)` を追加する
- [x] STDLIB-IO-PATH-FN-077: `Path.writeLines(lines: Iterable<CharSequence>, charset, options)` を追加する
- [x] STDLIB-IO-PATH-FN-078: `Path.writeLines(lines: Sequence<CharSequence>, charset, options)` を追加する
- [x] STDLIB-IO-PATH-FN-079: `Path.writer(charset, options)` を追加する
- [ ] STDLIB-IO-PATH-FN-080: `Path.writeText(text, charset, options)` を既存 `writeText(text)` stub から公式 shape へ広げる
- [ ] STDLIB-JVM-PROP-002: `Enum.declaringJavaClass` extension property を追加する
- [x] STDLIB-JVM-PROP-003: `KClass<T>.java` extension property を追加する
- [x] STDLIB-JVM-PROP-005: `KClass<T>.javaClass` extension property を追加する
- [x] STDLIB-JVM-PROP-006: `KClass<T>.javaObjectType` extension property を追加する
- [x] STDLIB-JVM-PROP-007: `KClass<T>.javaPrimitiveType` extension property を追加する
- [ ] STDLIB-JVM-PROP-008: `Class<T>.kotlin` extension property を追加する
- [x] STDLIB-JVM-OPTIONALS-FN-001: `Optional<T>.asSequence()` を追加する
- [x] STDLIB-JVM-OPTIONALS-FN-003: `Optional<T>.getOrElse(defaultValue)` を追加する
- [x] STDLIB-JVM-OPTIONALS-FN-004: `Optional<T>.getOrNull()` を追加する
- [x] STDLIB-JVM-OPTIONALS-FN-005: `Optional<T>.toCollection(destination)` を追加する
- [ ] STDLIB-JVM-OPTIONALS-FN-006: `Optional<T>.toList()` を追加する
- [x] STDLIB-JVM-OPTIONALS-FN-007: `Optional<T>.toSet()` を追加する
- [x] STDLIB-JS-TYPE-003: `kotlin.js.Dynamic` external interface を追加する
- [x] STDLIB-JS-TYPE-012: `kotlin.js.JsArray` external class を追加する
- [x] STDLIB-JS-TYPE-013: `kotlin.js.JsBigInt` external class を追加する
- [x] STDLIB-JS-TYPE-014: `kotlin.js.JsBoolean` external class を追加する
- [x] STDLIB-JS-TYPE-025: `kotlin.js.JsNumber` external class を追加する
- [ ] STDLIB-JS-TYPE-027: `kotlin.js.JsReference` external interface を追加する
- [x] STDLIB-JS-TYPE-029: `kotlin.js.JsString` external class を追加する
- [x] STDLIB-JS-PROP-001: `kotlin.js.console` external property を追加する
- [x] STDLIB-JS-PROP-003: `KClass<T>.js` extension property を追加する
- [x] STDLIB-JS-PROP-004: `JsClass<T>.kotlin` extension property を追加する
- [x] STDLIB-JS-FN-001: `Date.Companion.now()` を追加する
- [x] STDLIB-JS-FN-002: `dateLocaleOptions(init)` を追加する
- [x] STDLIB-JS-FN-004: `JsReference<T>.get()` を追加する
- [ ] STDLIB-JS-FN-005: `JsArray<T>.get(index)` を追加する
- [x] STDLIB-JS-FN-006: `RegExpMatch.get(index)` を追加する
- [ ] STDLIB-JS-FN-007: `dynamic.iterator()` を追加する
- [ ] STDLIB-JS-FN-009: `JsArray<T>()` factory を追加する
- [x] STDLIB-JS-FN-015: `RegExp.reset()` を追加する
- [ ] STDLIB-JS-FN-016: `JsArray<T>.set(index, value)` を追加する
- [x] STDLIB-JS-FN-017: `Promise<T>.then(onFulfilled)` を追加する
- [x] STDLIB-JS-FN-018: `Promise<T>.then(onFulfilled, onRejected)` を追加する
- [x] STDLIB-JS-FN-019: `JsArray<T>.toArray()` を追加する
- [ ] STDLIB-JS-FN-020: `JsBoolean.toBoolean()` を追加する
- [x] STDLIB-JS-FN-021: `JsNumber.toDouble()` を追加する
- [x] STDLIB-JS-FN-022: `JsNumber.toInt()` を追加する
- [ ] STDLIB-JS-FN-023: `Array<T>.toJsArray()` を追加する
- [ ] STDLIB-JS-FN-024: `List<T>.toJsArray()` を追加する
- [ ] STDLIB-JS-FN-025: `Long.toJsBigInt()` を追加する
- [ ] STDLIB-JS-FN-026: `Boolean.toJsBoolean()` を追加する
- [x] STDLIB-JS-FN-027: `Double.toJsNumber()` を追加する
- [ ] STDLIB-JS-FN-028: `Int.toJsNumber()` を追加する
- [ ] STDLIB-JS-FN-029: `T.toJsReference()` を追加する
- [x] STDLIB-JS-FN-030: `String.toJsString()` を追加する
- [x] STDLIB-JS-FN-031: `JsArray<T>.toList()` を追加する
- [x] STDLIB-JS-FN-032: `JsBigInt.toLong()` を追加する
- [x] STDLIB-JS-FN-033: `JsAny.toThrowableOrNull()` を追加する
 - [ ] STDLIB-JS-COLLECTIONS-TYPE-001: `kotlin.js.collections.JsArray<E>` external class を追加する
 - [x] STDLIB-JS-COLLECTIONS-TYPE-002: `kotlin.js.collections.JsMap<K, V>` external class を追加する
 - [x] STDLIB-JS-COLLECTIONS-TYPE-001: `kotlin.js.collections.JsArray<E>` external class を追加する
 - [ ] STDLIB-JS-COLLECTIONS-TYPE-002: `kotlin.js.collections.JsMap<K, V>` external class を追加する
- [ ] STDLIB-JS-COLLECTIONS-TYPE-003: `kotlin.js.collections.JsReadonlyArray<E>` external interface を追加する
- [ ] STDLIB-JS-COLLECTIONS-TYPE-004: `kotlin.js.collections.JsReadonlyMap<K, V>` external interface を追加する
- [x] STDLIB-JS-COLLECTIONS-TYPE-005: `kotlin.js.collections.JsReadonlySet<E>` external interface を追加する
- [x] STDLIB-JS-COLLECTIONS-TYPE-006: `kotlin.js.collections.JsSet<E>` external class を追加する
- [x] STDLIB-JS-COLLECTIONS-FN-001: `JsReadonlyArray<E>.toList()` を追加する
- [x] STDLIB-JS-COLLECTIONS-FN-002: `JsReadonlyMap<K,V>.toMap()` を追加する
- [ ] STDLIB-JS-COLLECTIONS-FN-003: `JsReadonlyArray<E>.toMutableList()` を追加する
- [ ] STDLIB-JS-COLLECTIONS-FN-004: `JsReadonlyMap<K,V>.toMutableMap()` を追加する
- [ ] STDLIB-JS-COLLECTIONS-FN-005: `JsReadonlySet<E>.toMutableSet()` を追加する
- [ ] STDLIB-JS-COLLECTIONS-FN-006: `JsReadonlySet<E>.toSet()` を追加する
- [x] STDLIB-STREAMS-FN-001: `DoubleStream.asSequence()` を追加する
- [x] STDLIB-STREAMS-FN-002: `IntStream.asSequence()` を追加する
- [x] STDLIB-STREAMS-FN-003: `LongStream.asSequence()` を追加する
- [x] STDLIB-STREAMS-FN-004: `Stream<T>.asSequence()` を追加する
- [ ] STDLIB-STREAMS-FN-005: `Sequence<T>.asStream()` を追加する
- [ ] STDLIB-STREAMS-FN-006: `DoubleStream.toList()` を追加する
- [ ] STDLIB-STREAMS-FN-007: `IntStream.toList()` を追加する
- [ ] STDLIB-STREAMS-FN-008: `LongStream.toList()` を追加する
- [ ] STDLIB-STREAMS-FN-009: `Stream<T>.toList()` を追加する
- [ ] STDLIB-WASM-TYPE-002: `kotlin.wasm.WasmExport` annotation を追加する
- [ ] STDLIB-WASM-TYPE-003: `kotlin.wasm.WasmImport` annotation を追加する
- [ ] STDLIB-WASM-UNSAFE-TYPE-001: `kotlin.wasm.unsafe.MemoryAllocator` abstract class を追加する
- [ ] STDLIB-WASM-UNSAFE-TYPE-002: `kotlin.wasm.unsafe.Pointer` value class を追加する
- [ ] STDLIB-WASM-UNSAFE-TYPE-003: `kotlin.wasm.unsafe.UnsafeWasmMemoryApi` marker annotation を追加する
- [ ] STDLIB-WASM-UNSAFE-FN-001: `withScopedMemoryAllocator(block)` を追加する
- [ ] STDLIB-CINTEROP-TYPE-001: `kotlinx.cinterop.Arena` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-002: `kotlinx.cinterop.ArenaBase` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-003: `kotlinx.cinterop.AutofreeScope` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-004: `kotlinx.cinterop.BetaInteropApi` annotation shape を公式 surface と整合させる
- [ ] STDLIB-CINTEROP-TYPE-005: `kotlinx.cinterop.BooleanVar` typealias を追加する
- [ ] STDLIB-CINTEROP-TYPE-006: `kotlinx.cinterop.BooleanVarOf<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-007: `kotlinx.cinterop.ByteVar` typealias を追加する
- [ ] STDLIB-CINTEROP-TYPE-008: `kotlinx.cinterop.ByteVarOf<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-009: `kotlinx.cinterop.CArrayPointer<T>` typealias を追加する
- [ ] STDLIB-CINTEROP-TYPE-010: `kotlinx.cinterop.CArrayPointerVar<T>` typealias を追加する
- [ ] STDLIB-CINTEROP-TYPE-011: `kotlinx.cinterop.CEnum` interface surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-012: `kotlinx.cinterop.CEnumVar` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-013: `kotlinx.cinterop.CFunction<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-014: `kotlinx.cinterop.COpaque` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-015: `kotlinx.cinterop.COpaquePointer` typealias shape を既存 class stub と整合させる
- [ ] STDLIB-CINTEROP-TYPE-016: `kotlinx.cinterop.COpaquePointerVar` typealias を追加する
- [ ] STDLIB-CINTEROP-TYPE-017: `kotlinx.cinterop.CPointed` class shape を公式 surface と整合させる
- [ ] STDLIB-CINTEROP-TYPE-018: `kotlinx.cinterop.CPointer<T>` class shape を公式 surface と整合させる
- [ ] STDLIB-CINTEROP-TYPE-019: `kotlinx.cinterop.CPointerVar<T>` typealias shape を公式 surface と整合させる
- [ ] STDLIB-CINTEROP-TYPE-020: `kotlinx.cinterop.CPointerVarOf<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-021: `kotlinx.cinterop.CPrimitiveVar` sealed class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-022: `kotlinx.cinterop.CStructVar` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-023: `kotlinx.cinterop.CValue<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-024: `kotlinx.cinterop.CValues<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-025: `kotlinx.cinterop.CValuesRef<T>` class shape を公式 surface と整合させる
- [ ] STDLIB-CINTEROP-TYPE-026: `kotlinx.cinterop.CVariable` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-027: `kotlinx.cinterop.DeferScope` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-028: `kotlinx.cinterop.NativeFreeablePlacement` class surface を追加する
- [ ] STDLIB-CINTEROP-TYPE-029: `kotlinx.cinterop.NativePlacement` class shape を公式 surface と整合させる
- [ ] STDLIB-CINTEROP-TYPE-030: `kotlinx.cinterop.StableRef<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-PROP-001: `CPointer<T>.pointed` property を追加する
- [ ] STDLIB-CINTEROP-PROP-002: `CPointer<T>.rawValue` property を追加する
- [ ] STDLIB-CINTEROP-PROP-003: `nativeHeap` property を追加する
- [ ] STDLIB-CINTEROP-FN-001: `alloc<T>()` を追加する
- [ ] STDLIB-CINTEROP-FN-002: `allocArray<T>(length)` を追加する
- [ ] STDLIB-CINTEROP-FN-003: `asStableRef<T>()` を追加する
- [ ] STDLIB-CINTEROP-FN-004: `cstr` helper を追加する
- [ ] STDLIB-CINTEROP-FN-005: `wcstr` helper を追加する
- [ ] STDLIB-CINTEROP-FN-006: `defer(block)` を追加する
- [ ] STDLIB-CINTEROP-FN-007: `free(pointed)` を追加する
- [ ] STDLIB-CINTEROP-FN-008: `memScoped(block)` を追加する
- [ ] STDLIB-CINTEROP-FN-009: `pin()` を追加する
- [ ] STDLIB-CINTEROP-FN-010: `place(value)` を追加する
- [ ] STDLIB-CINTEROP-FN-011: `CPointer<T>.plus(index)` を追加する
- [ ] STDLIB-CINTEROP-FN-012: `readValue()` を追加する
- [ ] STDLIB-CINTEROP-FN-013: `refTo(index)` を追加する
- [ ] STDLIB-CINTEROP-FN-014: `reinterpret<T>()` を追加する
- [ ] STDLIB-CINTEROP-FN-015: `CPointer<T>.get(index)` を追加する
- [ ] STDLIB-CINTEROP-FN-016: `CPointer<T>.set(index, value)` を追加する
- [ ] STDLIB-CINTEROP-FN-017: `Array<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-018: `ByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-019: `DoubleArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-020: `FloatArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-021: `IntArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-022: `LongArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-023: `ShortArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-024: `UByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-025: `UIntArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-026: `ULongArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-027: `UShortArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-028: `List<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-029: `ByteArray.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-030: `CPointer<ByteVar>.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-031: `CPointer<ShortVar>.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-032: `CPointer<UShortVar>.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-033: `ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence)` を追加する
- [ ] STDLIB-CINTEROP-FN-034: `CPointer<ShortVar>.toKStringFromUtf16()` を追加する
- [ ] STDLIB-CINTEROP-FN-035: `CPointer<UShortVar>.toKStringFromUtf16()` を追加する
- [ ] STDLIB-CINTEROP-FN-036: `CPointer<IntVar>.toKStringFromUtf32()` を追加する
- [ ] STDLIB-CINTEROP-FN-037: `CPointer<ByteVar>.toKStringFromUtf8()` を追加する
- [ ] STDLIB-CINTEROP-FN-038: `CPointer<T>?.toLong()` を追加する
- [ ] STDLIB-CINTEROP-FN-039: `typeOf<T>()` を追加する
- [ ] STDLIB-CINTEROP-FN-040: `unwrapKotlinObjectHolder(holder)` を追加する
- [ ] STDLIB-CINTEROP-FN-041: `CValue<T>.useContents(block)` を追加する
- [ ] STDLIB-CINTEROP-FN-042: `T.usePinned(block)` を追加する
- [ ] STDLIB-CINTEROP-FN-043: `vectorOf(Float, Float, Float, Float)` の公式 annotation/signature を既存 stub と整合させる
- [ ] STDLIB-CINTEROP-FN-044: `vectorOf(Int, Int, Int, Int)` の公式 annotation/signature を既存 stub と整合させる
- [ ] STDLIB-CINTEROP-FN-045: `CValue<T>.write(location)` を追加する
- [ ] STDLIB-CINTEROP-FN-046: `writeBits(ptr, offset, size, value)` を追加する
- [ ] STDLIB-CINTEROP-FN-047: `zeroValue<T>()` を追加する
- [ ] STDLIB-CINTEROP-FN-048: `zeroValue<T>(size, align)` を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-001: `kotlinx.cinterop.internal.CCall` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-002: `kotlinx.cinterop.internal.CEnumEntryAlias` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-003: `kotlinx.cinterop.internal.CEnumVarTypeSize` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-004: `kotlinx.cinterop.internal.CGlobalAccess` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-005: `kotlinx.cinterop.internal.ConstantValue` object を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-006: `kotlinx.cinterop.internal.CStruct` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-FN-001: `convertBlockPtrToKotlinFunction(blockPtr)` を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-FN-002: `detachObjCObject(obj)` を追加する
- [ ] STDLIB-DOM-TYPE-001: `org.w3c.dom.ItemArrayLike<T>` external interface を追加する
- [ ] STDLIB-DOM-FN-001: `ItemArrayLike<T>.asList()` を追加する
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
