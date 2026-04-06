# Kotlin Compiler Remaining Tasks

最終更新: 2026-04-01

---

## 運用ルール

- `TODO.md` は未完了タスクを主に管理しつつ、直近で完了した大きめの項目は `[x]` で残してよい。
- タスクIDはカテゴリ接頭辞 (`LEX/TYPE/EXPR/CTRL/DECL/CLASS/PROP/FUNC/GEN/NULL/CORO/STDLIB/ANNO/TOOL/MPP`) + 3桁連番を使用する。
- 完了済みタスクを参照する場合は `[x]` または `既存実装済み` のどちらかで明示する。
- 共通完了条件（全タスク共通）:
  1. `Scripts/diff_kotlinc.sh` が exit 0 かつ stdout 完全一致
  2. golden テストが byte 一致
  3. エラーケースで `KSWIFTK-*` 診断コード出力
  4. 各項目末尾エッジケース golden が通過

---

## 未完了バックログ

監査で見つかった「簡易実装（Stub）」や「中途半端なパス」を将来の改善項目として追跡する。

---

### Kotlin Stdlib 互換性（独立タスク）

#### Phase 1: 基本型と配列 (高優先度)


#### Phase 1: オブジェクト指向機能 (高優先度)


#### Phase 2: プロパティデリゲート (中優先度)


#### Phase 2: ジェネリクスと型システム (中優先度)

#### Phase 2: リフレクション (中優先度)

- [x] STDLIB-REFLECT-066: 型リフレクション完全実装
  - **仕様**: 型情報のリフレクションアクセス
  - **実装内容**:
    - KType: 型情報の表現 (RuntimeKTypeBox)
    - 型引数: arguments (RuntimeKTypeProjectionBox)
    - 分類: classifier (KClass raw handle)
    - null可能性: isMarkedNullable
    - ジェネリック型の分解
    - 配列型の要素型取得
    - 型射影: KTypeProjection (variance: IN/OUT/INVARIANT/STAR)
    - 文字列表現: toString()
  - **現状**: 完全実装済み - 全APIが利用可能
  - **関連ファイル**: `RuntimeReflection.swift`, `RuntimeStringArray.swift`, `RuntimeTypes.swift`
  - **テストケース**: `Scripts/diff_cases/type_reflection.kt`
  - **実装API**: kk_ktype_create, kk_ktype_classifier, kk_ktype_arguments, kk_ktype_isMarkedNullable, kk_ktype_to_string, kk_typeof, kk_ktypeprojection_create, kk_ktypeprojection_type, kk_ktypeprojection_variance

#### Phase 3: コルーチンと並行処理 (低優先度)


    - compareAndSet: CAS操作
    - getAndUpdate, updateAndGet: アトミック更新
  - **現状**: 完全実装済み (AtomicBoolean追加、getAndUpdate/updateAndGet全型対応)
  - **関連ファイル**: `RuntimeAtomic.swift`
  - **テストケース**: `Scripts/diff_cases/atomic_basic.kt`

#### Phase 3: 時間と期間 (低優先度)

  - **関連ファイル**: `RuntimeFileIO.swift`
  - **テストケース**: `Scripts/diff_cases/files_utility.kt`, `Scripts/diff_cases/buffered_io.kt`

#### Phase 3: I/Oとファイルシステム (低優先度)


#### Phase 3: 数学関数 (低優先度)

#### Phase 3: アノテーションとメタプログラミング (低優先度)

---

## 実装計画のまとめ

### 残タスク数: 16件

### 実装方針

1. **段階的実装**: Phase 1から順に実装し、各フェーズ完了後に評価
2. **網羅的テスト**: 各タスクに対応するテストケースを作成・維持
3. **一貫性維持**: 既存実装との互換性を確保しつつ機能拡張
4. **ドキュメント整備**: 実装仕様と使用例を詳細に記録

#### Phase 4: 高度コレクションとデータ構造 (低優先度)


#### Phase 4: シリアライゼーション (低優先度)

#### Phase 4: ネットワークとHTTP (低優先度)

#### Phase 4: データベースアクセス (低優先度)

- [ ] STDLIB-DB-140: JDBC基本実装

