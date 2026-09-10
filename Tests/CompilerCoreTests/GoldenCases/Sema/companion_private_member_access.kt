// RF-FIXTURE-021: companion <-> instance private member access in both
// directions — companion members may read instance private properties and
// call instance private functions, and instance members may read companion
// private members. Execution is covered by
// Scripts/diff_cases/companion_private_access.kt.
package golden.sema

class Database {
    private val connection: String = "jdbc:default"
    private fun ping(): Boolean = true

    companion object {
        fun getConnection(db: Database): String = db.connection
        fun check(db: Database): Boolean = db.ping()
    }
}

class OuterClass {
    private val outerSecret: String = "outer"

    companion object {
        private val companionSecret: String = "companion"

        fun getOuterSecret(outer: OuterClass): String = outer.outerSecret
        fun getCompanionSecret(): String = companionSecret
    }

    fun getCompanionSecretFromOuter(): String = Companion.companionSecret
}
