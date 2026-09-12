# Runs entirely on Modal's remote infrastructure -- nothing in this file's
# GPU/model code executes on your machine. The `image` below describes a
# container that Modal builds and runs on their H100 instances; your laptop
# only needs the lightweight `modal` client (already installed locally) to
# define, deploy, and call this app.
#
# `from __future__ import annotations` defers type-hint evaluation, since
# this file is imported by the local `modal` CLI (this machine runs Python
# 3.9, which doesn't support the `str | None` union syntax below at runtime
# without this).
from __future__ import annotations

import modal

app = modal.App("omnivoice-tts")

image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install(
        "torch==2.8.0+cu128",
        "torchaudio==2.8.0+cu128",
        extra_index_url="https://download.pytorch.org/whl/cu128",
    )
    .pip_install("omnivoice", "soundfile")
)


@app.cls(
    gpu="H100",
    image=image,
    min_containers=0,  # scale to zero when idle -- this is what prevents idle billing
    scaledown_window=10,  # shut the container down 10s after the last request --
    # kept short since testing is bursty/manual right now; raise this once there's
    # real back-to-back traffic where avoiding repeated cold starts is worth the
    # small extra idle cost
)
class OmniVoiceModel:
    @modal.enter()
    def load(self):
        # Imported here, not at module scope, since torch/omnivoice are only
        # installed in the remote image -- this file is also parsed locally
        # by the `modal` CLI to build the app graph, and the local machine
        # doesn't have these packages.
        import torch
        from omnivoice import OmniVoice

        self.model = OmniVoice.from_pretrained(
            "k2-fsa/OmniVoice",
            device_map="cuda:0",
            dtype=torch.float16,
        )

    @modal.method()
    def generate_cloned(self, text: str, ref_audio_bytes: bytes, ref_text: str | None = None) -> bytes:
        """Zero-shot cloning from a reference clip. OmniVoice's own docs call
        this the most stable mode, but it needs a real ~3-25s reference clip
        per voice."""
        import tempfile

        with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
            tmp.write(ref_audio_bytes)
            tmp.flush()
            kwargs = {"text": text, "ref_audio": tmp.name}
            if ref_text:
                kwargs["ref_text"] = ref_text
            audio = self.model.generate(**kwargs)
        return _to_wav_bytes(audio)

    @modal.method()
    def generate_designed(self, text: str, instruct: str) -> bytes:
        """Voice design: describe the voice (gender, age, pitch, accent,
        style) instead of cloning from audio. No reference clip needed.
        Per OmniVoice's docs, this mode is only trained on Chinese/English
        and is less proven than cloning."""
        audio = self.model.generate(text=text, instruct=instruct)
        return _to_wav_bytes(audio)


def _to_wav_bytes(audio) -> bytes:
    import io

    import soundfile as sf

    buf = io.BytesIO()
    sf.write(buf, audio[0], 24000, format="WAV")
    return buf.getvalue()


SAMPLE_LINE = "Hey, what did you want to talk about?"

# Placeholder descriptions for the 4 characters, using only the fixed
# instruct vocabulary OmniVoice actually accepts (confirmed by running this
# and reading the ValueError's own list of valid tags -- free-form
# descriptors like "warm" or "mid-thirties" are rejected). Comma + space
# separated, English tags only (don't mix with Chinese tags).
DESIGNED_VOICES = {
    "marcus": "male, middle-aged, low pitch",
    "priya": "female, young adult, moderate pitch",
    "dana": "female, young adult, high pitch",
    "alex": "male, young adult, moderate pitch",
}


# Lightweight HTTP endpoint the Node backend calls. This deliberately does
# NOT run on a GPU or in the heavy `image` above -- it's a thin wrapper that
# delegates to OmniVoiceModel, which is the only thing that spins up (and
# bills for) an H100. Deploying/redeploying this costs effectively nothing;
# the GPU cost only happens when a request actually reaches generate_designed.
endpoint_image = modal.Image.debian_slim(python_version="3.11").pip_install("fastapi[standard]")


@app.function(image=endpoint_image)
@modal.fastapi_endpoint(method="POST")
def tts(item: dict):
    from fastapi import HTTPException
    from fastapi.responses import Response

    text = item.get("text")
    voice = item.get("voice")
    if not text or not voice:
        raise HTTPException(status_code=400, detail="Both 'text' and 'voice' are required")

    instruct = DESIGNED_VOICES.get(voice)
    if not instruct:
        raise HTTPException(status_code=400, detail=f"Unknown voice '{voice}'. Valid: {list(DESIGNED_VOICES)}")

    audio_bytes = OmniVoiceModel().generate_designed.remote(text, instruct)
    return Response(content=audio_bytes, media_type="audio/wav")


@app.local_entrypoint()
def test_design():
    """No reference clips needed -- run this first."""
    import pathlib

    out_dir = pathlib.Path(__file__).parent / "output"
    out_dir.mkdir(exist_ok=True)

    model = OmniVoiceModel()
    for voice_name, instruct in DESIGNED_VOICES.items():
        print(f"Generating (designed) for voice: {voice_name} ({instruct})")
        audio_bytes = model.generate_designed.remote(SAMPLE_LINE, instruct)
        out_path = out_dir / f"{voice_name}_designed.wav"
        out_path.write_bytes(audio_bytes)
        print(f"  -> wrote {out_path}")


@app.local_entrypoint()
def test_clone():
    """Needs a ~3-25s .wav per voice in voices/, named e.g. marcus.wav."""
    import pathlib

    here = pathlib.Path(__file__).parent
    voices_dir = here / "voices"
    out_dir = here / "output"
    out_dir.mkdir(exist_ok=True)

    ref_clips = sorted(voices_dir.glob("*.wav"))
    if not ref_clips:
        print(f"No reference clips found in {voices_dir}. Add a ~3-25s .wav per voice first.")
        return

    model = OmniVoiceModel()
    for ref_path in ref_clips:
        voice_name = ref_path.stem
        print(f"Generating (cloned) for voice: {voice_name}")
        audio_bytes = model.generate_cloned.remote(SAMPLE_LINE, ref_path.read_bytes())
        out_path = out_dir / f"{voice_name}_cloned.wav"
        out_path.write_bytes(audio_bytes)
        print(f"  -> wrote {out_path}")
