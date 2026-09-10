package kotlin.coroutines

// KSP-1147: expose the published internal SafeContinuation constructor from
// bundled Kotlin source. Its continuation behavior remains in the receiver
// members handled by the follow-up SafeContinuation migration.
@PublishedApi
@SinceKotlin("1.3")
internal class SafeContinuation<in T> : Continuation<T> {
    @PublishedApi
    internal constructor(delegate: Continuation<T>)
}
