import CoreLocation
import SwiftUI

struct PermissionCard: View {
    @EnvironmentObject private var engine: LocationEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("位置情報の許可")
                .font(.headline)
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                if engine.authorizationStatus == .notDetermined {
                    Button("使用中のみ許可") {
                        engine.requestWhenInUseAuthorization()
                    }
                    .buttonStyle(.borderedProminent)
                } else if engine.authorizationStatus == .authorizedWhenInUse {
                    Button("常に許可へ進む") {
                        engine.requestAlwaysAuthorization()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(engine.isRecording ? "記録停止" : "記録開始") {
                    engine.isRecording ? engine.stop() : engine.start()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var explanation: String {
        switch engine.authorizationStatus {
        case .authorizedAlways:
            return "常時記録が有効です。アプリを閉じていても記録されます。"
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
