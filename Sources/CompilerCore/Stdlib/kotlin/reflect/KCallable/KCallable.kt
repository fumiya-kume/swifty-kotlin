/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KCallable.kt.
 */

package kotlin.reflect

/**
 * Represents a callable entity, such as a function or a property.
 *
 * The runtime supplies the metadata for these two Native reflection properties;
 * the declarations remain source-backed so inheritance and member lookup use
 * the same contract as the Kotlin/Native stdlib.
 */
public interface KCallable<out R> {
    public val name: String
    public val returnType: KType
}
