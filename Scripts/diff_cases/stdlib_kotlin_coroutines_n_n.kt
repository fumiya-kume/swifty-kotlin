import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.AbstractCoroutineContextKey
import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.RestrictsSuspension
import kotlin.coroutines.coroutineContext
import kotlin.coroutines.suspendCoroutine

@OptIn(kotlin.ExperimentalStdlibApi::class)
fun abstractElement(value: AbstractCoroutineContextElement): CoroutineContext.Element = value

@OptIn(kotlin.ExperimentalStdlibApi::class)
fun abstractKey(value: AbstractCoroutineContextKey<CoroutineContext.Element, CoroutineContext.Element>): CoroutineContext.Key<CoroutineContext.Element> = value

fun continuationContext(value: Continuation<Int>): CoroutineContext = value.context

fun interceptorContext(value: ContinuationInterceptor): CoroutineContext = value

fun emptyContext(): CoroutineContext = EmptyCoroutineContext

suspend fun currentContext(): CoroutineContext = coroutineContext

fun continuationFactory(): Continuation<Int> = Continuation<Int>(EmptyCoroutineContext) { _ -> }

@RestrictsSuspension
class RestrictedScope

suspend fun resumedValue(): Int = suspendCoroutine { continuation ->
    continuation.resumeWith(Result.success(42))
}

fun main() {
    println("ok")
}
