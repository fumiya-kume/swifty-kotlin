/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin.native.concurrent

import kotlin.internal.KsSymbolName

/**
 * A [Long] value that is always updated atomically.
 *
 * This is the legacy Kotlin/Native atomic API. Use
 * `kotlin.concurrent.atomics.AtomicLong` instead.
 */
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicLong instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicLong"),
    DeprecationLevel.ERROR
)
public class AtomicLong {
    @KsSymbolName("kk_atomic_long_create")
    public constructor(value: Long = 0L)
}
