@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.concurrent.SharedImmutable

@SharedImmutable
val sharedValue: Int = 42

fun readSharedValue(): Int = sharedValue
