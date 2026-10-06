# 検証結果

検証日：2026-10-02（日本時間）。Apple Silicon Mac、Swift 6.2.3、Swift 5言語モード、macOS 13 deployment target。

## 実施済み

- Release最適化でネイティブarm64アプリのコンパイル成功。
- Info.plist検証、ad-hocコード署名検証成功。
- 独自アイコンをPNGからICNSへ生成しアプリへ組み込み。
- `./test.sh`：**331チェック成功**。全12キー、Custom axis全12種、全MIDI音高の反転、二度の反転によるpitch class復元、SMF再読み込み、開始・終了・ベロシティ・チャンネル・ON/OFF対応の保持、Running Status、velocity 0 Note Off、非ノートイベント保持、トラック別処理、ドラム除外、Blend、転回形、主要コードテンプレート、不正データ・全バイト位置での切断入力を検証。
- macOSの通常のLaunch Services経由でアプリ起動成功。ウィンドウ幅1180ポイントで実際のSwiftUI表示を取得し、主要ボタン、色分け、比較表示を目視確認。長い内容は中央領域をスクロールして利用するレイアウト。
- アプリの診断モードで、`NSItemProvider`のファイルURLを本番のドロップ受け入れ処理に渡し、デモ17ノートの読み込み・17ノートの変換・書き出しファイル生成に成功。
- 通常環境のAVMIDIPlayerでNegative再生開始を確認。`isPlaying = true`、再生位置が約1.03秒まで進行。エラーなし。音声を録音して波形／聴感評価したものではありません。

## 未検証

- Finderから手動でマウスを使ったドロップ、保存ダイアログでの手動保存。
- Logic Proがドラッグ書き出しを受け取り、音源を鳴らす一連の操作。
- 比較再生の全曲終了までの手動聴感テスト。
- Intel Macでの実行、別MacでのGatekeeper動作、全DAW・全MIDIファイルとの互換性。

GUI操作ツールがこのセッションでは利用できなかったため、ドロップ処理の検証は上記のファイル受け渡しによるものです。実際のマウス操作の成功とは区別しています。

## 再実行

```bash
./test.sh
./build.sh
mkdir -p /tmp/negative-harmony-qa
open -n "build/Negative Harmony MIDI Converter.app" --args --smoke-test /tmp/negative-harmony-qa
```

診断モードはデモMIDI、`gui-smoke.json`、表示中のウィンドウ画像`app-preview.png`を指定先に保存し、短いNegative再生を行って停止します。通常の起動ではこの処理は実行されません。
