package golden.sema

fun chunkedLengths(value: CharSequence): List<Int> = value.chunked(2) { it.length }

fun chunkedStrings(value: String): List<String> = value.chunked(3) { it.toString() }

fun main() {
    chunkedLengths("abcd")
    chunkedStrings("abcde")
}
