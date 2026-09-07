/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KClass.kt.
 */

package kotlin.reflect

/**
 * The KClass identity contract is supplied by the platform runtime.
 *
 * KClass handles are interned by the represented type token in this runtime,
 * so the existing Any equality and hashCode lowering provides the matching
 * value semantics for these declarations.
 */
public interface KClass<T : Any> : KClassifier {
    public override fun equals(other: Any?): Boolean
    public override fun hashCode(): Int
}
