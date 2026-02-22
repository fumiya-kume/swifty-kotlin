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

- [ ] P5-21: `try/catch/finally` の例外チャネル制御フローを KIR/Lowering で実装する（spec.md J11.3/J13.3）
  - [ ] BuildKIR の `tryExpr` lowering で catch/finally を捨てる現実装を置換し、分岐ブロックを生成する
  - [ ] catch parameter（`catch (e: E)` の `e`）をスコープへ束縛し、catch body で参照可能にする
  - [ ] 複数 catch 節を宣言順で評価し、例外型（`E`）に一致した節だけへ遷移する型マッチを実装する
  - [ ] `outThrown` を監視して catch へ遷移し、catch 未処理時は呼び出し元へ再送する経路を実装する
  - [ ] `finally` の常時実行順序（normal/exception 両経路）を保証する

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

- [ ] P5-36: import alias（`import a.b.C as X`）を解決規則へ組み込む（spec.md J5/J7）
  - [ ] `ImportDecl` に alias 情報を追加し、Parser/AST builder で `as` 句を保持する
  - [ ] `populateImportScopes` で alias 名を明示 import 優先順位に従って登録する
  - [ ] alias 衝突・未解決 import の診断を追加する

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
