fun main() {
    outer@ for (i in 0..2) {
        for (j in 0..2) {
            if (j == 1) break@outer
            println("$i $j")
        }
    }
    println("done")
}
