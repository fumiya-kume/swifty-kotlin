# Phase 1 stdlib Gap Inventory

Audited packages: `kotlin` (top-level), `kotlin.text` (String/Char/text utils), `Array` (kotlin.Array + typed arrays).

Status legend: **done** = `@_cdecl` present and wired; **partial** = subset implemented; **missing** = no implementation found.

Audit date: 2026-04-17. Source: `Sources/Runtime/` `@_cdecl` scan.

---

## `kotlin` package — top-level functions & types

| API | Status | Notes |
|---|---|---|
| `println(Any?)` | done | `kk_println_any`, `kk_println_newline`, typed variants |
| `print(Any?)` | done | `kk_print_any`, `kk_print_noarg` |
| `require(Boolean)` | done | `kk_require`, `kk_require_lazy` |
| `check(Boolean)` | done | `kk_check`, `kk_check_lazy` |
| `error(String)` | done | `kk_error` |
| `TODO(String)` | missing | no `kk_todo` found |
| `assert(Boolean)` | done | `kk_assertions_enabled`, `kk_assertions_set_enabled`, `kk_assertions_reset` |
| `with<T,R>(receiver, block)` | done | inline-expanded via Sema synthetic stub (STDLIB-061) |
| `T.let(block)` | done | inline-expanded via Sema synthetic stub |
| `T.also(block)` | done | inline-expanded via Sema synthetic stub |
| `T.run(block)` | missing | no runtime entry; not in scope-function stubs |
| `T.apply(block)` | missing | no `kk_apply` or inline stub found |
| `T.takeIf(predicate)` | missing | listed in stub file comment but not registered |
| `T.takeUnless(predicate)` | missing | listed in stub file comment but not registered |
| `repeat(times, block)` | missing | no `kk_repeat` found |
| `lazy(block)` | done | `kk_lazy_create`, `kk_lazy_get_value`, `kk_lazy_is_initialized` |
| `runCatching(block)` | done | `kk_runCatching` |
| `Result<T>` | done | full set: `kk_result_*` (18 entries) |
| `Pair<A,B>` | done | `kk_pair_new`, `kk_pair_first`, `kk_pair_second`, `kk_pair_toList`, `kk_pair_to_string` |
| `Triple<A,B,C>` | done | `kk_triple_new`, `kk_triple_first/second/third`, `kk_triple_toList`, `kk_triple_to_string` |
| `Any.equals(other)` | done | `kk_any_equals` |
| `Any.hashCode()` | done | `kk_any_hashCode` |
| `Any.toString()` | done | `kk_any_to_string` |
| `compareValues(a,b)` | done | `kk_compareValues`, `kk_compareValuesBy`, `kk_compareValuesBy1/3` |
| `maxOf(a,b)` / `minOf(a,b)` | partial | available via `kk_math_*`; no generic `kk_maxOf`/`kk_minOf` for arbitrary T |
| `Int` / `Long` / `Double` / `Float` numeric ops | done | coerce/range/bit-ops all present |
| `Char` ops | done | `kk_char_*` (30+ entries) |
| `IntRange` / `CharRange` / progression | done | `kk_range_*`, `kk_char_range_*`, `kk_int_progression_fromClosedRange` |
| `Sequence<T>` | done | 60+ `kk_sequence_*` entries |
| `Iterable<T>` | done | `kk_iterable_asSequence` + list/set/map iterators |
| `kotlin.math.*` | done | full trig/exp/log/round set (80+ `kk_math_*`) |
| `kotlin.random.Random` | done | `kk_random_*` (via RuntimeRandom.swift) |
| `kotlin.use(block)` | done | `kk_use` |

**kotlin package summary:** 29 rows — done: 22, partial: 1, missing: 6 (`TODO`, `run`, `apply`, `takeIf`, `takeUnless`, `repeat`)

---

## `kotlin.text` package — String & text utilities

