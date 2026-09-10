package kotlin.coroutines

// KSP-1145: EmptyCoroutineContext's public behavior is pure Kotlin stdlib
// semantics. The compiler/runtime context bridges remain responsible for
// context values that contain runtime-owned elements.
public object EmptyCoroutineContext : CoroutineContext {
    public override fun <E : Element> get(key: Key<E>): E? = null

    public override fun <R> fold(
        initial: R,
        operation: (R, Element) -> R
    ): R = initial

    public override operator fun plus(context: CoroutineContext): CoroutineContext = context

    public override fun minusKey(key: Key<*>): CoroutineContext = this

    public override fun hashCode(): Int = 0

    public override fun toString(): String = "EmptyCoroutineContext"
}
