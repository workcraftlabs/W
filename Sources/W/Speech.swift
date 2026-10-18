import Speech
import AVFoundation

@MainActor final class SpeechInput: ObservableObject {
    @Published var listening = false
    @Published var error = ""
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    func start(onText: @escaping (String) -> Void) async {
        error = ""
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard speech == .authorized, mic else { error = "Enable Microphone and Speech Recognition in System Settings, or type your task."; return }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "On-device dictation isn't available for this language. Type your task instead."; return
        }
        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true; self.request = request
        let input = engine.inputNode, format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { error = "No microphone available."; return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        do { engine.prepare(); try engine.start(); listening = true }
        catch { self.error = error.localizedDescription; stop(); return }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result { onText(result.bestTranscription.formattedString) }
                if error != nil || result?.isFinal == true { self?.stop() }
            }
        }
    }
    func stop() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; listening = false
    }
}
