inline fun invokeBlock(block: () -> Int): Int = block()
inline fun nested(block: () -> Int): Int = invokeBlock(block)

fun capturedResult(): Int {
    val captured = 5
    try {
        return nested { captured + 2 }
    } finally {
        println("finally")
    }
}

fun caughtResult(): Int {
    try {
        return nested { throw IllegalStateException("boom") }
    } catch (e: IllegalStateException) {
        println("caught")
        return -1
    } finally {
        println("finally")
    }
}

fun main() {
    println(capturedResult())
    println(caughtResult())
}
