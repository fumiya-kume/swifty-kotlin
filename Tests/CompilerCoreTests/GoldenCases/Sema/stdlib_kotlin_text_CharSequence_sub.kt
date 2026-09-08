package golden.sema

fun charSequenceSubSequenceRange(source: CharSequence): CharSequence =
    source.subSequence(1..3)

fun charSequenceSubSequenceEmpty(source: CharSequence): CharSequence =
    source.subSequence(2 until 2)
