//
//  Models.swift
//  openai-realtime
//
//  Created by Bart Trzynadlowski on 10/15/24.
//
//  TODO
//  ----
//  - conversation.item.create items (client -> server) should be handled the way received
//    realtime.item (or indeed, server events themselves) are: using an enum of different possible
//    objects. Here, we have created multiple conversation.item.create structures just to handle
//    the different item types.
//

import Foundation

// MARK: Server and client objects

struct Event: Decodable {
    let type: String
}

struct Content: Codable {
    var type: String
    var text: String?
    var audio: String?
    var transcript: String?
}

struct TurnDetection: Codable {
    var type: String = "server_vad"
    var threshold: Float = 0.5
    var prefixPaddingMs: Int = 300
    var silenceDurationMs: Int = 200
}

struct Tool: Codable {
    var type: String = "function"
    var name: String
    var description: String
    var parameters: Parameters

    struct Parameters: Codable {
        var type: String = "object"
        var properties: [String: Property]
        var required: [String]

        struct Property: Codable {
            var type: String
            var description: String?
        }
    }
}

// MARK: Client objects

struct SessionUpdateEvent: Encodable {
    var eventId: String?
    let type: String = "session.update"
    var session: Session

    struct Session: Codable {
        var model: String
        var modalities: [String]
        var instructions: String
        var voice: String
        var inputAudioFormat: String
        var outputAudioFormat: String
        var inputAudioTranscription: String?
        var turnDetection: TurnDetection
        var tools: [Tool]
        var toolChoice: String
        var temperature: Float
        var maxOutputTokens: Int?

        init(_ session: RealtimeSession) {
            model = session.model
            modalities = session.modalities
            instructions = session.instructions
            voice = session.voice
            inputAudioFormat = session.inputAudioFormat
            outputAudioFormat = session.outputAudioFormat
            inputAudioTranscription = session.inputAudioTranscription
            turnDetection = session.turnDetection
            tools = session.tools
            toolChoice = session.toolChoice
            temperature = session.temperature
            maxOutputTokens = session.maxOutputTokens
        }
    }
}

struct ResponseCreateEvent: Encodable {
    var eventId: String?
    let type: String = "response.create"
    var response: Response

    struct Response: Encodable {
        var modalities: [String]?
        var instructions: String?
        var voice: String?
        var outputAudioFormat: String?
        var temperature: Float?
        var maxOutputTokens: Int?
    }
}

struct ConversationMessageItemCreateEvent: Encodable {
    var eventId: String?
    let type: String = "conversation.item.create"
    var previousItemId: String?
    var item: MessageItem

    struct MessageItem: Encodable {
        var id: String?
        var type: String = "message"
        var status: String?
        var role: String
        var content: [Content]
    }
}

struct ConversationFunctionCallOutputItemCreateEvent: Encodable {
    var eventId: String?
    let type: String = "conversation.item.create"
    var previousItemId: String?
    var item: FunctionCallOutputItem

    struct FunctionCallOutputItem: Encodable {
        var id: String?
        var type: String = "function_call_output"
        var callId: String
        var output: String
    }
}

struct InputAudioBufferAppendEvent: Encodable {
    var eventId: String?
    let type = "input_audio_buffer.append"
    var audio: String
}

// MARK: Server objects

struct RealtimeSession: Decodable {
    var id: String
    var object: String = "realtime.session"
    var model: String
    var modalities: [String]
    var instructions: String
    var voice: String
    var inputAudioFormat: String
    var outputAudioFormat: String
    var inputAudioTranscription: String?
    var turnDetection: TurnDetection
    var toolChoice: String
    var tools: [Tool]
    var temperature: Float
    var maxOutputTokens: Int?
}

struct RealtimeMessageItem: Decodable {
    let id: String
    let object: String
    let status: String
    let role: String
    let content: [Content]
}

struct RealtimeFunctionCallItem: Decodable {
    let id: String
    let object: String
    let status: String
    let name: String
    let callId: String
    let arguments: String
}

enum RealtimeItem: Decodable {
    case message(RealtimeMessageItem)
    case functionCall(RealtimeFunctionCallItem)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ItemType: String, Codable {
        case message = "message"
        case functionCall = "function_call"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)

        // Decode based on "type" field
        switch type {
        case .message:
            let event = try RealtimeMessageItem(from: decoder)
            self = .message(event)

        case .functionCall:
            let event = try RealtimeFunctionCallItem(from: decoder)
            self = .functionCall(event)
        }
    }
}

struct SessionCreatedEvent: Decodable {
    let eventId: String?
    var session: RealtimeSession
}

struct SessionUpdatedEvent: Decodable {
    let eventId: String?
    var session: RealtimeSession
}

struct Response: Decodable {
    let id: String
    let object: String
    let status: String
    let output: [ RealtimeItem ]
}

struct ResponseCreatedEvent: Decodable {
    let eventId: String?
    let response: Response
}

struct ResponseDoneEvent: Decodable {
    let eventId: String?
    let response: Response
}

struct ResponseAudioDeltaEvent: Decodable {
    let eventId: String?
    let responseId: String?
    let itemId: String?
    let outputIndex: Int
    let contentIndex: Int
    let delta: String
}

struct ResponseAudioDoneEvent: Decodable {
    let eventId: String?
    let responseId: String?
    let itemId: String?
    let outputIndex: Int
    let contentIndex: Int
}

enum ServerEvent: Decodable {
    case sessionCreated(SessionCreatedEvent)
    case sessionUpdated(SessionUpdatedEvent)
    case responseCreated(ResponseCreatedEvent)
    case responseDone(ResponseDoneEvent)
    case responseAudioDeltaEvent(ResponseAudioDeltaEvent)
    case responseAudioDoneEvent(ResponseAudioDoneEvent)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum EventType: String, Codable {
        case sessionCreated = "session.created"
        case sessionUpdated = "session.updated"
        case responseCreated = "response.created"
        case responseDone = "response.done"
        case responseAudioDelta = "response.audio.delta"
        case responseAudioDone = "response.audio.done"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)

        // Decode based on "type" field
        switch type {
        case .sessionCreated:
            let event = try SessionCreatedEvent(from: decoder)
            self = .sessionCreated(event)

        case .sessionUpdated:
            let event = try SessionUpdatedEvent(from: decoder)
            self = .sessionUpdated(event)

        case .responseCreated:
            let event = try ResponseCreatedEvent(from: decoder)
            self = .responseCreated(event)

        case .responseDone:
            let event = try ResponseDoneEvent(from: decoder)
            self = .responseDone(event)

        case .responseAudioDelta:
            let event = try ResponseAudioDeltaEvent(from: decoder)
            self = .responseAudioDeltaEvent(event)

        case .responseAudioDone:
            let event = try ResponseAudioDoneEvent(from: decoder)
            self = .responseAudioDoneEvent(event)
        }
    }
}

// MARK: Server object decoding

func decodeServerEvent(from json: String) -> ServerEvent? {
    guard let jsonData = json.data(using: .utf8) else { return nil }
    do {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ServerEvent.self, from: jsonData)
    } catch {
        print("Error: Unable to decode server event from JSON: \(error.localizedDescription)")
    }
    return nil
}
