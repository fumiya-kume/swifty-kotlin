// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

import kotlin.native.runtime.GC

fun main() {
    val processor: GC.MainThreadFinalizerProcessor? = null
    println(processor == null)
}
