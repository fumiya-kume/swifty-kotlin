# stdlib Gap Inventory – Phase 2: collections / sequences / ranges

Task: STDLIB-GAP-PH2  
Date: 2026-04-17  
Baseline: Kotlin 2.3.10 stable

Legend: **implemented** = sema stub + lowering + runtime; **partial** = sema stub exists but lowering/runtime incomplete or via fallback; **gap** = not yet supported.

---

## kotlin.collections

### Core Types

| Type | Status | Notes |
|---|---|---|
| `List<T>` | implemented | full sema stub + codegen |
| `MutableList<T>` | implemented | |
| `Set<T>` | implemented | |
| `MutableSet<T>` | implemented | |
| `Map<K,V>` | implemented | |
| `MutableMap<K,V>` | implemented | |
| `Collection<T>` | implemented | |
| `MutableCollection<T>` | implemented | |
| `Iterable<T>` | implemented | |
| `MutableIterable<T>` | implemented | |
| `Iterator<T>` | implemented | |
| `MutableIterator<T>` | implemented | |
| `ListIterator<T>` | implemented | |
| `MutableListIterator<T>` | implemented | |
| `ArrayDeque<T>` | implemented | |
| `LinkedList<T>` | implemented | alias to `ArrayDeque` |
| `Grouping<T,K>` | gap | `groupingBy` / `eachCount` not supported |

### Factory Functions

| Function | Status | Notes |
|---|---|---|
| `listOf(...)` | implemented | |
| `mutableListOf(...)` | implemented | |
| `setOf(...)` | implemented | |
| `mutableSetOf(...)` | implemented | |
| `mapOf(...)` | implemented | |
| `mutableMapOf(...)` | implemented | |
| `emptyList()` | implemented | |
| `emptySet()` | implemented | |
| `emptyMap()` | implemented | |
| `buildList { }` | implemented | |
| `buildSet { }` | implemented | |
| `buildMap { }` | implemented | |
| `arrayOf(...)` | implemented | |
| `emptyArray()` | implemented | |
| `sortedSetOf(...)` | gap | `TreeSet` not supported |
| `sortedMapOf(...)` | gap | `TreeMap` not supported |
| `linkedMapOf(...)` | gap | `LinkedHashMap` not supported |
| `linkedSetOf(...)` | gap | `LinkedHashSet` not supported |

### List / Collection Transform Operations

| Operation | Status | Notes |
|---|---|---|
| `map` | implemented | |
| `mapIndexed` | implemented | |
| `mapNotNull` | implemented | |
| `mapIndexedNotNull` | gap | |
| `filter` | implemented | |
| `filterIndexed` | implemented | |
| `filterNot` | implemented | |
| `filterNotNull` | implemented | |
| `filterIsInstance<T>` | implemented | |
| `flatMap` | implemented | |
| `flatten` | implemented | |
| `forEach` | implemented | |
| `forEachIndexed` | implemented | |
| `onEach` | implemented | |
| `onEachIndexed` | implemented | |
| `take` | implemented | |
| `takeLast` | implemented | |
| `takeWhile` | implemented | |
| `takeLastWhile` | implemented | |
| `drop` | implemented | |
| `dropLast` | implemented | |
| `dropWhile` | implemented | |
| `dropLastWhile` | implemented | |
| `distinct` | implemented | |
| `distinctBy` | implemented | |
| `chunked` | implemented | |
| `windowed` | implemented | |
| `zip` | implemented | |
| `zipWithNext` | implemented | |
| `unzip` | implemented | |
| `partition` | implemented | |
| `reversed` | implemented | |
| `asReversed` | implemented | |
| `shuffled` | implemented | |
| `sorted` | implemented | |
| `sortedDescending` | implemented | |
| `sortedBy` | implemented | |
| `sortedByDescending` | implemented | |
| `sortedWith` | implemented | |
| `slice` | implemented | |
| `subList` | implemented | |
| `withIndex` | implemented | |
| `binarySearch` | implemented | |
| `toTypedArray` | gap | |
| `sortedArray` | gap | |
| `sortedArrayDescending` | gap | |

### List Aggregate / Query Operations

