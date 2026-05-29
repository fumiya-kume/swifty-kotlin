# stdlib Gap Inventory — Phase 3

**Packages**: `kotlin.io` (common) · `kotlin.time` · `kotlin.concurrent` · `kotlin.concurrent.atomics`
**Survey date**: 2026-04-17
**Kotlin target**: 2.3.10 stable

---

## Summary counts

| Package | Implemented | Missing / Partial | Total audited |
|---|---|---|---|
| `kotlin.io` (common) | 18 | 0 | 18 |
| `kotlin.time` | 86 | 3 | 89 |
| `kotlin.concurrent` | 20 | 0 | 20 |
| `kotlin.concurrent.atomics` | 68 | 0 | 68 |
| **Total** | **192** | **3** | **195** |

---

## kotlin.io (common)

### Implemented

| API | Runtime symbol | STDLIB ref |
|---|---|---|
| `println()` | `kk_println_newline` | STDLIB-063 |
| `println(message: Any?)` | `kk_println_any` | STDLIB-063 |
| `print()` | `kk_print_noarg` | STDLIB-572 |
| `print(message: Any?)` | `kk_print_any` | STDLIB-572 |
| `readLine(): String?` | `kk_readline` | STDLIB-063 |
| `readln(): String` | `kk_readln` | STDLIB-130 |
| `readlnOrNull(): String?` | `kk_readlnOrNull` | STDLIB-571 |
| `File` constructor (path) | `kk_file_new` | STDLIB-320 |
| `File` constructor (parent, child) | `kk_file_new_parent_child` | STDLIB-IO-087 |
| `File.readText()` | `kk_file_readText` | STDLIB-320 |
| `File.writeText()` | `kk_file_writeText` | STDLIB-320 |
| `File.appendText()` | `kk_file_appendText` | STDLIB-664 |
| `File.readLines()` | `kk_file_readLines` | STDLIB-320 |
| `File.readBytes()` | `kk_file_readBytes` | STDLIB-665 |
| `File.forEachLine {}` | `kk_file_forEachLine` | STDLIB-322 |
| `File.useLines {}` | `kk_file_useLines` | STDLIB-566 |
| `File.bufferedReader()` | `kk_file_bufferedReader` | STDLIB-567 |
| `BufferedReader.readLine()` | `kk_buffered_reader_readLine` | STDLIB-567 |
| `BufferedReader.readLines()` | `kk_buffered_reader_readLines` | STDLIB-567 |
| `BufferedReader.close()` | `kk_buffered_reader_close` | STDLIB-567 |
| `File.bufferedWriter()` | `kk_file_bufferedWriter` | STDLIB-IO-091 |
| `BufferedWriter.write()` | `kk_buffered_writer_write` | STDLIB-IO-091 |
| `File.copyTo()` | `kk_file_copyTo*` | STDLIB-IO-FN-015 |
| `File.copyRecursively()` | `kk_file_copyRecursively*` | STDLIB-IO-FN-012 |
| `File.deleteRecursively()` | `kk_file_deleteRecursively` | STDLIB-030 |
| `File.walk()` | `kk_file_walk` | STDLIB-323 |
| `File.walk(direction)`, `.walkTopDown()`, `.walkBottomUp()` | `kk_file_walk_direction`, `kk_file_walkTopDown`, `kk_file_walkBottomUp` | STDLIB-030 |
| `File.exists()`, `.isFile()`, `.isDirectory()` | `kk_file_exists` etc. | STDLIB-321 |
| `File.delete()`, `.mkdirs()`, `.listFiles()` | `kk_file_delete` etc. | STDLIB-323 |

### Missing / Partial

No remaining `kotlin.io` common gaps in the Phase 3 audit scope. File copy, recursive copy,
recursive delete, walk direction shortcuts, deprecated temp-file helpers, and
`kotlin.io.path` temp-file variants are covered by runtime symbols and compiler stubs.

---

## kotlin.time

### Implemented

