/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/NativeConcurrentAnnotations.kt>
 * and kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Annotations.kt>.
 */

package kotlin.native.concurrent

/**
 * This annotation has no effect, and its usages can be safely dropped.
 *
 * Since 1.7.20 usage of this annotation is deprecated. See
 * https://kotlinlang.org/docs/native-migration-guide.html for details.
 */
@Deprecated("This annotation is redundant and has no effect")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
@Target(AnnotationTarget.PROPERTY)
@Retention(AnnotationRetention.BINARY)
public annotation class SharedImmutable
