# OpenAI Realtime API on iOS with SwiftUI

This is a minimalistic example of OpenAI's new [Realtime API](https://platform.openai.com/docs/guides/realtime) for iOS with SwiftUI.
The microphone is turned off when the assistant is formulating or speaking a response in order to prevent feedback from the speaker
triggering more assistant responses, so it is not interruptible.

A single function, `get_weather`, is implemented, so you can ask, for example, "What should I wear today?"

![Meme](docs/farmer.jpg)

It ain't much... but it'll get you started.