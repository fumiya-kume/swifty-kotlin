// swiftlint:disable file_length

// UIntProgression / UIntRange / ULongProgression / ULongRange
// runtime entry points (STDLIB-RANGE-036/037/039, STDLIB-524).
//
// HOF logic and range-handle validation live in RuntimeRangeSharedHOF.swift.
// These @_cdecl functions are thin ABI entry points.

// MARK: - UIntProgression operations (STDLIB-RANGE-039)

@_cdecl("__kk_uint_rangeTo")
public func __kk_uint_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1))
}

@_cdecl("__kk_uint_downTo")
public func __kk_uint_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1))
}

@_cdecl("__kk_uint_step")
public func __kk_uint_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    runtimeUnsignedStep(rangeRaw, stepValue)
}

@_cdecl("kk_uint_range_reversed")
public func kk_uint_range_reversed(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_reversed") { range in
        runtimeUnsignedRangeReversed(range)
    }
}

@_cdecl("kk_uint_range_toList")
public func kk_uint_range_toList(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_toList") { range in
        RuntimeUnsignedRangeHOFKind.toList(range)
    }
}

@_cdecl("__kk_uint_range_iterator")
public func __kk_uint_range_iterator(_ rangeRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: rangeRaw) != nil { return rangeRaw }
    guard let range = runtimeRangeBox(from: rangeRaw) else { return 0 }
    return registerRuntimeObject(
        RuntimeRangeIteratorBox(current: range.first, last: range.last, step: range.step)
    )
}

@_cdecl("__kk_uint_range_hasNext")
public func __kk_uint_range_hasNext(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil { return __kk_iterator_builder_hasNext(iterRaw) }
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else { return 0 }
    let current = UInt(bitPattern: iterator.current)
    let last = UInt(bitPattern: iterator.last)
    if iterator.step > 0 { return current <= last ? 1 : 0 }
    if iterator.step < 0 { return current >= last ? 1 : 0 }
    return 0
}

@_cdecl("__kk_uint_range_next")
public func __kk_uint_range_next(_ iterRaw: Int) -> Int {
    if runtimeIteratorBuilderBox(from: iterRaw) != nil { return __kk_iterator_builder_next(iterRaw) }
    guard let iterator = runtimeRangeIteratorBox(from: iterRaw) else { return 0 }
    let current = iterator.current
    let uCurrent = UInt(bitPattern: current)
    if iterator.step > 0 {
        let uStep = UInt(bitPattern: iterator.step)
        let (next, overflow) = uCurrent.addingReportingOverflow(uStep)
        iterator.current = overflow ? iterator.last : Int(bitPattern: next)
        if overflow { iterator.step = 0 }
    } else if iterator.step < 0 {
        let uStep = UInt(iterator.step.magnitude)
        let (next, overflow) = uCurrent.subtractingReportingOverflow(uStep)
        iterator.current = overflow ? iterator.last : Int(bitPattern: next)
        if overflow { iterator.step = 0 }
    }
    return current
}

// MARK: - UIntRange properties and HOFs (STDLIB-RANGE-036)

@_cdecl("kk_uint_range_contains")
public func kk_uint_range_contains(_ rangeRaw: Int, _ value: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_contains") { range in
        runtimeUnsignedRangeContains(range, value)
    }
}

@_cdecl("kk_uint_range_isEmpty")
public func kk_uint_range_isEmpty(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_isEmpty") { range in
        RuntimeUnsignedRangeHOFKind.isEmpty(range) ? 1 : 0
    }
}

@_cdecl("kk_uint_range_first")
public func kk_uint_range_first(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_first") { range in
        range.first
    }
}

@_cdecl("kk_uint_range_last")
public func kk_uint_range_last(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_last") { range in
        range.last
    }
}

@_cdecl("kk_uint_range_step")
public func kk_uint_range_step(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_step") { range in
        range.step
    }
}

@_cdecl("kk_uint_range_count")
public func kk_uint_range_count(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_count") { range in
        runtimeUnsignedRangeCount(range)
    }
}

@_cdecl("kk_uint_range_sum")
public func kk_uint_range_sum(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_sum") { range in
        runtimeUnsignedRangeSum(range)
    }
}

