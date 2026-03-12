fun main() {
    try {
        throw IllegalArgumentException("bad arg")
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        throw IllegalStateException("bad state")
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    try {
        throw RuntimeException("test msg")
    } catch (e: Exception) {
        println(e.message)
        println(e.cause)
    }
}
