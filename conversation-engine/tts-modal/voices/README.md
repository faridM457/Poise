# Reference voice clips

Drop one `.wav` file per character here, named after the voice, e.g.:

```
marcus.wav
priya.wav
dana.wav
alex.wav
```

Requirements (per OmniVoice's own docs):
- ~3-25 seconds of clear speech.
- Any voice you have the rights to use for cloning — e.g. record yourself
  or a willing collaborator saying a sentence or two in each target voice's
  style (QuickTime Player / Voice Memos both work fine for a quick clip).
- No transcript file needed — OmniVoice auto-transcribes the reference clip
  with Whisper if you don't supply `ref_text`.

These files are not committed anywhere by this setup — they're read locally
by `test.py`'s local entrypoint and sent to the Modal function per call.
