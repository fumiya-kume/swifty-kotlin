package golden.sema

class CustomLazy<T>(private val stored: T) : Lazy<T> {
    override val value: T
        get() = stored
    override fun isInitialized(): Boolean = true
}

val delegated: Int by CustomLazy(42)

fun useLazyGetValue(): Int {
    return delegated
}
