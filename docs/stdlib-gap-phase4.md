# Phase 4 stdlib Gap Inventory — STDLIB-GAP-PH4

Generated: 2026-04-17. Tracks coverage status for the eight stdlib sub-packages
targeted in Phase 4.

Legend: **Done** = runtime entry point exists + sema stub registered.  
**Partial** = some coverage but known gaps remain.  
**Gap** = no implementation.

---

## 1. `kotlin.math`

### Top-level functions — Double / Float overloads

| Symbol | Status | Notes |
|---|---|---|
| `abs(Int/Long/Double/Float)` | Done | `kk_math_abs*` |
| `sqrt(Double/Float)` | Done | `kk_math_sqrt*` |
| `pow(Double,Double)` | Done | `kk_math_pow` |
| `ceil / floor / round / truncate` | Done | Double + Float |
| `sin/cos/tan/asin/acos/atan` | Done | Double + Float |
| `atan2(Double,Double)` / Float | Done | |
| `exp / ln / log2 / log10 / log(x,base)` | Done | Double + Float |
| `sinh / cosh / tanh / cbrt` | Done | STDLIB-MATH-109 |
| `acosh / asinh / atanh` | Done | STDLIB-MATH-113 |
| `sign(Double/Float)` | Done | |
| `hypot(Double,Double)` / Float | Done | |
| `IEEErem(Double,Double)` / Float | Done | STDLIB-514 |
| `withSign(Double,Double)` / Float / Int | Done | STDLIB-514 |
| `nextTowards(Double,Double)` | Done | STDLIB-514 |
| `ulp / nextUp / nextDown` | Done | Double + Float |
| `roundToInt / roundToLong` | Done | Double + Float |
| `roundUp/Down/Ceiling/Floor/HalfUp/HalfDown/HalfEven/Unnecessary` | Done | IEEE 754 modes |

### Constants

| Symbol | Status | Notes |
|---|---|---|
| `PI`, `E` | Done | `kk_math_pi/e`, properties registered |
| `Double.MAX/MIN/POSITIVE_INFINITY/NEGATIVE_INFINITY/NaN` | Done | |
| `Float.MAX/MIN/POSITIVE_INFINITY/NEGATIVE_INFINITY/NaN` | Done | |
| `Int.MAX_VALUE / MIN_VALUE` | Done | |
| `Long.MAX_VALUE / MIN_VALUE` | Done | |

### Known gaps

| Gap | Description |
|---|---|
| `min(a,b)` / `max(a,b)` top-level (all types) | No `kk_math_min_*` / `kk_math_max_*` entry points registered as sema stubs; callers currently rely on collection `minOf/maxOf` lowering |
| `clamp(value,min,max)` | No runtime entry point or sema stub |
| `Float.nextTowards` overload | Only `Double` variant exists (`kk_math_nextTowards`); Float overload missing |
| `abs(Short/Byte)` | No dedicated entry points; Short/Byte fall through to Int path |

**Summary: ~4 gaps, 25+ items Done.**

---

## 2. `kotlin.random`

### `Random` object / factory

| Symbol | Status | Notes |
|---|---|---|
| `Random(seed: Int)` constructor | Done | `kk_random_create_seeded` |
| `Random(seed: Long)` constructor | Done | `kk_random_create_seeded` |
| `Random.Default` singleton | Done | `kk_random_default` |
| `asKotlinRandom()` | Done | `kk_random_asKotlinRandom` |
| `Random.asJavaRandom()` | Done | `kk_random_asJavaRandom` |

### Instance methods

