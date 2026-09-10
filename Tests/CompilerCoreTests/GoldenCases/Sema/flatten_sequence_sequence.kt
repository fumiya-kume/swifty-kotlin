// RF-FIXTURE-010: Sequence<Sequence<T>>.flatten() resolves through the
// Sequence flatten overload and returns Sequence<T>.

fun flattenSequences(seqs: Sequence<Sequence<Int>>) {
    val flattened = seqs.flatten()
    val checked: Sequence<Int> = flattened
}
