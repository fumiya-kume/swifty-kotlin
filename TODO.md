# Kotlin Compiler Remaining Tasks

最終更新: 2026-02-22

## P0 (Core Correctness)

- [x] P0-1: Overload 可能なシンボルテーブルへ変更（同一 FQName の関数共存）
  - [x] `SymbolTable` を `fqName -> [SymbolID]` 対応に変更
  - [x] duplicate 判定を宣言種別ごとに見直し（function/constructor は許可）
  - [x] 型解決側で `lookup` 結果の kind フィルタを適用

- [x] P0-2: expected type 伝播を最小実装
  - [x] `inferExpr` に `expectedType` を通す
  - [x] `resolveCall` 呼び出しへ `expectedType` を渡す
  - [x] 既存型チェックとの整合を確認

- [x] P0-3: OverloadResolver の parameter mapping 拡張
  - [x] named args 対応
  - [x] default args 対応
  - [x] vararg 展開対応（trailing vararg）

## P1 (Language Semantics)

- [x] P1-1: Scope 解決順位の本実装（local/import/default import）
- [x] P1-2: 拡張関数の receiver 解決（現在は unqualified call で除外）
- [x] P1-3: Data-flow / smart cast / sealed・enum・nullable exhaustiveness 拡張
  - [x] enum / nullable when exhaustiveness の拡張
  - [x] sealed exhaustiveness
  - [x] smart cast (stable variable) の本体
    - [x] when の null 分岐ベース最小 smart cast
    - [x] when branch 条件（sealed subtype / Boolean）での smart cast
- [x] P1-4: Sema Pass B 拡張（getter/setter/init/initializer）
  - [x] property initializer の型チェック/推論
  - [x] property getter/setter の本体型チェック
  - [x] class/object init block の本体解析
- [x] P1-5: 呼び出し引数仕様の拡張（named+positional 混在, spread, non-trailing vararg）
  - [x] OverloadResolver の mixed named+positional 対応
  - [x] OverloadResolver の spread 制約対応（non-vararg への spread 拒否）
  - [x] OverloadResolver の non-trailing vararg 対応
  - [x] Frontend/AST で named/spread call args を保持して Resolver に渡す
- [x] P1-6: Kotlin 2.3 stable 機能差分の穴埋め（spec.md J0/J5/J6）
  - [x] nested typealias（class/object 内）を Parser/AST/Sema で扱う
  - [x] `return`/`if`/`try` を expression-body で正しく扱う式パーサを実装
  - [x] `script` ルート（`SyntaxKind.script`）の parse パスを実装

## P2 (Backend / Runtime)

- [x] P2-1: Lowering 各パスの本処理化（現在の marker/rename ベースを置換）
  - [x] generic rename pass を廃止し、専用 pass（For/When/Property/Lambda/Inline/Coroutine）へ置換
  - [x] ForLowering: `__for_expr__` を `iterator` + `kk_for_lowered` 呼び出しへ展開
  - [x] PropertyLowering: `get/set` を accessor kind 引数つき `kk_property_access` に lowering
  - [x] InlineLowering: inline 関数呼び出しを body 展開し、結果参照を alias で再配線
  - [x] DataEnumSealedSynthesis: enum/sealed/data 向け synthetic helper（count/copy）を生成
  - [x] CoroutineLowering: suspend 関数の lowered clone 生成 + hidden continuation 引数付与 + call-site 書き換え
  - [x] ABILowering: 既知 non-throwing runtime call を除外した `outThrown` 設定
  - [x] Coroutine state machine / strict ABI channel（CPS 本体変換・throw 経路）を段階実装
    - [x] external call（symbol 未解決）でも `outThrown` チャネルを使う C backend 生成に拡張
    - [x] lowered suspend 本体で suspend call の `outThrown` 伝播をテスト固定
    - [x] suspend overload（同名）でも `name+arity` で lowered target へ call-site rewrite
- [x] P2-2: ABI 実装（例外チャネル・vtable/itable・レイアウト）
  - [x] synthetic C backend で `outThrown` 引数を内部 call に伝播し、throw 値を呼び出し元へ転送
  - [x] nominal layout（header/field/vtable/itable count, superClass）を Sema で合成し metadata へ出力
  - [x] vtable slot を override 同一 slot で割当（name+arity ベース dispatch key）
  - [x] class layout を継承込みで合成（super fields を instance size へ反映）
  - [x] metadata `superFq` / `fields` / `vtable` / `itable` を import 側で反映
- [x] P2-3: `.kklib` 消費側（-I から manifest/metadata 読込）
- [x] P2-4: LLVM C API backend への移行
  - [x] Codegen backend を抽象化し `-Xir backend=...` で選択可能に変更
  - [x] `backend=llvm-c-api` 選択時の `LLVMCAPIBackend` スキャフォールド（警告つきフォールバック）を追加
  - [x] `backend-strict=true` で未実装時に即 error へ切替（CI 用ガード）
  - [x] LLVM C API dynamic bindings loader（`dlopen` / `dlsym`）を追加
  - [x] LLVM C API bindings（modulemap / SwiftPM link 設定）を追加
  - [x] LLVM C API で最小 IR 生成（const / return / call / branch）
  - [x] LLVM C API で Object 出力パス（target machine 初期化 + emit）
  - [x] 既存 synthetic C backend と emit 出力互換テストを追加
- [x] P2-5: Runtime GC 実装（mark-sweep + root map）
  - [x] stop-the-world mark-sweep collector を実装
  - [x] root set（globals / stack frame map / coroutine）走査を実装
  - [x] `kk_register_frame_map` 系 API と compiler 側 map 出力を実装（現状は 0-root map 生成）
- [x] P2-6: coroutine CPS/state machine lowering 実装
  - [x] lowered suspend 関数へ state enter/exit helper 挿入（state machine 骨格）
  - [x] suspension point ごとの label 設定 + `COROUTINE_SUSPENDED` 早期 return ガード挿入
  - [x] suspension point ベースの state block 分割を追加
  - [x] linear state label dispatch（resume label による再開地点ジャンプ）を追加
  - [x] CFG ベースの suspension point 分割と label dispatch 生成
- [x] P2-7: kotlinc 差分テストハーネスの整備
  - [x] `Scripts/diff_kotlinc.sh` を追加（kotlinc 実行結果との stdout/exit 比較）
- [x] P2-8: LLVM C API backend の runtime/ABI 追従（spec.md J15）
  - [x] `kk_string_concat` / 例外チャネル / coroutine helper 呼び出しの native lowering を実装
  - [x] `backend=llvm-c-api` で executable までの E2E テストを追加
  - [x] fallback を撤去し、non-strict でも LLVM C API native backend のみを使用

## P3 (Spec Compliance Backlog)

- [x] P3-1: 決定性・エラー規約の固定（spec.md J0）
  - [x] 出力決定性テスト（同一入力/同一オプションで byte 同一）を追加（`.kir` / `.ll` / `.o`）
  - [x] compiler/runtime の panic 経路を診断コード方針に沿って整理
- [x] P3-2: 型システムの仕様追従（spec.md J8/J9）
  - [x] class/interface 継承関係を `TypeSystem.isSubtype` に反映
  - [x] declaration-site variance と use-site variance 合成規則を強化
  - [x] generic constraints の失敗診断精度を改善
- [x] P3-3: KIR の型付き IR 化強化（spec.md J11/J12）
  - [x] `if/for/try` など制御構造の KIR 表現を marker 依存から段階的に脱却
  - [x] KIR value/type 情報の保持を強化し lowering の前提を明確化
- [x] P3-4: Name mangling/ABI 厳密化（spec.md J13）
  - [x] signature の型符号化ルール（nullable / function / suspend）を反映
  - [x] decl kind（getter/setter/constructor）の区別を mangling に反映
- [x] P3-5: Coroutine フル CPS 仕様追従（spec.md J17）
  - [x] continuation object（spill slots + label）生成を実装
    - [x] continuation allocation helper（`kk_coroutine_continuation_new`）導入
    - [x] label state の enter/set/exit を continuation object ベースへ移行
    - [x] spill slots / completion を continuation object に保持
  - [x] suspension 跨ぎ live 解析に基づく spill/reload を実装
  - [x] suspend 例外伝播を含む golden/E2E テストを追加
- [x] P3-6: テストハーネス拡張（spec.md J18/J19）
  - [x] Lexer/Parser/Sema の golden test セットを追加
  - [x] `Scripts/check_coverage.sh` を CI gate に組み込み
  - [x] `diff_kotlinc.sh` の回帰ケースを継続追加

## P4 (Spec Diff Expansion)

- [x] P4: Kotlin spec 差分テストの拡充（継続）
  - [x] `Scripts/diff_kotlinc.sh` の対象ケースを言語機能ごとに増やす
    - [x] `hello.kt` / `control_when.kt` / `boolean_when.kt` / `if_expr.kt` / `overload.kt` / `string_concat.kt` / `type_error.kt`
  - [x] golden 更新ワークフロー（差分可視化 + approve 手順）をドキュメント化
    - [x] `Scripts/README.md` を追加
  - [x] diff ケースを CI で定期実行する job を追加

## P5 (Spec Gap Backlog)

- [x] P5-1: call lowering で default 引数補完を実装（spec.md J9/J11/J12）
  - [x] `CallBinding.parameterMapping` を使って omitted parameter を KIR call 引数に補完
  - [x] named/reordered call の最終引数列を callee parameter 順へ正規化
  - [x] `named_default.kt` 回帰ケース（`sum(a = 3, c = 4)`）を pass させる
  - [x] 再現: `bash Scripts/diff_kotlinc.sh /tmp/named_default.kt`

- [x] P5-2: block 内 local declaration/assignment を AST/Sema/KIR で実装（spec.md J5/J6/J7/J11）
  - [x] `val/var` 文ノードを AST に導入し、block body に保持
  - [x] local symbol 生成・スコープ解決・再代入検査（`val` 不変）を実装
  - [x] assignment 文（`x = ...`）を AST/Sema/KIR に接続
  - [x] KIR の local load（local 参照）を導入

- [x] P5-3: receiver 参照（`this`/extension receiver）の束縛と lowering を完成（spec.md J7/J9/J12）
  - [x] extension/member body で `this` を implicit receiver として束縛
  - [x] unresolved identifier が external symbol call に落ちる経路を遮断
  - [x] `extension.kt` 回帰ケース（`x.inc2()`）を pass させる
  - [x] 再現: `bash Scripts/diff_kotlinc.sh /tmp/extension.kt`

- [x] P5-4: runtime value 表現の整合（null と primitive 0 の分離）を修正（spec.md J16）
  - [x] synthetic runtime `kk_println_any` の判定を tagged/value-aware に変更
  - [x] `println(0)` / `println(null)` の差分テストを追加
  - [x] 再現: `bash Scripts/diff_kotlinc.sh /tmp/zero_print.kt`

- [x] P5-5: diff/golden ケースを P5 領域で拡張（spec.md J18）
  - [x] default args / local var / receiver / zero-null 表示の回帰ケースを `Scripts/diff_cases` へ追加
  - [x] 失敗時 artifact を CI summary に出す補助スクリプトを追加

- [x] P5-6: `.kklib` import 側の inline body 読み込みと跨モジュール inline 展開を実装（spec.md J14.3/J12）
  - [x] `manifest.json` の `inlineKIRDir` を解決し、`inline-kir/*.kirbin` を読み込むローダーを追加
  - [x] import した inline 関数 symbol と inline body を関連付ける中間表現を `SemaModule`/KIR へ保持
  - [x] `InlineLowering` が同一モジュール定義だけでなく import 済み inline body も展開対象にする
  - [x] 2 モジュール回帰ケース（library の `inline fun` を consumer で呼ぶ）を `Scripts/diff_kotlinc.sh` に追加

- [x] P5-7: runtime object header を `kk_alloc` で実体化し、layout 情報と整合させる（spec.md J16.1/J16.3）
  - [x] `KKObjHeader { typeInfo, flags, size }` を実メモリレイアウトとして確保し、`kk_alloc` が header+payload を初期化する
  - [x] GC 走査を header 経由の `KTypeInfo` 参照に統一し、外部 `heapObjects` bookkeeping 依存を段階的に縮小する
  - [x] nominal layout（Sema 合成値）と runtime header/payload offset の整合テストを追加する

- [x] P5-8: coroutines の non-suspend 起動経路（KxMini）を compiler/runtime 間で接続する（spec.md J17.3/J15.3）
  - [x] runtime に `runBlocking` / `launch` / `async` / `delay` の C ABI エントリを追加し、backend から呼べる形に固定する
  - [x] suspend 関数参照から continuation 起動 API へ橋渡しする lowering（または stdlib shim）を実装する
  - [x] `delay` 実装を `DispatchSourceTimer` ベースへ揃え、resume タイミングの振る舞いを仕様化する
  - [x] `delay` を含む最小 coroutine E2E（起動・suspend・resume）の diff/golden ケースを追加する

