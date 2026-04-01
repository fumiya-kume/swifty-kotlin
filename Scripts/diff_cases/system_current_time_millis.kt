fun main() {
    // STDLIB-TIME-085: System clock complete implementation

    // currentTimeMillis: millisecond-precision wall-clock time
    val millis = System.currentTimeMillis()
    println(millis > 0)

    // nanoTime: nanosecond-precision monotonic time
    val t1 = System.nanoTime()
    val t2 = System.nanoTime()
    println(t2 >= t1)

    // Time precision: currentTimeMillis returns milliseconds
    val millis2 = System.currentTimeMillis()
    println(millis2 >= millis)
}
