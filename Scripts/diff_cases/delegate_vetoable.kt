import kotlin.properties.Delegates

var age: Int by Delegates.vetoable(0) { prop, old, new ->
    new >= 0
}

fun main() {
    println(age)
}