- [x] P5-9: 配列アクセスの bounds check を IR/runtime 境界で実装する（spec.md J15.3）
  - [x] AST/KIR に array load/store（index 付き）表現を導入し、codegen で runtime 呼び出しへ lowering する
  - [x] runtime に配列境界チェック API（in-range 判定と throw 経路）を追加する
  - [x] out-of-bounds 例外が `outThrown` チャネルで伝播する E2E ケースを追加する

- [x] P5-10: parser の missing-token 挿入と同期点スキップを仕様どおり実装する（spec.md J5.4）
  - [x] 期待トークン欠如時に virtual/missing token を CST に保持できる仕組みを追加する
  - [x] トップレベル/ブロック内の同期点（`;`/改行/`}`/`catch`/`finally`/`else`/EOF）までの回復を明示実装する
  - [x] 回復後も parse 継続し、診断と CST dump が安定する golden を追加する

- [x] P5-11: loop 構文を AST→KIR→Lowering まで通しで実装する（spec.md J5/J6/J11/J12）
  - [x] `for`/`while`/`do-while` を Parser/AST で専用ノード化し、`SyntaxKind.loopStmt` を実生成する
  - [x] BuildKIR で loop の制御フロー（label/jump）を生成する
  - [x] `break`/`continue`（必要なら label 付き）を loop 制御フローへ接続する
  - [x] `ForLoweringPass` の no-op 実装を置き換え、`iterator/hasNext/next` 展開を実装する
  - [x] loop 回帰ケースを `diff_kotlinc.sh` に追加する

- [x] P5-12: inline `reified` の hidden type token 伝播を実装する（spec.md J12.2）
  - [x] `reified` type parameter を Sema signature に保持し call binding で解決する
  - [x] call lowering 時に runtime type token 引数を追加する
  - [x] inline 展開先で token 利用を可能にする KIR/Lowering 経路を追加する

- [x] P5-13: `.kklib` の separate compilation link を完成させる（spec.md J14.1/J14.2）
  - [x] `manifest.json` の `objects` 配列を読み、consumer link 時に対象 object を自動追加する
  - [x] `-I` で見つかった `.kklib` の object 探索と重複排除を実装する
  - [x] 2 モジュールリンク（consumer が library object を自動リンク）E2E を追加する

- [x] P5-14: `metadata.bin` の公開 API 情報を仕様最小要件まで拡張する（spec.md J14.3）
  - [x] function/property の型シグネチャを import 側で再構築可能な形で保存/復元する
  - [x] nominal の field offset / vtable slot / itable slot 情報を metadata に保存/復元する
  - [x] metadata 不整合時の診断コード（`KSWIFTK-LIB-*`）を追加する

- [x] P5-15: LLVM C API backend の例外・runtime ABI 追従を synthetic backend 同等にする（spec.md J13.3/J15.3）
  - [x] `select` / `kk_when_select` の lowering を条件評価つき実装へ修正し、現行の擬似 no-op 実装を置換する
  - [x] `usesThrownChannel` call 後の `outThrown` 判定と例外経路分岐を実装する
  - [x] frame map 登録/解除（`kk_register_frame_map` / `kk_push_frame` / `kk_pop_frame`）を挿入する
  - [x] `kk_println_any`/runtime call の扱いを no-op ではなく実 call に揃える

- [x] P5-16: compiler 生成の GC root map を 0-root 固定から実 root 解析へ拡張する（spec.md J16.2）
  - [x] 関数ごとの root slot 解析（locals/temporaries/coroutine 参照）を実装する
  - [x] backend で `KKFrameMapDescriptor` の `rootCount/rootOffsets` を実データ生成する
  - [x] global/object root の `kk_register_global_root` / `kk_unregister_global_root` 呼び出しを codegen/link 境界で接続する
  - [x] continuation lifecycle の `kk_register_coroutine_root` / `kk_unregister_coroutine_root` 呼び出しを lowering/runtime 境界で接続する
  - [x] GC 回収回帰テスト（参照保持中は生存、解放後は回収）を追加する

- [x] P5-17: suspend lowering の `F$Cont` continuation 型生成を仕様どおり実装する（spec.md J17.2）
  - [x] 各 suspend 関数ごとに continuation nominal type（label/completion/spill fields）を KIR/Sema に生成する
  - [x] lowered 本体が `F$Cont` レイアウトを前提に spill/reload する経路へ移行する
  - [x] `F$Cont` 生成と state machine 復帰地点の整合を確認する回帰テストを追加する

- [x] P5-18: 公開 API 名を spec の固定シグネチャへ揃える（spec.md J1/J8）
  - [x] `CompilerOptions.debugInfo` 名称と CLI 連携を仕様名へ統一する（現行 `emitsDebugInfo` との差分解消）
  - [x] `TypeSystem.lub` / `TypeSystem.glb` の公開 API を追加し既存 `leastUpperBound` / `greatestLowerBound` と整合させる
  - [x] 既存テスト・呼び出し側を移行し、互換エイリアス（deprecated）方針を明文化する

- [x] P5-19: 演算子解決を sema 選択結果ベースへ移行する（spec.md J9/J12.2）
  - [x] `binary` 推論で extension operator 候補解決を導入し、固定型ルールのみを使う経路を縮小する
  - [x] BuildKIR の `binary` lowering で chosen callee symbol を直接 call する経路を追加し、`kk_op_*` 変換は fallback のみに限定する
  - [x] 演算子オーバーロード（extension）diff ケースを追加する（`Scripts/diff_cases/operator_extension.kt`）
  - [x] member operator 候補解決と member call lowering の統合（class member pipeline 完了後）

- [x] P5-20: lambda / object literal / callable reference を front-to-back で実装する（spec.md J5/J6/J12）
  - [x] Parser/AST に `lambdaLiteral` / `objectLiteral` / `callableRef` の実ノードを導入する
  - [x] Sema で lambda/callable reference の capture 解析と型推論（function type / receiver）を実装する
  - [x] KIR で lambda/callable reference を実体 callable symbol + capture 引数へ lower し、呼び出しを marker 非依存化する
  - [x] object literal を匿名オブジェクト実体として lowering/backend へ接続する（生成 constructor/factory 経路 + allocation call）
  - [x] lambda/object/callable ref の回帰ケースを追加する

- [x] P5-21: `try/catch/finally` の例外チャネル制御フローを KIR/Lowering で実装する（spec.md J11.3/J13.3）
  - [x] BuildKIR の `tryExpr` lowering で catch/finally を捨てる現実装を置換し、分岐ブロックを生成する
  - [x] catch parameter（`catch (e: E)` の `e`）をスコープへ束縛し、catch body で参照可能にする
  - [x] 複数 catch 節を宣言順で評価し、例外型（`E`）に一致した節だけへ遷移する型マッチを実装する
  - [x] `outThrown` を監視して catch へ遷移し、catch 未処理時は呼び出し元へ再送する経路を実装する
  - [x] `finally` の常時実行順序（normal/exception 両経路）を保証する

- [ ] P5-22: 式パーサ/型推論を Kotlin 基本演算子セットへ拡張する（spec.md J5/J6/J9）
  - [x] unary 演算（`!`/unary `+`/unary `-`）と優先順位を実装する
  - [ ] 比較/論理/型演算子（`!=`/`<`/`<=`/`>`/`>=`/`&&`/`||`/`is`/`as`）と優先順位を実装する
    - [x] 比較/論理（`!=`/`<`/`<=`/`>`/`>=`/`&&`/`||`）を Parser/Sema/KIR/backend に接続
    - [ ] 型演算子（`is`/`as`）を Parser/Sema/KIR/backend に接続
  - [ ] Elvis（`?:`）/ null 断定（`!!`）/ safe call（`?.`）を AST と型推論に反映する
  - [ ] assignment（`=` と複合代入）を式/文として扱い、`val` 再代入診断と接続する

- [x] P5-23: executable エントリラッパーで `outThrown` を監視し top-level 例外を処理する（spec.md J13.3）
  - [x] LinkPhase の C wrapper が `main(outThrown)` 呼び出し後に throw チャネルを確認するよう修正する
  - [x] throw 発生時の終了コード/診断出力ポリシーを定義し runtime `kk_panic` と整合させる（panic 形式メッセージ + exit code 1）
  - [x] top-level throw の E2E テストを追加する

- [ ] P5-24: CST 粒度を spec 最低ラインへ引き上げる（spec.md J5.1）
  - [ ] `importList` ノードを parser で実生成し、top-level 構造を明確化する
  - [ ] `ifExpr`/`whenExpr`/`tryExpr`/`callExpr` など主要構文の SyntaxKind を CST で直接生成する
  - [ ] AST builder の「statement 再パース」依存を段階的に削減する

- [ ] P5-25: 動的ディスパッチ（vtable/itable）を call lowering/codegen に接続する（spec.md J13.2）
  - [ ] member call で virtual dispatch が必要なケースを判定し、slot ベース呼び出し IR を導入する
  - [ ] class override は同一 vtable slot、interface call は itable 経由で解決する
  - [ ] override/interface dispatch の E2E 回帰ケースを追加する

- [ ] P5-26: ABILowering の boxing/unboxing を実装する（spec.md J12.1/J13.3）
  - [ ] nullable primitive と `Any?` 境界で boxing/unboxing 規則を実装する
  - [ ] runtime 値表現（tagged/boxed）と `kk_println_any`/call ABI の整合を取る
  - [ ] boxing 境界を含む型推論 + 実行回帰ケースを追加する

- [ ] P5-27: runtime C ABI シグネチャを spec 固定形へ厳密化する（spec.md J16.1）
  - [ ] `kk_alloc` など公開シンボルの引数/戻り型を仕様シグネチャへ揃える（nullable 許容の方針も含む）
  - [ ] compiler/backend 側の extern 宣言を runtime 実体と自動突合する仕組み（共有 header 生成など）を導入する
  - [ ] ABI ずれを検出するビルド時テストを追加する

- [ ] P5-28: `interface` 宣言を `class` へ潰さずに front-to-back で区別する（spec.md J6/J7/J13.2）
  - [ ] AST/Sema モデルで interface 種別を保持し、`FrontendPhases` の `interfaceDecl -> classDecl` 変換を解消する
  - [ ] header 収集・継承グラフ・layout 合成で interface を正しく扱う（superClass と interface 集合を分離）
  - [ ] interface 実装/override/dispatch の差分ケースを追加する

- [ ] P5-29: class/object body の member 宣言（fun/property）を AST/Sema/KIR に接続する（spec.md J6/J7/J12）
  - [ ] `ClassDecl`/`ObjectDecl` に member 宣言リストを保持し、body 内 `fun`/`val`/`var` を AST へ昇格する
  - [ ] nested `class`/`object` 宣言を class/object body から保持し、owner FQName 配下へシンボル化する
  - [ ] `ClassMemberScope` を使った member symbol 収集と参照解決（`this` レシーバ込み）を実装する
  - [ ] backing field 実体化と delegated property（`by`）の lowering を実装する
  - [ ] member 関数/プロパティを KIR へ落とし込み、metadata/layout と整合させる

- [ ] P5-30: constructor 宣言と呼び出し解決を実装する（spec.md J5/J7/J13）
  - [ ] primary/secondary constructor の構文を Parser/AST で扱い、`constructor` symbol を定義する
  - [ ] class 呼び出しを constructor overload 解決へ接続し、`super`/`this` 委譲規則を検査する
  - [ ] init block と constructor 実行順序を lowering/codegen で保証する

- [ ] P5-31: 型参照を named-only から拡張し、型引数・関数型・明示型引数呼び出しを実装する（spec.md J5/J6/J8/J9）
  - [ ] `TypeRef` を type arguments/projection(`in`/`out`/`*`)/function type/suspend function type 対応へ拡張する
  - [ ] `resolveTypeRef` で `ClassType.args` と `FunctionType` を復元し、variance 検査へ接続する
  - [ ] 継承節（`superTypes`）で型引数付き supertype を保持し、継承グラフ構築時に型実引数を失わないようにする
  - [ ] call-site 明示型引数（`foo<Int>(...)`）を parser/sema/resolver に通し、推論結果と統合する

- [ ] P5-32: typealias の実体型保存と展開解決を実装する（spec.md J6/J7/J8/J14.3）
  - [ ] `TypeAliasDecl` に RHS 型参照を保持し、Parser/AST builder で抽出する
  - [ ] Sema に alias target 解決と循環検出を追加し、型解決時に展開する
  - [ ] metadata export/import で typealias シグネチャを保存/復元し、不整合診断を追加する

- [x] P5-33: `throw` 式の表現と `outThrown` 送出を実装する（spec.md J11.3/J13.3）
  - [x] AST `Expr` に throw ノードを追加し、式パーサで `throw` を専用構文として扱う
  - [x] 型推論で `throw` の型を `Nothing` として扱い、制御フロー合流規則に反映する
  - [x] KIR/Lowering/Codegen で throwable 値を `outThrown` へ設定して即 return する経路を追加する

