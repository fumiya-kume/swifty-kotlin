# RF-LOWER-INLINE-001: 抽出前の契約と検証先

後続の Inline 分割では、以下の既存テストと追加した小さな回帰テストを使う。
展開回数・循環・展開量の制限変更は RF-LOWER-INLINE-010 以降で扱う。

| 契約 | 検証先 |
|---|---|
| 同名でも解決済みの非 inline symbol を展開しない | `LoweringPassRegressionTests+InlineContracts.swift` の `testInlineLoweringPreservesResolvedNonInlineOverload`。Kotlin ソースから2 overloadを解決して比較する。 |
| nested inline、既存ラベルとの衝突回避、同一入力の決定性 | 同ファイルの `testNestedInlineLabelRelocationIsDeterministicAndCollisionFree`。2段の展開を2箇所で呼び、ラベル一意性・jump参照・独立した2回のKIR生成結果を確認する。 |
| call の symbol・型・throw channel・qualified super、virtual call の receiver・dispatch | 同ファイルの `testInlineExpansionPreservesVirtualAndQualifiedSuperMetadata`。通常関数とラムダ展開の2経路で確認する。 |
| 実ソースの `super<Left>` の型指定 | 同ファイルの `testSourceInlinePreservesQualifiedSuperTarget` と Backend fixture `inline/qualified_super`。KIRの型指定と出力の両方を確認する。 |
| imported inline とライブラリ内getterへの参照 | `LibraryMetadataImportIntegrationTests` の `testInlineLoweringExpandsImportedInlineFunctionFromKklib` / `testImportedInlineBodyCallsLibraryPropertyGetterByLinkName`。 |
| imported virtual call の受理 | `LibMetadataImportIntegrationTests.testInlineKIRArtifactWithVirtualCallIsImported`。 |
| 捕捉lambda、nested inline、try/catch/finally の実行 | Backend fixture `inline/captured_try_finally`。捕捉値を返す経路と例外経路でfinallyの実行を確認する。`inline/qualified_super` は捕捉したthisでの呼び出しも実行する。 |
| lambdaの展開・解決不能時のfallback・const alias | `LoweringPassRegressionTests+InlineLambdaInlining.swift`。解決できないclosureを無理に展開しない契約も含む。 |
| reified token と型代入 | `LoweringPassRegressionTests+InlineReifiedTypeToken.swift`、`CodegenBackendIntegrationTests+InlineFunctionExceptionPropagation.swift`、`Scripts/diff_cases/inline_reified.kt`。 |
| non-local return と通常returnの混在 | `LoweringPassRegressionTests+InlineNonLocalReturn.swift`、`Scripts/diff_cases/bug_209_inline_nonlocal_return.kt`。 |
| catch内の複数call、inline castから呼び出し元catchへの例外伝播 | `CodegenBackendIntegrationTests+InlineFunctionTryCatchValueReturn.swift` / `+InlineFunctionExceptionPropagation.swift`。 |
| stdlib artifact経由の展開 | `StdlibArtifactRegressionTests` の `testInlineOnlyCallInsideSplicedLambdaThroughSharedStdlibArtifact` など既存suite。 |

今回の修正は、`expandInlineCall` / `expandLambdaBody` が `.call` を複製するときに落としていた `qualifiedSuperType` を引き継ぐもの。
最小ソースは実行結果だけでは欠落を検出できないため、展開前後のKIRにもassertionを置いている。
Backend fixtureはstdout・終了状態の回帰を受け持ち、KIR検証の代わりにはしない。

Coreの追加テストは `Tests/CompilerCoreTests/Lowering/`、上記Backend integrationファイルは
`Tests/CompilerBackendTests/Codegen/`、importテストは各targetの `Sema/` にある。
実行fixtureは `Tests/CompilerBackendTests/Fixtures/` 以下で自動検出される。
全Swift・Golden・全Kotlin差分の結果はPRの検証欄に記録し、共通RFゲートが未完了ならTODOは `[~]` とする。
