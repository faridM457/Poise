# Parked: self-hosted OmniVoice on Modal

**Not currently wired into the app.** The active TTS path is Deepgram
(`server/tts.js`), a managed API — see its comments for why.

This directory is kept as a working reference in case self-hosting is worth
revisiting later. Summary of why it was set aside for now:

- Every cold, isolated request pays a real cold-start tax (measured: a
  201-character line cost 4 cents, ~25-150x the steady-state per-character
  estimate) — dominant cost for sporadic dev/testing traffic and for any
  production traffic too sparse to keep a container warm.
- Keeping a GPU permanently warm (`min_containers=1`) to avoid that costs a
  flat ~$2,844/month (H100 on Modal) regardless of usage — that same money
  buys ~94.8 million characters on Deepgram's metered rate, i.e. a lot of
  usage has to happen before a warm pool pays for itself.
- Deepgram has no cold-start UX risk at any volume, no infrastructure to
  operate, and a simple, predictable per-character bill.

Self-hosting only wins once sustained traffic is high enough to either
naturally keep containers warm or justify a paid warm pool — worth
re-evaluating with real production usage data, not projections.

**The Modal deployment itself has been torn down** (`modal app stop`) —
the code below still works, but nothing is currently live or billable.
To revive it: `modal deploy app.py` from this directory, then point
`server/tts.js` back at the printed endpoint URL.

Everything else in this directory (app.py, voices/) is unchanged from when
it was the active path — see git history for how it was built and tested.
