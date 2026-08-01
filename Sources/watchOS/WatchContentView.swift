import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var recorder: WatchLocationRecorder
    @EnvironmentObject private var sender: WatchConnectivitySender

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: recorder.isRecording ? "location.fill" : "location.slash")
                .font(.title2)

            Text(recorder.isRecording ? "探索記録中" : "探索停止中")
                .font(.headline)

            Text("\(recorder.sampleCount)地点")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(recorder.isRecording ? "停止" : "探索開始") {
                recorder.isRecording ? recorder.stop() : recorder.start()
            }
            .tint(recorder.isRecording ? .red : .green)

            Text(sender.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = recorder.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }
}
