#!/usr/bin/env python3
"""Prepend an exact duration of digital silence to a PCM WAV file."""

from __future__ import annotations

import argparse
import wave
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--seconds", type=float, default=0.1)
    args = parser.parse_args()

    if args.seconds < 0.0:
        parser.error("--seconds must be non-negative")

    with wave.open(str(args.input), "rb") as source:
        parameters = source.getparams()
        audio_frames = source.readframes(source.getnframes())

    silence_frame_count = round(args.seconds * parameters.framerate)
    silence = bytes(silence_frame_count * parameters.nchannels * parameters.sampwidth)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(args.output), "wb") as destination:
        destination.setparams(parameters)
        destination.writeframes(silence + audio_frames)

    print(
        "%s: prepended %.3f seconds (%d frames)" %
        (args.output, silence_frame_count / parameters.framerate, silence_frame_count)
    )


if __name__ == "__main__":
    main()
