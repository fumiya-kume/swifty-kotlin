/*
 * KSP-1256: Kotlin/Native WeakReference receiver API.
 *
 * The runtime owns the weak-reference handle and its referent state. Keep the
 * public API in Kotlin source while using private bridges for those operations.
 */

@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.native.ref

import kotlin.experimental.ExperimentalNativeApi
import kotlin.internal.KsSymbolName

@KsSymbolName("kk_weak_ref_get")
private external fun __weakReferenceGet(reference: WeakReference<*>): Any?

@KsSymbolName("kk_weak_ref_clear")
private external fun __weakReferenceClear(reference: WeakReference<*>): Int

/** Backing store compatibility for the Kotlin/Native WeakReference contract. */
@PublishedApi
internal var WeakReference<*>.pointer: WeakReferenceImpl?
    get() = null
    set(newValue) {}

/** Clears the weak reference to its referent. */
@ExperimentalNativeApi
public fun <T : Any> WeakReference<T>.clear() {
    __weakReferenceClear(this)
}

/** Returns the referent while it is still alive, or null after collection. */
@ExperimentalNativeApi
@Suppress("UNCHECKED_CAST")
public fun <T : Any> WeakReference<T>.get(): T? =
    __weakReferenceGet(this) as T?

// Generic extension property type parameters are not supported by this parser;
// the star-projected receiver preserves the nullable read contract.
/** Returns the referent while it is still alive, or null after collection. */
@ExperimentalNativeApi
public val WeakReference<*>.value: Any?
    get() = this.get()
