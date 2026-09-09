/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 */

package kotlin.ranges

// KSP-1300: Keep the IntProgression nominal and its Companion source-backed.
// Runtime-backed members remain synthetic until their dedicated migrations.
public open class IntProgression internal constructor(
    start: Int,
    endInclusive: Int,
    step: Int,
) : Iterable<Int> {
    public companion object {}
}
