package golden.sema

import kotlin.math.PI

fun readPI(): Double = PI

fun readPICopy(): Double {
    val copied = PI
    return copied
}

fun readPIRawBits(): Long = PI.toRawBits()