| Operation | Status | Notes |
|---|---|---|
| `count` | implemented | |
| `any` | implemented | |
| `all` | implemented | |
| `none` | implemented | |
| `sum` | implemented | |
| `sumOf` | implemented | |
| `average` | implemented | |
| `min` | implemented | |
| `max` | implemented | |
| `minOrNull` | implemented | |
| `maxOrNull` | implemented | |
| `minOf` | implemented | |
| `maxOf` | implemented | |
| `minByOrNull` | implemented | |
| `maxByOrNull` | implemented | |
| `minWith` | implemented | |
| `maxWith` | implemented | |
| `minWithOrNull` | implemented | |
| `maxWithOrNull` | implemented | |
| `minOfOrNull` | implemented | |
| `maxOfOrNull` | implemented | |
| `minOfWith` | implemented | |
| `maxOfWith` | implemented | |
| `minOfWithOrNull` | implemented | |
| `maxOfWithOrNull` | implemented | |
| `reduce` | implemented | |
| `reduceIndexed` | implemented | |
| `reduceRight` | implemented | |
| `reduceIndexedOrNull` | implemented | |
| `reduceRightIndexed` | implemented | |
| `fold` | implemented | |
| `foldIndexed` | implemented | |
| `foldRight` | implemented | |
| `foldRightIndexed` | implemented | |
| `scan` | implemented | |
| `scanIndexed` | implemented | |
| `runningFold` | implemented | |
| `runningFoldIndexed` | implemented | |
| `runningReduce` | implemented | |
| `runningReduceIndexed` | implemented | |
| `first` | implemented | |
| `last` | implemented | |
| `firstOrNull` | implemented | |
| `lastOrNull` | implemented | |
| `singleOrNull` | implemented | |
| `find` | partial | via fallback |
| `findLast` | partial | via fallback |
| `indexOf` | implemented | |
| `lastIndexOf` | implemented | |
| `indexOfFirst` | implemented | |
| `indexOfLast` | implemented | |
| `elementAt` | implemented | |
| `elementAtOrNull` | implemented | |
| `elementAtOrElse` | implemented | |
| `random` | implemented | |
| `randomOrNull` | implemented | |
| `isEmpty` | implemented | |
| `isNotEmpty` | partial | via fallback |
| `size` | implemented | |
| `contains` | implemented | |
| `containsAll` | implemented | |
| `joinToString` | implemented | |
| `contentEquals` | implemented | |
| `contentHashCode` | implemented | |

### List Conversion

| Operation | Status | Notes |
|---|---|---|
| `toList` | implemented | |
| `toMutableList` | implemented | |
| `toSet` | implemented | |
| `toMutableSet` | implemented | |
| `toHashSet` | implemented | |
| `toMap` | implemented | |
| `toMutableMap` | implemented | |
| `asSequence` | implemented | |

### List Set Operations

| Operation | Status | Notes |
|---|---|---|
| `intersect` | implemented | |
| `union` | implemented | |
| `subtract` | implemented | |
| `plus` | partial | via Map/Set |
| `minus` | partial | via Map/Set |

### Group / Associate

| Operation | Status | Notes |
|---|---|---|
| `groupBy` | implemented | |
| `groupByTo` | implemented | |
| `associateBy` | implemented | |
| `associateWith` | implemented | |
| `associate` | implemented | |
| `associateByTo` | implemented | |
| `associateWithTo` | implemented | |
| `groupingBy` | gap | `Grouping<T,K>` not implemented |
| `eachCount` | gap | depends on `Grouping` |
| `eachCountTo` | gap | depends on `Grouping` |
| `fold` (Grouping) | gap | depends on `Grouping` |
| `aggregate` (Grouping) | gap | depends on `Grouping` |

### Map Operations

