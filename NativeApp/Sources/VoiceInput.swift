import AVFoundation
import Combine
import Speech

// MARK: - 音声入力（ネイティブ実装・Web版では非対応だった機能）
// 長年安定のAPIのみ使用（requestAuthorization / requestRecordPermissionのコールバック版）
@MainActor
final class VoiceTranscriber: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var errorMessage: String?

    private var recognizer: SFSpeechRecognizer? =
        SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    func toggle(onText: @escaping (String) -> Void) async {
        if isRecording {
            stop()
            return
        }
        await start(onText: onText)
    }

    private func start(onText: @escaping (String) -> Void) async {
        errorMessage = nil
        guard let recognizer else {
            errorMessage = "音声認識が使えません"
            return
        }
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else {
            errorMessage = "設定で音声認識を許可してください"
            return
        }
        let micOK = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micOK else {
            errorMessage = "設定でマイクを許可してください"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "マイクの準備に失敗しました"
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                self?.request?.append(buffer)
            }
        }
        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in onText(text) }
            if result.isFinal {
                Task { @MainActor in self.stop() }
            }
        }
        engine.prepare()
        do {
            try engine.start()
            isRecording = true
        } catch {
            errorMessage = "録音を開始できませんでした"
            stop()
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
