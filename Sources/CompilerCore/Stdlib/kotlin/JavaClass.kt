package kotlin

import java.lang.Class
import kotlin.internal.KsSymbolName

// The bundled parser represents generic extension properties as zero-argument
// functions while preserving property-style member lookup. This is the
// source-backed form of Kotlin's generic Any.javaClass property.
@KsSymbolName("__kk_any_javaClass")
private external fun <T : Any> __javaClass(value: T): Class<T>

public fun <T : Any> T.javaClass(): Class<T> = __javaClass(this)
