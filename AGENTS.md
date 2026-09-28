# Poise Project Rules

## Source Control And Attribution

- Do not initialize a Git repository.
- Do not run `git add`, `git commit`, `git push`, `git tag`, or modify Git remotes.
- Do not change `git user.name`, `git user.email`, or any Git configuration.
- Do not add `Co-authored-by`, `Generated-by`, `AI-generated`, `Codex`, `OpenAI`, or other AI attribution.
- Do not add author or copyright headers to new Swift files.
- Preserve any existing file headers without changing their authorship.
- Leave every change as ordinary uncommitted local files for review.
- Do not alter the bundle identifier, development team, signing configuration, or deployment target unless compilation absolutely requires it.

## Design Requirements

- Build Poise as a polished, interactive, native SwiftUI prototype for iPhone portrait.
- Preserve the approved visual identity from the eight reference JPGs: friendly rounded typography, deep navy text, Poise blue actions, mint completions, gold/orange rewards, pale blue panels, soft gray backgrounds, large rounded corners, subtle shadows, and tactile lower button edges.
- Do not recreate the desktop sidebar or right-side information column on iPhone.
- Keep the app original. It may be inspired by friendly progression apps, but must not copy Duolingo branding, assets, characters, wording, exact layouts, or proprietary visual elements.
- Use Swift and SwiftUI only. Do not use WebView, third-party dependencies, analytics, authentication, cloud storage, RevenueCat, StoreKit, voice analysis, video analysis, push notifications, or API keys embedded in the app.
- Networking and LLM calls ARE allowed, but only to the local `conversation-engine` dev server (`http://localhost:3000`) for real lesson content generation and grading -- never a direct third-party/LLM API call from the app itself, and no other network destination. This is a deliberate, narrow exception (added when the first real lesson was wired live) to the "no networking" rule above; it is not a general green light for arbitrary networking.
- Most lessons still use local mock data and local state, per the original design -- only lessons with a `LessonNode.engineLessonId` talk to the local server.
- NPC dialogue in the live lesson flow is spoken aloud via Pocket TTS (`Frameworks/PocketTTS.xcframework`, wired through `Poise/Services/PocketTTS/`), an on-device, no-network TTS engine -- not a third-party network service. This is a narrow, deliberate exception to the general "no third-party dependencies" rule above, scoped to this one bundled framework.
- Speech transcription IS allowed, narrowly: Apple's on-device `Speech` framework (`SFSpeechRecognizer`, via `Poise/Services/SpeechRecognitionService.swift`) lets the user speak their turn in the live roleplay composer instead of typing it. This is on-device only (no audio leaves the device for this), fills the text field for the user to review/edit, and never auto-sends. It supersedes the earlier "no speech transcription" / "do not request microphone" rules below for this one narrow use.
- Voice delivery analysis IS also allowed, narrowly: the user's own recorded turn audio is analyzed on-device for pace, pitch, tone, and filler words via the local `PoiseVoiceAnalysis` Swift package (vendored in-repo under `voice-analysis/`, zero remote dependencies declared in its `Package.swift`). The pipeline is AVFoundation (decode) plus Apple's on-device `Speech` framework (transcript and word timestamps) plus JavaScriptCore running a bundled, vendored pitch-detection script (Pitchy + fft.js, compiled in as a local resource, not fetched) for the acoustic metrics. No audio or derived data leaves the device via this feature, no new networking destination is introduced, no third-party network service or SDK is called, and no API key is involved. This is a narrow, deliberate exception to the general "no voice analysis" / "no third-party dependencies" rules above, scoped to this one on-device acoustic pipeline, and it broadens the microphone exception above: unlike dictation (which transcribes and discards), this retains the raw recording on-device for the lifetime needed to analyze it, but still never transmits it anywhere.
- Support light mode. Dark mode can be deferred.
- Use NavigationStack and TabView where appropriate.
- Use reusable SwiftUI components and keep features organized under App, Models, Theme, Components, and Features.
- Add accessibility labels for important buttons and controls.
- Avoid fixed dimensions that break on smaller iPhones and respect safe areas.
- Privacy controls must default off and must only update local UI state.
- Do not request microphone or camera permissions in this prototype.
