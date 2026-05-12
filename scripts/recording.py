#!/usr/bin/env python3
"""
Helpers for wkdomains recording demos.

This script keeps the fragile parts out of ad hoc shell:
- generate VoxCPM WAV files from a TSV manifest
- measure WAV durations exactly with ffprobe
- assemble raw video clips with one matching WAV per clip
- build contact sheets for visual QA

Manifests are tab-separated. Labels are treated as literal strings.
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path


DEFAULT_TTS_URL = "http://127.0.0.1:9002/say"
DEFAULT_WAV_DIR = Path("/Users/aa/os/VoxCPM/outputs/http")


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=True, text=True, capture_output=True)


def run_stream(args: list[str]) -> None:
    subprocess.run(args, check=True)


def ffprobe_duration(path: Path) -> float:
    result = run([
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=nw=1:nk=1",
        str(path),
    ])
    return float(result.stdout.strip())


def read_tsv(path: Path) -> list[list[str]]:
    with path.open(newline="") as handle:
        return [row for row in csv.reader(handle, delimiter="\t") if row]


def write_tsv(path: Path, rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerows(rows)


def dict_from_tsv(path: Path) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for row in read_tsv(path):
        if len(row) < 2:
            raise SystemExit(f"{path}: expected at least 2 columns, got {row!r}")
        result[row[0]] = row[1:]
    return result


def post_json(url: str, payload: dict[str, str]) -> dict[str, object]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"TTS request failed: {error.code} {body}") from error
    return json.loads(body)


def command_tts(args: argparse.Namespace) -> None:
    rows = read_tsv(args.input)
    output_rows: list[list[str]] = []

    for row in rows:
        if len(row) < 2:
            raise SystemExit(f"{args.input}: expected label<TAB>text, got {row!r}")
        label, text = row[0], row[1]
        voice = row[2] if len(row) > 2 and row[2] else args.voice
        filename = f"{args.prefix}_{label}.wav"
        payload = {"voice": voice, "text": text, "filename": filename}
        response = post_json(args.url, payload)
        wav_path = Path(str(response.get("path") or args.wav_dir / filename))
        if not wav_path.exists():
            raise SystemExit(f"TTS did not create expected WAV: {wav_path}")
        duration = ffprobe_duration(wav_path)
        output_rows.append([label, str(wav_path), f"{duration:.6f}"])
        print(f"{label}\t{wav_path}\t{duration:.6f}", flush=True)

    write_tsv(args.output, output_rows)


def command_measure(args: argparse.Namespace) -> None:
    rows = []
    for wav in args.wavs:
        path = Path(wav)
        rows.append([path.stem, str(path), f"{ffprobe_duration(path):.6f}"])
    write_tsv(args.output, rows)
    for row in rows:
        print("\t".join(row))


def command_assemble(args: argparse.Namespace) -> None:
    raws = dict_from_tsv(args.raws)
    wavs = dict_from_tsv(args.wavs)
    order = [line.strip() for line in args.order.read_text().splitlines() if line.strip()]
    args.work.mkdir(parents=True, exist_ok=True)

    concat_file = args.work / "concat.txt"
    concat_lines: list[str] = []

    for label in order:
        if label not in raws:
            raise SystemExit(f"Missing raw clip for label: {label}")
        if label not in wavs:
            raise SystemExit(f"Missing WAV for label: {label}")

        raw_path = Path(raws[label][0])
        wav_path = Path(wavs[label][0])
        wav_duration = ffprobe_duration(wav_path)
        clip_path = args.work / f"clip_{label}.mov"

        if not raw_path.exists():
            raise SystemExit(f"Missing raw file for {label}: {raw_path}")
        if not wav_path.exists():
            raise SystemExit(f"Missing WAV file for {label}: {wav_path}")

        if not clip_path.exists() or clip_path.stat().st_size == 0 or args.force:
            print(f"building {label}: {wav_duration:.6f}s", flush=True)
            run_stream([
                "ffmpeg",
                "-y",
                "-hide_banner",
                "-loglevel",
                "error",
                "-i",
                str(raw_path),
                "-i",
                str(wav_path),
                "-t",
                f"{wav_duration:.6f}",
                "-map",
                "0:v:0",
                "-map",
                "1:a:0",
                "-vf",
                f"scale={args.width}:{args.height}",
                "-c:v",
                "libx264",
                "-preset",
                args.preset,
                "-crf",
                str(args.crf),
                "-pix_fmt",
                "yuv420p",
                "-c:a",
                "aac",
                "-b:a",
                args.audio_bitrate,
                "-shortest",
                str(clip_path),
            ])
        else:
            print(f"using {label}", flush=True)

        concat_lines.append(f"file '{clip_path}'\n")

    concat_file.write_text("".join(concat_lines))
    run_stream([
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        str(concat_file),
        "-c",
        "copy",
        "-movflags",
        "+faststart",
        str(args.output),
    ])
    final_duration = ffprobe_duration(args.output)
    print(f"{args.output}\t{final_duration:.6f}")


def command_contact_sheet(args: argparse.Namespace) -> None:
    frames_dir = args.work / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    for existing in frames_dir.glob("frame_*.jpg"):
        existing.unlink()

    run_stream([
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(args.input),
        "-vf",
        f"fps=1/{args.every},scale={args.frame_width}:-1",
        str(frames_dir / "frame_%03d.jpg"),
    ])
    run_stream([
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-pattern_type",
        "glob",
        "-i",
        str(frames_dir / "*.jpg"),
        "-filter_complex",
        f"tile={args.columns}x{args.rows}:padding=10:margin=10:color=black",
        str(args.output),
    ])
    print(args.output)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="wkdomains recording demo helpers")
    subparsers = parser.add_subparsers(dest="command", required=True)

    tts = subparsers.add_parser("tts", help="Generate WAVs from label/text TSV")
    tts.add_argument("input", type=Path, help="TSV: label<TAB>text[<TAB>voice]")
    tts.add_argument("output", type=Path, help="Output TSV: label<TAB>wav_path<TAB>duration")
    tts.add_argument("--prefix", default="demo", help="WAV filename prefix")
    tts.add_argument("--voice", default="cinematic_trailer")
    tts.add_argument("--url", default=DEFAULT_TTS_URL)
    tts.add_argument("--wav-dir", type=Path, default=DEFAULT_WAV_DIR)
    tts.set_defaults(func=command_tts)

    measure = subparsers.add_parser("measure", help="Measure WAV durations")
    measure.add_argument("output", type=Path)
    measure.add_argument("wavs", nargs="+")
    measure.set_defaults(func=command_measure)

    assemble = subparsers.add_parser("assemble", help="Mux raw clips with matching WAVs")
    assemble.add_argument("--raws", type=Path, required=True, help="TSV: label<TAB>raw_mov")
    assemble.add_argument("--wavs", type=Path, required=True, help="TSV: label<TAB>wav_path<TAB>duration")
    assemble.add_argument("--order", type=Path, required=True, help="One label per line")
    assemble.add_argument("--work", type=Path, required=True)
    assemble.add_argument("--output", type=Path, required=True)
    assemble.add_argument("--width", type=int, default=1920)
    assemble.add_argument("--height", type=int, default=1080)
    assemble.add_argument("--crf", type=int, default=18)
    assemble.add_argument("--preset", default="veryfast")
    assemble.add_argument("--audio-bitrate", default="192k")
    assemble.add_argument("--force", action="store_true")
    assemble.set_defaults(func=command_assemble)

    contact = subparsers.add_parser("contact-sheet", help="Create sampled-frame contact sheet")
    contact.add_argument("--input", type=Path, required=True)
    contact.add_argument("--work", type=Path, required=True)
    contact.add_argument("--output", type=Path, required=True)
    contact.add_argument("--every", type=float, default=10)
    contact.add_argument("--frame-width", type=int, default=640)
    contact.add_argument("--columns", type=int, default=3)
    contact.add_argument("--rows", type=int, default=6)
    contact.set_defaults(func=command_contact_sheet)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
