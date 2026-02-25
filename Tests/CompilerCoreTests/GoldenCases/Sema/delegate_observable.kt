package golden.sema

import kotlin.properties.Delegates

var name: String by Delegates.observable("initial") { prop, old, new ->
    println("changed from $old to $new")
}

fun main() {
    println(name)
    name = "updated"
    println(name)
}
