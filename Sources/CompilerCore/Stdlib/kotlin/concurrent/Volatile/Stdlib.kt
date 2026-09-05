/*
 * Copyright 2010-2022 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/Volatile.kt>
 * and the Kotlin/Native actual declaration.
 */

package kotlin.concurrent

/**
 * Marks the backing field of the annotated `var` property as volatile.
 *
 * Only backing-field operations are atomic; a getter or setter that performs
 * multiple operations is not guaranteed to be atomic as a whole.
 */
@Target(AnnotationTarget.FIELD)
@Retention(AnnotationRetention.SOURCE)
@MustBeDocumented
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public annotation class Volatile()
