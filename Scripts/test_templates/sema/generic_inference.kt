package golden.sema

fun <T> id(x: T): T = x

fun useInference() {
    val a: Int = id(42)
    val b: String = id("hello")
    val c = id(true)
}
