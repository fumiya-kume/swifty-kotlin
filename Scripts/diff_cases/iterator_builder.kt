// STDLIB-331/564: iterator {} builder
fun main() {
    val iter = iterator {
        yield(10)
        yield(20)
        yield(30)
    }
    for (x in iter) {
        println(x)
    }

    var sum = 0
    val iter2 = iterator {
        yield(1)
        yield(2)
        yield(3)
    }
    for (x in iter2) {
        sum += x
    }
    println(sum)

    val computed = iterator {
        for (i in 1..5) {
            yield(i * i)
        }
    }
    for (v in computed) {
        println(v)
    }
}
