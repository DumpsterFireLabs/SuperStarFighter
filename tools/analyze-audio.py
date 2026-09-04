#!/usr/bin/env python3
"""Measure recorded PCM auditions and local audio/package footprint; stdlib only."""
import argparse
import array
import cmath
import json
import math
import re
from pathlib import Path
import struct
import wave


def samples(path):
    with wave.open(str(path), "rb") as source:
        if source.getsampwidth() != 2:
            raise ValueError("Audition analysis expects 16-bit PCM")
        data = array.array("h", source.readframes(source.getnframes()))
        return data, source.getnchannels(), source.getframerate()


def fft(values):
    count = len(values)
    if count <= 1:
        return values
    even, odd = fft(values[::2]), fft(values[1::2])
    factors = [cmath.exp(-2j * math.pi * index / count) * odd[index] for index in range(count // 2)]
    return [even[i] + factors[i] for i in range(count // 2)] + [even[i] - factors[i] for i in range(count // 2)]


def metrics(path):
    data, channels, rate = samples(path)
    peak = max((abs(value) for value in data), default=0) / 32768
    rms = math.sqrt(sum(value * value for value in data) / max(len(data), 1)) / 32768
    mono = [sum(data[index:index + channels]) / channels / 32768 for index in range(0, len(data), channels)]
    peak_index = max(range(len(mono)), key=lambda index: abs(mono[index])) if mono else 0
    start = max(0, min(peak_index - 512, len(mono) - 1024))
    window = mono[start:start + 1024]
    window += [0.0] * (1024 - len(window))
    spectrum = fft([value * (0.5 - 0.5 * math.cos(2 * math.pi * index / 1023)) for index, value in enumerate(window)])
    magnitudes = [abs(value) for value in spectrum[:512]]
    centroid = sum(index * rate / 1024 * value for index, value in enumerate(magnitudes)) / max(sum(magnitudes), 1e-12)
    return {"seconds": len(data) / channels / rate, "peak_dbfs": 20 * math.log10(max(peak, 1e-12)), "rms_dbfs": 20 * math.log10(max(rms, 1e-12)), "clipped_samples": sum(abs(value) >= 32767 for value in data), "peak_window_spectral_centroid_hz": centroid}


def channel_rms(path, begin, end):
    data, channels, rate = samples(path)
    if channels != 2:
        raise ValueError("Stereo recording is required for panning analysis")
    clip = data[round(begin * rate) * channels:round(end * rate) * channels]
    return [math.sqrt(sum(value * value for value in clip[channel::2]) / max(len(clip) / 2, 1)) / 32768 for channel in range(2)]


def package_footprint(path):
    with path.open("rb") as source:
        source.seek(-12, 2)
        length, magic = struct.unpack("<QI", source.read(12))
        if magic != 0x43504447:
            raise ValueError("No embedded Godot PCK footer")
        start = path.stat().st_size - length - 12
        source.seek(start)
        header = source.read(40)
        version = struct.unpack_from("<I", header, 4)[0]
        result = {"path": str(path), "executable_bytes": path.stat().st_size, "embedded_pck_bytes": length, "pack_format": version}
        if version == 4:
            source.seek(start + struct.unpack_from("<Q", header, 32)[0])
            count = struct.unpack("<I", source.read(4))[0]
            audio_entries = []
            for _ in range(count):
                name_length = struct.unpack("<I", source.read(4))[0]
                name = source.read(name_length).rstrip(b"\0").decode("utf-8")
                _, size = struct.unpack("<QQ", source.read(16))
                source.read(20)  # MD5 + entry flags
                if name.endswith(".sample"):
                    audio_entries.append({"path": name, "bytes": size})
            result["imported_audio_entries"] = audio_entries
            result["imported_audio_bytes"] = sum(entry["bytes"] for entry in audio_entries)
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--package", type=Path)
    args = parser.parse_args()
    report = {"recordings": {path.name: metrics(path) for path in sorted(args.directory.glob("*.wav"))}}
    source_rows = []
    for path in Path("assets/audio").rglob("*.wav"):
        with wave.open(str(path), "rb") as source:
            source_rows.append({"path": str(path), "bytes": path.stat().st_size, "seconds": source.getnframes() / source.getframerate(), "rate": source.getframerate(), "channels": source.getnchannels(), "sample_width": source.getsampwidth()})
    report["source_assets"] = source_rows
    report["source_bytes"] = sum(row["bytes"] for row in source_rows)
    report["local_import_cache_sample_bytes"] = sum(path.stat().st_size for path in Path(".godot/imported").glob("*.sample"))
    imported = set()
    for row in source_rows:
        settings = Path(row["path"] + ".import").read_text(encoding="utf-8")
        match = re.search(r'^path="res://([^\"]+)"', settings, re.MULTILINE)
        if match:
            imported.add(Path(match.group(1)))
    report["referenced_imported_sample_bytes"] = sum(path.stat().st_size for path in imported)
    audition = args.directory / "cue_audition.wav"
    if audition.exists():
        # The final fixture orders seven cues, then one left and one right shot.
        report["left_shot_channel_rms"] = channel_rms(audition, 7.0, 7.8)
        report["right_shot_channel_rms"] = channel_rms(audition, 8.0, 8.8)
    if args.package:
        report["existing_package"] = package_footprint(args.package)
    (args.directory / "analysis.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
