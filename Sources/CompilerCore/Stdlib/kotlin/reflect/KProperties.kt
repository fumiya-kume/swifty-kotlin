/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KProperty.kt.
 */

package kotlin.reflect

// KSP-682: KProperty0/1/2 and KMutableProperty0/1/2 public interface shells,
// migrated from synthetic Sema stubs (HeaderHelpers+SyntheticPropertyDelegateStubs)
// to bundled Kotlin source. The `() -> V` / `(T) -> V` / `(D, E) -> V` function-type
// supertypes (KSP-CAP-009) let property references be used as functions; Sema
// inheritance binding lowers them to the corresponding kotlin.Function{N} nominal
// interfaces. KProperty / KMutableProperty remain synthetic nominal surfaces.

public interface KProperty0<out V> : KProperty<V>, () -> V {
    public fun get(): V

    public fun getDelegate(): Any?

    override operator fun invoke(): V
}

public interface KMutableProperty0<V> : KProperty0<V>, KMutableProperty<V> {
    public fun set(value: V)
}

public interface KProperty1<T, out V> : KProperty<V>, (T) -> V {
    public fun get(receiver: T): V

    public fun getDelegate(receiver: T): Any?

    override operator fun invoke(p1: T): V
}

public interface KMutableProperty1<T, V> : KProperty1<T, V>, KMutableProperty<V> {
    public fun set(receiver: T, value: V)
}

public interface KProperty2<D, E, out V> : KProperty<V>, (D, E) -> V {
    public fun get(receiver1: D, receiver2: E): V

    public fun getDelegate(receiver1: D, receiver2: E): Any?

    override operator fun invoke(p1: D, p2: E): V
}

public interface KMutableProperty2<D, E, V> : KProperty2<D, E, V>, KMutableProperty<V> {
    public fun set(receiver1: D, receiver2: E, value: V)
}
