//
//  ContentView.swift
//  openai-realtime
//
//  Created by Bart Trzynadlowski on 10/15/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var _assistant = RealtimeGPTAssistant()

    var body: some View {
        VStack {
            Button("Connect to Assistant") {
                _assistant.connect()
            }
            List(Array(_assistant.messages.enumerated()), id: \.offset) { index, message in
                Text(message)
            }
        }
    }

    init() {
    }
}

#Preview {
    ContentView()
}
