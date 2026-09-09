@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.SafeContinuation

fun main() {
    val continuation: Continuation<Int> =
        Continuation<Int>(EmptyCoroutineContext) { _: Result<Int> -> }
    val safe: SafeContinuation<Int> = SafeContinuation(continuation)
    println(safe is SafeContinuation<*>)
}
