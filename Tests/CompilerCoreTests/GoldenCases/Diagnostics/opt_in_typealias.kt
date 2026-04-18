package golden.diagnostics

@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
annotation class ExperimentalTypealiasApi

@ExperimentalTypealiasApi
class ExperimentalBase

typealias AliasForExperimental = ExperimentalBase

fun useAlias(): AliasForExperimental = AliasForExperimental()
