/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license.
 */

package kotlin.native.concurrent

import kotlin.internal.KsSymbolName

// KSP-1236: Keep the top-level class and constructor source-backed. The
// value property and member operations are owned by KSP-1237.
@Deprecated(
    "Use kotlin.concurrent.atomics.AtomicReference instead.",
    ReplaceWith("kotlin.concurrent.atomics.AtomicReference"),
    DeprecationLevel.ERROR
)
public class FreezableAtomicReference<T> {
    @KsSymbolName("kk_freezable_atomic_ref_create")
    public constructor(value: T)
}
