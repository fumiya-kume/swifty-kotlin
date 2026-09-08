// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.ref APIs are Kotlin/Native-only and are not available in JVM kotlinc.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.ref.WeakReference
import kotlin.native.ref.value

fun clearWeakReference(reference: WeakReference<String>) {
    reference.clear()
}

fun getWeakReference(reference: WeakReference<String>): String? = reference.get()

fun valueWeakReference(reference: WeakReference<String>): Any? = reference.value
