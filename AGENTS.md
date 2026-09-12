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
- Use Swift and SwiftUI only. Do not use WebView, third-party dependencies, networking, LLM calls, analytics, authentication, cloud storage, RevenueCat, StoreKit, speech transcription, voice analysis, video analysis, push notifications, or API keys.
- Use local mock data and local state.
- Support light mode. Dark mode can be deferred.
- Use NavigationStack and TabView where appropriate.
- Use reusable SwiftUI components and keep features organized under App, Models, Theme, Components, and Features.
- Add accessibility labels for important buttons and controls.
- Avoid fixed dimensions that break on smaller iPhones and respect safe areas.
- Privacy controls must default off and must only update local UI state.
- Do not request microphone or camera permissions in this prototype.