| Sub-API group | Key runtime symbols | STDLIB ref |
|---|---|---|
| `Duration` constructors (`.seconds`, `.minutes`, `.hours`, `.days`, `.milliseconds`, `.microseconds`, `.nanoseconds`) | `kk_duration_from_*` (7 symbols) | STDLIB-230 |
| `Duration.inWhole*` (seconds, minutes, hours, milliseconds, nanoseconds) | `kk_duration_inWhole*` (5 symbols) | STDLIB-231 |
| `Duration` arithmetic (`+`, `-`, `*`, `/`, unary minus) | `kk_duration_plus/minus/times_int/div_int/unary_minus` | STDLIB-231 |
| `Duration.absoluteValue`, `isNegative`, `isPositive`, `isInfinite`, `isFinite` | 5 symbols | STDLIB-231 |
| `Duration.toString()` | `kk_duration_toString` | STDLIB-231 |
| `Instant.now()` / `Clock.System.now()` | `kk_instant_now`, `kk_clock_system_now` | STDLIB-TIME-083 |
| `Instant` arithmetic (`+Duration`, `-Duration`, `until`, `elapsed`, `compare`) | 5 symbols | STDLIB-TIME-083 |
| `Instant.fromEpochMilliseconds()` / `.toEpochMilliseconds()` | 2 symbols | STDLIB-TIME-083 |
| `Instant.fromEpochSeconds()` | `kk_instant_from_epoch_seconds` | STDLIB-TIME-083 |
| `TimeSource.Monotonic.markNow()` | `kk_time_source_mark_now` | STDLIB-TIME-180 |
| `TimeMark` arithmetic (`+Duration`, `-Duration`, `-TimeMark`, compare, hasPassed, hasNotPassed) | 6 symbols | STDLIB-TIME-180 |
| `measureTime {}` | `kk_measureTime` | STDLIB-585 |
| `measureTimedValue {}` | `kk_measureTimedValue` | STDLIB-660 |
| `TimedValue` (new, value, duration, toString) | 4 symbols | STDLIB-660 |
| `measureTimeMillis {}` | `kk_system_measureTimeMillis` | STDLIB-063 |
| `measureNanoTime {}` | `kk_system_measureNanoTime` | STDLIB-063 |
| Platform bridge: `java.time.Instant` ↔ `kotlin.time.Instant` | `kk_instant_to_java_instant`, `kk_java_instant_to_kotlin_instant`, accessors | STDLIB-TIME-181 |
| Platform bridge: `java.time.Duration` ↔ `kotlin.time.Duration` | `kk_duration_to_java_duration`, `kk_java_duration_to_kotlin_duration`, accessors | STDLIB-TIME-181 |
| Platform bridge: JS Date | `kk_instant_to_js_date`, `kk_js_date_to_kotlin_instant`, accessors | STDLIB-TIME-181 |
| Platform bridge: Foundation.Date (Native) | `kk_instant_to_foundation_date`, `kk_foundation_date_to_kotlin_instant` | STDLIB-TIME-181 |
| POSIX clock bridges | `kk_clock_gettime_realtime`, `kk_clock_gettime_monotonic_ns`, `kk_clock_monotonic_mark_now` | STDLIB-TIME-181 |

### Missing / Partial

| API | Gap description | Priority |
|---|---|---|
| `Duration.inWholeDays` | `kk_duration_inWholeDays` symbol absent; only `kk_duration_from_days` (constructor direction) exists | Medium |
| `Duration * Double` / `Duration / Double` | `kk_duration_times_double` / `kk_duration_div_double` symbols absent; only integer overloads present | Medium |
| `Duration.toComponents(action)` | Decompose-into-hours/minutes/seconds/nanoseconds callback form; no runtime or stub | Low |

---

## kotlin.concurrent

### Implemented

| API | Runtime symbol | Notes |
|---|---|---|
| `@Volatile` annotation | Compiler annotation stub | Annotation surface resolves; no separate runtime ABI symbol is required |
| `Thread` constructor (Runnable) | `kk_thread_create` | `java.lang.Thread` alias |
| `Thread.sleep(millis)` / `Thread.currentThread()` / `Thread.join()` | `kk_thread_sleep`, `kk_thread_currentThread`, `kk_thread_join` | Static and instance method stubs |
| `kotlin.concurrent.thread {}` | `kk_thread_create` (reused) | |
| `ThreadLocal<T>` constructor | `kk_thread_local_new` | |
| `ThreadLocal<T>.getOrSet {}` | `kk_thread_local_getOrSet` | |
| `Mutex` (create/lock/unlock/tryLock/isLocked/withLock) | `kk_mutex_*` (6 symbols) | |
| `Semaphore` (create/acquire/release/tryAcquire/availablePermits) | `kk_semaphore_*` (5 symbols) | |
| `ReadWriteLock` (create/read/write) | `kk_read_write_lock_*` (3 symbols) | |
| `ReentrantReadWriteLock.new` | `kk_reentrant_read_write_lock_new` | |
| `Lock.withLock {}` | `kk_lock_withLock` | |

