import kotlin.contracts.*

fun ensurePositive(value: Int) {
    contract {
        returns()
    }
    if (value <= 0) throw IllegalArgumentException("must be positive")
}

fun assertNotNull(value: Any?) {
    contract {
        returns() implies (value != null)
    }
    if (value == null) throw IllegalArgumentException("null")
}

fun main() {
    ensurePositive(42)
    println("ensurePositive passed")

    val y: String? = "world"
    assertNotNull(y)
    println(y.length)
}
