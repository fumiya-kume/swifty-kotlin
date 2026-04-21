#if canImport(Testing)
@testable import GoldenHarnessSupport
import Testing

@Suite("GoldenHarness.SemaComparisonNormalization")
struct GoldenHarnessSemaComparisonNormalizationTests {
    @Test
    func stripsUnusedSyntheticOverloadsBeforeComparing() {
        let expected = """
        symbol s800 kind=function fq=kotlin.text.removePrefix vis=public flags=synthetic sig=recv=String params=[String] ret=String suspend=0 defaults=[0] vararg=[0]
        symbol s802 kind=function fq=kotlin.text.removeSuffix vis=public flags=synthetic sig=recv=String params=[String] ret=String suspend=0 defaults=[0] vararg=[0]
        symbol s804 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=String params=[String] ret=String suspend=0 defaults=[0] vararg=[0]
        symbol s806 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=String params=[String,String] ret=String suspend=0 defaults=[0,0] vararg=[0,0]
        expr e3 memberCall recv=e1 callee=removePrefix args=[_:e2] type=String call=s800 map=[0->0] targs=[]
        expr e23 memberCall recv=e21 callee=removeSuffix args=[_:e22] type=String call=s802 map=[0->0] targs=[]
        expr e43 memberCall recv=e41 callee=removeSurrounding args=[_:e42] type=String call=s804 map=[0->0] targs=[]
        expr e64 memberCall recv=e61 callee=removeSurrounding args=[_:e62,_:e63] type=String call=s806 map=[0->0,1->1] targs=[]
        """

        let actual = """
        symbol s801 kind=function fq=kotlin.text.removePrefix vis=public flags=synthetic sig=recv=Class#708 params=[Class#708] ret=String suspend=0 defaults=[0] vararg=[0]
        symbol s803 kind=function fq=kotlin.text.removeSuffix vis=public flags=synthetic sig=recv=Class#708 params=[Class#708] ret=String suspend=0 defaults=[0] vararg=[0]
        symbol s805 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=Class#708 params=[Class#708] ret=String suspend=0 defaults=[0] vararg=[0]
        symbol s807 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=Class#708 params=[Class#708,Class#708] ret=String suspend=0 defaults=[0,0] vararg=[0,0]
        symbol s810 kind=function fq=kotlin.text.removePrefix vis=public flags=synthetic sig=recv=String params=[String] ret=String suspend=0 defaults=[0] vararg=[0]
        symbol s811 kind=function fq=kotlin.text.removeSuffix vis=public flags=synthetic sig=recv=String params=[String] ret=String suspend=0 defaults=[0] vararg=[0]
        symbol s812 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=String params=[String] ret=String suspend=0 defaults=[0] vararg=[0]
        symbol s813 kind=function fq=kotlin.text.removeSurrounding vis=public flags=synthetic sig=recv=String params=[String,String] ret=String suspend=0 defaults=[0,0] vararg=[0,0]
        expr e3 memberCall recv=e1 callee=removePrefix args=[_:e2] type=String call=s810 map=[0->0] targs=[]
        expr e23 memberCall recv=e21 callee=removeSuffix args=[_:e22] type=String call=s811 map=[0->0] targs=[]
        expr e43 memberCall recv=e41 callee=removeSurrounding args=[_:e42] type=String call=s812 map=[0->0] targs=[]
        expr e64 memberCall recv=e61 callee=removeSurrounding args=[_:e62,_:e63] type=String call=s813 map=[0->0,1->1] targs=[]
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func keepsTransitiveSymbolDependenciesUsedBySignatures() {
        let output = """
        symbol s10 kind=class fq=sample.Box vis=public flags=synthetic
        symbol s20 kind=function fq=sample.useBox vis=public flags=synthetic sig=recv=_ params=[Class#10] ret=Unit suspend=0 defaults=[0] vararg=[0]
        symbol s30 kind=function fq=sample.unused vis=public flags=synthetic sig=recv=_ params=[String] ret=Unit suspend=0 defaults=[0] vararg=[0]
        expr e0 call callee=e1 args=[] type=Unit call=s20 map=[] targs=[]
        """

        let normalized = GoldenHarness.normalizedForComparison(suiteName: "Sema", output: output)

        #expect(normalized.contains("symbol s0 kind=class fq=sample.Box"))
        #expect(normalized.contains("symbol s1 kind=function fq=sample.useBox"))
        #expect(normalized.contains("params=[Class#0]"))
        #expect(normalized.contains("call=s1"))
        #expect(!normalized.contains("sample.unused"))
    }

    @Test
    func normalizesGeneratedLocalScopeIDsEmbeddedInSymbolFQNs() {
        let expected = """
        symbol s40 kind=function fq=sample.wrap vis=public flags=_ sig=recv=_ params=[Int] ret=Int suspend=0 defaults=[0] vararg=[0]
        symbol s41 kind=valueParameter fq=sample.wrap.$17.value vis=private flags=_
        symbol s42 kind=function fq=sample.echo vis=public flags=_ sig=recv=_ params=[Int] ret=Int suspend=0 defaults=[0] vararg=[0]
        symbol s43 kind=valueParameter fq=sample.echo.$22.value vis=private flags=_
        expr e0 name(value) type=Int ref=s41
        expr e1 name(value) type=Int ref=s43
        """

        let actual = """
        symbol s140 kind=function fq=sample.wrap vis=public flags=_ sig=recv=_ params=[Int] ret=Int suspend=0 defaults=[0] vararg=[0]
        symbol s141 kind=valueParameter fq=sample.wrap.$3706.value vis=private flags=_
        symbol s142 kind=function fq=sample.echo vis=public flags=_ sig=recv=_ params=[Int] ret=Int suspend=0 defaults=[0] vararg=[0]
        symbol s143 kind=valueParameter fq=sample.echo.$3711.value vis=private flags=_
        expr e0 name(value) type=Int ref=s141
        expr e1 name(value) type=Int ref=s143
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }

    @Test
    func normalizesGeneratedNegativeSymbolReferences() {
        let expected = """
        symbol s0 kind=class fq=sample.Widget vis=public flags=_
        expr e0 name(value) type=Int ref=s-3
        expr e1 name(other) type=Int ref=s-9
        expr e2 binary(add) lhs=e0 rhs=e1 type=Int
        """

        let actual = """
        symbol s40 kind=class fq=sample.Widget vis=public flags=_
        expr e0 name(value) type=Int ref=s-43707
        expr e1 name(other) type=Int ref=s-43713
        expr e2 binary(add) lhs=e0 rhs=e1 type=Int
        """

        #expect(
            GoldenHarness.normalizedForComparison(suiteName: "Sema", output: actual)
                == GoldenHarness.normalizedForComparison(suiteName: "Sema", output: expected)
        )
    }
}
#endif
