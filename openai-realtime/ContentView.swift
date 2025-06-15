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
           
            List(Array(_assistant.messages.enumerated()), id: \.offset) { index, message in
                Text(message)
            }
        }
        .overlay(alignment: .bottom) {
            HStack{
                
              
                Spacer()
               
                Button {
                    _assistant.connect()
                } label: {
                    Label {
                        Text("聊天")
                    } icon: {
                        Image(systemName: "message")
                    }
                    

                }

                Spacer()
            }
            .padding()
        }
    }

    init() {
    }
}

#Preview {
    ContentView()
}
