fun main() {
    // Basic copyOf() - same size
    val arr = arrayOf(1, 2, 3)
    val copy = arr.copyOf()
    println(copy.toList())

    // copyOf() creates independent copy
    copy[0] = 99
    println(arr.toList())
    println(copy.toList())

    // copyOfRange
    println(arr.copyOfRange(0, 2).toList())
    println(arr.copyOfRange(1, 3).toList())
    println(arr.copyOfRange(0, 0).toList())

    // copyOf with new size (smaller)
    val smaller = arr.copyOf(2)
    println(smaller.toList())

    // copyOf with new size (same)
    val same = arr.copyOf(3)
    println(same.toList())

    // copyOf with new size (larger) - padded with null
    val larger = arr.copyOf(5)
    println(larger.toList())

    // String array
    val strs = arrayOf("a", "b", "c")
    println(strs.copyOf().toList())
    println(strs.copyOf(2).toList())
    println(strs.copyOf(5).toList())
    println(strs.copyOfRange(0, 2).toList())

    // Empty array
    val empty = arrayOf<Int>()
    println(empty.copyOf().toList())
    println(empty.copyOf(0).toList())
    println(empty.copyOf(3).toList())

    // Boolean array
    val bools = arrayOf(true, false, true)
    println(bools.copyOf().toList())
    println(bools.copyOf(2).toList())

    // copyOf with size 0
    println(arr.copyOf(0).toList())

    // Nested array (shallow copy)
    val nested = arrayOf(arrayOf(1, 2), arrayOf(3, 4))
    val nestedCopy = nested.copyOf()
    println(nestedCopy[0].toList())
    println(nestedCopy[1].toList())
    // Verify shallow copy: modifying inner array affects both
    nested[0][0] = 100
    println(nestedCopy[0].toList())

    // IntArray copyOf
    val intArr = intArrayOf(10, 20, 30)
    val intCopy = intArr.copyOf()
    println(intCopy.toList())
    println(intArr.copyOf(2).toList())
    println(intArr.copyOf(5).toList())
    println(intArr.copyOfRange(1, 3).toList())

    // copyOf independence for IntArray
    intCopy[0] = 999
    println(intArr.toList())
    println(intCopy.toList())

    // DoubleArray copyOf
    val dblArr = doubleArrayOf(1.5, 2.5, 3.5)
    println(dblArr.copyOf().toList())
    println(dblArr.copyOf(2).toList())
    println(dblArr.copyOf(5).toList())

    // LongArray copyOf
    val longArr = longArrayOf(100L, 200L, 300L)
    println(longArr.copyOf().toList())
    println(longArr.copyOf(2).toList())

    // BooleanArray copyOf
    val boolArr = booleanArrayOf(true, false)
    println(boolArr.copyOf().toList())
    println(boolArr.copyOf(4).toList())

    // CharArray copyOf
    val charArr = charArrayOf('x', 'y', 'z')
    println(charArr.copyOf().toList())
    println(charArr.copyOf(2).toList())

    // copyOfRange edge: full range
    println(arr.copyOfRange(0, 3).toList())

    // Multiple copyOf calls produce independent copies
    val a = arrayOf(1, 2, 3)
    val b = a.copyOf()
    val c = a.copyOf()
    b[0] = 10
    c[0] = 20
    println(a.toList())
    println(b.toList())
    println(c.toList())
}
