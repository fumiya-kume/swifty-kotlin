package golden.sema

fun charSequenceNone(cs: CharSequence): Boolean = cs.none()

fun stringNone(): Boolean = "x".none()

fun emptyNone(): Boolean = "".none()

fun charSequenceNonePredicate(cs: CharSequence): Boolean = cs.none { it == 'x' }
