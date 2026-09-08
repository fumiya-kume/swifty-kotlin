/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/properties/ObservableProperty.kt.
 */

@file:Suppress("KSWIFTK-SEMA-ABSTRACT")

package kotlin.properties

import kotlin.reflect.KProperty

/**
 * Base class for `by`-delegated properties that veto/observe value changes,
 * as returned by [Delegates.observable] and [Delegates.vetoable].
 */
public abstract class ObservableProperty<V>(initialValue: V) : ReadWriteProperty<Any?, V> {
    private var value: V = initialValue

    protected open fun beforeChange(property: KProperty<*>, oldValue: V, newValue: V): Boolean = true

    protected open fun afterChange(property: KProperty<*>, oldValue: V, newValue: V): Unit {}

    public override operator fun getValue(thisRef: Any?, property: KProperty<*>): V = value

    public override operator fun setValue(thisRef: Any?, property: KProperty<*>, value: V) {
        val oldValue = this.value
        if (!beforeChange(property, oldValue, value)) {
            return
        }
        this.value = value
        afterChange(property, oldValue, value)
    }

    override fun toString(): String = "ObservableProperty(value=$value)"
}
