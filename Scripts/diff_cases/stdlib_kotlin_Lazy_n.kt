class CustomLazy<T>(private val stored: T) : Lazy<T> {
    override val value: T
        get() = stored
    override fun isInitialized(): Boolean = true
}

val custom: Int by CustomLazy(42)
val standard: Int by lazyOf(99)

fun main() {
    println(custom)
    println(standard)
}
