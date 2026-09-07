/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/ContinuationInterceptor.kt.
 */

package kotlin.coroutines

// KSP-1140: keep the ContinuationInterceptor.Key companion object in bundled
// Kotlin source. The residual coroutine registry retains the interceptor's
// runtime-backed members until their dedicated migrations are complete.
public interface ContinuationInterceptor : CoroutineContext.Element {
    public companion object Key : CoroutineContext.Key<ContinuationInterceptor>
}
