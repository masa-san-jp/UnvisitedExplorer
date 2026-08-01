# iPhone・Apple Watch位置履歴による未訪問エリア探索アプリ設計

作成日: 2026-08-01

## 1. 結論

実現可能。ただし、24時間の受動記録はiPhoneを主系とし、Apple Watchは手動開始型の補助系とする。

- iPhone: Core Locationの標準更新、バックグラウンド位置更新、significant-change monitoringを併用する。
- Apple Watch: ユーザーが「探索開始」を押した期間だけ位置を取得し、WatchConnectivityでiPhoneへ転送する。
- 保存: 初期状態はSwiftDataによる端末内保存。外部サーバー送信はしない。
- 可視化: 位置点をそのまま大量表示せず、Web Mercator上の250mグリッドへ集約して訪問済みレイヤーを描画する。
- 行動促進: 現在地周辺の未訪問グリッドを距離順に提案し、Apple Mapsの徒歩ルートを起動する。

## 2. Appleプラットフォーム上の制約

### 2.1 iPhone

「常に許可」とBackground ModesのLocation updatesを有効化すれば、アプリが前面でない間も位置更新を受け取れる。ただし、取得間隔はアプリが秒単位で完全指定するものではなく、移動状況、精度要求、電池状態、OS判断の影響を受ける。

ユーザーがアプリをApp Switcherから明示的に強制終了した場合、バックグラウンド位置イベントによる復帰を前提にしてはいけない。再起動後やアップデート後も、ユーザーが一度アプリを開く運用を採る。

### 2.2 Apple Watch

watchOSアプリは「常に許可」を得ても、位置イベントだけで任意に自動起動されるとは限らない。したがって、Watch単独の完全自動・無期限・常時ロガーとして設計しない。

Watch側は次の用途に限定する。

1. iPhoneを持たない散歩・探索時に手動で記録開始する。
2. 取得した位置をWatchConnectivityのバックグラウンド転送キューへ積む。
3. iPhone到達時にSwiftDataへ統合する。
4. 今後、未訪問候補や探索ストリークを表示する。

## 3. MVP機能

### 3.1 位置取得

- iPhone: 75m移動フィルタ、100m級精度、OSによる自動停止許可。
- Watch: 手動探索時のみ40m移動フィルタ、10m級精度。
- 500mを超える水平誤差のサンプルは破棄。
- 近接・短時間の重複サンプルを破棄。
- 取得元をiPhone / Apple Watchで識別。

### 3.2 訪問判定

緯度経度をWeb Mercator座標へ変換し、250m四方のセルへ量子化する。1件以上の有効サンプルが入ったセルを訪問済みとする。

セルには次を保存する。

- セルキー
- 初回訪問時刻
- 最終訪問時刻
- サンプル数
- グリッドX/Y
- セルサイズ

### 3.3 地図表示

- Apple Mapをベースマップとして使用。
- 訪問済みセルを半透明ポリゴンで表示。
- 現在地または最後の位置を中心に、近距離の未訪問セルを3件表示。
- 「未訪問へ」でApple Mapsの徒歩ルートを起動。

### 3.4 行動促進

MVPでは毎日10時のローカル通知を任意で有効化する。通知は位置履歴を外部送信せず、端末内でスケジュールする。

将来版では以下へ拡張する。

- 天候、営業時間、移動可能時間を加味した候補選定
- 公園、ギャラリー、カフェ等のPOIを未訪問セル内から検索
- 徒歩時間別の提案
- 連続探索日数、月間新規セル数、エリア達成率
- 自宅・職場など除外ゾーン

## 4. データ構造

### LocationSample

- id: UUID
- timestamp: Date
- latitude / longitude
- altitude
- horizontalAccuracy / verticalAccuracy
- speed / course
- source
- gridKey

### VisitedCell

- key
- gridX / gridY
- cellSizeMeters
- firstVisitedAt
- lastVisitedAt
- visitCount

## 5. プライバシー・セキュリティ

位置履歴は極めて機微性が高いため、次を初期要件とする。

- 端末内保存を既定にする。
- iCloud / 独自サーバー同期は明示的な追加機能とする。
- Data Protectionを有効化する。
- GeoJSON / CSVの明示的エクスポートを提供する。
- 全削除を1画面で実行可能にする。
- 位置権限がなくても既存履歴の閲覧と削除は可能にする。
- 自宅・職場などの秘匿ゾーン機能を次期必須要件とする。

## 6. 電池消費方針

常時最高精度GPSは採用しない。iPhoneは100m級精度と距離フィルタを使い、OSの自動停止を許可する。高精度はユーザーが明示的に開始した探索セッションだけに限定する。

## 7. 実装ファイル

- `Sources/iOS/Services/LocationRecorder.swift`: iPhone位置取得
- `Sources/iOS/Services/LocationStore.swift`: SwiftData保存・セル集約
- `Sources/iOS/Views/VisitedMapView.swift`: 地図と訪問済みレイヤー
- `Sources/iOS/Services/ExplorationSuggestionEngine.swift`: 未訪問候補生成
- `Sources/watchOS/WatchLocationRecorder.swift`: Watch手動探索
- `Sources/watchOS/WatchConnectivitySender.swift`: iPhone転送
- `Sources/iOS/Services/WatchConnectivityReceiver.swift`: Watchデータ受信

## 8. 完了条件

MVPの完了条件は次のとおり。

1. iPhone実機で「常に許可」を取得できる。
2. 画面ロック後に移動し、位置サンプルが追加される。
3. 訪問済みセルが地図に追加される。
4. 未訪問セルを選ぶと徒歩ルートが起動する。
5. Watchで探索開始・停止ができる。
6. Watch取得点がiPhoneへ転送され、取得元がApple Watchとして保存される。
7. GeoJSON / CSVが書き出せる。
8. 全履歴を削除できる。
9. 1時間の実地試験でクラッシュしない。
10. 8時間のバックグラウンド試験で許容可能な電池消費か測定できる。

## 9. 次に必要な作業

このプロトタイプはソースコードとXcodeGen定義まで作成済み。macOS上でXcodeGenを実行し、Development Team、実機署名、Watchターゲットの埋め込み状態を確認してビルドする。その後、実地で取得頻度・電池消費・Watch転送の信頼性を測定し、距離フィルタを調整する。
