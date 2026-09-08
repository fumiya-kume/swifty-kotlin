private fun choose(flag: Boolean): Int {
    var value = 0
    if (flag) value = 1 else value = 2
    return value
}

private fun nested(outer: Boolean, inner: Boolean): Int {
    var value = 0
    if (outer) value = if (inner) 10 else 20 else value = 30
    return value
}

private fun dangling(outer: Boolean, inner: Boolean): Int {
    var value = 0
    if (outer) if (inner) value = 1 else value = 2 else value = 3
    return value
}

fun main() {
    println(choose(true))
    println(choose(false))
    println(nested(true, true))
    println(nested(true, false))
    println(nested(false, true))
    println(dangling(true, true))
    println(dangling(true, false))
    println(dangling(false, true))
    var total = 0
    for (index in 0..3) {
        if (index % 2 == 0) total += 1 else total += 10
    }
    println(total)
}
