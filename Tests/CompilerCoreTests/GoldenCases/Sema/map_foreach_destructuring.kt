// RF-FIXTURE-003: Map.forEach destructures each Map.Entry into key/value parameters.

fun forEachDestructured(values: Map<String, Int>) {
    values.forEach { (key, value) ->
        val checkedKey: String = key
        val checkedValue: Int = value
    }
}