- [x] P5-34: リテラル型サーフェス（Long/Float/Double/Char）を front-to-back で実装する（spec.md J4/J8/J12/J15）
  - [x] AST/式パーサで `long`/`float`/`double`/`char` literal を保持する
  - [x] 型推論で primitive 型を正しく付与し、二項演算の型規則を拡張する
  - [x] KIR/Codegen/runtime call で各 primitive 演算と表示の最小経路を実装する

- [x] P5-35: script ルートの top-level statement を AST 以降へ接続する（spec.md J0.4/J5/J6）
  - [x] `SyntaxKind.script` 配下の statement 群を BuildAST で保持する
  - [x] script 評価用の synthetic entry（`main` 相当）へ lowering する
  - [x] script 実行回帰ケースを `diff_kotlinc.sh` に追加する

- [x] P5-36: import alias（`import a.b.C as X`）を解決規則へ組み込む（spec.md J5/J7）
  - [x] `ImportDecl` に alias 情報を追加し、Parser/AST builder で `as` 句を保持する
  - [x] `populateImportScopes` で alias 名を明示 import 優先順位に従って登録する
  - [x] alias 衝突・未解決 import の診断を追加する

- [x] P5-37: string template 補間（`$name`/`${expr}`）を AST/KIR/codegen で実装する（spec.md J4/J5/J6/J12）
  - [x] 字句/構文で template segment と埋め込み式を保持し、`Expr` に string template ノードを導入する
  - [x] 型推論で template 埋め込み値を `String` 変換規則へ接続する
  - [x] KIR で `kk_string_concat` 連結へ lowering し、補間ケースの回帰テストを追加する

- [ ] P5-38: 型パラメータ境界（`T : Upper` / `where` 句）を Parser/Sema/Resolver に実装する（spec.md J6/J8/J9）
  - [ ] `TypeParamDecl` に upper bound 情報を保持し、宣言ヘッダで `where` 句を抽出する
  - [ ] 型推論/overload 解決で type argument が境界制約を満たすことを検証する
  - [ ] 境界違反時の診断と回帰ケース（宣言側・呼び出し側）を追加する

- [ ] P5-39: vararg 実引数を call lowering/ABI で正規化する（spec.md J9/J11/J12）
  - [ ] 複数実引数が 1 つの vararg parameter に束縛された場合に、KIR で配列（または等価表現）へパックする
  - [ ] spread 引数（`*args`）と通常引数の混在を lowering で保持し、callee 側 ABI と整合させる
  - [ ] vararg + default 引数 + named 引数の組み合わせ回帰ケースを追加する

- [ ] P5-40: 未解決参照・型参照の診断を strict 化する（spec.md J7/J8/J9）
  - [ ] `nameRef`/`call`/`memberCall` の unresolved 経路で `errorType` を返すだけでなく診断（`KSWIFTK-SEMA-*`）を出す
  - [ ] `resolveTypeRef` の未知型 fallback（`Any` へ丸める現実装）を廃止し、型名解決失敗を診断する
  - [ ] unresolved 診断の回帰ケース（識別子・関数呼び出し・型注釈）を追加する

- [ ] P5-41: local 変数宣言の完全化（未初期化宣言・型注釈）を実装する（spec.md J6/J7/J9）
  - [ ] AST `localDecl` が initializer 省略を表現できるよう拡張する（`var x: Int` 対応）
  - [ ] local 宣言の型注釈（`val x: T = ...` / `var x: T`）を保持し、推論/代入検査に接続する
  - [ ] 未初期化 local の使用前参照を診断する data-flow チェックを追加する

- [ ] P5-42: block-scope 宣言（local function など）を AST/Sema/KIR に接続する（spec.md J6/J7/J9）
  - [ ] block 内 `fun` 宣言を `blockExpressions` で捨てない AST 表現へ変更する
  - [ ] `FunctionScope`/`BlockScope` に local function symbol を登録し、後続式から参照解決できるようにする
  - [ ] local function 呼び出しの KIR 生成と回帰ケースを追加する

- [ ] P5-43: import 解決を library symbol まで拡張し wildcard/default import を有効化する（spec.md J7）
  - [ ] library import 時に package symbol と package->top-level symbol インデックスを構築する
  - [ ] `buildFileScopes` が source 由来だけでなく imported symbol を default/wildcard import 対象へ取り込むよう修正する
  - [ ] `import foo.bar.*` と default import が `.kklib` シンボルで機能する回帰ケースを追加する

- [ ] P5-44: coroutine launcher lowering の zero-argument 制約を解消する（spec.md J17.3）
  - [ ] `runBlocking`/`launch`/`async` が 0 引数 suspend 関数参照専用となっている制約を解除する
  - [ ] suspend lambda/closure と引数付き suspend 関数呼び出しへの橋渡しを実装する
  - [ ] launcher + 引数あり suspend 関数の E2E 回帰ケースを追加する

- [ ] P5-45: `-g` の debug info 出力を backend/link へ実装する（spec.md J1/J15）
  - [ ] `CompilerOptions.emitsDebugInfo` を `LLVMBackend`/`LLVMCAPIBackend` の emit path へ反映する
  - [ ] synthetic C backend の clang 呼び出しに debug flag を接続し、出力に debug section が含まれることを確認する
  - [ ] LLVM C API backend で DI metadata の最小生成（または仕様化した制限つき対応）を追加する

- [ ] P5-46: 数値リテラルの lexical grammar を Kotlin 仕様に合わせる（spec.md J4）
  - [ ] `0o` など Kotlin 非対応プレフィックスを受理しないよう lexer を修正する
  - [ ] underscore/suffix の許容位置を仕様どおりに検証し、違反時診断を固定する
  - [ ] 数値リテラル grammar 回帰ケース（valid/invalid）を golden に追加する

- [ ] P5-47: block expression の文脈で複文評価（複数 statement + 末尾式）を実装する（spec.md J6/J9/J11）
  - [ ] `ExpressionParser.parseBlockExpression` の単一式再パースを廃止し、block 内 statement 列と末尾式を AST で保持する
  - [ ] block expression 内の local declaration/scope を type inference に接続する
  - [ ] `if`/`when`/`try` branch に `{ a; b; c }` を置いた場合の型と実行順序を回帰テスト化する

- [ ] P5-48: `return` の制御フローを nested expression から正しく伝播させる（spec.md J6/J11/J12）
  - [ ] BuildKIR で `returnExpr` を値式として潰さず、関数終端ジャンプとして lowering する
  - [ ] `if`/`when`/`try` の分岐内部にある `return` を親関数の return へ接続する
  - [ ] nested return 回帰ケース（`if` 内 return / `when` branch return）を追加する

- [ ] P5-49: subject-less `when`（`when { ... }`）を Parser/Sema/KIR へ実装する（spec.md J5/J6/J9）
  - [ ] `parseWhenExpression` が subject 必須になっている現実装を拡張し、subject 省略形を AST で表現する
  - [ ] 分岐条件を `Boolean` 文脈で型検査し、exhaustiveness 規則へ接続する
  - [ ] subject-less when の回帰ケース（guard 連鎖）を追加する

- [ ] P5-50: `super` / qualified `this` 解決を実装する（spec.md J7/J9/J13.2）
  - [ ] AST に `super` / `this@Label`（必要最小）を区別する参照ノードを追加する
  - [ ] member 解決で supertype member lookup を実装し、override 先呼び出しに接続する
  - [ ] super call の lowering/codegen（direct/special dispatch）を追加する

- [ ] P5-51: `if/when` の branch 評価を eager `select` から制御フロー化へ移行する（spec.md J11/J12）
  - [ ] `BuildKIRPass` の `ifExpr`/`whenExpr` lowering で全分岐を先に評価してしまう現実装を廃止する
  - [ ] branch ごとに block/jump（または等価表現）を生成し、選択された分岐だけを評価する
  - [ ] 分岐内の副作用・`return`・`throw` が非選択分岐から漏れない回帰ケースを追加する

- [ ] P5-52: マルチファイル時の parse 境界を file 単位に固定する（spec.md J1/J5/J6）
  - [ ] `LexPhase` でファイルごとの EOF 境界情報を保持し、`ParsePhase` を file 単位で実行する
  - [ ] ファイル跨ぎで statement が連結される経路（token 連結時の境界欠落）を解消する
  - [ ] file ごとの `kotlinFile`/`script` 判定と `ASTFile` 構築が安定する回帰ケースを追加する

- [ ] P5-53: visibility（public/internal/protected/private）を解決規則へ反映する（spec.md J6.3/J7）
  - [ ] `lookup`/import 解決で不可視シンボルを候補から除外するアクセス制御層を追加する
  - [ ] top-level `private` の file スコープ制約と member `protected` 制約を検証する
  - [ ] 不可視参照時の診断（`KSWIFTK-SEMA-*`）と回帰ケースを追加する

- [ ] P5-54: `.kklib` manifest の固定スキーマ検証と互換性チェックを実装する（spec.md J14.2）
  - [ ] `formatVersion`/`moduleName`/`kotlinLanguageVersion`/`target` を読み取り、欠落・不整合を診断する
  - [ ] 現在ターゲットと非互換な library を import した場合に `KSWIFTK-LIB-*` で失敗させる
  - [ ] `objects`/`metadata`/`inlineKIRDir` のパス妥当性チェックを追加する

- [ ] P5-55: Data-flow 解析を true/false 分岐状態モデルへ拡張する（spec.md J10.1）
  - [ ] `DataFlowState` を式条件（`if`/`when`/logical op）で分岐生成し、CFG 合流点で merge する
  - [ ] smart cast/nullability 判定を ad-hoc 判定から `DataFlowState` 駆動へ移行する
  - [ ] 分岐後の型縮小・nullability 更新が維持される回帰ケースを追加する

- [ ] P5-56: default 引数の評価を callee 文脈セマンティクスへ合わせる（spec.md J9/J11/J12）
  - [ ] omitted 引数の default 式を caller 側で直接 lowering する現実装を廃止する
  - [ ] default 式が先行 parameter/receiver を参照できるよう callee 文脈で評価する
  - [ ] default 引数の評価順序（左から右）と副作用順を固定する回帰ケースを追加する

- [ ] P5-57: コンパイル性能計測基盤を整備する
  - [ ] `CompilerDriver` で各 phase の開始/終了時刻を記録し、`-Xfrontend time-phases`（仮）で集計を出力する
  - [ ] `Scripts/bench_compile.sh`（仮）を追加し、`--emit kir/object/executable` × backend（synthetic-c / llvm-c-api）を同条件で計測する
  - [ ] 単一ファイル/複数ファイル（`Scripts/diff_cases`）の基準値を保存し、回帰時に比較できるフォーマット（TSV/JSON）で出力する

- [ ] P5-58: BuildAST のトークン再走査と再パースを削減する
  - [ ] `collectTokens(from:in:)` の再帰収集結果を node 単位でキャッシュし、同一 node の重複走査を避ける
  - [ ] `ExpressionParser` 呼び出し前の `Array(...)` 断片コピーを削減し、token slice ベースで処理できる API に置換する
  - [ ] `parseBlockExpression` の再帰再パース（`ExpressionParser(tokens: trimmed, ...)`）を block statement 直列処理に置換する
  - [ ] AST 同値性（decl/expr 数と source range）を回帰テストで固定する

- [ ] P5-59: Sema/DataFlow の全シンボル走査をインデックス化する
  - [ ] `SymbolTable.allSymbols()` 依存箇所向けに owner/package/kind 別インデックスを導入する
  - [ ] `DataFlowSemaPass+LayoutSynthesis` の ownMethods/ownFields 抽出をインデックス参照へ置換し、N^2 走査を回避する
  - [ ] `DataFlowAnalysis.enumEntryNames` を enum owner -> entry 名キャッシュへ置換する
  - [ ] `ASTModule.sortedFiles` の都度ソートを廃止し、構築時に安定順を保持する

- [ ] P5-60: Lowering/Codegen のスループットを改善する
  - [ ] Lowering pass に precondition を導入し、対象命令が存在しない pass の `transformFunctions` 実行を skip する
  - [ ] `KIRArena.transformFunctions` に unchanged fast-path を追加し、未変更関数の body 再割当を抑制する
  - [ ] object/executable のデフォルト backend を `llvm-c-api` に切り替える可否を性能/互換テストで検証する
  - [ ] synthetic C backend 継続時は runtime stub を共有 object 化し、clang 入力量と起動回数のオーバーヘッドを削減する

- [ ] P5-61: フロントエンドを file 単位で並列実行可能にする
  - [ ] `LexPhase`/`ParsePhase`/`BuildASTPhase` の中間表現を file 単位で保持し、全ファイル連結前提を段階的に解消する
  - [ ] `-Xfrontend jobs=N`（仮）で file 並列実行を有効化し、出力順序は fileID 順で決定的に固定する
  - [ ] multi-file compile ベンチ（10/50/100 file）を追加し、単スレッド比の speedup と診断順序の安定性を検証する