| Operation | Status | Notes |
|---|---|---|
| `keys` | implemented | |
| `values` | implemented | |
| `entries` | implemented | |
| `containsKey` | implemented | |
| `containsValue` | implemented | |
| `getOrDefault` | implemented | |
| `getOrElse` | implemented | |
| `getOrNull` | implemented | |
| `getValue` | implemented | |
| `mapKeys` | implemented | |
| `mapValues` | implemented | |
| `filterKeys` | implemented | |
| `filterValues` | implemented | |
| `forEach` | implemented | |
| `map` | implemented | |
| `flatMap` | implemented | |
| `filter` | implemented | |
| `any` | implemented | |
| `all` | implemented | |
| `none` | implemented | |
| `count` | implemented | |
| `maxByOrNull` | implemented | |
| `minByOrNull` | implemented | |
| `plus` | implemented | |
| `minus` | implemented | |
| `mapNotNull` | implemented | |
| `toSortedMap` | gap | `TreeMap` not supported |

### MutableList / MutableCollection Operations

| Operation | Status | Notes |
|---|---|---|
| `add` | implemented | |
| `addAll` | implemented | |
| `remove` | implemented | |
| `removeAll` | implemented | |
| `removeAt` | implemented | |
| `retainAll` | implemented | |
| `clear` | implemented | |
| `set` | implemented | |
| `sort` | implemented | |
| `sortBy` | implemented | |
| `sortByDescending` | implemented | |
| `sortDescending` | implemented | |
| `sortWith` | gap | |
| `reverse` | implemented | |
| `shuffle` | implemented | |
| `fill` | gap | |
| `replaceAll` | gap | |
| `removeIf` | gap | |

---

## kotlin.sequences

### Core Types and Builders

| Type/Function | Status | Notes |
|---|---|---|
| `Sequence<T>` | implemented | |
| `sequenceOf(...)` | implemented | |
| `emptySequence()` | implemented | |
| `generateSequence { }` | implemented | `seedFunction` and `nextFunction` forms |
| `sequence { yield / yieldAll }` | implemented | coroutine-style builder |
| `SequenceScope` | implemented | |
| `constrainOnce` | gap | `ConstrainedOnceSequence` not implemented |

### Sequence Intermediate Operations

| Operation | Status | Notes |
|---|---|---|
| `map` | implemented | |
| `mapIndexed` | implemented | |
| `mapNotNull` | implemented | |
| `mapIndexedNotNull` | gap | |
| `filter` | implemented | |
| `filterNot` | implemented | |
| `filterNotNull` | implemented | |
| `filterIsInstance<T>` | gap | on Sequence |
| `filterIndexed` | gap | on Sequence |
| `flatMap` | implemented | |
| `flatten` | implemented | |
| `onEach` | implemented | |
| `onEachIndexed` | gap | on Sequence |
| `take` | implemented | |
| `takeWhile` | gap | on Sequence |
| `drop` | implemented | |
| `dropWhile` | gap | on Sequence |
| `distinct` | implemented | |
| `distinctBy` | gap | on Sequence |
| `zip` | implemented | |
| `zipWithNext` | implemented | |
| `chunked` | implemented | |
| `windowed` | implemented | |
| `withIndex` | implemented | |
| `sorted` | implemented | |
| `sortedBy` | implemented | |
| `sortedDescending` | implemented | |
| `sortedWith` | gap | on Sequence |
| `sortedByDescending` | gap | on Sequence |
| `plus` | implemented | |
| `minus` | implemented | |
| `ifEmpty` | implemented | |
| `constrainOnce` | gap | |

### Sequence Terminal Operations

| Operation | Status | Notes |
|---|---|---|
| `forEach` | implemented | |
| `forEachIndexed` | implemented | |
| `first` | implemented | |
| `last` | implemented | |
| `firstOrNull` | implemented | |
| `lastOrNull` | implemented | |
| `singleOrNull` | implemented | |
| `count` | implemented | |
| `any` | gap | on Sequence |
| `all` | gap | on Sequence |
| `none` | gap | on Sequence |
| `find` | gap | on Sequence |
| `findLast` | gap | on Sequence |
| `elementAt` | gap | on Sequence |
| `elementAtOrNull` | gap | on Sequence |
| `indexOf` | gap | on Sequence |
| `contains` | gap | on Sequence |
| `sum` | gap | on Sequence |
| `sumOf` | implemented | |
| `average` | gap | on Sequence |
| `minOrNull` | implemented | |
| `maxOrNull` | implemented | |
| `minByOrNull` | gap | on Sequence |
| `maxByOrNull` | gap | on Sequence |
| `minOf` | gap | on Sequence |
| `maxOf` | gap | on Sequence |
| `reduce` | implemented | |
| `reduceIndexed` | implemented | |
| `fold` | implemented | |
| `foldIndexed` | implemented | |
| `scan` | implemented | |
| `runningFold` | implemented | |
| `runningReduce` | implemented | |
| `partition` | gap | on Sequence |
| `unzip` | gap | on Sequence |
| `associate` | implemented | |
| `associateBy` | implemented | |
| `associateWith` | gap | on Sequence |
| `groupBy` | implemented | |
| `toList` | implemented | |
| `toSet` | implemented | |
| `toMap` | implemented | |
| `toMutableList` | gap | on Sequence |
| `toMutableSet` | gap | on Sequence |
| `asIterable` | implemented | |
| `joinToString` | implemented | |

