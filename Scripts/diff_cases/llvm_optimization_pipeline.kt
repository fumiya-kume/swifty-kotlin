fun optimizedSum(limit: Int): Int {
    var sum = 0
    var index = 0
    while (index < limit) {
        if (index % 2 == 0) {
            sum += index
        } else {
            sum -= index
        }
        index++
    }
    return sum
}

fun optimizedOverflow(value: Int): Int {
    var result = value
    result += 1
    return result
}

fun main() {
    println(optimizedSum(0))
    println(optimizedSum(10))
    println(optimizedSum(11))
    println(optimizedOverflow(Int.MAX_VALUE))
    try {
        require(optimizedSum(2) >= 0) { "negative" }
    } catch (error: IllegalArgumentException) {
        println(error.message)
    }
}
