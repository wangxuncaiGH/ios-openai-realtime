//
//  AudioManager.swift
//  openai-realtime
//
//  Created by Bart Trzynadlowski on 10/16/24.
//

import AVFoundation

class AudioManager {
    static let shared = AudioManager()

    private var _audioEngine = AVAudioEngine()
    private var _playerNode = AVAudioPlayerNode()
    private var _isRunning = false
    private var _outputConverter: AVAudioConverter?

    private init() {
   }

    func startRecording(onSamplesRecorded: @escaping AVAudioNodeTapBlock) {
        guard !_isRunning else { return }
        startAudioEngine()
        let inputFormat = _audioEngine.inputNode.outputFormat(forBus: 0)
        _audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat, block: onSamplesRecorded)
    }

    func stopRecording() {
        guard _isRunning else { return }
        log("Stopping audio manager")
        _audioEngine.inputNode.removeTap(onBus: 0)
        _audioEngine.stop()
        tearDownAudioGraph()
        _isRunning = false
    }

    private func startAudioEngine() {
        guard !_isRunning else { return }
        setupAudioSession()
        setupAudioGraph()
        _audioEngine.prepare()
        do {
            try _audioEngine.start()
            log("Started audio engine")
            _isRunning = true
        } catch {
            log("Error: Unable to start audio engine: \(error.localizedDescription)")
            tearDownAudioGraph()
        }
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [ .defaultToSpeaker ])
            try audioSession.setActive(true)//, options: .notifyOthersOnDeactivation)
        } catch {
            log("Error: Unable to set up audio session: \(error.localizedDescription)")
        }
    }

    private func setupAudioGraph() {
        _audioEngine.attach(_playerNode)
        let mainMixer = _audioEngine.mainMixerNode
        let inputFormat = _audioEngine.inputNode.outputFormat(forBus: 0)
        _audioEngine.connect(_playerNode, to: mainMixer, format: inputFormat)

        // For some godforsaken reason, if you call this *before* the first call to
        // _audioEngine.attach(), everything breaks and no audio is received
        do {
            try _audioEngine.inputNode.setVoiceProcessingEnabled(true)
        } catch {
            log("Error: Failed to enable voice processing: \(error.localizedDescription)")
        }
    }

    private func tearDownAudioGraph() {
        _audioEngine.disconnectNodeInput(_playerNode)
        _audioEngine.disconnectNodeOutput(_playerNode)
    }

    func playSound(buffer: AVAudioPCMBuffer, onFinished: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let convertedBuffer = convertAudioToOutputFormat(buffer) else { return }
            _playerNode.stop()
            _playerNode.scheduleBuffer(convertedBuffer, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                log("Finished playback")
                DispatchQueue.main.async {
                    onFinished?()
                }
            }
            _playerNode.play()
        }
    }

    private func getOutputAudioConverter(inputFormat: AVAudioFormat) -> AVAudioConverter? {
        let outputFormat = _playerNode.outputFormat(forBus: 0)

        if let converter = _outputConverter {
            if converter.inputFormat == inputFormat {
                return converter
            }
        }

        _outputConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
        return _outputConverter
    }

    private func convertAudioToOutputFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = getOutputAudioConverter(inputFormat: buffer.format) else { return nil }

        if buffer.format == converter.outputFormat {
            return buffer
        }

        let outputFrameCapacity = AVAudioFrameCount(ceil(converter.outputFormat.sampleRate / buffer.format.sampleRate) * Double(buffer.frameLength))
        guard let outputAudioBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: outputFrameCapacity) else {
            print("Error: Unable to allocate output buffer for conversion")
            return nil
        }

        var error: NSError?
        var allSamplesReceived = false
        converter.convert(to: outputAudioBuffer, error: &error, withInputFrom: { (inNumPackets: AVAudioPacketCount, outError: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
            if allSamplesReceived {
                outError.pointee = .noDataNow
                return nil
            }
            allSamplesReceived = true
            outError.pointee = .haveData
            return buffer
        })

        guard error == nil else {
            print("Error: Failed to convert audio: \(error!.localizedDescription)")
            return nil
        }

        return outputAudioBuffer
    }
}

fileprivate func log(_ message: String) {
    print("[AudioManager] \(message)")
}
