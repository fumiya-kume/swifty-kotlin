fun main() {
    repeat(4) { index ->
        println(index)
    }

    repeat(3) {
        println(it)
    }

    repeat(3) {
        println("i=$it")
    }

    repeat(0) {
        println("never")
    }

    repeat(1) {
        println("once")
    }

    var sum = 0
    repeat(5) {
        sum += it
    }
    println(sum)
}