- [ ] P5-62: library import / metadata 復元のキャッシュを導入する
  - [ ] `DataFlowSemaPass+LibraryImport` の manifest/metadata 読み込み結果を path + mtime キーで再利用する
  - [ ] `MetadataTypeSignatureParser` の parse 結果を signature 文字列キーで memoize し、重複復元を削減する
  - [ ] import が多いケース（複数 `.kklib`）の compile ベンチを追加し、Sema 時間の改善率を計測する

- [ ] P5-63: 型推論と呼び出し解決のホットパスをキャッシュする
  - [ ] `OverloadResolver.resolveCall` の結果を callee/arg type/expected type/receiver type キーでキャッシュする
  - [ ] `TypeCheckSemaPass` の `scope.lookup` / `symbols.symbol` の反復参照をローカルキャッシュ化する
  - [ ] キャッシュ有効/無効を切り替える debug flag（`-Xfrontend sema-cache=...` 仮）を追加し、差分検証テストを用意する

- [ ] P5-64: external toolchain 呼び出しのオーバーヘッドを削減する
  - [ ] `LinkPhase` の entry wrapper 生成を UUID 一時ファイル依存から安定パス + 内容差分更新へ置換する
  - [ ] synthetic C backend の巨大 runtime stub 文字列を固定オブジェクト化し、毎回の C 生成量を削減する
  - [ ] codegen/link の subprocess 実行時間を個別に計測し、`time-phases` 出力へ統合する

## P5 (Spec Gap Backlog) — Kotlin 構文完全対応拡張

### Null Safety

- [ ] P5-65: `?.` / `!!` / `?:` を型推論・KIR lowering・runtime まで front-to-back で実装する（spec.md J8/J9/J10）
  - [ ] Parser/AST に `safeCall`（`?.`）/ `notNullAssert`（`!!`）/ `elvisExpr`（`?:`）ノードを導入する
  - [ ] `resolveTypeRef`/`inferExpr` で null-safe call の結果型を `T?` に推論し、`!!` を `T?` → `T`（失敗時 `NullPointerException` throw）として扱う
  - [ ] KIR に `safeCall` 専用 IR ノードを導入し、null チェック分岐と非 null 分岐を明示的に生成する
  - [ ] `?:` の RHS を lazy eval（LHS が non-null の場合は RHS を評価しない）として lowering する
  - [ ] runtime `kk_null_check`（`!!` 用）を `outThrown` チャネル経由で NPE を送出する形で実装する
  - [ ] `?.`/`!!`/`?:` を含む diff/golden 回帰ケースを追加し、`kotlinc` と出力一致を確認する
  - **完了条件**: `?.`/`!!`/`?:` すべてで `Scripts/diff_kotlinc.sh` が pass し、null-chain 複合式の型推論が一致する

- [ ] P5-66: nullable/non-null スマートキャスト伝播を DataFlowState に統合する（spec.md J10/J10.1）
  - [ ] `DataFlowState` に variable ごとの nullability-refined 型（`narrowedType`）を追加する
  - [ ] `if (x != null)` / `x ?: return` / `!!` などのガードパターンを DataFlowAnalysis が認識し、then 分岐で `x` の型を non-null に narrow する
  - [ ] DataFlowState の merge（CFG join 点）で nullability 情報を conservative merge（nullable ← nullable ∪ non-null）する
  - [ ] smart cast 済み変数への `.method()` 呼び出しが `?.` 不要で解決されることを確認する
  - [ ] P5-55 で追加済の true/false 分岐モデルへ nullability 判定を接続する
  - [ ] nullability smart cast の境界ケース（再代入後の失効、ラムダ内キャプチャ）の診断回帰ケースを追加する
  - **完了条件**: `if (x != null) x.length` 系パターンが warning・unsafe キャストなしでコンパイルし、再代入後は smart cast が失効する

---

### 演算子と式

- [ ] P5-67: compound assignment 演算子（`+=` / `-=` / `*=` / `/=` / `%=`）を parser/sema/KIR に実装する（spec.md J5/J9）
  - [ ] Parser/AST に `compoundAssign` ノードを追加し、`+=` 〜 `%=` に対応するトークンを認識する
  - [ ] Sema で `x += y` を `x = x.plus(y)`（または operator function）へ desugaring し、`val` への再代入を診断する
  - [ ] `augmentedAssignment` operator（`plusAssign`/`minusAssign` 等）が定義されている型では `plusAssign` 優先で解決する
  - [ ] KIR/codegen で compound assign を read-modify-write の IR シーケンスへ lowering する
  - [ ] compound assign × member property / index 演算子（`a[i] += 1`）の組み合わせを正しく展開する
  - [ ] `+=` / `-=` を含む diff/golden 回帰ケースを追加する（primitive・コレクション・演算子オーバーロード）
  - **完了条件**: `a += b` が `a.plusAssign(b)` または `a = a.plus(b)` に正しく desugaring され、`kotlinc` 出力と一致する

- [ ] P5-68: range/progression 演算子（`..` / `..<` / `downTo` / `step`）を構文・型推論・for 展開へ接続する（spec.md J5/J9）
  - [ ] Parser/AST に `rangeExpr`（`a..b`）と `rangeUntilExpr`（`a..<b`）を追加する
  - [ ] Sema で `..` を `rangeTo`（`IntRange` 等）operator へ desugaring し、型引数を推論する
  - [ ] `downTo`/`step` を infix 関数呼び出しとして overload 解決に通す
  - [ ] ForLowering で `IntRange`/`LongRange` の `iterator`/`hasNext`/`next` を定数畳み込み可能な形で展開する
  - [ ] `for (i in 0..10)` / `for (i in 10 downTo 0 step 2)` の diff/golden ケースを追加する
  - **完了条件**: `for (i in 1..5)` / `for (i in 5 downTo 1 step 2)` が `kotlinc` と同一出力で動作する

- [ ] P5-69: index アクセス演算子（`a[i]` / `a[i] = v`）を `get`/`set` operator call へ desugaring する（spec.md J9）
  - [ ] Parser/AST に `indexedAccessExpr`（`a[i, ...]`）を追加する
  - [ ] Sema で読み取り文脈の `a[i]` を `a.get(i)`、代入文脈の `a[i] = v` を `a.set(i, v)` へ desugaring する
  - [ ] compound assign と組み合わせた `a[i] += 1` → `a.set(i, a.get(i).plus(1))` の展開を実装する
  - [ ] 多次元インデックス（`a[i, j]`）を複数クオーティング引数として解決する
  - [ ] 配列・文字列・カスタム演算子それぞれの diff/golden ケースを追加する
  - **完了条件**: `Array<Int>` / カスタム `operator fun get` で `a[i]` が正しく呼び出され、bounds check と組み合わせて動作する

- [ ] P5-70: `invoke` 演算子を関数呼び出し解決に統合する（spec.md J9）
  - [ ] `callExpr` 解決時に callee が関数型でない場合に `operator fun invoke` 候補を overload resolver へフォールバックする
  - [ ] lambda/callable reference 型の `invoke` と通常 `operator fun invoke` を統一した解決経路に通す
  - [ ] object が `invoke` を持つ場合の `obj(args)` 構文を Parser/Sema で認識し、member call へ lowering する
  - [ ] `invoke` 演算子の diff/golden ケース（function object、SAM 等）を追加する
  - **完了条件**: `class F { operator fun invoke(x: Int) = x }; val f = F(); f(1)` が動作し、`kotlinc` 出力と一致する

- [ ] P5-71: `in` / `!in` 演算子と `contains` operator への desugaring を実装する（spec.md J9）
  - [ ] Parser/AST で `inExpr`（`x in collection`）/ `notInExpr`（`x !in collection`）を認識する
  - [ ] Sema で `x in c` → `c.contains(x)`、`x !in c` → `!c.contains(x)` へ desugaring する
  - [ ] `when` branch の `in range` / `!in list` パターンを型検査・exhaustiveness に接続する（P5-83 と連携）
  - [ ] `in` を使った `for` ループ・`when`・条件式の diff/golden ケースを追加する
  - **完了条件**: `x in 1..10`、`when` branch の `in list` 形式が `kotlinc` と同一結果で動作する

- [ ] P5-72: 比較演算子を `compareTo` へ desugaring し `Comparable<T>` 連携を実装する（spec.md J9）
  - [ ] Sema で `a < b` / `a <= b` / `a > b` / `a >= b` を `a.compareTo(b) < 0` 等へ desugaring する
  - [ ] `Comparable<T>` を実装した型の比較に overload resolver を通す
  - [ ] プリミティブ型（`Int`/`Long`/`Double` 等）は直接比較 IR に最適化する
  - [ ] `compareTo` desugaring を含む diff/golden ケース（String 比較・カスタム Comparable）を追加する
  - **完了条件**: `String` / カスタム `Comparable` 実装型の `<`/`>=` が `kotlinc` 出力と一致する

---

### クラス機能

- [ ] P5-73: `companion object` を最上位シングルトンとして front-to-back で実装する（spec.md J6/J7）
  - [ ] Parser/AST に `companionObjectDecl`（`companion object [Name] { ... }`）を追加し、`ClassDecl` に保持する
  - [ ] Sema で companion を owner class と同一 FQName スコープに配置し、unqualified な companion member 参照を解決する
  - [ ] companion object を global singleton としてシンボル化し、lazy 初期化パターン（またはスタティック初期化相当）を lowering で生成する
  - [ ] `ClassName.memberName` 形式の companion member 参照を member call lowering へ接続する
  - [ ] `companion object` の `const val`・factory 関数を含む diff/golden ケースを追加する
  - **完了条件**: `Foo.create()` のような companion factory が動作し、companion singleton が一度だけ初期化される

- [ ] P5-74: `data class` の合成メンバ（`copy`/`componentN`/`equals`/`hashCode`/`toString`）を完成させる（spec.md J6/J14.3）
  - [ ] DataEnumSealedSynthesis で `data class` の primary constructor 引数から `componentN()` を生成する
  - [ ] `copy(param = value)` を named argument 付き constructor 呼び出しとして合成する
  - [ ] `equals`（structual equality）/ `hashCode` / `toString` を field リストから合成し、既存 override と整合させる
  - [ ] `==`（`equals` desugaring）/ destructuring で `componentN` を正しく呼ぶ回帰ケースを追加する
  - [ ] metadata export で合成メンバのシグネチャが保存され、import 先から呼び出せることを確認する
  - **完了条件**: `data class Point(val x: Int, val y: Int)` の全合成メンバが `kotlinc` と同一動作をする

- [ ] P5-75: `value class` / `@JvmInline` の boxing 省略と ABI 整合を実装する（spec.md J6/J8/J13）
  - [ ] Parser/AST/Sema で `value class` キーワードを認識し、single-property 制約を検証する
  - [ ] Sema で value class をラッパー除去（unboxed）または boxed の 2 種として型システムに統合する
  - [ ] ABILowering で value class のラップ/アンラップ境界（inline/non-inline 境界）に boxing/unboxing を挿入する
  - [ ] value class を `Any`/インターフェース型として扱う文脈で boxing が発生することを確認する
  - [ ] value class の diff/golden ケース（unboxed 演算・interface 境界 boxing）を追加する
  - **完了条件**: `value class Meter(val value: Int)` が unboxed で渡され、boxing 境界のみで `kk_alloc` が呼ばれる

- [ ] P5-76: `enum class` の `values()`/`valueOf()`/`ordinal`/`name` 合成を front-to-back で完成させる（spec.md J6/J9）
  - [ ] DataEnumSealedSynthesis で `values()` 配列・`valueOf(String)` 検索を合成し、KIR/codegen に接続する
  - [ ] 各 enum entry に `ordinal`（宣言順 Int）と `name`（文字列）フィールドを合成し getter を生成する
  - [ ] enum entry の body（メンバ定義・abstract override）を解析し、entry 固有実装を dispatch する
  - [ ] `when` exhaustiveness に合成 entry set を利用する（P5-83 と連携）
  - [ ] `values()`/`valueOf()`/`ordinal`/`name` を含む diff/golden ケースを追加する
  - **完了条件**: `enum class Color { RED, GREEN, BLUE }; Color.values().map { it.name }` が `kotlinc` と同一出力になる

- [ ] P5-77: inner class / nested class の解決と `this@Outer` 参照を実装する（spec.md J6/J7）
  - [ ] Parser/AST で `inner class` キーワードを認識し、`ClassDecl` に `isInner` フラグを保持する
  - [ ] Sema で inner class のインスタンス化（`outer.Inner()`）を `Outer` インスタンス参照つきで解決する
  - [ ] inner class body で `this@Outer` を outer インスタンスとして束縛し、outer メンバを参照解決する
  - [ ] nested class（`inner` なし）からは outer メンバを参照できないことを診断する
  - [ ] inner class のインスタンス化・outer メンバ参照・`this@Outer` の diff/golden ケースを追加する
  - **完了条件**: `outer.Inner().foo()` で outer の field にアクセスでき、non-inner nested class から outer へのアクセスが診断される

