# 未踏マップ / UnvisitedExplorer

iPhoneとApple Watchの位置履歴から訪問済みエリアを250mグリッドで可視化し、近隣の未訪問エリアへ移動するきっかけを作るSwiftUIプロトタイプです。

## 実装済み

- iPhoneのCore Locationバックグラウンド記録
- Significant-change location monitoring
- SwiftDataへの端末内保存
- 訪問済み250mグリッドのMapKitレイヤー表示
- 現在地付近の未訪問セル提案
- Apple Maps徒歩ルート起動
- 日次リマインダー
- GeoJSON / CSVエクスポート
- Apple Watchの手動探索記録とWatchConnectivity転送

## 起動

```bash
cd UnvisitedExplorer
make project
```

XcodeでDevelopment Teamを選択し、iPhone実機で実行してください。位置情報の「常に許可」は、最初に「Appの使用中」を許可した後に要求します。

## 重要な制約

- iPhoneでユーザーがアプリを明示的に強制終了した場合、位置イベントによる自動再起動は期待できません。
- Apple WatchはOSによる自動起動が保証されないため、Watch側はユーザーが「探索開始」を押したセッションだけを記録します。
- バックグラウンド位置情報は電池消費とApp Reviewの審査理由になるため、用途説明・停止操作・データ削除を明確にしています。
- この環境にはXcodeとApple SDKがないため、Swift構文検査まで実施し、実機ビルドと署名はmacOS上で行う必要があります。
