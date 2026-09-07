/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/time/measureTime.kt.
 */

package kotlin.time

/**
 * A value returned by [measureTimedValue] function.
 *
 * @property value a result value of the code block being measured.
 * @property duration a duration of the code block execution.
 */
public data class TimedValue<T>(public val value: T, public val duration: Duration)
