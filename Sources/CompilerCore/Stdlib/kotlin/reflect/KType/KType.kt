/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KType.kt.
 */

package kotlin.reflect

// KSP-1332: source-backed KType surface. Runtime-created KType boxes provide
// the abstract properties through their native interface itable.
public interface KType {
    public val classifier: KClassifier?

    public val arguments: List<KTypeProjection>

    public val isMarkedNullable: Boolean
}
