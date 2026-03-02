fun classifyInt(x: Int): String = when (x) {
    1, 2, 3 -> "few"
    else -> "many"
}

fun duplicateHitCount(x: Int): Int {
    var hits = 0
    when (x) {
        1, 1, 2 -> {
            hits = hits + 1
        }
        else -> {
            hits = hits + 10
        }
    }
    return hits
}

fun main() {
    println(classifyInt(1))
    println(classifyInt(5))
    println(duplicateHitCount(1))
    println(duplicateHitCount(3))
}
