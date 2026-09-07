fun main() {
    val sized = BooleanArray(3)
    println(sized.size)
    println(sized[0])

    val initialized = BooleanArray(4) { it % 2 == 0 }
    println(initialized.size)
    println(initialized[0])
    println(initialized[1])
    println(initialized[3])
    println(BooleanArray(0) { true }.size)
}
