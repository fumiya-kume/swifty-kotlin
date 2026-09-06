package golden.sema

import kotlin.native.runtime.GC

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun mainThreadFinalizerProcessorType(): GC.MainThreadFinalizerProcessor? = null
