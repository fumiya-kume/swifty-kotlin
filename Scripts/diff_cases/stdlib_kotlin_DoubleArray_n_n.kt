fun main() {
    try {
        DoubleArray(-1)
        println("no throw")
    } catch (e: NegativeArraySizeException) {
        println("negative: ${e.message}")
    }

    val empty = DoubleArray(0)
    val zeros = DoubleArray(3)
    val values = DoubleArray(4) { it.toDouble() + 0.5 }
    println(empty.size)
    println(zeros[0])
    println(values.size)
    println(values[0])
    println(values[3])
}
