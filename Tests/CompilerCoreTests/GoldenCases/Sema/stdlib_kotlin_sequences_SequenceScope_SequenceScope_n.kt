fun sequenceScopeContract(
    values: Iterable<Int>,
    source: Sequence<Int>,
): Sequence<Int> {
    return sequence {
        yield(1)
        yieldAll(values.iterator())
        yieldAll(values)
        yieldAll(source)
    }
}
