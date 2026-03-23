fun computeValue(flag: Boolean): Int {
    return if (flag) 42 else 0
}

fun main() {
    when (val result = computeValue(true)) {
        42 -> println("got 42: $result")
        0 -> println("got zero")
        else -> println("unexpected: $result")
    }

    when (val x = computeValue(false)) {
        0 -> println("zero: $x")
        else -> println("other: $x")
    }
}