@_cdecl("kk_uint_range_toUIntArray")
public func kk_uint_range_toUIntArray(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_toUIntArray") { range in
        RuntimeUnsignedRangeHOFKind.toList(range)
    }
}

@_cdecl("kk_uint_range_forEach")
public func kk_uint_range_forEach(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_forEach", operation: RuntimeUnsignedRangeHOFKind.forEach)
}

@_cdecl("kk_uint_range_reduce")
public func kk_uint_range_reduce(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_reduce", operation: RuntimeUnsignedRangeHOFKind.reduce)
}

@_cdecl("kk_uint_range_reduceIndexed")
public func kk_uint_range_reduceIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                        _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_reduceIndexed", operation: RuntimeUnsignedRangeHOFKind.reduceIndexed)
}

@_cdecl("kk_uint_range_fold")
public func kk_uint_range_fold(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFoldHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, initialValue, fnPtr, closureRaw, outThrown,
                             functionName: "kk_uint_range_fold", operation: RuntimeUnsignedRangeHOFKind.fold)
}

@_cdecl("kk_uint_range_foldIndexed")
public func kk_uint_range_foldIndexed(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                                      _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFoldHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, initialValue, fnPtr, closureRaw, outThrown,
                             functionName: "kk_uint_range_foldIndexed", operation: RuntimeUnsignedRangeHOFKind.foldIndexed)
}

@_cdecl("kk_uint_range_find")
public func kk_uint_range_find(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_uint_range_find", orNull: true)
}

@_cdecl("kk_uint_range_findLast")
public func kk_uint_range_findLast(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                   _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_uint_range_findLast", orNull: true)
}

@_cdecl("kk_uint_range_first_predicate")
public func kk_uint_range_first_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_uint_range_first_predicate", orNull: false)
}

@_cdecl("kk_uint_range_firstOrNull_predicate")
public func kk_uint_range_firstOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_uint_range_firstOrNull_predicate", orNull: true)
}

@_cdecl("kk_uint_range_firstOrNull")
public func kk_uint_range_firstOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_firstOrNull") { range in
        RuntimeUnsignedRangeHOFKind.firstOrNull(range)
    }
}

@_cdecl("kk_uint_range_last_predicate")
public func kk_uint_range_last_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_uint_range_last_predicate", orNull: false)
}

@_cdecl("kk_uint_range_lastOrNull_predicate")
public func kk_uint_range_lastOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_uint_range_lastOrNull_predicate", orNull: true)
}

@_cdecl("kk_uint_range_lastOrNull")
public func kk_uint_range_lastOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_lastOrNull") { range in
        RuntimeUnsignedRangeHOFKind.lastOrNull(range)
    }
}

@_cdecl("__kk_uint_range_randomOrNull")
public func __kk_uint_range_randomOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw: nil,
                                  functionName: "__kk_uint_range_randomOrNull")
}

@_cdecl("__kk_uint_range_randomOrNull_random")
public func __kk_uint_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw: randomRaw,
                                  functionName: "__kk_uint_range_randomOrNull_random")
}

@_cdecl("__kk_uint_range_random")
public func __kk_uint_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, 0, outThrown,
                            functionName: "__kk_uint_range_random")
}

@_cdecl("__kk_uint_range_random_random")
public func __kk_uint_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw, outThrown,
                            functionName: "__kk_uint_range_random_random")
}

@_cdecl("kk_uint_range_any")
public func kk_uint_range_any(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_any", operation: RuntimeUnsignedRangeHOFKind.any)
}

@_cdecl("kk_uint_range_all")
public func kk_uint_range_all(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_all", operation: RuntimeUnsignedRangeHOFKind.all)
}

@_cdecl("kk_uint_range_none")
public func kk_uint_range_none(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_uint_range_none", operation: RuntimeUnsignedRangeHOFKind.none)
}

@_cdecl("__kk_uint_range_chunked")
public func __kk_uint_range_chunked(_ rangeRaw: Int, _ size: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if size <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "size \(size) must be greater than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_uint_range_chunked") { range in
        RuntimeUnsignedRangeHOFKind.chunked(range, size)
    }
}

