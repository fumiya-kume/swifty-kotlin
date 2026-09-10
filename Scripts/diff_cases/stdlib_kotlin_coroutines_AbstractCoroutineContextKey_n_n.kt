@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.coroutines.AbstractCoroutineContextKey
import kotlin.coroutines.CoroutineContext

class BaseKey : CoroutineContext.Key<BaseElement>

interface BaseElement : CoroutineContext.Element

interface DerivedElement : BaseElement

class DerivedKey : AbstractCoroutineContextKey<BaseElement, DerivedElement>(
    BaseKey(),
    { element -> element as? DerivedElement }
)

fun main() {
    val key: CoroutineContext.Key<DerivedElement> = DerivedKey()
    println(key is CoroutineContext.Key<*>)
}
