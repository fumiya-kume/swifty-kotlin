fun labeledBreak() {
    outer@ for (i in 0..2) {
        for (j in 0..2) {
            if (j == 1) break@outer
        }
    }
}

fun labeledContinue() {
    outer@ for (i in 0..2) {
        for (j in 0..2) {
            if (j == 1) continue@outer
        }
    }
}

fun labeledReturn() {
    listOf(1, 2, 3).forEach lit@{
        if (it == 2) return@lit
        println(it)
    }
}
