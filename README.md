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

## 訪問判定の用例と設計の背景

ここでの「訪問済み」は、採用された位置サンプルが属するセルを記録した状態です。例えば精度・鮮度・重複の検査を通った二つの点が同じセルに入れば、そのセルの訪問回数と日時を更新します。セル全域を歩いたことや、測位されなかった経路を通過したことの証明ではありません。

[LocationStore](Sources/iOS/Services/LocationStore.swift)が採用・保存をまとめ、[GeoGrid](Sources/Shared/GeoGrid.swift)が緯度経度をMercator座標へ投影してセルを決めます。現在の250mは**投影座標上のセル辺長**であり、地表上でどの緯度でも正確に250mとなる意味ではありません。仕様書の等角グリッド案と現在の実装方式は異なるため、現在の判定はコードを参照してください。

[仕様書](docs/mitou-map-ios-app-specification.md)は、日常の行動範囲を広げる動機と、端末内でデータを保持・取り出せることを重視しています。誤った位置で訪問済みにするより、不確かな点を採用しない方針も説明されています。250mは試作の既定粒度であり、最適性が実証された値とは扱いません。

## 成立と次の展開

2026年8月1日付の仕様・初期実装から、[8月3日の過去データインポート](https://github.com/masa-san-jp/UnvisitedExplorer/commit/178ab17df29d22cf56a5347eb5c1d8b28956096e)や[記録経路別の計測](https://github.com/masa-san-jp/UnvisitedExplorer/commit/1ec57ad03d1c7e84847dc65c74b844b03439c35b)へ整備が進んでいます。既存の位置履歴を引き継ぎ、どの記録経路が働いたかを確かめるための拡張です。

今後の評価では、実機移動での欠損・誤記録・電池消費と探索提案の有用性を確認します。仕様中のiCloud同期や地域統計連携などは構想として区別し、OSのバックグラウンド動作や常時記録を保証するものとは扱いません。
