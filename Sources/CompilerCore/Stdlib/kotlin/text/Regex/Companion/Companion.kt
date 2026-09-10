/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib
 * (libraries/stdlib/native-wasm/src/kotlin/text/Regex.kt and
 * libraries/stdlib/native-wasm/src/kotlin/text/regex/Pattern.kt).
 */

package kotlin.text

/**
 * Returns a pattern that matches [literal] literally.
 *
 * This is the Kotlin/Native equivalent of `Pattern.quote`: the `\\E` sequence
 * must be closed and reopened when it occurs inside the quoted region.
 */
public fun Regex.Companion.escape(literal: String): String {
    val result = StringBuilder(literal.length + 4)
    result.append("\\Q")
    var index = 0
    while (index < literal.length) {
        if (literal[index] == '\\' && index + 1 < literal.length && literal[index + 1] == 'E') {
            result.append("\\E\\\\E\\Q")
            index += 2
        } else {
            result.append(literal[index])
            index += 1
        }
    }
    result.append("\\E")
    return result.toString()
}

/**
 * Returns a replacement string that treats [literal] as literal text.
 *
 * Only backslash and dollar have replacement-language meaning, so every
 * occurrence of either character is escaped with one preceding backslash.
 */
public fun Regex.Companion.escapeReplacement(literal: String): String {
    var index = 0
    var hasSpecialCharacter = false
    while (index < literal.length) {
        if (literal[index] == '\\' || literal[index] == '$') {
            hasSpecialCharacter = true
            break
        }
        index += 1
    }
    if (!hasSpecialCharacter) return literal

    val result = StringBuilder(literal.length * 2)
    index = 0
    while (index < literal.length) {
        val character = literal[index]
        if (character == '\\' || character == '$') {
            result.append('\\')
        }
        result.append(character)
        index += 1
    }
    return result.toString()
}
