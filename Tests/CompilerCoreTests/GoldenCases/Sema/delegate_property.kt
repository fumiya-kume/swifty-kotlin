package golden.sema

val lazyVal: String by lazy {
    "hello"
}

fun main() {
    println(lazyVal)
}
