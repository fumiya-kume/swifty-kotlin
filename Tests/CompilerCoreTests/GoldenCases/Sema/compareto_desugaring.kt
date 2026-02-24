class Temperature(val degrees: Int) : Comparable<Temperature> {
    override fun compareTo(other: Temperature): Int = this.degrees - other.degrees
}

fun stringCompareLt(a: String, b: String): Boolean = a < b

fun stringCompareGe(a: String, b: String): Boolean = a >= b

fun stringCompareLe(a: String, b: String): Boolean = a <= b

fun stringCompareGt(a: String, b: String): Boolean = a > b

fun customCompareLt(a: Temperature, b: Temperature): Boolean = a < b

fun customCompareGe(a: Temperature, b: Temperature): Boolean = a >= b

fun primitiveCompare(a: Int, b: Int): Boolean = a < b
