//
//  RealtimeGPTAssistant.swift
//  openai-realtime
//
//  Created by Bart Trzynadlowski on 10/16/24.
//

import AVFoundation
import Starscream

fileprivate let systemPrompt = """
You are a helpful and friendly AI .
"""

class RealtimeGPTAssistant: ObservableObject {
    @Published var messages: [String] = []

    private var _socket:Starscream.WebSocket?
    private var _converter: AVAudioConverter?
    private let _outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!

    private var _isResponseInProgress = false
    private var _receivedAudioBase64: String = ""

    func connect() {
//        guard let apiKey = UserDefaults.standard.string(forKey: "openai_api_key") else {
//            messages.append("No API key! Please set it in app settings.")
//            return
//        }
       
        let url = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=qwen-omni-turbo-realtime-2025-05-08")!
      //  let url = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=qwen-omni-turbo-realtime")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \("sk-your-bailiankey")", forHTTPHeaderField: "Authorization")
        request.addValue("gummy-realtime-v1", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        _socket = Starscream.WebSocket(request: request)
        _socket?.delegate = self
        _socket?.connect()
    }
  
    
    func sendMessage(_ message: Encodable) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let jsonData = try? encoder.encode(message),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        _socket?.write(string: jsonString)
    }

    private func onSamplesReceived(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Convert to format expected by OpenAI and get raw bytes
        guard let audioBuffer = convertAudio(buffer) else { return }
        guard let sampleBytes = audioBuffer.audioBufferList.pointee.mBuffers.mData else { return }
        let sampleData = Data(bytes: sampleBytes, count: Int(audioBuffer.audioBufferList.pointee.mBuffers.mDataByteSize))

        // Send
        let msg = InputAudioBufferAppendEvent(audio: sampleData.base64EncodedString())
        sendMessage(msg)
    }

    private func convertAudio(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = getAudioConverter(inputFormat: buffer.format) else { return nil }
        guard let outputAudioBuffer = AVAudioPCMBuffer(pcmFormat: _outputFormat, frameCapacity: buffer.frameLength) else {
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

    private func getAudioConverter(inputFormat: AVAudioFormat) -> AVAudioConverter? {
        if _converter == nil {
            _converter = AVAudioConverter(from: inputFormat, to: _outputFormat)
            if _converter == nil {
                print("Error: Unable to create audio converter")
            }
        }
        return _converter
    }
}

extension RealtimeGPTAssistant: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(_):
            print("WebSocket connected")
            AudioManager.shared.startRecording(onSamplesRecorded: onSamplesReceived)

        case .text(let string):
            print("Received text: \(string)")

            guard let event = decodeServerEvent(from: string) else { break }

            switch event {
            case .sessionCreated(let sessionCreated):
                print("Got session created event")

                // Update session params
                var msg = SessionUpdateEvent(session: .init(sessionCreated.session))
                msg.session.instructions = systemPrompt
                msg.session.tools = [
                    Tool(
                        name: "get_weather",
                        description: "Local weather today",
                        parameters: .init(properties: [:], required: [])
                    )
                ]

                sendMessage(msg)

            case .sessionUpdated:
                print("Got session.updated")

            case .responseCreated:
                print("Got response.created")
                _isResponseInProgress = true

            case .responseDone(let responseDone):
                print("Got response.done")

                var text = ""
                var functionOutputs: [ConversationFunctionCallOutputItemCreateEvent] = []
                for item in responseDone.response.output {
                    switch item {
                    case .message(let message):
                        text += "\(message.role): "
                        for content in message.content {
                            if let contentText = content.transcript {
                                text += contentText
                                text += "\n"
                            }
                        }
                        text += "\n"

                    case .functionCall(let functionCall):
                        if functionCall.name == "get_weather" {
                            let result = ConversationFunctionCallOutputItemCreateEvent(item: .init(callId: functionCall.callId, output: "50F, cloudy, gusts up to 10 mph"))
                            functionOutputs.append(result)
                        }
                        text += "function_call: \(functionCall.name)(\(functionCall.arguments))"
                    }
                }

                _isResponseInProgress = false

                if functionOutputs.count > 0 {
                    _isResponseInProgress = true
                    for msg in functionOutputs {
                        sendMessage(msg)
                    }
                    sendMessage(ResponseCreateEvent(response: .init()))
                }

                DispatchQueue.main.async {
                    self.messages.append(text)
                }

            case .responseAudioDeltaEvent(let audioDelta):
                print("Got response.audio.delta")
                _receivedAudioBase64 += audioDelta.delta

            case .responseAudioDoneEvent:
                guard let data = Data(base64Encoded: _receivedAudioBase64) else { break }
                guard let buffer = AVAudioPCMBuffer.fromData(data, format: _outputFormat) else { break }
                AudioManager.shared.playSound(buffer: buffer, onFinished: {
                    //如何把说的语音转成mp3保存到文件app？
                    print("我说完了。。。。。。。。。。。。。。。。。。。。。。。。。。。。。。\n")
                })
                _receivedAudioBase64 = ""
            }

        case .disconnected(let reason, let code):
            print("WebSocket disconnected: \(reason) with code: \(code)")
            AudioManager.shared.stopRecording()

        case .error(let error):
            print("WebSocket error: \(error?.localizedDescription ?? "Unknown error")")

        default:
            break
        }
    }
}
