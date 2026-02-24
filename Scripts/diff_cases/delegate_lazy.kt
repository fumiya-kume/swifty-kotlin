val message: String by lazy {
    println("initializing")
    "hello"
}

fun main() {
    println(message)
    println(message)
}
