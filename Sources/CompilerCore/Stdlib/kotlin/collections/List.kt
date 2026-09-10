/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Lists.kt.
 */

package kotlin.collections

// KSP-697: keep List's covariant nominal shell in Kotlin source. Indexed and
// iterator members remain compiler residuals; LateListIndexedMembers is retained
// until KSP-699 as required by the migration boundary.
public interface List<out E> : Collection<E>
