package golden.sema

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

fun emptyGet(key: CoroutineContext.Key<CoroutineContext.Element>): CoroutineContext.Element? =
    EmptyCoroutineContext.get(key)

fun emptyFold(): Int = EmptyCoroutineContext.fold(7) { acc, _ -> acc + 1 }

fun emptyPlus() = EmptyCoroutineContext + EmptyCoroutineContext

fun emptyMinusKey(key: CoroutineContext.Key<CoroutineContext.Element>): CoroutineContext =
    EmptyCoroutineContext.minusKey(key)

fun emptyHashCode(): Int = EmptyCoroutineContext.hashCode()

fun emptyToString(): String = EmptyCoroutineContext.toString()

fun main() {
    println(emptyFold())
    println(emptyPlus() === EmptyCoroutineContext)
    println(emptyHashCode())
    println(emptyToString())
}
