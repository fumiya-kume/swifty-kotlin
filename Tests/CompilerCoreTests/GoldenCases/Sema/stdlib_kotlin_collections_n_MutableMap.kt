// KSP-946: source-backed MutableMap nominal declaration with residual mutation APIs.
abstract class CustomMutableMap : MutableMap<String, Int>

fun widen(values: MutableMap<String, Int>): Map<String, Number> = values

fun mutate(values: MutableMap<String, Int?>): MutableMap<String, Int?> {
    values["present"] = 1
    values.put("present", null)
    values.remove("missing")
    values.putAll(mapOf("from" to 2))
    return values
}