### Missing / Partial

None.

---

## kotlin.concurrent.atomics

### Implemented

| Type | Operations | Runtime symbols |
|---|---|---|
| `AtomicInt` | create, load, store, exchange, CAS, CAX, fetchAndAdd, addAndFetch, inc/dec, getAndUpdate, updateAndGet | 12 symbols (`kk_atomic_int_*`) |
| `AtomicLong` | same set as AtomicInt | 12 symbols (`kk_atomic_long_*`) |
| `AtomicBoolean` | create, load, store, exchange, CAS, CAX, getAndUpdate, updateAndGet | 8 symbols (`kk_atomic_bool_*`) |
| `AtomicReference<T>` | create, load, store, exchange, CAS, CAX, getAndUpdate, updateAndGet | 8 symbols (`kk_atomic_ref_*`) |
| `AtomicIntArray` | create, size, loadAt, storeAt, exchangeAt, CASAt, CAXAt, fetchAndUpdateAt, getAndUpdateAt, updateAndGetAt, fetchAndAddAt, addAndFetchAt, inc/decAt, Java bridge aliases | 18 symbols (`kk_atomic_int_array_*`) |
| `AtomicLongArray` | same set as AtomicIntArray | 18 symbols (`kk_atomic_long_array_*`) |
| `AtomicBooleanArray` | create, size, loadAt, storeAt, exchangeAt, CASAt, CAXAt, fetchAndUpdateAt, getAndUpdateAt, updateAndGetAt | 10 symbols (`kk_atomic_bool_array_*`) |
| `AtomicArray<T>` | create/of, size, loadAt, storeAt, exchangeAt, CASAt, CAXAt, fetchAndUpdateAt, updateAt, updateAndFetchAt, Java bridge aliases | `kk_atomic_ref_array_*` |
| Package aliases | `kotlin.concurrent.AtomicInt` / array types → `kotlin.concurrent.atomics.*` surfaces | Compiler alias stubs |

### Missing / Partial

None.

---

## Legend

- **Implemented**: runtime `@_cdecl` symbol exists AND compiler stub registered in `HeaderHelpers+Synthetic*.swift`
- **Missing**: no runtime symbol and/or no compiler stub found
- **Partial**: compiler stub present but runtime semantics incomplete, or vice-versa

## Key source files

| File | Coverage |
|---|---|
| `Sources/Runtime/RuntimeStringArray.swift` | `kotlin.io` top-level functions |
| `Sources/Runtime/RuntimeFileIO.swift` | `kotlin.io` File / BufferedReader / streams |
| `Sources/Runtime/RuntimeDuration.swift` | `kotlin.time.Duration` |
| `Sources/Runtime/RuntimeInstant.swift` | `kotlin.time.Instant` |
| `Sources/Runtime/RuntimeTime.swift` | `kotlin.time` platform bridges, TimeMark |
| `Sources/Runtime/RuntimeAtomic.swift` | `kotlin.concurrent.atomics` all types |
| `Sources/Runtime/RuntimeThread.swift` | `java.lang.Thread` / `kotlin.concurrent.thread` |
| `Sources/Runtime/RuntimeSync.swift` | `kotlin.concurrent` Mutex/Semaphore/Lock |
| `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticTODOAndIOStubs.swift` | `kotlin.io` stubs |
| `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticAtomicStubs.swift` | atomic stubs |
| `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticConcurrencyStubs.swift` | concurrency stubs |
| `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticDurationStubs.swift` | Duration stubs |
| `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticInstantStubs.swift` | Instant stubs |
| `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticExperimentalTimeStubs.swift` | TimeMark stubs |
