/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Collections.kt.
 */

package kotlin.collections

// KSP-697: the mutable collection shell is source-backed. Mutating members and
// their runtime bridges remain residual registrations for the later bridge work.
public interface MutableCollection<E> : Collection<E>, MutableIterable<E>
