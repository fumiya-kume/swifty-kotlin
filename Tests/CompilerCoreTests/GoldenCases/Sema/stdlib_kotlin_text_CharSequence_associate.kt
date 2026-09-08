package golden.sema

fun charSequenceAssociate(source: CharSequence): Map<Char, Int> =
    source.associate { ch -> ch to if (ch == 'a') 1 else 2 }

fun charSequenceAssociateBy(source: CharSequence): Map<Int, Char> =
    source.associateBy { ch -> if (ch == 'a') 0 else 1 }

fun charSequenceAssociateByTransform(source: CharSequence): Map<Int, String> =
    source.associateBy(
        { ch -> if (ch == 'a') 0 else 1 },
        { ch -> if (ch == 'a') "A" else "other" }
    )

fun charSequenceAssociateByTo(source: CharSequence): MutableMap<Int, Char> {
    val destination = mutableMapOf<Int, Char>()
    return source.associateByTo(destination) { ch -> if (ch == 'a') 0 else 1 }
}

fun charSequenceAssociateByToTransform(source: CharSequence): MutableMap<Int, String> {
    val destination = mutableMapOf<Int, String>()
    return source.associateByTo(
        destination,
        { ch -> if (ch == 'a') 0 else 1 },
        { ch -> if (ch == 'a') "A" else "other" }
    )
}

fun charSequenceAssociateTo(source: CharSequence): MutableMap<Char, Int> {
    val destination = mutableMapOf<Char, Int>()
    return source.associateTo(destination) { ch -> ch to 1 }
}

fun charSequenceAssociateWith(source: CharSequence): Map<Char, Int> =
    source.associateWith { ch -> if (ch == 'a') 1 else 2 }

fun charSequenceAssociateWithTo(source: CharSequence): MutableMap<Char, Int> {
    val destination = mutableMapOf<Char, Int>()
    return source.associateWithTo(destination) { ch -> if (ch == 'a') 1 else 2 }
}
