package golden.parser

val lazyVal: String by lazy {
    "hello"
}

fun main() {
    println(lazyVal)
}
