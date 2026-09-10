import kotlin.properties.Delegates

var observed: Int by Delegates.observable(1) { _, old, new -> println("observed:$old->$new") }
var accepted: Int by Delegates.vetoable(0) { _, _, new -> new >= 0 }
var late: Int by Delegates.notNull()

fun main() {
    observed = 2
    accepted = -1
    println(accepted)
    late = 3
    println(late)
}
