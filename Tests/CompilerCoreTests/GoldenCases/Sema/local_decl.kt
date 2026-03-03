fun typedLocal() {
    val x: Int = 10
    println(x)
}

fun inferredLocal() {
    val y = 20
    println(y)
}

fun mutableTyped() {
    var z: Int = 30
    z = 40
    println(z)
}

fun deferredValInit() {
    val a: Int
    a = 5
    println(a)
}

fun useBeforeInit() {
    var b: Int
    println(b)
}
