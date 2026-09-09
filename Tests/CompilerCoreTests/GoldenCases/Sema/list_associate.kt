// RF-FIXTURE-009: the associate family builds a Map from element lambdas —
// associate takes a Pair, associateBy extracts the key, associateWith extracts
// the value.

fun associatePairs(values: List<String>) {
    val assoc = values.associate { it to it.length }
    val checked: Map<String, Int> = assoc
}

fun associateKeys(values: List<String>) {
    val byKey = values.associateBy { it.length }
    val checked: Map<Int, String> = byKey
}

fun associateValues(values: List<String>) {
    val withVal = values.associateWith { it.length }
    val checked: Map<String, Int> = withVal
}
