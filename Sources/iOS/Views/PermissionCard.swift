import CoreLocation
import SwiftUI

struct PermissionCard: View {
    @EnvironmentObject private var recorder: LocationRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("位置情報の許可")
                .font(.headline)
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                if recorder.authorizationStatus == .notDetermined {
                    Button("使用中のみ許可") {
                        recorder.requestWhenInUseAuthorization()
                    }
                    .buttonStyle(.borderedProminent)
                } else if recorder.authorizationStatus == .authorizedWhenInUse {
                    Button("常に許可へ進む") {
                        recorder.requestAlwaysAuthorization()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(recorder.isRecording ? "記録停止" : "記録開始") {
                    recorder.isRecording ? recorder.stopRecording() : recorder.startRecording()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var explanation: String {
        switch recorder.authorizationStatus {
        case .authorizedAlways:
            return "常時記録が有効です。iPhoneを再起動した後は一度アプリを開いてください。"
        case .authorizedWhenInUse:
            return "アプリ使用中は記録できます。閉じている間も記録するには「常に許可」が必要です。"
        case .denied, .restricted:
            return "設定アプリから位置情報を許可してください。"
        case .notDetermined:
            return "まず使用中の位置情報を許可し、その後で常時許可へ進みます。"
        @unknown default:
            return "位置情報の状態を確認できません。"
        }
    }
}
