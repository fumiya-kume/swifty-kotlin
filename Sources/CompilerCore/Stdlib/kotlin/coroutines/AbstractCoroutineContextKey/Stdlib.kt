@file:Suppress("KSWIFTK-SEMA-ABSTRACT")

package kotlin.coroutines

import kotlin.coroutines.CoroutineContext.Element
import kotlin.coroutines.CoroutineContext.Key

@SinceKotlin("1.3")
@ExperimentalStdlibApi
public abstract class AbstractCoroutineContextKey<B : Element, E : B>(
    baseKey: Key<B>,
    private val safeCast: (element: Element) -> E?
) : Key<E> {
    private val topmostKey: Key<*> = findTopmostKey(baseKey)

    private fun findTopmostKey(key: Key<*>): Key<*> =
        if (key is AbstractCoroutineContextKey<*, *>) key.topmostKey else key

    internal fun tryCast(element: Element): E? = safeCast(element)

    internal fun isSubKey(key: Key<*>): Boolean =
        key === this || topmostKey === key
}
