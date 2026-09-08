package golden.sema

fun main() {
    val sized = ByteArray(3)
    println(sized.size)
    println(sized[0])

    val initialized = ByteArray(4) { (it + 1).toByte() }
    println(initialized.size)
    println(initialized[0])
    println(initialized[3])
    println(ByteArray(0) { 42 }.size)
}
