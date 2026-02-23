package golden.sema

fun readOnly(list: MutableList<out Number>): Number = list[0]

fun writeOnly(list: MutableList<in Int>) {
    list.add(42)
}

fun starProjection(list: List<*>): Any? = list[0]