| API | Status | Notes |
|---|---|---|
| `String.trim()` | done | `kk_string_trim` |
| `String.trimStart()` / `trimEnd()` | done | `kk_string_trimStart`, `kk_string_trimEnd` |
| `String.trimIndent()` / `trimMargin()` | done | `kk_string_trimIndent`, `kk_string_trimMargin`, `kk_string_trimMargin_default` |
| `String.lowercase()` / `uppercase()` | done | `kk_string_lowercase`, `kk_string_uppercase` |
| `String.lowercase(Locale)` / `uppercase(Locale)` | done | `kk_string_lowercase_locale`, `kk_string_uppercase_locale` |
| `String.isEmpty()` / `isNotEmpty()` | done | `kk_string_isEmpty`, `kk_string_isNotEmpty` |
| `String.isBlank()` / `isNotBlank()` | done | `kk_string_isBlank`, `kk_string_isNotBlank` |
| `String.startsWith(prefix)` / `endsWith(suffix)` | done | `kk_string_startsWith`, `kk_string_endsWith` |
| `String.contains(other)` | done | `kk_string_contains_str` |
| `String.indexOf(str)` / `lastIndexOf` | done | `kk_string_indexOf`, `kk_string_indexOf_from`, `kk_string_lastIndexOf` |
| `String.indexOfFirst` / `indexOfLast` | done | `kk_string_indexOfFirst`, `kk_string_indexOfLast` |
| `String.substring(range/start/end)` | done | `kk_string_substring`, `kk_string_subSequence` |
| `String.substringBefore/After` | done | `kk_string_substringBefore`, `kk_string_substringAfter`, `kk_string_substringAfterLast`, `kk_string_substringBeforeLast` |
| `String.replace(old,new)` / `replaceFirst` | done | `kk_string_replace`, `kk_string_replaceFirst`, `kk_string_replaceRange` |
| `String.replaceFirstChar` | done | `kk_string_replaceFirstChar` |
| `String.split(delimiter)` | done | `kk_string_split`, `kk_string_splitToSequence` |
| `String.lines()` / `lineSequence()` | done | `kk_string_lines`, `kk_string_lineSequence` |
| `String.repeat(n)` | done | `kk_string_repeat` |
| `String.reversed()` | done | `kk_string_reversed` |
| `String.padStart` / `padEnd` | done | `kk_string_padStart`, `kk_string_padEnd`, default variants |
| `String.toInt()` / `toLong()` / `toDouble()` etc. | done | all `kk_string_to*` conversions with `OrNull` variants |
| `String.toByteArray()` / `encodeToByteArray()` | done | `kk_string_toByteArray`, `kk_string_encodeToByteArray`, charset variants |
| `String.toCharArray()` | done | `kk_string_toCharArray` |
| `String.toList()` / `toSet()` / `asSequence()` | done | `kk_string_toList`, `kk_string_asSequence`, `kk_string_asIterable` |
| `String.map` / `filter` / `forEach` / `flatMap` etc. | done | full HOF set: `kk_string_map`, `kk_string_filter`, `kk_string_filterIndexed`, `kk_string_mapIndexed`, `kk_string_mapNotNull`, `kk_string_find`, `kk_string_findLast` |
| `String.first` / `last` / `single` / `count` | done | `kk_string_first`, `kk_string_last`, `kk_string_single`, `kk_string_count` |
| `String.drop` / `take` / `dropWhile` / `takeWhile` | done | all four and `dropLast`/`takeLast` variants |
| `String.chunked` / `windowed` / `zipWithNext` | done | `kk_string_chunked`, `kk_string_windowed*`, `kk_string_zipWithNext` |
| `String.joinToString` | done | `kk_string_joinToString` |
| `String.partition` | done | `kk_string_partition` |
| `String.all` / `any` / `none` | done | `kk_string_all`, `kk_string_any`, `kk_string_none` |
| `String.equalsIgnoreCase` / `compareToIgnoreCase` | done | `kk_string_equalsIgnoreCase`, `kk_string_compareToIgnoreCase`, `kk_string_compareTo_member`, `kk_string_compareTo_locale` |
| `String.commonPrefixWith` / `commonSuffixWith` | done | both with and without `ignoreCase` variants |
| `String.removePrefix` / `removeSuffix` / `removeSurrounding` | done | `kk_string_removePrefix`, `kk_string_removeSuffix`, `kk_string_removeSurrounding`, `kk_string_removeSurrounding_pair` |
| `String.prependIndent` / `replaceIndent` | done | `kk_string_prependIndent`, `kk_string_replaceIndent`, default variants |
| `String.format(vararg)` | done | `kk_string_format` |
| `String.normalize()` / `isNormalized()` | done | `kk_string_normalize`, `kk_string_isNormalized`, normalization form consts |
| `String.get(index)` / `getOrNull` | done | `kk_string_get`, `kk_string_getOrNull` |
| `String.iterator` | done | `kk_string_iterator`, `kk_string_iterator_hasNext`, `kk_string_iterator_next`, iterable variants |
| `StringBuilder` | done | `kk_string_builder_*` (via RuntimeStringBuilder.swift) |
| `Regex` | done | `kk_regex_*` (via RuntimeRegex.swift) |
| `Char` classification & conversion | done | `kk_char_isDigit/isLetter/isUpperCase/isLowerCase/isWhitespace` etc. (30+ entries) |
| `String.toBigDecimal` / `toBigInteger` | done | `kk_string_toBigDecimal`, `kk_string_toBigInteger`, `kk_bignum_toString` |
| `HexFormat` / `bytearray.toHexString` | done | `kk_bytearray_toHexString` (via RuntimeHexFormat.swift) |
| `Charset` constants | done | `kk_charset_utf_8`, `kk_charset_utf_16`, `kk_charset_iso_8859_1` etc. (9 constants) |
| `String.compareTo(locale)` | done | `kk_string_compareTo_locale` |
| `decodeToString(byteArray)` | done | `kk_bytearray_decodeToString`, charset variant |
| `charArrayOf().concatToString()` | done | `kk_chararray_concatToString` |

