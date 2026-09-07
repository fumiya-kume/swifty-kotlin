/*
 * KSP-1261: Source-backed nominal declaration for Kotlin/Native GC.
 *
 * The remaining GC members are intentionally retained by the synthetic
 * runtime surface until their owning migration tasks are completed.
 */

package kotlin.native.runtime

@NativeRuntimeApi
@SinceKotlin("1.9")
public object GC {
    public object MainThreadFinalizerProcessor {}
}
