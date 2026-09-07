/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 *
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/native/runtime/GCInfo.kt.
 */

package kotlin.native.runtime

// KSP-1271: The public constructor is source-backed here. The sweptCount and
// keptCount receiver properties remain synthetic/runtime-backed for KSP-1272,
// so the constructor parameters intentionally do not use `val`.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class SweepStatistics(
    sweptCount: Long,
    keptCount: Long,
)
