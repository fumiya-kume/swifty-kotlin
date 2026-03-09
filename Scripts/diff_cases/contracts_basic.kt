import kotlin.contracts.contract

fun requireNotNullText(value: String?) {
    contract {
        returns() implies (value != null)
    }
    if (value == null) {
        throw Exception("missing")
    }
}

fun main() {
    val text: String? = "hello"
    requireNotNullText(text)
    println(text.length)
}