- [ ] P5-78: `sealed class`/`sealed interface` の sealed hierarchy 検証と exhaustiveness を強化する（spec.md J6/J10）
  - [ ] Sema で sealed hierarchy 直接 subclass がコンパイル対象の同一パッケージ内に限定されることを検証する
  - [ ] `when` exhaustiveness チェックで sealed の直接サブクラス集合を metadata から復元し、欠落 branch を診断する
  - [ ] cross-module sealed（library の sealed を consumer が `when`）でも exhaustiveness チェックが動作するよう metadata を拡張する
  - [ ] sealed interface（`sealed interface`）と sealed class の両方で exhaustiveness が機能することを確認する
  - [ ] outside-package subclass の診断・cross-module exhaustiveness の diff/golden ケースを追加する
  - **完了条件**: 全 branch を列挙した sealed `when` は else 不要、一つでも欠けると `KSWIFTK-SEMA-*` 診断が出る

---

### プロパティとデリゲート

- [ ] P5-79: property delegation（`by`）を `getValue`/`setValue`/`provideDelegate` operator へ fully desugar する（spec.md J7/J9/J12）
  - [ ] Parser/AST で `val x by delegate` 構文を `PropertyDecl.delegateExpr` として保持する
  - [ ] Sema で delegate 型の `getValue`/`setValue` operator 候補を overload resolver に通し、型を推論する
  - [ ] `provideDelegate` が定義されている場合は初期化時に呼び出しを挿入する
  - [ ] PropertyLowering で `val x by d` を `private val _x = d.provideDelegate(...)`, `get() = _x.getValue(...)` へ展開する
  - [ ] `by lazy { }` / `by observable(...)` / カスタム delegate の diff/golden ケースを追加する
  - **完了条件**: `val x by lazy { 42 }` が遅延初期化として動作し、`kotlinc` と同一出力になる

- [ ] P5-80: `lazy` / `observable` / `vetoable` 標準 delegates を stdlib stub として接続する（spec.md J7）
  - [ ] runtime/stdlib stub に `kotlin.properties.Lazy<T>` / `ReadWriteProperty<T, V>` の C ABI インターフェースを追加する
  - [ ] `lazy { }` の thread-safety モード（`SYNCHRONIZED` / `NONE`）を compiler option で選択できるようにする
  - [ ] `observable` / `vetoable` を callback 付き delegate として lowering 経路に接続する
  - [ ] stdlib delegate を使った diff/golden ケース（`lazy`/`observable`）を追加する
  - **完了条件**: `by lazy`・`by Delegates.observable` が機能し、初期化・callback の順序が `kotlinc` と一致する

- [ ] P5-81: computed property（getter-only）の backing field なし合成を完成させる（spec.md J7/J12）
  - [ ] PropertyLowering で `val x: Int get() = expr` 形式をバッキングフィールドなしの getter 呼び出しに lowering する
  - [ ] `var` property の custom getter/setter を accessor kind 引数なしの直接 call に整理し、`kk_property_access` 依存を解消する
  - [ ] getter-only property が override される場合の vtable slot 割当を確認する
  - [ ] getter/setter 双方にカスタム実装を持つ property の diff/golden ケースを追加する
  - **完了条件**: `val computed: String get() = "hello"` が毎回呼び出され、backing field が生成されないことを codegen で確認できる

- [ ] P5-82: destructuring declaration（`val (a, b) = pair`）と `componentN` 解決を実装する（spec.md J5/J6/J9）
  - [ ] Parser/AST に `destructuringDecl`（`val (a, b, ...) = expr`）ノードを追加する
  - [ ] Sema で RHS の型から `component1()`〜`componentN()` を overload 解決し、各変数の型を推論する
  - [ ] `data class` の componentN 合成（P5-74）と連携し、for ループ内 destructuring（`for ((k, v) in map)`）を展開する
  - [ ] アンダースコア（`val (a, _, c) = triple`）で不要な component を skip する
  - [ ] lambda 引数の destructuring（`pairs.map { (a, b) -> a + b }`）を lambda body で展開する
  - [ ] destructuring の diff/golden ケース（data class・Map.Entry・lambda）を追加する
  - **完了条件**: `val (x, y) = Point(1, 2)` が `component1()`/`component2()` 呼び出しに展開され動作する

- [ ] P5-83: `when` の型パターン（`is T` / `in range` / `!in collection`）と guard を完全実装する（spec.md J6/J9/J10）
  - [ ] Parser/AST で `when` branch condition に `is T`（型チェック）/ `in expr`（`in` テスト）/ `!in expr`（`!in` テスト）を表現する
  - [ ] `is T` branch 直後に smart cast（P5-66 連携）を適用する
  - [ ] `in range` / `!in list` を P5-71 の `contains` desugaring 経由で評価する
  - [ ] subject-less `when`（P5-49）と型パターンを組み合わせた guard 連鎖を型検査する
  - [ ] sealed / enum × 型パターンの exhaustiveness チェックを接続する（P5-76/P5-78 連携）
  - [ ] 型パターン・range テスト・`!in` を組み合わせた diff/golden ケースを追加する
  - **完了条件**: `when (x) { is Foo -> ...; in 1..10 -> ...; !in list -> ... }` が `kotlinc` と同一出力で動作する

---

### コレクションと標準ライブラリ最小連携

- [ ] P5-84: `Array<T>` / `List<T>` / `Map<K,V>` のリテラル（`listOf`/`mapOf`/`arrayOf`）を stdlib stub で最小実装する（spec.md J15）
  - [ ] runtime/stdlib stub に `kk_list_of` / `kk_map_of` / `kk_array_of` の C ABI 関数を追加する
  - [ ] `listOf(...)` / `mapOf(...)` / `arrayOf(...)` を上記 ABI に lowering する compiler-side shim を実装する
  - [ ] `List<T>` / `Map<K, V>` の `size`・`get`・`contains`・`iterator` を stub で実装する
  - [ ] `for (x in list)` が stub 実装の `iterator()` 経由で動作することを確認する
  - [ ] `listOf`/`mapOf`/`arrayOf` を含む diff/golden ケースを追加する
  - **完了条件**: `listOf(1, 2, 3).size` / `for (x in listOf(...))` が `kotlinc` と同一出力になる

- [ ] P5-85: コレクション型の型引数推論（`listOf(1, 2)` → `List<Int>`）を overload resolver に統合する（spec.md J8/J9）
  - [ ] `TypeInferenceEngine` で generic stub 関数への型引数推論を vararg element 型から行う
  - [ ] 混在型（`listOf(1, "a")`）の LUB 型推論（`List<Any>`）を実装する
  - [ ] explicit 型引数（`listOf<Number>(1, 2.0)`）と推論結果を統合する
  - [ ] 型引数推論の diff/golden ケース（unifrom/mixed element type）を追加する
  - **完了条件**: `listOf(1, 2, 3)` の型が `List<Int>` と推論され、混在型が `List<Any>` となる

---

### アノテーション

- [ ] P5-86: `@annotation` 構文を Parser/AST/Sema で保持し、use-site target を metadata に反映する（spec.md J6/J14.3）
  - [ ] Parser/AST でアノテーション（`@Foo` / `@Foo(args)` / `@file:Foo`）を modifiers node に保持する
  - [ ] Sema でアノテーション型を `class` シンボルとして解決し、引数の型を検証する
  - [ ] use-site target（`@get:` / `@set:` / `@field:` 等）を property accessor へ付与する規則を実装する
  - [ ] `metadata.bin` にアノテーション情報を保存・復元し、import 側から参照できるようにする
  - [ ] アノテーション定義・付与・metadata 往復の基本 diff/golden ケースを追加する
  - **完了条件**: `@Deprecated("use foo instead") fun bar()` が Sema で認識され、metadata に保存・復元される

- [ ] P5-87: `@Suppress` / `@Deprecated` / `@JvmStatic` など built-in アノテーションの特別処理を追加する（spec.md J6）
  - [ ] `@Suppress("UNCHECKED_CAST")` で指定した診断コードを当該 node で抑制する compiler ルールを追加する
  - [ ] `@Deprecated(..., level = ERROR/WARNING)` で呼び出し元に診断を発生させる
  - [ ] `@JvmStatic` on companion member → companion singleton 上の static-like (toplevel) 関数扱いへの lowering を追加する
  - [ ] `@Suppress`/`@Deprecated` の動作を確認する diff/golden ケースを追加する
  - **完了条件**: `@Suppress` が対象診断を抑制し、`@Deprecated(level = ERROR)` が呼び出し元をコンパイルエラーにする

---

### コルーチン拡張

- [x] P5-88 (runtime ABI): `Flow<T>` の runtime C ABI stub を Coroutine Runtime ABI タスクへ統合済み
  - [x] `kk_flow_create` / `kk_flow_emit` / `kk_flow_collect` を RuntimeABISpec・RuntimeABIExterns・C preamble に追加
  - [ ] `flow { emit(x) }` を `Flow<T>` ビルダとして lowering し、emit point を suspension として扱う
  - [ ] `collect { value -> ... }` を suspend 呼び出しのループ展開として lowering する
  - [ ] backpressure なし hot skip / cold flow の基本動作を diff/golden ケースで追加する
  - **完了条件**: `flow { emit(1); emit(2) }.collect { println(it) }` が `kotlinc` と同一出力で動作する

- [ ] P5-89: structured concurrency（`CoroutineScope` / `cancel` / `Job`）の runtime C ABI を整備する（spec.md J17）
  - [ ] runtime に `kk_coroutine_scope_new` / `kk_coroutine_scope_cancel` / `kk_job_join` を追加する
  - [ ] `coroutineScope { }` ブロックの開始・終了・cancel 伝播を lowering で生成する
  - [ ] `launch` / `async` で生成した `Job` / `Deferred<T>` の lifecycle を parent scope へ登録する
  - [ ] `cancel` 呼び出し後に子 coroutine が `CancellationException` を受け取る E2E ケースを追加する
  - **完了条件**: `coroutineScope { launch { delay(100) } }` が scope 終了後に全子 coroutine の完了を待ち、cancel が子へ伝播する

---

### 診断・ツーリング

- [ ] P5-90: 診断コードを全 pass で体系化し、LSP 向け出力（location / severity / codeAction）を実装する
  - [ ] 全 Sema/Parse 診断を `KSWIFTK-{PASS}-{CODE}` 規則で列挙し、`DiagnosticRegistry` に集約する
  - [ ] 診断に source location（file / line / column）と severity（error/warning/note）を必ず付与する
  - [ ] JSON 形式（`-Xdiagnostics json`）で診断を出力するオプションを追加し、LSP が消費できるスキーマで出力する
  - [ ] `codeAction`（quick-fix 提案）を診断コードごとに定義し、最低 10 個の quick-fix を実装する
  - [ ] 診断 JSON 出力の golden ケースを追加し、スキーマ変更を検知する
  - **完了条件**: 全診断が `KSWIFTK-*` コードを持ち、JSON 出力が LSP 準拠スキーマで整合し、golden テストが pass する

- [ ] P5-91: incremental compilation（変更ファイルのみ再コンパイル）の基盤を整備する（spec.md J1）
  - [ ] `CompilerDriver` に入力ファイルの content hash / mtime を記録するキャッシュ層を追加する
  - [ ] 変更なしファイルの Parse/AST/Sema 結果を `.kirbin` キャッシュから再利用する経路を実装する
  - [ ] 依存グラフ（symbol 使用関係）を构築し、変更ファイルに依存するファイルを再コンパイル対象に追加する
  - [ ] incremental ビルドと full ビルドの出力（object/executable）が byte 同一になることを検証する
  - [ ] 10 ファイル構成でのインクリメンタル vs full の compile 時間を計測し、改善率を記録する
  - **完了条件**: 1 ファイル変更で変更ファイルと依存ファイルのみ再コンパイルされ、成果物が full ビルドと一致する

- [ ] P5-92: source-map / DWARF debug info 出力を LLVM C API backend に実装する（spec.md J1/J15）
  - [ ] LLVM C API で `DIBuilder` を使い、source file / compilation unit メタデータを生成する
  - [ ] 関数・変数宣言に対応する `DISubprogram` / `DILocalVariable` を生成し、IR に attach する
  - [ ] 各 KIR instruction の source location（file/line/column）を AST から伝播し、LLVM `DebugLoc` を設定する
  - [ ] `-g` フラグ付きビルドの object file に DWARF section が含まれることを `dwarfdump` / `llvm-dwarfdump` で確認する
  - [ ] debugger（lldb）でステップ実行できる最小 E2E ケースをドキュメント化する
  - **完了条件**: `-g` ビルドの object に DWARF .debug_info が存在し、`lldb` でソース行にブレークポイントが設定できる

