/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Iterables.kt.
 */

package kotlin.collections

// KSP-697: keep the nominal interface source-backed. The iterator member and
// compiler/runtime bridges remain residual registrations until their respective
// collection migrations can remove them without changing dispatch metadata.
// Keep the parameter name aligned with the residual shell so source collection
// loading can reuse its type-parameter symbol without orphaning iterator calls.
public interface Iterable<out E>
