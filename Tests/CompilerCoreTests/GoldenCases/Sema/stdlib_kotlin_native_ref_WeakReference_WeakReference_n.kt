@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package golden.sema

import kotlin.native.ref.WeakReference
import kotlin.native.ref.value

fun clearWeakReference(reference: WeakReference<String>) {
    reference.clear()
}

fun getWeakReference(reference: WeakReference<String>): String? = reference.get()

fun valueWeakReference(reference: WeakReference<String>): Any? = reference.value