## P5 (Spec Gap Backlog) — Kotlin 完全仕様準拠 拡張②

> 共通完了条件ルール（全項目に適用）  
> 1. `Scripts/diff_kotlinc.sh` が exit 0 かつ stdout 完全一致  
> 2. golden テストが byte 一致  
> 3. エラーケースで `KSWIFTK-*` 診断コード出力  
> 4. 各項目末尾エッジケース golden が通過

---

### 🔤 Lexer / Literals

- [ ] P5-93: multiline raw string（`"""..."""`）のエスケープなし文字列リテラルを完全実装する（spec.md J4）
  - [ ] `"""` で囲われた生文字列トークンを Lexer で独立したトークン種別（`rawStringLiteral`）として扱う
  - [ ] 内部改行・タブ・`\` をエスケープ不要として保持し、文字コード変換を行わない
  - [ ] `trimIndent()` / `trimMargin()` の stdlib stub を追加し、common 用法を lowering で接続する
  - [ ] raw string 内の `$` 補間（`${expr}`・`$name`）を通常 template と同等に処理する
  - [ ] raw string リテラルの diff/golden ケース（multiline・補間・末尾空白除去）を追加する
  - **完了条件**: `"""line1\nline2$var""".trimIndent()` が `kotlinc` と同一出力になる

- [ ] P5-94: Char リテラルのエスケープシーケンス全網羅と Unicode escape を実装する（spec.md J4）
  - [ ] `\t` / `\n` / `\r` / `\\` / `\'` / `\"` / `\$` の 7 種を Lexer で正しい Char コードに変換する
  - [ ] `\uXXXX` Unicode エスケープを Lexer で 4 桁 hex → UTF-16 コードポイントへ変換する
  - [ ] 不正なエスケープシーケンス（`\q` 等）に対して `KSWIFTK-LEX-*` 診断を出す
  - [ ] Char 算術（`'a' + 1`・`'z' - 'a'`）の型推論と runtime 演算を実装する
  - [ ] Char エスケープ・Unicode escape の diff/golden ケースを追加する
  - **完了条件**: `'\u0041'` が `'A'` と同一 Char 値になり、不正エスケープが診断される

- [ ] P5-95: 数値リテラルの underscore/suffix/binary 形式と型強制を完全実装する（spec.md J4）
  - [ ] `1_000_000` の underscore 区切りを lexer で処理し、値には影響しない
  - [ ] `0b1010` binary リテラルを Kotlin 仕様どおりに受理する（`0o` 等は拒否・診断）
  - [ ] `0xFF` / `0XDEADBEEF` hex リテラルの大文字小文字を正規化する
  - [ ] `1L` / `1.0f` / `1.0` / `1.0F` の suffix を保持し、型推論で `Long`/`Float`/`Double` を確定する
  - [ ] 範囲外リテラル（`Int` に入らない `999999999999`）の診断を追加する
  - [ ] all-format の diff/golden ケース（binary・hex・underscore・suffix・範囲外）を追加する
  - **完了条件**: Kotlin spec §4 の有効リテラル全形式が parse でき、無効形式が `KSWIFTK-LEX-*` 診断される

---

### 📐 Type System

- [ ] P5-96: `Nothing` 型の型推論・制御フロー Unreachable 統合を完成させる（spec.md J8/J10）
  - [ ] `throw`・`return`・`break`・`continue` の型を `Nothing` として型推論に一貫して伝播させる
  - [ ] `Nothing` を LUB 規則のボトム型として扱い、`if/when/try` の分岐合流で正しく処理する
  - [ ] `Nothing?` と `Nothing` の区別（`null` は `Nothing?`）を型システムに反映する
  - [ ] 到達不能コード（`Nothing` の後の文）を DataFlow が unreachable と判定し diagnostic を出す
  - [ ] `throw`/`return` による分岐縮小の diff/golden ケース（型推論・到達不能）を追加する
  - **完了条件**: `val x: Int = if (cond) 1 else throw E()` が型エラーなしで `Int` と推論され、到達不能行が診断される

- [ ] P5-97: intersection type（`T & U`）と captured type を型システムに追加する（spec.md J8）
  - [ ] `TypeRef` に intersection 型（`A & B`）構文を Parser/AST で追加する（`T & Any` definitelyNonNull を含む）
  - [ ] `inferExpr` で smart cast 後の refinement 型を intersection として表現できるようにする
  - [ ] intersection 型のサブタイプ規則（`A & B <: A`、`A & B <: B`）を `TypeSystem.isSubtype` に追加する
  - [ ] `T & Any`（definitely non-nullable）の型推論と `?.` 解決への影響を実装する
  - [ ] intersection smart cast の diff/golden ケースを追加する
  - **完了条件**: `fun <T> foo(x: T & Any)` の引数が non-null として扱われ、smart cast が不要になる

- [ ] P5-98: 型投影（`out T` / `in T` / `*`）の use-site variance を完全実装する（spec.md J8）
  - [ ] `TypeRef` の use-site `out`/`in`/`*` を covariant/contravariant/bivariant projection として保持する
  - [ ] star projection `*` を `out Any?` として扱い、write を禁止・read を `Any?` として型付けする
  - [ ] use-site variance と declaration-site variance の合成規則（in×in=out 等）を `TypeSystem` に実装する
  - [ ] variance 違反のメンバアクセスに `KSWIFTK-SEMA-VAR-*` 診断を出す
  - [ ] star projection / `in T` / `out T` の diff/golden ケースを追加する
  - **完了条件**: `val list: MutableList<out Number>` で `.add(...)` が型エラー、`.get(0)` が `Number` になる

- [ ] P5-99: typealias の generic alias・循環検出・展開深度制限を完全実装する（spec.md J6/J8）
  - [ ] `typealias Func<T> = (T) -> T` のような generic typealias を Sema で展開する
  - [ ] 循環 alias（`typealias A = B; typealias B = A`）を detect し `KSWIFTK-SEMA-ALIAS-CYCLE` を出す
  - [ ] alias 展開後の型が variance 制約を壊さないことを検証する
  - [ ] recursive type の展開に最大深度制限（例: 32 段）を設けてループを防ぐ
  - [ ] generic alias diff/golden ケース（lambda alias・circular alias エラー）を追加する
  - **完了条件**: `typealias Predicate<T> = (T) -> Boolean` が call-site で正しく展開され型チェックが通る

---

### ⚙️ Expressions / Operators

- [ ] P5-100: `as`（unsafe cast）/ `as?`（safe cast）を型推論・KIR・runtime まで実装する（spec.md J9）
  - [ ] Parser/AST に `castExpr`（`expr as Type`）/ `safeCastExpr`（`expr as? Type`）ノードを追加する
  - [ ] `as` は cast 失敗時に `ClassCastException` を `outThrown` 経由で throw し、型を target type へ narrow する
  - [ ] `as?` は cast 失敗時に `null` を返し、型を `TargetType?` へ narrow する
  - [ ] KIR に cast チェック命令を追加し、codegen で runtime `kk_typecheck` 呼び出しへ lowering する
  - [ ] `as` cast 後の smart cast（P5-66 連携）伝播を実装する
  - [ ] unsafe/safe cast の diff/golden ケース（成功・失敗・null 入力）を追加する
  - **完了条件**: `x as String` が非 String で `ClassCastException`、`x as? String` が `null` を返し `kotlinc` と一致

- [ ] P5-101: `is` / `!is` 型検査と smart cast を完全実装する（spec.md J9/J10）
  - [ ] Parser/AST に `typeCheckExpr`（`expr is Type` / `expr !is Type`）ノードを追加する
  - [ ] `is` チェック後の then branch で変数型を narrowed type に smart cast する（P5-66 連携）
  - [ ] `!is` チェック後の else branch でも narrow を適用する
  - [ ] ジェネリクス型（`x is List<*>`）の reified 制限と erasure 警告を実装する
  - [ ] `is` check を `&&` / `||` と組み合わせた場合の smart cast 伝播を実装する
  - [ ] `is`/`!is` の diff/golden ケース（基本・&&条件・ジェネリクス erasure 警告）を追加する
  - **完了条件**: `if (x is String) x.length` が smart cast で動作し、`x !is String` branch で元の型になる

- [ ] P5-102: 演算子の優先順位テーブルを Kotlin 仕様完全準拠で実装する（spec.md J5）
  - [ ] Kotlin 仕様の 16 優先順位レベル（postfix > prefix > type_rhs > multiplicative > additive > range > infix > Elvis > named checks > comparison > equality > conjunction > disjunction > spread > assignment）を Parser に実装する
  - [ ] infix 関数呼び出し（`a shl b`・`a or b`）を中置演算子として正しい優先順位で解析する
  - [ ] `!!` の postfix 優先順位（`.` より低くないこと）を確認する
  - [ ] `a + b * c - d / e` 等の混在式が正しい AST 木を生成することを golden で固定する
  - [ ] 優先順位境界での結合テスト（parser golden）を追加する
  - **完了条件**: `1 + 2 * 3 == 7`・`true || false && false == true` が `kotlinc` と同一に評価される

- [ ] P5-103: bitwise / shift 演算子（`and`/`or`/`xor`/`inv`/`shl`/`shr`/`ushr`）を infix 関数として実装する（spec.md J9）
  - [ ] `Int`/`Long` の `and`/`or`/`xor`/`inv`/`shl`/`shr`/`ushr` を stdlib infix 関数として stub 実装する
  - [ ] Sema で infix 関数呼び出し構文（`a shl 3`）を overload resolver に通す
  - [ ] bit 演算の結果型推論（`Int and Int → Int`）を実装する
  - [ ] `inv()` の unary 用法と `and`/`or`/`xor` の二項用法の diff/golden ケースを追加する
  - **完了条件**: `(0xFF and 0x0F).toString(16)` が `kotlinc` と同一出力（`"f"`）になる

- [ ] P5-104: `@Label` / `return@label` / `break@label` / `continue@label` を完全実装する（spec.md J5/J6）
  - [ ] Parser/AST で `@Label` prefix を関数リテラル・ループ・`return`/`break`/`continue` に付与できるようにする
  - [ ] Sema で label scope を管理し、`return@label` が lambda/fun のいずれを対象にするか解決する
  - [ ] `break@outer` / `continue@outer` を nested loop の外側ループ制御フローへ接続する
  - [ ] `return@label` がラムダ内から外側関数へ non-local return する場合の lowering を実装する
  - [ ] labeled break/continue/return の diff/golden ケース（入れ子ループ・inline lambda non-local return）を追加する
  - **完了条件**: `outer@ for (...) { for (...) { break@outer } }` が外側ループを抜け `kotlinc` と一致

---

### 🔀 Control Flow (エッジケース)

- [ ] P5-105: `when` の複数条件ブランチ（`,` 区切り）と exhaustive 診断精度を強化する（spec.md J5/J6）
  - [ ] `when` branch の condition として `,` 区切り複数値（`1, 2, 3 -> ...`）を Parser/AST で保持する
  - [ ] Sema で複数条件を OR 結合として型検査し、exhaustiveness に反映する
  - [ ] KIR lowering で複数条件を OR jump として展開し、重複ヒットを排除する
  - [ ] sealed/enum × 複数条件の exhaustiveness 診断精度を向上する
  - [ ] `,` 区切り複数条件・range guard の diff/golden ケースを追加する
  - **完了条件**: `when (x) { 1, 2 -> "few"; else -> "many" }` が `kotlinc` と同一動作する

- [ ] P5-106: `try` を式として使う場合の型推論と `finally` 影響を実装する（spec.md J6/J11）
  - [ ] `val x = try { ... } catch { ... }` の型を `try`/`catch` 最終式の LUB で推論する
  - [ ] `finally` ブロックの戻り値が型推論を汚染しない（`Unit` 扱い）ことを保証する
  - [ ] `catch` ブランチが複数ある場合の各ブランチ型合流を実装する
  - [ ] some exception type のみ catch し残りを再 throw する制御フロー型推論を実装する
  - [ ] try 式の diff/golden ケース（型合流・finally 影響なし・複数 catch）を追加する
  - **完了条件**: `val x: String = try { "ok" } catch (e: Exception) { "err" }` が型エラーなしでコンパイルされる

- [ ] P5-107: `do-while` の condition スコープと `break`/`continue`・初回実行を完全実装する（spec.md J5/J6）
  - [ ] `do { body } while (cond)` のパースで condition が body スコープ外であることを保証する
  - [ ] `do-while` 内の `break` / `continue` を正しい label ターゲットに接続する
  - [ ] do-while の初回実行保証（condition が false でも body が 1 回実行）を codegen で保証する
  - [ ] do-while + label + break の diff/golden ケースを追加する
  - **完了条件**: `do { ... } while (false)` が body を 1 回実行し、`break` が正しくループを脱出する

---

### 📋 Declarations

