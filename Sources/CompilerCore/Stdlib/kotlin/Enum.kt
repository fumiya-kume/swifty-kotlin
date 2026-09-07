/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/Enum.kt.
 */

@file:Suppress("KSWIFTK-SEMA-ABSTRACT")

package kotlin

import kotlin.internal.KsSymbolName

// KSP-732: nominal `kotlin.Enum<T : Enum<T>>` declaration migrated out of the
// synthetic self-registration. The compiler still lowers enum representation
// details (name/ordinal and enum-specific string conversion), while the public
// member contracts are declared here for normal source binding and metadata.
public abstract class Enum<T : Enum<T>> protected constructor(
    name: String,
    ordinal: Int
) : Comparable<T> {
    // KSP-837: source-backed declarations for the six public Enum members.
    @KsSymbolName("__kk_comparable_compareTo")
    public final override external operator fun compareTo(other: T): Int

    @KsSymbolName("kk_any_member_equals")
    public final override external fun equals(other: Any?): Boolean

    @KsSymbolName("kk_any_member_hashCode")
    public final override external fun hashCode(): Int

    public final val name: String

    public final val ordinal: Int

    @KsSymbolName("kk_any_member_to_string")
    public override external fun toString(): String

    public companion object {}
}

// KSP-776: These declarations are the source-backed public surface for the
// reified enum intrinsics. Their fallback bodies are never executed for a
// concrete enum call: CallTypeChecker records the intrinsic binding and
// CallLowerer expands it using the enum class's generated members.
public inline fun <reified T : Enum<T>> enumValues(): Array<T> =
    throw IllegalStateException("enumValues is expanded by the compiler")

public inline fun <reified T : Enum<T>> enumValueOf(name: String): T =
    throw IllegalStateException("enumValueOf is expanded by the compiler")