| Symbol | Status | Notes |
|---|---|---|
| `nextInt()` | Done | |
| `nextInt(until)` | Done | |
| `nextInt(from, until)` | Done | |
| `nextInt(range: IntRange)` | Done | `kk_random_nextInt_rangeObject` |
| `nextLong()` | Done | |
| `nextLong(until)` | Done | |
| `nextLong(from, until)` | Done | |
| `nextLong(range: LongRange)` | Done | `kk_random_nextLong_rangeObject` |
| `nextUInt()` | Done | |
| `nextUInt(until)` | Done | |
| `nextUInt(from, until)` | Done | |
| `nextUInt(range: UIntRange)` | Done | `kk_random_nextUInt_uintRange` |
| `nextULong()` | Done | |
| `nextULong(until)` | Done | |
| `nextULong(from, until)` | Done | |
| `nextULong(range: ULongRange)` | Done | `kk_random_nextULong_ulongRange` |
| `nextFloat()` | Done | |
| `nextFloat(until)` | Done | |
| `nextFloat(from, until)` | Done | STDLIB-655 |
| `nextDouble()` | Done | |
| `nextDouble(until)` | Done | |
| `nextDouble(from, until)` | Done | |
| `nextBoolean()` | Done | |
| `nextBytes(array: ByteArray)` | Done | STDLIB-653 |
| `nextBytes(size: Int)` | Done | `kk_random_nextBytes_size` |
| `nextBytes(array: ByteArray, fromIndex, toIndex)` | Done | `kk_random_nextBytes_range` |
| `nextUBytes(size: Int)` | Done | `kk_random_nextUBytes_size` |
| `nextUBytes(array: UByteArray)` | Done | `kk_random_nextUBytes` |
| `nextUBytes(array: UByteArray, fromIndex, toIndex)` | Done | `kk_random_nextUBytes_range` |
| `nextBits(bitCount)` | Done | `kk_random_nextBits` |

### `SecureRandom`

| Symbol | Status | Notes |
|---|---|---|
| `SecureRandom.getInstance()` | Done | `kk_secure_random_get_instance` |
| `setSeed(seed: Int)` | Done | |
| `generateSeed(size: Int)` | Done | |
| `nextBytes(array)` | Done | |
| `nextBytes(size: Int)` factory | Gap | Missing allocating overload |

Inventory is pinned by `RandomSyntheticLinkTests+OverloadCoverage` and runtime ABI coverage in
`RuntimeABISpec+Random`.

**Summary: 1 gap, 39 items Done.**

---

## 3. `kotlin.reflect`

### `KClass<T>`

| Symbol | Status | Notes |
|---|---|---|
| `simpleName`, `qualifiedName` | Done | `kk_kclass_get_simple_name/qualified_name` |
| `supertypes` | Done | `kk_kclass_supertypes` |
| `isData/isSealed/isValue/isAbstract/isOpen/isFinal/isInterface/isObject/isEnum` | Done | |
| `members` / `membersCount` | Done | `kk_kclass_members / members_count` |
| `memberFunctions` / `memberProperties` | Done | `kk_kclass_member_functions/properties` |
| `declaredMemberFunctions` / `declaredMemberProperties` | Done | |
| `constructors` / `primaryConstructor` | Done | |
| `getAnnotations` / `findAnnotation` | Done | |
| `isInstance(value)` | Done | |
| `createInstance()` | Done | |
| `typeParameters` | Done | `kk_kclass_type_parameters` |
| `visibility` | Done | `kk_kclass_visibility` |
| `instanceSize` / `arity` (stub) | Partial | Return 0; metadata not populated yet |

### `KType`

| Symbol | Status | Notes |
|---|---|---|
| `create / classifier / arguments / isMarkedNullable / toString` | Done | |
| `KTypeProjection create / type / variance` | Done | |
| `KVariance` enum | Done | |
| `KType.equals` / `hashCode` | Gap | No `kk_ktype_equals`; equality check falls back to pointer identity |

### `KFunction<T>`

| Symbol | Status | Notes |
|---|---|---|
| `create / create_full / call 0–3 / call_vararg` | Done | |
| `getName / getArity / getReturnType / isSuspend / getParameters / getValueParameters / getType` | Done | |
| `visibility` / `annotations` on KFunction | Gap | No getter entry points for visibility or annotation list |

### `KProperty` / `KMutableProperty`

| Symbol | Status | Notes |
|---|---|---|
| Stub create / getter / setter attachment | Done | `kk_kproperty_stub_*` |
| `KProperty.get()` direct dispatch | Partial | Returns `UnsupportedOperationException`; bound-receiver path lowered at call site |
| `KProperty.name / returnType / visibility / isConst / isLateinit` | Done | |

### `KParameter`

| Symbol | Status | Notes |
|---|---|---|
| `create / getIndex / getName / getType / isOptional / getKind` | Done | |

### `KConstructor`

| Symbol | Status | Notes |
|---|---|---|
| `create / call 0–3 / call_vararg / getName / getArity / getReturnType / isPrimary / getVisibility / getParameters` | Done | |

**Summary: ~2 gaps (KType equality, KFunction visibility/annotations), most items Done.**

---

## 4. `kotlin.comparisons`

