/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 *
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/native/runtime/GCInfo.kt.
 */

package kotlin.native.runtime

// KSP-1272: Keep both native GC sweep counters source-backed and immutable.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class SweepStatistics(
    public val sweptCount: Long,
    public val keptCount: Long,
)
