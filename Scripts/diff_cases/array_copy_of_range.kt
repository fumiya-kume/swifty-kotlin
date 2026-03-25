fun main() {
    // Basic copyOfRange
    val arr = arrayOf(10, 20, 30, 40, 50)
    val sub = arr.copyOfRange(1, 4)
    println(sub.toList())

    // Full range copy
    val full = arr.copyOfRange(0, arr.size)
    println(full.toList())

    // Empty range (fromIndex == toIndex)
    val empty = arr.copyOfRange(2, 2)
    println(empty.toList())

    // Single element range
    val single = arr.copyOfRange(3, 4)
    println(single.toList())

    // First element only
    val first = arr.copyOfRange(0, 1)
    println(first.toList())

    // Last element only
    val last = arr.copyOfRange(4, 5)
    println(last.toList())

    // copyOfRange with String array
    val strArr = arrayOf("a", "b", "c", "d")
    val strSub = strArr.copyOfRange(1, 3)
    println(strSub.toList())

    // Verify copy independence (modification doesn't affect original)
    val original = arrayOf(1, 2, 3, 4, 5)
    val copy = original.copyOfRange(0, 3)
    copy[0] = 99
    println(original.toList())
    println(copy.toList())
}
// SKIP-DIFF: array copyOfRange parity pending