- [ ] STDLIB-DB-141: トランザクション管理完全実装

- [ ] STDLIB-DB-142: コネクションプール完全実装

#### Phase 4: ロギングとデバッグ (低優先度)

- [ ] STDLIB-LOG-147: ロギング基本実装

- [ ] STDLIB-LOG-148: ロギング高度機能完全実装

- [ ] STDLIB-LOG-149: アサーション完全実装
  - **仕様**: アサーションの完全サポート
  - **実装内容**:
    - assert関数: アサーション実行
    - assert関数（メッセージ付き）: アサーション実行（メッセージ付き）
    - assert関数（ラムダ式）: アサーション実行（ラムダ式）
    - assert関数（ラムダ式、メッセージ付き）: アサーション実行（ラムダ式、メッセージ付き）
  - **現状**: アサーションは未実装
  - **関連ファイル**: `RuntimeAssertions.swift`
  - **テストケース**: `Scripts/diff_cases/assertions.kt`

#### Phase 4: 国際化とローカライゼーション (低優先度)

- [ ] STDLIB-I18N-152: 数値フォーマット完全実装

- [ ] STDLIB-I18N-153: 日付フォーマット基本実装

#### Phase 4: パフォーマンスと最適化 (低優先度)

---

## テスト改善タスク

### 高優先度：テストカバレッジ拡充

- [ ] TEST-VAL-001: Value Classesテスト拡充 (現在4件→15件)
  - **追加内容**:
    - ボクシングの境界条件テスト
    - ジェネリクスとの組み合わせテスト
    - 配列とコレクションでの使用テスト
    - 継承とインターフェースのテスト
  - **関連ファイル**: `Scripts/diff_cases/value_class_*.kt`

- [ ] TEST-SCRIPT-002: Scriptモードテスト拡充 (現在3件→10件)
  - **追加内容**:
    - 複雑な式の評価テスト
    - トップレベル関数定義テスト
    - import文の使用テスト
    - REPL的な使用ケース
  - **関連ファイル**: `Scripts/diff_cases/script_*.kt`

- [ ] TEST-CORO-003: 高度なCoroutine機能テスト (現在29件→40件)
  - **追加内容**:
    - Structured Concurrencyテスト
    - Flowのバックプレッシャーテスト
    - Coroutineのエッジケース
    - Exception handling in coroutines
  - **関連ファイル**: `Scripts/diff_cases/*coroutine*.kt`

- [ ] TEST-ERR-004: エラーケースと診断コード網羅 (現在3件→20件)
  - **追加内容**:
    - 型推論エラーパターン (KSWIFTK-TYPE-*)
    - セマンティックエラーパターン (KSWIFTK-SEMA-*)
    - リンカエラーパターン (KSWIFTK-LINK-*)
    - 診断コードの網羅的テスト
  - **関連ファイル**: `Scripts/diff_cases/*error*.kt`

### 中優先度：テスト品質とインフラ改善

- [ ] TEST-SMOKE-005: Smoke Testsの軽微な拡充 (現在5件→8件)
  - **追加内容**:
    - 空ファイルのハンドリングテスト
    - 不正なUTF-8文字の処理テスト
    - 巨大ファイルの処理テスト
    - 複数ファイル入力の基本テスト
  - **関連ファイル**: `Tests/CompilerCoreTests/Integration/SmokeTests.swift`

- [ ] TEST-INT-006: Integration Testsの整理と重複削減
  - **改善内容**:
    - jscpdで検出された重複テストの統合
    - テストヘルパーの共通化
    - テストカテゴリの明確化 (Unit/Integration/E2E/Regression)
    - 2,460テストメソッドの整理
  - **関連ファイル**: `Tests/CompilerCoreTests/Integration/*.swift`

- [ ] TEST-CI-007: CIパイプラインの最適化
  - **改善内容**:
    - 並列実行の動的worker数調整
    - kotlincダウンロードのキャッシュ改善
    - タイムアウトの段階的短縮 (120→60分)
    - アーティファクト保持期間延長 (14→30日)
  - **関連ファイル**: `.github/workflows/ci.yml`