@_cdecl("__kk_uint_range_windowed")
public func __kk_uint_range_windowed(_ rangeRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if size <= 0 || step <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Both size \(size) and step \(step) must be greater than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_uint_range_windowed") { range in
        RuntimeUnsignedRangeHOFKind.windowed(range, size, step, partialWindows)
    }
}

@_cdecl("__kk_uint_range_take")
public func __kk_uint_range_take(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_uint_range_take") { range in
        RuntimeUnsignedRangeHOFKind.take(range, n)
    }
}

@_cdecl("__kk_uint_range_drop")
public func __kk_uint_range_drop(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "__kk_uint_range_drop") { range in
        RuntimeUnsignedRangeHOFKind.drop(range, n)
    }
}

@_cdecl("kk_uint_range_average")
public func kk_uint_range_average(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_average") { range in
        RuntimeUnsignedRangeHOFKind.average(range)
    }
}

@_cdecl("kk_uint_range_sorted")
public func kk_uint_range_sorted(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_uint_range_sorted") { range in
        RuntimeUnsignedRangeHOFKind.sorted(range)
    }
}

// MARK: - ULong HOFs (STDLIB-RANGE-037/039)

@_cdecl("kk_ulong_range_mapIndexed")
public func kk_ulong_range_mapIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                      _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_mapIndexed", operation: RuntimeUnsignedRangeHOFKind.mapIndexed)
}

@_cdecl("kk_ulong_range_mapNotNull")
public func kk_ulong_range_mapNotNull(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                      _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_mapNotNull", operation: RuntimeUnsignedRangeHOFKind.mapNotNull)
}

@_cdecl("kk_ulong_range_filter")
public func kk_ulong_range_filter(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_filter", operation: RuntimeUnsignedRangeHOFKind.filter)
}

@_cdecl("kk_ulong_range_filterIndexed")
public func kk_ulong_range_filterIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_filterIndexed", operation: RuntimeUnsignedRangeHOFKind.filterIndexed)
}

@_cdecl("kk_ulong_range_filterNot")
public func kk_ulong_range_filterNot(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                     _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_filterNot", operation: RuntimeUnsignedRangeHOFKind.filterNot)
}

@_cdecl("kk_ulong_range_reduce")
public func kk_ulong_range_reduce(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                  _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_reduce", operation: RuntimeUnsignedRangeHOFKind.reduce)
}

@_cdecl("kk_ulong_range_reduceIndexed")
public func kk_ulong_range_reduceIndexed(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                         _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_reduceIndexed", operation: RuntimeUnsignedRangeHOFKind.reduceIndexed)
}

@_cdecl("kk_ulong_range_fold")
public func kk_ulong_range_fold(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFoldHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, initialValue, fnPtr, closureRaw, outThrown,
                             functionName: "kk_ulong_range_fold", operation: RuntimeUnsignedRangeHOFKind.fold)
}

@_cdecl("kk_ulong_range_foldIndexed")
public func kk_ulong_range_foldIndexed(_ rangeRaw: Int, _ initialValue: Int, _ fnPtr: Int, _ closureRaw: Int,
                                       _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFoldHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, initialValue, fnPtr, closureRaw, outThrown,
                             functionName: "kk_ulong_range_foldIndexed", operation: RuntimeUnsignedRangeHOFKind.foldIndexed)
}

@_cdecl("kk_ulong_range_find")
public func kk_ulong_range_find(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_ulong_range_find", orNull: true)
}

@_cdecl("kk_ulong_range_findLast")
public func kk_ulong_range_findLast(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                    _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_ulong_range_findLast", orNull: true)
}

@_cdecl("kk_ulong_range_first_predicate")
public func kk_ulong_range_first_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                           _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_ulong_range_first_predicate", orNull: false)
}

@_cdecl("kk_ulong_range_firstOrNull_predicate")
public func kk_ulong_range_firstOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                                 _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeFirstMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                                functionName: "kk_ulong_range_firstOrNull_predicate", orNull: true)
}

@_cdecl("kk_ulong_range_firstOrNull")
public func kk_ulong_range_firstOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_firstOrNull") { range in
        RuntimeUnsignedRangeHOFKind.firstOrNull(range)
    }
}

