package golden.sema

fun main() {
    val sized: Array<String?> = Array(2)
    println(sized.size)
    val initialized = Array(3) { index -> "item$index" }
    println(initialized[0])
    println(initialized[2])
}