- [ ] TEST-REPORT-008: テストレポート形式の改善
  - **改善内容**:
    - TSV→JSON形式での詳細レポート
    - 失敗ケースの詳細情報追加
    - Golden Testsのスマート更新検出
    - 差分の可視化改善
  - **関連ファイル**: `Scripts/diff_kotlinc_ci_summary.sh`

### テスト改善の実装方針

1. **網羅性優先**: Value Classesとエラーケースから優先実装
2. **段階的追加**: 各カテゴリを段階的に拡充
3. **CI連携**: 新規テストはCIで自動実行されるように設定
4. **ドキュメント化**: 各テストケースの目的と期待結果を明記

- [ ] STDLIB-PERF-154: メモリ管理基本実装
  - **仕様**: メモリ管理の基本的な機能
  - **実装内容**:
    - メモリ使用量: Runtime.getRuntime().totalMemory()
    - 空きメモリ: freeMemory(), maxMemory()
    - ガベージコレクション: System.gc()
    - メモリリーク検出: メモリリークの検出ツール
    - パフォーマンス監視: メモリ使用量の監視
  - **現状**: メモリ管理は未実装
  - **関連ファイル**: `RuntimeMemory.swift`
  - **テストケース**: `Scripts/diff_cases/memory_management.kt`

---

#### Phase 5: 実験的機能と高度API (低優先度)

#### Phase 5: プラットフォーム固有機能 (低優先度)

- [ ] STDLIB-JVM-166: Javaプレビュー機能完全実装

- [ ] STDLIB-JS-167: JavaScript固有API完全実装

- [ ] STDLIB-NATIVE-168: Native固有API完全実装

- [x] STDLIB-NATIVE-169: プラットフォーム情報完全実装

#### Phase 5: 非推奨APIと移行 (低優先度)

#### Phase 5: 高度リフレクションとメタプログラミング (低優先度)

- [ ] STDLIB-REFL-172: メタデータAPI完全実装
  - **仕様**: kotlinx-metadata互換のメタデータAPI
  - **実装内容**:
    - KmFunction: 関数メタデータ
    - KmConstructor: コンストラクタメタデータ
    - KmAnnotation: アノテーションメタデータ
    - compilerPluginMetadata: コンパイラプラグインメタデータ
    - メタデータシリアライズ: メタデータのシリアライズ/デシリアライズ
  - **現状**: メタデータAPIは未実装
  - **関連ファイル**: `RuntimeMetadata.swift`
  - **テストケース**: `Scripts/diff_cases/metadata_api.kt`

- [ ] STDLIB-REFL-173: コンパイラプラグインAPI完全実装
  - **仕様**: コンパイラプラグインAPIの完全サポート
  - **実装内容**:
    - CommandProcessor: コンパイラコマンド処理
    - ExtensionRegistrar: 拡張登録
    - IrGenerationExtension: IR生成拡張
    - ClassBuilderInterceptor: クラスビルダーインターセプト
    - プラグインメタデータ: プラグイン情報の保存
  - **現状**: コンパイラプラグインAPIは未実装
  - **関連ファイル**: `CompilerPlugin.swift`
  - **テストケース**: `Scripts/diff_cases/compiler_plugin_api.kt`

- [ ] STDLIB-REFL-174: KSP（シンボル処理）基本実装
  - **仕様**: Kotlin Symbol Processingの基本的なサポート
  - **実装内容**:
    - SymbolProcessor: シンボルプロセッサインターフェース
    - KSPLogger: ロギング機能
    - Resolver: シンボル解決
    - CodeGenerator: コード生成
    - プロセッサ登録: プロセッサの登録と実行
  - **現状**: KSPは未実装
  - **関連ファイル**: `RuntimeKSP.swift`
  - **テストケース**: `Scripts/diff_cases/ksp_basic.kt`

- [ ] STDLIB-REFL-175: アノテーション処理高度機能完全実装
  - **仕様**: アノテーション処理の高度な機能
  - **実装内容**:
    - KAPT統合: Kotlin Annotation Processing Tool
    - ラウンド処理: 複数ラウンドの処理
    - 増分処理: 増分コンパイル対応
    - オプション管理: プロセッサオプション
    - エラー報告: コンパイルエラーの生成
  - **現状**: アノテーション処理は未実装
  - **関連ファイル**: `RuntimeKAPT.swift`
  - **テストケース**: `Scripts/diff_cases/annotation_processing.kt`

