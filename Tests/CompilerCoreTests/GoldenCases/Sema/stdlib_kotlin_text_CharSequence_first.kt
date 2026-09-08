package golden.sema

fun charSequenceFirst(cs: CharSequence): Char = cs.first()

fun charSequenceFirstPredicate(cs: CharSequence): Char = cs.first { it == 'x' }

fun charSequenceFirstOrNull(cs: CharSequence): Char? = cs.firstOrNull()

fun charSequenceFirstOrNullPredicate(cs: CharSequence): Char? = cs.firstOrNull { it == 'x' }

fun stringFirst(): Char = "x".first()

fun emptyFirstOrNull(): Char? = "".firstOrNull()
