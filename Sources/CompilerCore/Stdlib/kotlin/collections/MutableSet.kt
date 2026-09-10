/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Set.kt
 * (builtins declaration of kotlin.collections.MutableSet).
 */

package kotlin.collections

// KSP-947: the nominal `MutableSet<E>` declaration is source-backed here. The
// compiler-side shell remains the fallback for contexts without the bundled
// stdlib, while its runtime-linked mutation members remain as bridges.
//
// `MutableCollection` will provide `MutableIterable` transitively when its
// separate source migration lands. Keep the direct edge here until then so
// bundled MutableSet values preserve the existing iterable type surface.
// The abstract mutation surface is inherited from MutableCollection; the
// compiler-side members retain their runtime links for the shared set box.

/**
 * A generic unordered collection of elements that supports adding and removing
 * elements.
 */
public interface MutableSet<E> : Set<E>, MutableCollection<E>, MutableIterable<E>