---

## kotlin.ranges

### Range Types

| Type | Status | Notes |
|---|---|---|
| `IntRange` | implemented | first, last, step, isEmpty, contains, iterator, reversed, toList, sorted, take, drop, etc. |
| `LongRange` | implemented | |
| `UIntRange` | implemented | |
| `ULongRange` | implemented | |
| `IntProgression` | implemented | fromClosedRange, step, reversed, isEmpty, first, last, toList, average |
| `LongProgression` | implemented | |
| `UIntProgression` | implemented | |
| `ULongProgression` | implemented | |
| `CharRange` | partial | handled via fallback logic; no first-class sema stub |
| `CharProgression` | gap | not implemented |
| `ClosedRange<T>` (generic) | gap | no generic interface stub |
| `OpenEndRange<T>` (generic) | implemented | interface stub added; `..<` operator typing still partial |

### Range Operators and Extension Functions

| Operation | Status | Notes |
|---|---|---|
| `..` (rangeTo) | implemented | |
| `..<` (rangeUntil) | partial | lexer/parser support; sema resolves via fallback |
| `downTo` | implemented | |
| `step` | implemented | |
| `until` | implemented | |
| `reversed` | implemented | |
| `contains` | implemented | |
| `isEmpty` | implemented | |
| `first` / `last` / `step` properties | implemented | |
| `iterator` | implemented | |
| `toList` | implemented | |
| `sorted` | implemented | |
| `average` | implemented | |
| `sum` | gap | on ranges |
| `toIntArray` | implemented | |
| `toLongArray` | implemented | |
| `toUIntArray` | implemented | |
| `toULongArray` | implemented | |
| `toSet` | gap | on ranges |
| `toSortedSet` | gap | |
| `constrainTo` | gap | |
| `take` | implemented | |
| `drop` | implemented | |
| `firstOrNull` | implemented | |
| `lastOrNull` | implemented | |
| `coerceIn` | implemented | |
| `coerceAtLeast` | implemented | |
| `coerceAtMost` | implemented | |
| `random` | gap | on ranges |
| `count` | gap | on ranges (no explicit stub; may fall through) |

---

## Gap Summary

| Package | Implemented | Partial | Gap | Total |
|---|---|---|---|---|
| `kotlin.collections` | ~95 | ~5 | ~18 | ~118 |
| `kotlin.sequences` | ~38 | 0 | ~25 | ~63 |
| `kotlin.ranges` | ~22 | ~3 | ~9 | ~34 |
| **Total** | **~155** | **~8** | **~52** | **~215** |

### Top Priority Gaps

1. **`kotlin.sequences`**: `any/all/none/find/contains/elementAt` – common terminal ops missing on `Sequence`
2. **`kotlin.sequences`**: `takeWhile/dropWhile/filterIndexed/distinctBy/sortedWith` – intermediate ops missing
3. **`kotlin.sequences`**: `partition/unzip/associateWith` – pair-producing terminals missing
4. **`kotlin.collections`**: `Grouping<T,K>` + `groupingBy/eachCount` – needed for aggregate grouping patterns
5. **`kotlin.collections`**: `sortWith/fill/replaceAll/removeIf` on `MutableList`
6. **`kotlin.ranges`**: `CharRange` first-class stub + `CharProgression`
7. **`kotlin.ranges`**: `ClosedRange<T>` generic interface