**kotlin.text summary:** 46 rows — done: 46, partial: 0, missing: 0

STDLIB-005 scope is closed for string conversion, split, and replacement edge
cases. The surface is covered by the registered `kk_string_to*` conversion
links, `kk_string_split_limit`/`kk_string_splitToSequence`,
`kk_string_replace*` runtime entries, and focused sema/runtime edge-case tests.

---

## `Array<T>` (and typed arrays) — kotlin.Array + extension functions

| API | Status | Notes |
|---|---|---|
| `arrayOf(vararg)` | done | `kk_array_of` |
| `emptyArray()` | done | `kk_empty_array` |
| `Array(size, init)` | done | `kk_array_new` |
| `array[index]` (get) | done | `kk_array_get`, `kk_array_get_inbounds` |
| `array[index] = value` (set) | done | `kk_array_set` |
| `array.size` | done | `kk_array_size` |
| `array.isEmpty()` | done | `kk_array_is_empty` |
| `array.copyOf()` / `copyOfRange()` | done | `kk_array_copyOf`, `kk_array_copyOfRange` |
| `array.fill(element)` | done | `kk_array_fill` |
| `array.contentEquals(other)` | done | `kk_array_contentEquals` |
| `array.contentHashCode()` | done | `kk_array_contentHashCode` |
| `array.toList()` / `toMutableList()` | done | `kk_array_toList`, `kk_array_toMutableList` |
| `array.asSequence()` | done | `kk_array_asSequence` |
| `array.forEach` / `forEachIndexed` | partial | `kk_array_forEach` done; `forEachIndexed` missing |
| `array.map` / `mapIndexed` / `mapNotNull` | done | `kk_array_map`, `kk_array_mapIndexed`, `kk_array_mapNotNull` |
| `array.filter` / `filterIndexed` / `filterNot` / `filterNotNull` | done | all four present |
| `array.find` / `findLast` | done | `kk_array_find`, `kk_array_findLast` |
| `array.first` / `last` / `firstOrNull` / `lastOrNull` | done | all four present |
| `array.any` / `all` / `none` | done | `kk_array_any`, `kk_array_all`, `kk_array_none` |
| `array.count(predicate)` | done | `kk_array_count` |
| `array.fold` / `foldIndexed` | done | `kk_array_fold`, `kk_array_foldIndexed` |
| `array.reduce` / `reduceIndexed` / `reduceOrNull` | done | all three present |
| `array.flatMap` | done | `kk_array_flatMap` |
| `array.sorted` / `sortedBy` / `sortedDescending` | missing | no `kk_array_sorted*` entries |
| `array.reversed()` / `reversedArray()` | missing | no `kk_array_reversed` found |
| `array.contains(element)` | done | `kk_array_contains` |
| `array.indexOf(element)` / `lastIndexOf` | done | `kk_array_indexOf`, `kk_array_lastIndexOf` |
| `array.sum` / `sumOf` | missing | no `kk_array_sum*` found |
| `array.average()` | missing | no `kk_array_average` found |
| `array.max` / `min` / `maxOrNull` / `minOrNull` | missing | no `kk_array_max*`/`kk_array_min*` found |
| `array.joinToString` | missing | no `kk_array_joinToString` found |
| `array.withIndex()` | missing | no `kk_array_withIndex` found |
| `array.zip(other)` | missing | no `kk_array_zip` found |
| `array.partition(predicate)` | missing | no `kk_array_partition` found |
| `array.toTypedArray()` | done | `kk_list_toTypedArray` (from list side) |
| `array.plus(element/array)` | missing | no `kk_array_plus` found |
| `array.contentToString()` | missing | no `kk_array_contentToString` found |
| `intArrayOf()` / `longArrayOf()` etc. | partial | size+toList present for all 12 typed arrays; HOF extensions missing |
| `IntArray.sum()` / `average()` etc. | missing | no typed-array sum/average |
| `ArrayDeque<T>` | done | `kk_arraydeque_new/addFirst/addLast/removeFirst/removeLast/first/last/size/isEmpty/toString` |

**Array summary:** 40 rows — done: 27, partial: 2, missing: 11

STDLIB-004 scope is now closed for Array / primitive-array generation,
conversion, and boundary behavior. Coverage is pinned by
`CodegenBackendIntegrationTests+PrimitiveArrayEdgeCases`,
`ArraySyntheticMemberLinkTests`, `ListSyntheticMemberLinkTests`,
`RuntimeCollectionHOFTests`, and `RuntimeUnsignedArrayAsListTests`. Remaining
Array API gaps above are tracked by `STDLIB-GAP-PH1` rather than STDLIB-004.

---

## Totals

| Package | Total rows | done | partial | missing |
|---|---|---|---|---|
| `kotlin` (top-level) | 29 | 22 | 1 | 6 |
| `kotlin.text` | 46 | 46 | 0 | 0 |
| `Array` | 40 | 27 | 2 | 11 |
| **Grand total** | **115** | **95** | **3** | **17** |
