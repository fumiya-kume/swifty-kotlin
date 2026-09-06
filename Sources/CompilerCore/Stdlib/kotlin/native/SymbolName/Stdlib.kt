package kotlin.native

/**
 * Internal opt-in marker used by Kotlin/Native's dangerous SymbolName API.
 */
@kotlin.RequiresOptIn(
    message = "@SymbolName is dangerous deprecated and internal annotation. See https://youtrack.jetbrains.com/issue/KT-46649",
    level = kotlin.RequiresOptIn.Level.ERROR
)
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
internal annotation class SymbolNameIsInternal

/**
 * Assigns a native symbol name to a top-level function.
 */
@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@SymbolNameIsInternal
public annotation class SymbolName(val name: String)