- [ ] P5-108: top-level property の backing field・getter/setter・初期化順序を front-to-back で実装する（spec.md J6/J7）
  - [ ] top-level `val`/`var` を property シンボルとして扱い、getter/setter ABI を生成する
  - [ ] top-level property の初期化順序（宣言順・依存あり）を global initializer で保証する
  - [ ] top-level `var` への setter を通した代入（`Pkg.x = 1`）を解決する
  - [ ] top-level getter/setter を持つ property の diff/golden ケースを追加する
  - **完了条件**: top-level `val pi = 3.14` と `var counter = 0` が `kotlinc` と同一動作する

- [ ] P5-109: `const val` のコンパイル時定数畳み込みを実装する（spec.md J6/J7）
  - [ ] `const val` を宣言時に型チェックし、primitive/String 限定であることを検証する
  - [ ] `const val` を参照する式を Sema/KIR で定数値に畳み込み、実 getter 呼び出しを省く
  - [ ] annotation 引数に `const val` を使えることを Sema で検証する（P5-86 連携）
  - [ ] companion object / top-level の `const val` の diff/golden ケースを追加する
  - **完了条件**: `const val MAX = 100; if (x > MAX) ...` が `if (x > 100)` と同等にコンパイルされる

- [ ] P5-110: `lateinit var` の初期化チェックと `isInitialized` を実装する（spec.md J6/J7）
  - [ ] `lateinit var` を Sema で認識し、nullable でないこと・reference type 制約を検証する
  - [ ] 未初期化 `lateinit var` へのアクセス時に `UninitializedPropertyAccessException` を `outThrown` 経由で throw する
  - [ ] `::x.isInitialized` を property reference の特別属性として Sema/KIR に接続する
  - [ ] lateinit を使った diff/golden ケース（初期化前アクセス例外・isInitialized）を追加する
  - **完了条件**: 未初期化 `lateinit var` アクセスが `UninitializedPropertyAccessException` を throw する

- [ ] P5-111: `object` declaration（singleton）の lazy 初期化と init block 実行順序を実装する（spec.md J6/J7）
  - [ ] `object Foo { ... }` を one-time lazy init singleton としてシンボル化し、global initializer guard を生成する
  - [ ] object への最初のアクセス時に初期化が走り、2 回目以降はキャッシュを返すことを保証する
  - [ ] object body の init block 実行順序（property initializer → init block）を codegen で保証する
  - [ ] object singleton の diff/golden ケース（lazy init・init block 順序）を追加する
  - **完了条件**: `object Counter { var n = 0 }` が singleton 保証で動作し、`kotlinc` と同一出力になる

---

### 🏗️ Class / Object

- [ ] P5-112: abstract class / abstract member の制約と override 強制を実装する（spec.md J6/J7）
  - [ ] `abstract class` / `abstract fun` / `abstract val` を Sema で認識し、インスタンス化禁止を診断する
  - [ ] concrete subclass がすべての abstract member を override しない場合に `KSWIFTK-SEMA-ABSTRACT` を出す
  - [ ] `abstract class` への direct `super.foo()` 呼び出しを禁止し診断する
  - [ ] abstract class inheritance と override の diff/golden ケースを追加する
  - **完了条件**: `abstract class A { abstract fun f() }; class B : A() { override fun f() = 1 }` が正しくコンパイルされる

- [ ] P5-113: `interface` default method（body あり fun in interface）を front-to-back で実装する（spec.md J6/J7/J13.2）
  - [ ] interface body 内に body を持つ fun 宣言を Parser/AST/Sema で保持する
  - [ ] concrete class が override しない場合に interface default 実装を itable 経由で dispatch する
  - [ ] default method と concrete override の共存を vtable/itable で正しく表現する（P5-25 連携）
  - [ ] interface default method の diff/golden ケース（デフォルト利用・override・property default getter）を追加する
  - **完了条件**: interface default method が override されない場合に default 実装が呼ばれる

- [ ] P5-114: 多重インターフェース実装と diamond override の解決規則を実装する（spec.md J7/J13.2）
  - [ ] class が複数 interface を実装する場合の itable 割当ロジックを拡張する（slot conflict 解決）
  - [ ] 同名 default method を複数 interface が持つ場合に override を強制し `KSWIFTK-SEMA-DIAMOND` を出す
  - [ ] `super<InterfaceName>.method()` で特定 interface の default 実装を明示呼び出しできる
  - [ ] diamond 継承の itable 共有・override 強制の diff/golden ケースを追加する
  - **完了条件**: `class C : A, B` で両方に同名 default method があると `override` を強制し診断が出る

- [ ] P5-115: `open` / `final` / `override` 修飾子の継承制約を完全実装する（spec.md J6/J7）
  - [ ] `final` class または `final fun` を override しようとした場合に `KSWIFTK-SEMA-FINAL` を出す
  - [ ] `open` でない class への subclass 化を診断する（Kotlin はデフォルト `final`）
  - [ ] `override` 修飾子なしで親の関数を隠蔽した場合に Error/Warning を出す
  - [ ] `open`/`final`/`override` の diff/golden ケースを追加する
  - **完了条件**: non-open class の継承は診断され、`open class` の継承と override が `kotlinc` と一致する

- [ ] P5-116: `data object` / anonymous object の型と等値比較を実装する（spec.md J6）
  - [ ] `data object Singleton` を singleton かつ equals/hashCode/toString 合成ありとして扱う
  - [ ] anonymous object（`object : Interface { ... }`）を object literal（P5-20）と統合する
  - [ ] anonymous object の型を local nominal として推論し、呼び出しスコープ内で有効にする
  - [ ] data object / anonymous object の diff/golden ケースを追加する
  - **完了条件**: `data object None` が `None == None` → `true`、`None.toString()` → `"None"` を返す

- [ ] P5-117: constructor の `init` block と primary constructor property の初期化順序を保証する（spec.md J7）
  - [ ] primary constructor の `val`/`var` パラメータを property として宣言と同時に初期化する
  - [ ] class body 内の property 初期化と `init { }` block の実行を宣言順（上から下）で保証する
  - [ ] secondary constructor が `this(...)` で primary を必ず委譲（または `super(...)` 委譲）することを検証する
  - [ ] 初期化順序に依存したコードの diff/golden ケース（`init` block 2 つ・property 依存）を追加する
  - **完了条件**: `class A { val x = f(); init { println(x) }; val y = x + 1 }` が宣言順で初期化される

---

### 🧩 Functions

- [ ] P5-118: tail-recursive 関数（`tailrec fun`）の末尾呼び出し最適化を実装する（spec.md J9）
  - [ ] `tailrec` 修飾子を Sema で認識し、最後の式が self-recursive call であることを検証する
  - [ ] tail call が満たされない場合に `KSWIFTK-SEMA-TAILREC` warning を出す
  - [ ] KIR/Lowering で `tailrec fun` をループ（label jump）へ変換し、スタック消費を抑制する
  - [ ] 深い再帰が tailrec により StackOverflow を起こさないことを E2E テストで確認する
  - **完了条件**: `tailrec fun fact(n: Int, acc: Int = 1): Int` が 100000 段の再帰で StackOverflow しない

- [ ] P5-119: infix 関数宣言（`infix fun`）の構文と解決を実装する（spec.md J9）
  - [ ] `infix fun T.foo(arg: Type)` を parser/AST で infix function として保持する
  - [ ] `a foo b` 形式の中置呼び出しを Sema で receiver + infix function 呼び出しへ解決する
  - [ ] infix 関数の優先順位を通常関数呼び出しより低く、`||`/`&&` より高く設定する（P5-102 連携）
  - [ ] `to`（`Pair` infix）/ カスタム infix の diff/golden ケースを追加する
  - **完了条件**: `1 to "one"` が `Pair(1, "one")` に、カスタム infix 関数が正しい優先順位で評価される

- [ ] P5-120: `operator fun` の全標準 operator を網羅し診断を整備する（spec.md J9）
  - [ ] 標準 operator 名（`plus`/`minus`/`times`/`div`/`rem`/`unaryPlus`/`unaryMinus`/`not`/`inc`/`dec`/`rangeTo`/`rangeUntil`/`contains`/`get`/`set`/`invoke`/`iterator`/`hasNext`/`next`/`component1..N`/`compareTo`/`equals`）を全列挙する
  - [ ] operator 名と引数・戻り値の型制約を Sema で検証する（例: `inc()` は receiver 型を返す）
  - [ ] `operator` 修飾子なしで operator 名の関数を演算子として使おうとした場合に診断する
  - [ ] `inc`/`dec`（prefix/postfix `++`/`--`）の pre/post セマンティクスを正しく lowering する
  - [ ] 全 operator 記号 → 関数名マッピングの diff/golden ケースを追加する
  - **完了条件**: `operator fun inc()` が `++x` に desugared され、`operator` なし fun は演算子として使えない

