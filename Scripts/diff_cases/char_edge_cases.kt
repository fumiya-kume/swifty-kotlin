fun main() {
    println('5'.digitToInt())
    println('9'.digitToInt())
    println('a'.digitToIntOrNull())

    try {
        println('z'.digitToInt())
    } catch (e: Throwable) {
        println("invalid-char")
    }

    println('ß'.uppercase())
    println('İ'.lowercase())
}
