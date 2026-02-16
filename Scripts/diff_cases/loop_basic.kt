fun main() {
    var first = true
    var count = 0
    while (first) {
        count = count + 1
        first = false
    }
    do {
        count = count + 1
        first = false
    } while (first)
    println(count)
}
