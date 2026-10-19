import Speech
import AVFoundation

@MainActor final class SpeechInput: ObservableObject {
    @Published var starting = false
    private var generation = UUID()
    @Published var listening = false
    @Published var error = ""
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    func start(onText: @escaping (String) -> Void) async {
        guard !starting, !listening else { return }
        stop()
        let generation = self.generation
        starting = true
        defer { if self.generation == generation { starting = false } }
        error = ""
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard self.generation == generation else { return }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard self.generation == generation else { return }
        guard speech == .authorized, mic else { error = "Enable Microphone and Speech Recognition in System Settings, or type your task."; return }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "On-device dictation isn't available for this language. Type your task instead."; return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true; self.request = request
        let input = engine.inputNode, format = engine.inputNode.outputFormat(forBus: 0)
        let hardware = input.inputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0, format.sampleRate > 0, format.channelCount > 0 else { error = "No microphone available."; return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        do { engine.prepare(); try engine.start(); listening = true }
        catch { self.error = error.localizedDescription; stop(); return }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if let result { onText(result.bestTranscription.formattedString) }
                if error != nil || result?.isFinal == true { self.stop() }
            }
        }
    }
    func stop() {
        generation = UUID()
        starting = false
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); task?.cancel(); task = nil; request = nil; listening = false
    }
}
