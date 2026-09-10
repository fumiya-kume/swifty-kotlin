package golden.sema

import kotlin.ExperimentalStdlibApi
import kotlin.coroutines.AbstractCoroutineContextKey
import kotlin.coroutines.CoroutineContext

class BaseKey : CoroutineContext.Key<BaseElement>

interface BaseElement : CoroutineContext.Element

interface DerivedElement : BaseElement

@OptIn(ExperimentalStdlibApi::class)
class DerivedKey : AbstractCoroutineContextKey<BaseElement, DerivedElement>(
    BaseKey(),
    { element -> element as? DerivedElement }
)
