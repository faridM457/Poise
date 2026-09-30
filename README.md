# Poise

Poise is an iPhone app for practicing the workplace conversations people put off: giving hard feedback, setting a boundary, saying no to your boss, managing up, and the genuinely difficult talks every manager eventually faces. You have the conversation out loud with an AI coworker who speaks, reacts in character, and pushes back like a real person, then get specific feedback on how it went.

Built for first-time managers, and anyone about to have a conversation they'd rather not wing.

## Features

- **Curriculum:** 5 units and 26 conversations (Foundations, Giving Feedback, Setting Boundaries, Managing Up, Hard Conversations), each unit ending in a checkpoint that combines its skills.
- **A fresh scenario every time:** each lesson is an authored template (the situation, what can't change, how the other person behaves), and the engine generates a concrete new instance of it on every run.
- **A coworker who talks back:** original characters (illustrated in Adobe Illustrator, animated in Adobe Character Animator), each with its own voice synthesized on-device.
- **Speak or type:** on-device dictation that keeps filler words, with playback of your own recordings.
- **Specific feedback:** whether you met the lesson's goals, plus clarity, empathy, and resolution, with notes on what you actually said.
- **Voice analysis (Pro):** pace, pitch variation, and filler words measured on-device, with a delivery grade.
- **Custom scenarios (Pro):** describe the conversation you're dreading and practice it.
- **Habit tools:** streaks, a weekly goal, badges, a practice calendar, and push reminders.

## How it works

```
iPhone app (SwiftUI)                         conversation-engine (Node.js)
  - lessons, progress, UI                      - scenario -> opening -> turns -> feedback
  - on-device TTS (Pocket TTS)    HTTPS -->    - energy ledger, conversation tokens,
  - on-device dictation + voice                  rate limits (SQLite)
    analysis (recordings stay                  - Claude Haiku 4.5 via Amazon Bedrock
    on the phone)
```

- **App:** native SwiftUI. Progress syncs through iCloud key-value storage; Sign in with Apple keeps a subscription recognized across devices.
- **Conversation engine:** Express server on AWS Lightsail. Each lesson is a pipeline of schema-constrained model calls: generate the scenario from its template, generate a neutral opening line, then for each turn generate the reply and grade it against the lesson's criteria, and finally grade the whole transcript. The server also enforces practice energy, signs conversation tokens, rate-limits, and resists prompt injection.
- **Voice on the device:**
  - Text-to-speech: [Pocket TTS](https://github.com/kyutai-labs/pocket-tts) via the Rust/Candle port [pocket-tts-ios](https://github.com/UnaMentis/pocket-tts-ios), with custom character voices.
  - Dictation: Apple's `SpeechAnalyzer` / `SpeechTranscriber`.
  - Delivery analysis: the `PoiseVoiceAnalysis` Swift package in `voice-analysis/` (AVFoundation decoding, Apple Speech word timestamps, and a bundled pitch detector run in JavaScriptCore). Only a small numeric summary is sent for grading, and only for Pro users.
- **Monetization and engagement:** RevenueCat (subscriptions and ad-revenue tracking), one non-personalized AdMob interstitial after a lesson for free users (with Google's consent flow in the EEA, UK and Switzerland), and OneSignal push reminders.

## Repository layout

| Path | What's there |
| --- | --- |
| `Poise/` | The iOS app: `App`, `Features`, `Components`, `Models`, `Services`, `Theme` |
| `OneSignalNotificationServiceExtension/` | Push notification service extension |
| `conversation-engine/` | Node.js server (`server/`), lesson templates (`server/lessons.js`), local test site (`public/`) |
| `voice-analysis/` | On-device delivery analysis package (Swift + bundled JavaScript) |
| `Frameworks/PocketTTS.xcframework/` | Pocket TTS headers; the libraries are built separately (see below) |
| `ONESIGNAL_CONTRACT.md` | Tags, events, and launch URLs the app sends to OneSignal |

## Running it locally

### Conversation engine

```sh
cd conversation-engine
npm install
cp .env.example .env    # fill in AWS credentials, region, and the other values it documents
npm start               # http://localhost:3000
```

Node 22 or later (the energy ledger uses the built-in `node:sqlite`). Set `ENGINE_DRY_RUN=true` in `.env` to stub the model entirely and make no paid calls.

### iOS app

Requires Xcode 26 or later; the app targets iOS 26.5. Debug builds talk to `http://localhost:3000`, so run the engine first (a physical phone needs a tunnel to reach your Mac).

Some large or licensed assets are not checked in (see `.gitignore`) and must be supplied before the app builds:

- `Poise/Resources/Models/model.safetensors` and `tokenizer.model`: the Pocket TTS model from Kyutai.
- `Frameworks/PocketTTS.xcframework/*/libpocket_tts_ios.a`: build from [UnaMentis/pocket-tts-ios](https://github.com/UnaMentis/pocket-tts-ios) at commit `ce0a41d` with `scripts/build-ios.sh`. The checked-in headers and `Poise/Services/PocketTTS/pocket_tts_ios.swift` must come from the same build.
- `Poise/Resources/CharacterAnimations/*.mp4`: the character animation clips.

Then open `Poise.xcodeproj`, select the `Poise` scheme, and run.

## Privacy

Voice recordings never leave the device and are deleted when a lesson ends. The text of a conversation is sent to the conversation engine and Amazon Bedrock to generate replies and feedback, and isn't stored afterward. Full details are in the [privacy policy](https://sapersolutions.com/poise/privacy).

## Links

- Privacy policy: https://sapersolutions.com/poise/privacy
- Terms of use: https://sapersolutions.com/poise/terms

Published by Saper Solutions LLC.