| Symbol | Status | Notes |
|---|---|---|
| `Comparator<T>` interface synthetic stub | Done | Registered via `HeaderHelpers+SyntheticComparatorStubs` |
| `Comparator.compare(a, b)` | Done | Interface member |
| `compareBy { }` (single selector) | Done | `kk_comparator_from_selector` |
| `compareByDescending { }` | Done | `kk_comparator_from_selector_descending` |
| `compareBy` multi-selector | Done | `kk_comparator_from_multi_selectors*` |
| `compareByPrimitive` | Done | `kk_comparator_from_selector_primitive` |
| `compareByDescending` primitive variant | Done | `kk_comparator_from_selector_primitive_descending` |
| `thenBy` | Done | `kk_comparator_then_by / kk_comparator_then_by_comparator_selector` |
| `thenByDescending` | Done | `kk_comparator_then_by_descending / kk_comparator_then_by_descending_comparator_selector` |
| `thenComparator` | Done | `kk_comparator_then_comparator` |
| `thenDescending` | Done | `kk_comparator_then_descending` |
| `naturalOrder()` | Done | `kk_comparator_natural_order` |
| `reverseOrder()` | Done | `kk_comparator_reverse_order` |
| `reversed()` | Done | `kk_comparator_reversed` |
| `nullsFirst / nullsLast` | Done | `kk_comparator_nulls_first / nulls_last` |
| `compareValues(a, b)` top-level | Done | `kk_compareValues` |
| `compareValuesBy(a, b, selector)` | Done | `kk_compareValuesBy1` |
| `compareValuesBy(a, b, selector1, selector2)` | Done | `kk_compareValuesBy` |
| `compareValuesBy(a, b, selector1, selector2, selector3)` | Done | `kk_compareValuesBy3` |
| `compareValuesBy(a, b, vararg selectors)` | Done | `kk_compareValuesByVararg` |
| `compareValuesBy(a, b, comparator, selector)` | Done | `kk_compareValuesByComparator` |

Inventory is pinned by `ComparisonsAPISurfaceInventoryTests` and runtime ABI coverage in
`RuntimeABISpec+Comparator`.

**Summary: 0 gaps, 20 items Done.**

---

## 5. `kotlin.annotation`

| Symbol | Status | Notes |
|---|---|---|
| `@Target` annotation class | Done | STDLIB-METAPROG-116 |
| `@Retention` annotation class | Done | |
| `@MustBeDocumented` | Done | |
| `@Repeatable` | Done | |
| `AnnotationTarget` enum (all 15 entries) | Done | |
| `AnnotationRetention` enum (SOURCE/BINARY/RUNTIME) | Done | |
| `kotlin.Suppress` | Done | |
| `kotlin.Deprecated` + `DeprecationLevel` enum | Done | |
| `kotlin.ReplaceWith` | Done | |
| `kotlin.OptIn` / `kotlin.RequiresOptIn` + Level enum | Done | |
| `kotlin.WasExperimental` | Done | |
| `kotlin.Metadata` | Done | |
| `kotlin.ExperimentalStdlibApi` | Done | |
| `kotlin.annotation.Target` applied to `@Target` itself | Done | |
| Custom annotation class declaration & usage | Partial | Annotation classes parsed/type-checked but argument default values not fully propagated |

**Summary: ~1 partial gap (annotation argument defaults), all core items Done.**

---

## 6. `kotlin.system`

| Symbol | Status | Notes |
|---|---|---|
| `exitProcess(status: Int): Nothing` | Done | `kk_system_exitProcess` |
| `currentTimeMillis(): Long` | Done | `kk_system_currentTimeMillis` |
| `nanoTime(): Long` | Done | `kk_system_nanoTime` |
| `measureTimeMillis { }` | Done | `kk_system_measureTimeMillis` |
| `measureNanoTime { }` | Done | `kk_system_measureNanoTime` |
| `System.processStartNanos` property | Done | `kk_system_process_start_nanos` |
| `System.gc()` | Done | `kk_system_gc` |
| `getenv(key)` / `getenv()` map | Gap | No runtime entry point or sema stub |
| `hostname()` | Gap | No runtime entry point |

**Summary: ~2 gaps (env access, hostname), 7 items Done.**

---

## 7. `kotlin.uuid`