@_cdecl("kk_ulong_range_last_predicate")
public func kk_ulong_range_last_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                          _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_ulong_range_last_predicate", orNull: false)
}

@_cdecl("kk_ulong_range_lastOrNull_predicate")
public func kk_ulong_range_lastOrNull_predicate(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeLastMatchEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                               functionName: "kk_ulong_range_lastOrNull_predicate", orNull: true)
}

@_cdecl("kk_ulong_range_lastOrNull")
public func kk_ulong_range_lastOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_lastOrNull") { range in
        RuntimeUnsignedRangeHOFKind.lastOrNull(range)
    }
}

@_cdecl("__kk_ulong_range_randomOrNull")
public func __kk_ulong_range_randomOrNull(_ rangeRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw: nil,
                                  functionName: "__kk_ulong_range_randomOrNull")
}

@_cdecl("__kk_ulong_range_randomOrNull_random")
public func __kk_ulong_range_randomOrNull_random(_ rangeRaw: Int, _ randomRaw: Int) -> Int {
    runtimeRangeRandomOrNullEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw: randomRaw,
                                  functionName: "__kk_ulong_range_randomOrNull_random")
}

@_cdecl("__kk_ulong_range_random")
public func __kk_ulong_range_random(_ rangeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, 0, outThrown,
                            functionName: "__kk_ulong_range_random")
}

@_cdecl("__kk_ulong_range_random_random")
public func __kk_ulong_range_random_random(_ rangeRaw: Int, _ randomRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeRangeRandomEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, randomRaw, outThrown,
                            functionName: "__kk_ulong_range_random_random")
}

@_cdecl("kk_ulong_range_any")
public func kk_ulong_range_any(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_any", operation: RuntimeUnsignedRangeHOFKind.any)
}

@_cdecl("kk_ulong_range_all")
public func kk_ulong_range_all(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_all", operation: RuntimeUnsignedRangeHOFKind.all)
}

@_cdecl("kk_ulong_range_none")
public func kk_ulong_range_none(_ rangeRaw: Int, _ fnPtr: Int, _ closureRaw: Int,
                                _ outThrown: UnsafeMutablePointer<Int>?) -> Int
{
    runtimeRangeHOFEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, fnPtr, closureRaw, outThrown,
                         functionName: "kk_ulong_range_none", operation: RuntimeUnsignedRangeHOFKind.none)
}

@_cdecl("kk_ulong_range_chunked")
public func kk_ulong_range_chunked(_ rangeRaw: Int, _ size: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if size <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "size \(size) must be greater than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_chunked") { range in
        RuntimeUnsignedRangeHOFKind.chunked(range, size)
    }
}

@_cdecl("kk_ulong_range_windowed")
public func kk_ulong_range_windowed(_ rangeRaw: Int, _ size: Int, _ step: Int, _ partialWindows: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if size <= 0 || step <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Both size \(size) and step \(step) must be greater than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_windowed") { range in
        RuntimeUnsignedRangeHOFKind.windowed(range, size, step, partialWindows)
    }
}

@_cdecl("kk_ulong_range_take")
public func kk_ulong_range_take(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_take") { range in
        RuntimeUnsignedRangeHOFKind.take(range, n)
    }
}

@_cdecl("kk_ulong_range_drop")
public func kk_ulong_range_drop(_ rangeRaw: Int, _ n: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    if n < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(n) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_drop") { range in
        RuntimeUnsignedRangeHOFKind.drop(range, n)
    }
}

@_cdecl("kk_ulong_range_average")
public func kk_ulong_range_average(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_average") { range in
        RuntimeUnsignedRangeHOFKind.average(range)
    }
}

@_cdecl("kk_ulong_range_sorted")
public func kk_ulong_range_sorted(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_sorted") { range in
        RuntimeUnsignedRangeHOFKind.sorted(range)
    }
}

// MARK: - ULongProgression operations (STDLIB-RANGE-039)

@_cdecl("kk_ulong_rangeTo")
public func kk_ulong_rangeTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: 1))
}

@_cdecl("__kk_ulong_downTo")
public func __kk_ulong_downTo(_ lhs: Int, _ rhs: Int) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: lhs, last: rhs, step: -1))
}

