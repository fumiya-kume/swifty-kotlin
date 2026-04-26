@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val stringArray = arrayOf("a", "c", "e", "g")
    println(stringArray.binarySearch("c"))
    println(stringArray.binarySearch("d", 1))
    println(stringArray.binarySearch("g", 1, 4))

    val intArray = intArrayOf(10, 20, 30, 40)
    println(intArray.binarySearch(20))
    println(intArray.binarySearch(25, 1))
    println(intArray.binarySearch(40, 1, 4))

    val uintArray = uintArrayOf(10u, 20u, 30u, 40u)
    println(uintArray.binarySearch(30u))
    println(uintArray.binarySearch(15u, 1))
    println(uintArray.binarySearch(40u, 1, 4))

    val ulongArray = ulongArrayOf(10uL, 20uL, 30uL, 40uL)
    println(ulongArray.binarySearch(30uL))
    println(ulongArray.binarySearch(15uL, 1))
    println(ulongArray.binarySearch(40uL, 1, 4))
}
