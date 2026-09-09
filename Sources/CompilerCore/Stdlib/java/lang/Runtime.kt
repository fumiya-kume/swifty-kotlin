package java.lang

import kotlin.internal.KsSymbolName

public object Runtime {
    @KsSymbolName("__kk_runtime_getRuntime")
    private external fun __getRuntime(): Runtime

    @KsSymbolName("__kk_runtime_totalMemory")
    private external fun __totalMemory(): Long

    @KsSymbolName("__kk_runtime_freeMemory")
    private external fun __freeMemory(): Long

    @KsSymbolName("__kk_runtime_maxMemory")
    private external fun __maxMemory(): Long

    public fun getRuntime(): Runtime = __getRuntime()

    public fun totalMemory(): Long = __totalMemory()

    public fun freeMemory(): Long = __freeMemory()

    public fun maxMemory(): Long = __maxMemory()
}