#### Phase 5: 高度Flowとコルーチン (低優先度)

- [ ] STDLIB-FLOW-176: Flow高度演算子完全実装
  - **仕様**: kotlinx.coroutinesの高度Flow演算子
  - **実装内容**:
    - 変換演算子: map, filter, transform, takeWhile, dropWhile
    - フラット化: flatMapConcat, flatMapMerge, flatMapLatest
    - 組合せ演算子: combine, zip, merge
    - バッファリング: buffer, conflate, flowOn
    - タイミング: debounce, sample, delayEach
  - **現状**: 基本的なFlowは実装済み、高度な演算子は未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_advanced_operators.kt`

- [ ] STDLIB-FLOW-177: SharedFlowとStateFlow完全実装
  - **仕様**: ホットストリームの完全サポート
  - **実装内容**:
    - SharedFlow: マルチキャストホットフロー
    - StateFlow: 状態保持ホットフロー
    - shareIn(): コールドフローからSharedFlowへの変換
    - stateIn(): コールドフローからStateFlowへの変換
    - リプレイキャッシュ: 過去値のキャッシュ機能
  - **現状**: SharedFlowとStateFlowは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/shared_state_flow.kt`

- [ ] STDLIB-FLOW-178: Flowビルダー完全実装
  - **仕様**: 全てのFlowビルダーの完全サポート
  - **実装内容**:
    - flowOf(): 固定値からのフロー生成
    - emptyFlow(): 空フロー生成
    - channelFlow(): チャネルベースのフロー
    - callbackFlow(): コールバックベースのフロー
    - asFlow(): コレクションからのフロー変換
  - **現状**: 基本的なflowビルダーは実装済み、高度なビルダーは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_builders.kt`

- [ ] STDLIB-FLOW-179: Flowエラーハンドリング完全実装
  - **仕様**: Flowの完全なエラーハンドリング
  - **実装内容**:
    - catch(): 上流例外の処理
    - retry(): 失敗時のリトライ
    - retryWhen(): 条件付きリトライ
    - onErrorReturn(): エラー時のデフォルト値
    - onErrorResume(): エラー時の代替フロー
  - **現状**: Flowエラーハンドリングは未実装
  - **関連ファイル**: `RuntimeCoroutine.swift`
  - **テストケース**: `Scripts/diff_cases/flow_error_handling.kt`

#### Phase 5: 高度時間測定 (低優先度)

- [ ] STDLIB-TIME-180: 実験的時間API完全実装
  - **仕様**: 実験的時間APIの完全サポート
  - **実装内容**:
    - @ExperimentalTime: 実験的時間APIマーカー
    - Clockインターフェース: 時計の抽象化
    - Clock.System: システム時計実装
    - TimeSource: 時間ソースの抽象化
    - TimeMark: 時間マークと差分計算
  - **現状**: 基本的な時間APIは実装済み、実験的APIは未実装
  - **関連ファイル**: `RuntimeTime.swift`
  - **テストケース**: `Scripts/diff_cases/experimental_time.kt`

- [ ] STDLIB-TIME-181: プラットフォーム時間変換完全実装
  - **仕様**: プラットフォーム固有の時間API変換
  - **実装内容**:
    - JVM: Instant.toJavaInstant(), java.time.Instant.toKotlinInstant()
    - JVM: Duration.toJavaDuration(), java.time.Duration.toKotlinDuration()
    - JS: Instant.toJSDate(), Date.toKotlinInstant()
    - Native: プラットフォーム固有時間API
    - 変換の安全性: 型安全な時間変換
  - **現状**: プラットフォーム時間変換は未実装
  - **関連ファイル**: `RuntimeTime.swift`
  - **テストケース**: `Scripts/diff_cases/platform_time_conversion.kt`

---

### 全体実装計画の最終更新

**残タスク数: 16件**

Phase 1-3の基盤タスクを優先し、Phase 4-5は段階的に実装します。
