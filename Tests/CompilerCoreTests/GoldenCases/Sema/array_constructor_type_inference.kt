// RF-FIXTURE-002: Array(size) { ... } element type — inferred from the initializer,
// taken from an explicit type argument, or taken from the expected type.

fun arrayConstructorWithInit() {
    val doubled = Array(5) { it * 2 }
    val checked: Array<Int> = doubled
}

fun arrayConstructorExplicitTypeArgWinsOverExpectedType() {
    val array: Array<out Any> = Array<Int>(3) { it }
}

fun arrayConstructorExpectedType() {
    val array: Array<String> = Array(3) { "x" }
}
