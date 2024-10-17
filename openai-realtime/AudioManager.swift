//
//  AudioManager.swift
//  openai-realtime
//
//  Created by Bart Trzynadlowski on 10/16/24.
//

import AVFoundation

class AudioManager {
    static let shared = AudioManager()

    private var _isRunning = false
    private var _audioEngine = AVAudioEngine()
    private var _silenceInputMixerNode = AVAudioMixerNode()
    private var _playerNode = AVAudioPlayerNode()
    private var _outputConverter: AVAudioConverter?
    private var _pendingBuffers: [(buffer: AVAudioPCMBuffer, onFinished: (() -> Void)?)] = []

    var isPlaying: Bool {
        return _pendingBuffers.count > 0
    }

    func startRecording(onSamplesRecorded: @escaping AVAudioNodeTapBlock) {
        if !_isRunning {
            start()
        }
        let format = _silenceInputMixerNode.outputFormat(forBus: 0)
        _silenceInputMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format, block: onSamplesRecorded)
    }

    func stopRecording() {
        _silenceInputMixerNode.removeTap(onBus: 0)
    }

    func playSound(buffer: AVAudioPCMBuffer, onFinished: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let convertedBuffer = convertAudioToOutputFormat(buffer) else { return }
            _pendingBuffers.append((buffer: convertedBuffer, onFinished: onFinished))
            if _pendingBuffers.count == 1 {
                log("Playing first buffer")
                playNextBuffer()
            }
        }
    }

    // Execute on main queue
    private func playNextBuffer() {
        if let buffer = _pendingBuffers.first {
            log("Playing next buffer...")
            _playerNode.play()
            _playerNode.scheduleBuffer(buffer.buffer, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                log("Finished playback")
                DispatchQueue.main.async {
                    self._playerNode.stop() // not really needed
                    self._pendingBuffers.removeFirst()
                    self.playNextBuffer()
                    buffer.onFinished?()
                }
            }
        } else {
            log("Finished playing all pending buffers")
        }
    }

    private func start() {
        guard !_isRunning else { return }
        setupAudioSession()
        setupAudioGraph()
        startAudioEngine()
        _isRunning = true
    }

    private func stop() {
        guard _isRunning else { return }
        log("Stopping audio manager")
        _audioEngine.stop()
        tearDownAudioGraph()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [ .defaultToSpeaker ])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            log("Error: AVAudioSession: \(error)")
        }
    }

    private func setupAudioGraph() {
        // Feed input into mixer node that suppresses audio to avoid feedback while recording. For
        // some reason, need to reduce input volume to 0 (which doesn't affect taps on this node,
        // evidently). Output volume has no effect unless changed *after* the node is attached to
        // the engine and then ends up silencing output as well.
        _silenceInputMixerNode.volume = 0
        _audioEngine.attach(_silenceInputMixerNode)

        // Input node -> silencing mixer node
        let inputNode = _audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        _audioEngine.connect(inputNode, to: _silenceInputMixerNode, format: inputFormat)

        // Connect to main mixer node. We can change the number of samples but not the sample rate
        // here.
        let mainMixerNode = _audioEngine.mainMixerNode
        let mixerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)
        _audioEngine.connect(_silenceInputMixerNode, to: mainMixerNode, format: mixerFormat)

        // Create an output node for playback
        _audioEngine.attach(_playerNode)    // output player
        _audioEngine.connect(_playerNode, to: _audioEngine.mainMixerNode, format: mixerFormat)

        // Start audio engine
        _audioEngine.prepare()
    }

    private func tearDownAudioGraph() {
        _audioEngine.disconnectNodeInput(_silenceInputMixerNode)
        _audioEngine.disconnectNodeOutput(_silenceInputMixerNode)
        _audioEngine.disconnectNodeInput(_playerNode)
        _audioEngine.disconnectNodeOutput(_playerNode)
        _audioEngine.disconnectNodeInput(_audioEngine.inputNode)
        _audioEngine.disconnectNodeOutput(_audioEngine.inputNode)
        _audioEngine.disconnectNodeInput(_audioEngine.mainMixerNode)
        _audioEngine.disconnectNodeOutput(_audioEngine.mainMixerNode)
        _audioEngine.detach(_silenceInputMixerNode)
        _audioEngine.detach(_playerNode)
    }

    private func startAudioEngine() {
        do {
            try _audioEngine.start()
            log("Started audio engine")
        } catch {
            log("Error: Could not start audio engine: \(error)")
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
