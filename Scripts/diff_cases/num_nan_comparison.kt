// SKIP-DIFF: SPEC-NUM-0003 — Double/Float relational operators (<, <=, >, >=)
// must use IEEE-754 comparison, where any comparison involving NaN is false.
// kswiftk desugars them through Comparable.compareTo (a total order in which NaN
// is the largest value) or, after bypassing that, through integer bit comparison,
// both of which diverge from IEEE. Remove SKIP-DIFF once primitive float
// relational operators are lowered to kk_op_dlt/dle/dgt/dge with proper rank.
//
// Expected (kotlinc): every NaN comparison below prints false.
fun main() {
    val nan = Double.NaN
    println(nan < 1.0)
    println(1.0 < nan)
    println(nan > 1.0)
    println(1.0 > nan)
    println(nan <= 1.0)
    println(nan >= 1.0)
    // == / != are already correct (false / true):
    println(nan == nan)
    println(nan != nan)
}
