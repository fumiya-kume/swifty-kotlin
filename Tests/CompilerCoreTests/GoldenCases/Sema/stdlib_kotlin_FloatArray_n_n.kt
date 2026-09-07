package golden.sema

fun main() {
    val sizeOnly = FloatArray(3)
    println(sizeOnly.size)
    println(sizeOnly[0])

    val initialized = FloatArray(4) { index ->
        when (index) {
            0 -> 1.5f
            1 -> 2.5f
            2 -> -3.5f
            else -> 4.5f
        }
    }
    println(initialized.size)
    println(initialized[0])
    println(initialized[3])
    println(FloatArray(0) { 42.0f }.size)
}
