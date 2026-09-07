package golden.sema

import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext

fun continuationInterceptorKey(): CoroutineContext.Key<ContinuationInterceptor> =
    ContinuationInterceptor.Key
