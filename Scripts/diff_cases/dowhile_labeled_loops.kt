fun main() {
    var i = 0
    do { i++; print("$i ") } while (i < 5)
    println()
    outer@ for (i in 1..3) {
        for (j in 1..3) {
            if (j == 2) continue@outer
            print("$i$j ")
        }
    }
    println()
    outer@ for (i in 1..5) {
        for (j in 1..5) {
            if (i * j > 6) break@outer
            print("${i*j} ")
        }
    }
    println()
}
