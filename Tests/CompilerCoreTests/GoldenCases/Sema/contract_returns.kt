import kotlin.contracts.*

fun requireNonNull(value: Any?): Any {
    contract {
        returns() implies (value != null)
    }
    if (value == null) throw IllegalArgumentException()
    return value
}

fun bareReturns(x: Int) {
    contract {
        returns()
    }
    if (x < 0) throw IllegalArgumentException()
}

fun returnsTrue(condition: Boolean): Boolean {
    contract {
        returns(true)
    }
    if (!condition) throw IllegalArgumentException()
    return true
}

fun returnsFalse(condition: Boolean): Boolean {
    contract {
        returns(false)
    }
    if (condition) throw IllegalArgumentException()
    return false
}

// Multi-effect contract block: exercises blockExpr(statements, trailingExpr, ...)
// aggregation with multiple effect expressions in a single contract lambda.
fun multiEffect(value: Any?, condition: Boolean): Boolean {
    contract {
        returns() implies (value != null)
        returns(true)
    }
    if (value == null) throw IllegalArgumentException()
    if (!condition) throw IllegalArgumentException()
    return true
}

fun main() {
    val x: String? = "hello"
    requireNonNull(x)
    println(x.length)

    bareReturns(42)

    val flag = returnsTrue(true)
    println(flag)

    val flag2 = returnsFalse(false)
    println(flag2)

    val y: String? = "world"
    val result = multiEffect(y, true)
    println(result)
}
