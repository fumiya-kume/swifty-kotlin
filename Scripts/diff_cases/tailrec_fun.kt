tailrec fun countDown(n: Int): Int {
    if (n == 0) return 0
    return countDown(n - 1)
}

fun main() {
    println(countDown(100000))
}
