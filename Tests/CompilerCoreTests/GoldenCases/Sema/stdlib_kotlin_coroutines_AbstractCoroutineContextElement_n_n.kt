package golden.sema

import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

abstract class Probe(key: CoroutineContext.Key<*>) : AbstractCoroutineContextElement(key)
