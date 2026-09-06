@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val generic = arrayOf(10, 20, 30, 40)
    println(generic.sliceArray(1..2).toList())
    println(generic.sliceArray(listOf(3, 1)).toList())
    println(generic.reversedArray().toList())
    val genericView = generic.asList()
    generic[1] = 99
    println(genericView)

    val ints = intArrayOf(1, 2, 3, 4)
    println(ints.sliceArray(1..2).toList())
    println(ints.sliceArray(listOf(3, 1)).toList())
    println(ints.reversedArray().toList())
    val intView = ints.asList()
    ints[1] = 88
    println(intView)
    println(ints.toTypedArray().toList())
    println(IntArray(0).reversedArray().size)

    val uints = uintArrayOf(10u, 20u, 30u, 40u)
    println(uints.sliceArray(1..2).toList())
    println(uints.sliceArray(listOf(3, 1)).toList())
    println(uints.reversedArray().toList())
    val uintView = uints.asList()
    uints[1] = 77u
    println(uintView)
    println(uints.toTypedArray().toList())
}
