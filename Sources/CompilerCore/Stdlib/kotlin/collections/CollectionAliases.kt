/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/collections/TypeAliases.kt,
 * where these names are typealiases onto the java.util collection classes.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// The runtime represents every mutable collection with a single boxed
// implementation per kind, so the aliases target the mutable interfaces directly
// instead of the java.util classes the JVM stdlib points at.

public typealias ArrayList<E> = MutableList<E>

/**
 * Hash-based mutable set implementation.
 *
 * The Kotlin/Native `KonanSet` marker is an internal platform type that is not
 * modeled by KSwiftK. The public nominal hierarchy is preserved here while
 * the shared runtime set box supplies storage and collection operations.
 */
public class HashSet<E> : AbstractMutableSet<E>, MutableSet<E> {
    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)
}

/**
 * A mutable hash map backed by the runtime map representation.
 *
 * The constructor calls are rewritten to `__kk_hash_map_of` by
 * `CollectionLiteralLoweringPass`, which keeps the nominal class visible to
 * sema while sharing MutableMap storage and dispatch at runtime.
 */
public class HashMap<K, V> : MutableMap<K, V> {
    constructor()
    constructor(initialCapacity: Int)
    constructor(initialCapacity: Int, loadFactor: Float)
    constructor(original: Map<out K, V>)
}

public typealias LinkedHashMap<K, V> = MutableMap<K, V>

/**
 * Insertion-ordered mutable set.
 *
 * Construction is lowered to the runtime set entry points (`__kk_emptySet` for
 * the empty/capacity forms, `__kk_iterable_toMutableSet` for the copy form) by
 * `CollectionLiteralLoweringPass`. The `init` block additionally attaches a
 * backing `RuntimeSetBox` to source-allocated instances (including user
 * subclasses) so `MutableSet` member calls operate on real storage.
 */
@KsSymbolName("__kk_linked_hash_set_init")
private external fun <E> __kkLinkedHashSetInit(set: LinkedHashSet<E>)

@KsSymbolName("__kk_collection_size")
private external fun <E> __kkLinkedHashSetSize(set: LinkedHashSet<E>): Int

@KsSymbolName("__kk_collection_containsAll")
private external fun <E> __kkLinkedHashSetContainsAll(
    set: LinkedHashSet<E>,
    elements: Collection<@UnsafeVariance E>
): Boolean

@KsSymbolName("__kk_set_contains")
private external fun <E> __kkLinkedHashSetContains(
    set: LinkedHashSet<E>,
    element: E
): Boolean

@KsSymbolName("__kk_set_is_empty")
private external fun <E> __kkLinkedHashSetIsEmpty(set: LinkedHashSet<E>): Boolean

@KsSymbolName("kk_list_iterator")
private external fun <E> __kkLinkedHashSetIterator(set: LinkedHashSet<E>): Iterator<E>

public open class LinkedHashSet<E> : MutableSet<E> {
    init {
        __kkLinkedHashSetInit(this)
    }

    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)

    override val size: Int
        get() = __kkLinkedHashSetSize(this)

    override fun contains(element: E): Boolean = __kkLinkedHashSetContains(this, element)

    override fun isEmpty(): Boolean = __kkLinkedHashSetIsEmpty(this)

    override fun iterator(): Iterator<E> = __kkLinkedHashSetIterator(this)

    override fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean =
        __kkLinkedHashSetContainsAll(this, elements)
}