| Symbol | Status | Notes |
|---|---|---|
| `Uuid.random()` | Done | `kk_uuid_random` |
| `Uuid.parse(uuidString)` | Done | `kk_uuid_parse` |
| `Uuid.nameUUIDFromBytes(name)` | Done | `kk_uuid_nameUUIDFromBytes` |
| `toString()` | Done | `kk_uuid_toString` |
| `toHexString()` | Done | `kk_uuid_toHexString` |
| `toLongs()` | Done | `kk_uuid_toLongs` |
| `toByteArray()` | Done | `kk_uuid_toByteArray` |
| `version` / `variant` | Done | |
| `mostSignificantBits` / `leastSignificantBits` | Done | |
| `Uuid.fromLongs(msb, lsb)` | Gap | No `kk_uuid_fromLongs` entry point or sema stub |
| `Uuid.fromByteArray(bytes)` | Gap | No `kk_uuid_fromByteArray` entry point or sema stub |
| `Uuid.parseOrNull(uuidString)` | Gap | No null-safe parse variant |
| `Uuid.equals / hashCode / compareTo` | Partial | `equals/hashCode` deferred to generic object comparison; `compareTo` not stubbed |

**Summary: ~4 gaps, 10 items Done.**

---

## 8. `kotlin.native` (and `kotlinx.cinterop`)

### `kotlin.native` annotations

| Symbol | Status | Notes |
|---|---|---|
| `@ObjCName` | Done | `kotlin.native` package, STDLIB-NativeInterop |
| `@CName` | Done | |
| `@ObjCSignatureOverride` | Done | |
| `@HidesFromObjC` | Done | |
| `@ShouldRefineInSwift` / `@RefinesInSwift` | Done | |
| `kotlin.experimental.ExperimentalNativeApi` | Done | |
| `kotlin.experimental.ExperimentalObjCName/Refinement/Enum` | Done | |

### `kotlinx.cinterop` types

| Symbol | Status | Notes |
|---|---|---|
| `NativePointed / CPointed / COpaquePointer` | Done | Synthetic class stubs |
| `NativePlacement / MemScope` | Done | |
| `CValuesRef<T> / CPointer<T> / CPointerVar<T>` | Done | Generic stubs with type parameters |
| `ByteVar … DoubleVar` primitive vars | Done | |
| `ExperimentalForeignApi` / `BetaInteropApi` annotations | Done | |
| `CPointer` runtime box (`kk_cpointer_new/address`) | Done | |
| `COpaquePointer` runtime box | Done | |
| `nativeHeap.alloc<T>` / `free` | Done | `kk_native_heap_alloc/free` |
| `memScoped { }` / `MemScope.alloc<T>` | Done | `kk_mem_scope_enter/exit/alloc` |
| `pinObject / unpinObject` | Done | `kk_pin_object / kk_unpin_object` |
| `StableRef<T>` | Gap | No `kk_stable_ref_*` entry points or sema stubs |
| `Arena` | Gap | No `kk_arena_*` entry points |
| `pointed` property accessor on `CPointer` | Gap | No lowering path for `ptr.pointed` |
| `CFunction<T>` | Gap | No stub or runtime entry point |
| `interpretCPointer<T>` / `nativeNullPtr` | Gap | Not wired |

**Summary: ~5 gaps (StableRef, Arena, pointed accessor, CFunction, interpretCPointer), 14 items Done.**

---

## Overall Phase 4 Counts

| Package | Done | Partial | Gap |
|---|---|---|---|
| `kotlin.math` | 25 | 0 | 4 |
| `kotlin.random` | 39 | 0 | 1 |
| `kotlin.reflect` | 28 | 2 | 2 |
| `kotlin.comparisons` | 20 | 0 | 0 |
| `kotlin.annotation` | 14 | 1 | 0 |
| `kotlin.system` | 7 | 0 | 2 |
| `kotlin.uuid` | 10 | 1 | 4 |
| `kotlin.native` / `kotlinx.cinterop` | 14 | 0 | 5 |
| **Total** | **157** | **4** | **18** |

---

## High-priority gaps to close next

1. **`kotlin.math` — `min/max/clamp` top-level** (frequently used in real code)
2. **`kotlin.uuid` — `fromLongs`, `fromByteArray`, `parseOrNull`** (API completeness)
3. **`kotlin.random` — `SecureRandom.nextBytes(size)`** (allocating overload parity)
4. **`kotlin.reflect` — `KType.equals`** (needed for `typeOf<T>() == typeOf<U>()` patterns)
5. **`kotlinx.cinterop` — `StableRef<T>`** (required by Kotlin/Native interop patterns)
