fun main() {
    println('5'.digitToInt())
    println('f'.digitToIntOrNull(16))
    println('G'.digitToIntOrNull(16))

    try {
        println('z'.digitToInt(10))
    } catch (e: Throwable) {
        println("invalid-char")
    }

    try {
        println('5'.digitToInt(1))
    } catch (e: Throwable) {
        println("invalid-radix-low")
    }

    try {
        println('5'.digitToInt(37))
    } catch (e: Throwable) {
        println("invalid-radix-high")
    }

    println('ß'.uppercase())
    println('İ'.lowercase())
}
