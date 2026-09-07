package kotlin.system

import kotlin.internal.KsSymbolName

// Compatibility object retained for the JVM-shaped system API used by existing
// diff cases. The public members are Kotlin declarations; only the OS-backed
// operations remain external bridges.
public object System {
    @KsSymbolName("__kk_system_currentTimeMillis")
    private external fun __currentTimeMillis(): Long

    @KsSymbolName("__kk_system_nanoTime")
    private external fun __nanoTime(): Long

    @KsSymbolName("__kk_system_process_start_nanos")
    private external fun __processStartNanos(): Long

    public fun currentTimeMillis(): Long = __currentTimeMillis()

    public fun nanoTime(): Long = __nanoTime()

    public fun processStartNanos(): Long = __processStartNanos()
}
