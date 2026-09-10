@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.concurrent.MutableData

fun defaultCapacity(): MutableData = MutableData()

fun explicitCapacity(): MutableData = MutableData(4)
