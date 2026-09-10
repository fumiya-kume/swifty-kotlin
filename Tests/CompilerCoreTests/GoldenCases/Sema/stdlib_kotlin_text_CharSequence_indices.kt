package golden.sema

fun charSequenceIndices(value: CharSequence): IntRange = value.indices

fun stringIndices(): IntRange = "abc".indices

fun emptyStringIndices(): IntRange = "".indices
