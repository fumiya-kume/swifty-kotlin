// STDLIB-COMP-041: Comparable interface complete implementation
// Tests: compareTo(), comparison operator synthesis, Comparable type constraints, null-safe comparison

class Temperature(val degrees: Int) : Comparable<Temperature> {
    override fun compareTo(other: Temperature): Int = this.degrees - other.degrees
}

fun <T : Comparable<T>> max(a: T, b: T): T = if (a > b) a else b

fun nullSafeCompare(a: Temperature?, b: Temperature): Int = a?.compareTo(b) ?: -1

fun compareInts(a: Int, b: Int): Boolean = a < b

fun compareTemperatures(a: Temperature, b: Temperature): Boolean = a < b

fun compareGe(a: Temperature, b: Temperature): Boolean = a >= b