@_cdecl("__kk_ulong_step")
public func __kk_ulong_step(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    runtimeUnsignedStep(rangeRaw, stepValue)
}

@_cdecl("kk_ulong_range_reversed")
public func kk_ulong_range_reversed(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_reversed") { range in
        runtimeUnsignedRangeReversed(range)
    }
}

// MARK: - ULongRange toList (STDLIB-524)

@_cdecl("kk_ulong_range_toList")
public func kk_ulong_range_toList(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeUnsignedRangeHOFKind.self, rangeRaw, functionName: "kk_ulong_range_toList") { range in
        RuntimeUnsignedRangeHOFKind.toList(range)
    }
}

@_cdecl("kk_range_step")
public func kk_range_step(_ rangeRaw: Int) -> Int {
    runtimeRangeEntry(RuntimeSignedRangeHOFKind.self, rangeRaw, functionName: "kk_range_step") { range in
        range.step
    }
}

private func runtimeUnsignedStep(_ rangeRaw: Int, _ stepValue: Int) -> Int {
    guard stepValue > 0 else { return rangeRaw }
    guard stepValue != Int.min else { return rangeRaw }
    guard let range = runtimeRangeBox(from: rangeRaw) else { return rangeRaw }
    if range.step == 0 { return rangeRaw }
    let nextStep = range.step < 0 ? (0 &- stepValue) : stepValue
    let firstUnsigned = UInt(bitPattern: range.first)
    let lastUnsigned = UInt(bitPattern: range.last)
    let alignedLast: Int
    if nextStep > 0 {
        guard firstUnsigned <= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.last &- range.first
        let remainder = diff % nextStep
        alignedLast = range.last &- remainder
    } else {
        guard firstUnsigned >= lastUnsigned else {
            return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: range.last, step: nextStep))
        }
        let diff = range.first &- range.last
        let remainder = diff % (0 &- nextStep)
        alignedLast = range.last &+ remainder
    }
    return registerRuntimeObject(RuntimeRangeBox(first: range.first, last: alignedLast, step: nextStep))
}

private func runtimeUnsignedRangeReversed(_ range: RuntimeRangeBox) -> Int {
    registerRuntimeObject(RuntimeRangeBox(first: range.last, last: range.first, step: 0 &- range.step))
}

private func runtimeUnsignedRangeContains(_ range: RuntimeRangeBox, _ value: Int) -> Int {
    let first = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    let unsignedValue = UInt(bitPattern: value)
    let rawStep = range.step
    if rawStep > 0 {
        let unsignedStep = UInt(bitPattern: rawStep)
        guard first <= unsignedValue && unsignedValue <= last else { return 0 }
        return (unsignedValue - first) % unsignedStep == 0 ? 1 : 0
    } else if rawStep < 0 {
        let unsignedStep = UInt(bitPattern: -rawStep)
        guard last <= unsignedValue && unsignedValue <= first else { return 0 }
        return (first - unsignedValue) % unsignedStep == 0 ? 1 : 0
    }
    return 0
}

private func runtimeUnsignedRangeSum(_ range: RuntimeRangeBox) -> Int {
    var sum = UInt(0)
    var current = UInt(bitPattern: range.first)
    let last = UInt(bitPattern: range.last)
    if range.step > 0 {
        let unsignedStep = UInt(bitPattern: range.step)
        while current <= last {
            sum &+= current
            let (next, overflow) = current.addingReportingOverflow(unsignedStep)
            if overflow { break }
            current = next
        }
    } else if range.step < 0 {
        let unsignedStep = UInt(range.step.magnitude)
        while current >= last {
            sum &+= current
            let (next, overflow) = current.subtractingReportingOverflow(unsignedStep)
            if overflow { break }
            current = next
        }
    }
    return Int(bitPattern: sum)
}

private func runtimeRangeIteratorBox(from rawValue: Int) -> RuntimeRangeIteratorBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeRangeIteratorBox.self)
}

private func runtimeIteratorBuilderBox(from rawValue: Int) -> RuntimeIteratorBuilderBox? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(pointer, to: RuntimeIteratorBuilderBox.self)
}
