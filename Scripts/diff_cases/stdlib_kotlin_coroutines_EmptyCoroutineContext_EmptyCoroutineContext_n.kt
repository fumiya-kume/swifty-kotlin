import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

fun emptyGet(key: CoroutineContext.Key<CoroutineContext.Element>): CoroutineContext.Element? =
    EmptyCoroutineContext.get(key)

fun emptyMinusKey(key: CoroutineContext.Key<CoroutineContext.Element>): CoroutineContext =
    EmptyCoroutineContext.minusKey(key)

fun main() {
    println(EmptyCoroutineContext.fold(7) { acc, _ -> acc + 1 })
    println(EmptyCoroutineContext + EmptyCoroutineContext === EmptyCoroutineContext)
    println(EmptyCoroutineContext.hashCode())
    println(EmptyCoroutineContext.toString())
}
