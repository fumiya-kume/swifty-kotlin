/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/CoroutineContextImpl.kt.
 */

@file:Suppress("KSWIFTK-SEMA-ABSTRACT")

package kotlin.coroutines

import kotlin.coroutines.CoroutineContext.Element
import kotlin.coroutines.CoroutineContext.Key

/**
 * Base class for [CoroutineContext.Element] implementations.
 *
 * The constructor parameter is intentionally kept separate from the `key`
 * member migration, which is tracked by KSP-1137.
 */
@SinceKotlin("1.3")
public abstract class AbstractCoroutineContextElement(key: Key<*>) : Element
