/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.native.runtime

// KSP-1269: source-back the public RootSetStatistics nominal declaration and
// constructor. Its residual property surface remains synthetic until KSP-1270.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class RootSetStatistics(
    threadLocalReferences: Long,
    stackReferences: Long,
    globalReferences: Long,
    stableReferences: Long,
)
