fun main() {
    // arrayOf with Int elements: get() should return Int
    val intArr = arrayOf(1, 2, 3)
    println(intArr.get(0))
    println(intArr.size)
    println(intArr.contains(2))

    // arrayOf with String elements
    val strArr = arrayOf("hello", "world")
    println(strArr.get(0))
    println(strArr.size)

    // intArrayOf: get() should return Int
    val primitiveArr = intArrayOf(10, 20, 30)
    println(primitiveArr.get(0))
    println(primitiveArr.size)
}