- [ ] P5-121: function type / lambda の `it`・型省略・destructuring を完全実装する（spec.md J9/J12）
  - [ ] 単一引数 lambda の暗黙引数（`it`）を Sema でスコープに束縛する
  - [ ] lambda パラメータの型が context から推論される場合（`list.map { it + 1 }`）に型注釈を省略できる
  - [ ] lambda パラメータを `(a, b)` 形式で destructuring する（P5-82 連携）
  - [ ] trailing lambda 構文（`foo(1) { it * 2 }`）を parser で正しく扱う（P5-20 連携）
  - [ ] `it`・型省略・destructuring の diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3).map { it * 2 }` / `pairs.map { (a,b) -> a + b }` が `kotlinc` と一致

---

### 🏠 Properties

- [ ] P5-122: extension property を型システム・member dispatch に統合する（spec.md J7/J9）
  - [ ] `val String.firstChar: Char get() = this[0]` を extension property シンボルとして Sema に登録する
  - [ ] extension property の `get`/`set` を extension function として ABI lowering する
  - [ ] extension property を import・overload resolver で解決し、member property より低い優先順位を保つ
  - [ ] extension property の diff/golden ケース（読み取り・書き込み・import）を追加する
  - **完了条件**: `val String.firstChar get() = this[0]` が `"hello".firstChar` で `'h'` を返す

- [ ] P5-123: getter/setter 内で backing field を参照する `field` キーワードを実装する（spec.md J7）
  - [ ] getter/setter body 内で `field` を backing field への参照として Sema で解決する
  - [ ] `field` への代入（setter 内）と読み取り（getter 内）を backing field load/store IR に lowering する
  - [ ] `field` を getter/setter 外で使うと `KSWIFTK-SEMA-FIELD` 診断を出す
  - [ ] `field` を使う diff/golden ケース（カスタム setter で validate してから set）を追加する
  - **完了条件**: `var x: Int = 0; set(v) { field = if (v < 0) 0 else v }` が setter で field に正しく書き込む

- [ ] P5-124: `provideDelegate` operator と `KProperty<*>` stub を完全連携させる（spec.md J7/J9）
  - [ ] property 初期化時に `provideDelegate(thisRef, property)` を自動呼び出しし、delegate オブジェクトをキャッシュする
  - [ ] `thisRef` 引数（property が属する receiver）と `property` 引数（`KProperty<*>` stub）を lowering で渡す
  - [ ] `KProperty<*>` stub（name/returnType 最小）を metadata 経由で compiler から参照できる形で定義する
  - [ ] `provideDelegate` を持つ delegate の diff/golden ケースを追加する
  - **完了条件**: `operator fun provideDelegate(...)` が property 初期化時に呼ばれ `getValue` が使用される

---

### 🧬 Generics（エッジケース）

- [ ] P5-125: 複数 upper bound（`where T : A, T : B`）と F-bound（`T : Comparable<T>`）を完全実装する（spec.md J8）
  - [ ] `where` 句の複数 upper bound を `TypeParamDecl` に保持し、overload 解決で全境界を検証する
  - [ ] `T : Comparable<T>` のような自己参照 upper bound（F-bound）を循環検出せずに解決する
  - [ ] 複数 upper bound に違反する型引数に `KSWIFTK-SEMA-BOUND` 診断を出す
  - [ ] F-bound generics の diff/golden ケースを追加する
  - **完了条件**: `fun <T> max(a: T, b: T): T where T : Comparable<T>` が `max(1, 2)` / `max("a", "b")` で動作する

- [ ] P5-126: generic function の型推論（引数型・expected type からの自動推論）を完全実装する（spec.md J8/J9）
  - [ ] 引数型からの逆算（`foo(listOf(1, 2))` → `T = List<Int>`）を `TypeInferenceEngine` で実装する
  - [ ] expected type（代入先型）からの backward 推論を実装する
  - [ ] 推論失敗時に型引数の明示を要求する `KSWIFTK-SEMA-INFER` 診断を出す
  - [ ] 各種推論シナリオの diff/golden ケース（引数型・expected type・推論失敗）を追加する
  - **完了条件**: `fun <T> id(x: T): T = x` の `id(42)` が `Int` 型を返し explicit `<Int>` と同一になる

- [ ] P5-127: variance（`out T`/`in T`）の declaration-site 制約違反診断を実装する（spec.md J8）
  - [ ] `class Box<out T>` で `in` 位置（関数引数）に `T` が登場したら `KSWIFTK-SEMA-VARIANCE` を出す
  - [ ] `class Sink<in T>` で `out` 位置（戻り値）に `T` が登場したら診断する
  - [ ] private member は variance チェックの例外となる規則（Kotlin 仕様）を実装する
  - [ ] contravariance の subtype 逆転（`Consumer<in Number>` に `IntConsumer` を代入不可）を型システムに反映する
  - [ ] variance 違反・安全な use の diff/golden ケースを追加する
  - **完了条件**: `class Producer<out T>(val value: T)` は OK、`fun set(v: T) {}` 追加は `KSWIFTK-SEMA-VARIANCE` になる

- [ ] P5-128: `reified` inline 関数での `T::class` / `typeOf<T>()` を完全実装する（spec.md J12.2）
  - [ ] `reified T` の inline body 内で `T::class`・`typeOf<T>()` が有効になるよう lowering する
  - [ ] `typeOf<T>()` を runtime 型トークン（`KClass` stub）へ lowering し、`simpleName`・`qualifiedName` を実装する
  - [ ] non-inline 文脈で `T::class`（non-reified）を使った場合に `KSWIFTK-SEMA-REIFIED` 診断を出す
  - [ ] `reified T` × `typeOf` / `T::class` の diff/golden ケースを追加する
  - **完了条件**: `inline fun <reified T> typeNameOf() = T::class.simpleName` が正しい型名を返す

- [ ] P5-129: generic lambda と SAM conversion（functional interface）を実装する（spec.md J8/J12）
  - [ ] `fun interface` キーワードを Sema で認識し、SAM conversion の対象と判定する
  - [ ] lambda を SAM 型（`Runnable`・カスタム functional interface）へ暗黙変換する
  - [ ] SAM conversion 後の型推論と overload 解決への影響を実装する
  - [ ] SAM lambda が `invoke` 経由で呼ばれることと、object キャッシュを確認する
  - [ ] `fun interface` / SAM conversion の diff/golden ケースを追加する
  - **完了条件**: `fun interface Action { fun run() }; val a: Action = { println("hi") }; a.run()` が動作する

---

### 🛡️ Null Safety（エッジケース）

- [ ] P5-130: platform type（nullability 不明型 `T!`）の扱いを実装する（spec.md J8）
  - [ ] externally-declared symbol（`.kklib` import）で nullability 情報がない型を platform type として表現する
  - [ ] platform type は nullable にも non-null にも代入でき、利用時に nullability 警告を出す
  - [ ] platform type を明示した nullable/non-null へ代入する文脈で型チェックを緩和する
  - [ ] platform type の diff/golden ケースを追加する
  - **完了条件**: 外部 API から返された型が `T!` として扱われ、null チェックなし使用に `KSWIFTK-SEMA-PLATFORM` warning が出る

- [ ] P5-131: nullable receiver（`T?.foo()`）拡張関数を Sema で解決する（spec.md J7/J9）
  - [ ] `fun String?.isNullOrEmpty()` のような nullable receiver の拡張関数を Sema で登録・解決する
  - [ ] nullable receiver 拡張は `?.` なしに直接呼べることを Sema で許可する
  - [ ] nullable receiver 拡張の優先順位（non-null receiver extension より低い）を解決規則に反映する
  - [ ] nullable receiver 拡張の diff/golden ケースを追加する
  - **完了条件**: `null.isNullOrEmpty()` が `NullPointerException` を出さず `true` を返し `kotlinc` と一致する

- [ ] P5-132: nullable な型引数（`List<String?>`）と non-null 型引数（`List<String>`）の区別を実装する（spec.md J8）
  - [ ] `List<String?>` と `List<String>` を異なる型として扱い代入を制限する
  - [ ] `T` が `String?` にバインドされる場合と `String` にバインドされる場合を overload 解決で区別する
  - [ ] nullable 型引数を持つ generic type の `get()`/`set()` 呼び出し型を正しく推論する
  - [ ] `List<String?>` の diff/golden ケース（nullable element access）を追加する
  - **完了条件**: `val list: List<String?> = listOf("a", null)` の `list[1]` が `String?` 型になる

---

### ⚡ Coroutines（エッジケース）

> **Note**: P5-88 / P5-133 / P5-134 / P5-135 の runtime C ABI stub 部分は
> 「Coroutine Runtime ABI」タスクとして統合済み。各 `kk_*` 関数は
> `RuntimeABISpec` / `RuntimeABIExterns` / `RuntimeCoroutine.swift` / C preamble に一括定義されている。
> 残りのサブタスク（lowering・diff/golden ケース）は個別に実装する。

- [x] P5-133 (runtime ABI): `withContext` / Dispatchers の runtime C ABI stub を Coroutine Runtime ABI タスクへ統合済み
  - [x] `kk_dispatcher_default` / `kk_dispatcher_io` / `kk_dispatcher_main` / `kk_with_context` を RuntimeABISpec・RuntimeABIExterns・C preamble に追加
  - [ ] `withContext` body を新たな coroutine context で実行し、完了後に元 context へ戻る lowering を実装する
  - [ ] `withContext` の diff/golden ケース（context 切り替え・例外伝播）を追加する
  - **完了条件**: `withContext(Dispatchers.IO) { heavyWork() }` が別 dispatcher で実行され結果を返す

- [x] P5-134 (runtime ABI): `Channel<T>` の runtime C ABI stub を Coroutine Runtime ABI タスクへ統合済み
  - [x] `kk_channel_create` / `kk_channel_send` / `kk_channel_receive` / `kk_channel_close` を RuntimeABISpec・RuntimeABIExterns・C preamble に追加
  - [ ] `channel.send(value)` / `channel.receive()` を suspension point として KIR に lowering する
  - [ ] unbuffered channel の rendezvous semantics（sender が receiver を待つ）を runtime で実装する
  - [ ] producer/consumer pattern の diff/golden ケースを追加する
  - **完了条件**: `val ch = Channel<Int>(); launch { ch.send(42) }; println(ch.receive())` が `42` を出力する

- [x] P5-135 (runtime ABI): `async`/`await`（`Deferred<T>`）の runtime C ABI stub を Coroutine Runtime ABI タスクへ統合済み
  - [x] `kk_await_all` を RuntimeABISpec・RuntimeABIExterns・C preamble に追加（`kk_kxmini_async` / `kk_kxmini_async_await` は既存）
  - [ ] `async { }` が `Deferred<T>` を返す lowering を実装する
  - [ ] `deferred.await()` を suspension point として実装し、結果型 `T` を推論する
  - [ ] async/await の diff/golden ケース（並列計算・例外伝播）を追加する
  - **完了条件**: `val result = async { 1 + 2 }.await()` が `3` を返し `kotlinc` と同一出力になる

- [ ] P5-136: coroutine cancellation と `CancellationException` の伝播を実装する（spec.md J17）
  - [ ] cancellation を suspension point で確認するチェックを各 `kk_coroutine_*` helper に追加する
  - [ ] `job.cancel()` 呼び出し後に子 coroutine が次の suspension point で `CancellationException` を受け取る
  - [ ] `CancellationException` は silent re-throw（catch で再 throw）する規則を Sema/runtime に反映する
  - [ ] cancellation propagation の diff/golden ケースを追加する
  - **完了条件**: `launch { while(true) delay(10) }.cancel()` が coroutine を停止し `CancellationException` が伝播する

---

### 📦 Stdlib / DSL

- [ ] P5-137: スコープ関数（`let`/`run`/`apply`/`also`/`with`）を extension として実装する（spec.md J9/J12）
  - [ ] `let`/`run`/`apply`/`also`/`with` を stdlib extension function stub として定義する
  - [ ] 各スコープ関数の receiver / lambda parameter / 戻り値の型規則を正確に実装する
    - `let { it -> R }` → receiver を `it`、戻り値 `R`
    - `run { this -> R }` → receiver を `this`、戻り値 `R`
    - `apply { this -> Unit }` → receiver を `this`、戻り値は receiver
    - `also { it -> Unit }` → receiver を `it`、戻り値は receiver
    - `with(obj) { this -> R }` → 通常（非 extension）関数
  - [ ] null 安全 `let`（`nullable?.let { ... }`）のショートサーキット動作を確認する
  - [ ] スコープ関数の diff/golden ケース（null-safe let・builder apply）を追加する
  - **完了条件**: `val len = "hello".let { it.length }` が `5` を返し `kotlinc` と一致する

- [ ] P5-138: `buildString`/`buildList`/`buildMap` DSL builder を実装する（spec.md J9/J12）
  - [ ] `buildString { append("a"); append("b") }` を `StringBuilder` ベースの DSL として実装する
  - [ ] `buildList { add(1); add(2) }` を mutable list builder として実装する
  - [ ] builder lambda の receiver (`StringBuilder`/`MutableList`) を Sema で `this` として束縛する
  - [ ] builder DSL の diff/golden ケース（buildString・buildList）を追加する
  - **完了条件**: `buildString { append("hello "); append("world") }` が `"hello world"` を返す

- [ ] P5-139: `Sequence<T>` と lazy evaluation chain（`asSequence`/`map`/`filter`/`toList`）を実装する
  - [ ] `Sequence<T>` を lazy iterator-based collection として runtime stub に定義する
  - [ ] `asSequence()`・`map`・`filter`・`take`・`toList()` を Sequence extension stub として実装する
  - [ ] Sequence は terminal operation（`toList()` 等）まで評価しない lazy semantics を保証する
  - [ ] `sequence { yield(x) }` builder を coroutine-based lazy generator として stub 実装する
  - [ ] Sequence chain の diff/golden ケースを追加する
  - **完了条件**: `listOf(1,2,3).asSequence().map { it*2 }.filter { it>2 }.toList()` が `[4, 6]` を返す

---

### 🌐 Multiplatform / Misc

- [ ] P5-140: `expect`/`actual` 宣言を parser/sema/metadata で扱う（spec.md J14 / Kotlin MPP）
  - [ ] `expect fun foo()` を abstract-like 宣言として Parser/AST で保持する
  - [ ] `actual fun foo()` を対応する `expect` の実装として Sema でマッチングする
  - [ ] `expect` に対する `actual` が存在しない場合に `KSWIFTK-MPP-UNRESOLVED` を出す
  - [ ] `expect`/`actual` の最小 diff/golden ケース（common + platform モジュール構成）を追加する
  - **完了条件**: `expect fun platform()` に対する `actual fun platform()` が正しくリンクされ動作する

- [ ] P5-141: file-level annotation（`@file:JvmName`・`@file:Suppress`）と package-level 制約を実装する（spec.md J6）
  - [ ] `@file:AnnotationName` を Parser/AST でファイルレベル annotation として保持する
  - [ ] `@file:Suppress("CODE")` をファイル全体への診断抑制として Sema で適用する
  - [ ] `@file:JvmName("...")` を ABI / metadata で保持し、他モジュールから参照できるようにする
  - [ ] file-level annotation の diff/golden ケースを追加する
  - **完了条件**: `@file:Suppress("UNUSED")` がファイル全体の UNUSED 警告を抑制する

---

## 優先度マトリクス（P5-93〜P5-141）

| 優先度 | 番号 | 理由 |
|---|---|---|
| 🔴 P0 ブロッカー | P5-93/94/95 | Lexer 欠損は基本テストが通らない |
| 🔴 P0 ブロッカー | P5-96/98/100/101/102 | 型システム基盤・演算子が未実装では他が動かない |
| 🟠 P1 高 | P5-97/99, P5-103/104 | intersection type・typealias edge・bitwise・label |
| 🟠 P1 高 | P5-105/106/107 | 制御フロー完全化（when 複数条件・try 式・do-while） |
| 🟠 P1 高 | P5-112/113/115, P5-118/119/120 | class 制約・interface default・tailrec・infix・operator 全網羅 |
| 🟡 P2 中 | P5-108〜P5-111, P5-117 | top-level property・const・lateinit・object・init 順序 |
| 🟡 P2 中 | P5-121〜P5-124 | lambda it・extension property・field・provideDelegate |
| 🟡 P2 中 | P5-125〜P5-129 | Generics edge（F-bound・推論・variance・reified・SAM） |
| 🟡 P2 中 | P5-114/116 | diamond 継承・data object |
| 🟢 P3 低 | P5-130/131/132 | Null Safety edge（platform type・nullable receiver・nullable 型引数） |
| 🟢 P3 低 | P5-133〜P5-136 | Coroutine 拡張（withContext・Channel・async/await・cancellation） |
| 🟢 P3 低 | P5-137〜P5-139 | Stdlib DSL（スコープ関数・builder・Sequence） |
| 🟢 P3 低 | P5-140/141 | Multiplatform（expect/actual）・file annotation |
