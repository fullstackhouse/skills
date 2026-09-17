#!/usr/bin/env bash
# Get readable, timestamped text out of a video/audio URL or local file.
#
#   transcribe.sh [options] <url | file>
#
# Prefers human-written subtitles when the source has them; otherwise
# transcribes locally with Whisper (no audio leaves the machine). Idempotent:
# re-running against the same input reuses the existing transcript.
set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/fsh-video-brief"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINDOW=45
LANG_OPT=""
MODEL=""
OUT=""
FORCE=0
AUTO_SUBS=0
WHISPER_ONLY=0

usage() {
  cat <<'EOF'
Usage: transcribe.sh [options] <url | file>

  --out DIR      where to put artifacts (default: a stable dir under $TMPDIR)
  --lang XX      source language hint, e.g. pl, en (default: auto-detect)
  --model NAME   Whisper model, or a path to a local model dir
                 (default: large-v3-turbo — ~1.6 GB on first use)
  --auto-subs    accept machine-generated captions from the platform (fast, lossy)
  --whisper      always transcribe locally, even if real subtitles exist
  --window SEC   seconds of speech per timestamped paragraph (default: 45)
  --force        redo even if a transcript is already there

Writes transcript.txt (timestamped, the thing to read), plus meta.json and the
raw subtitle/SRT file. Prints the paths and how the text was produced.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --lang) LANG_OPT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --window) WINDOW="$2"; shift 2 ;;
    --auto-subs) AUTO_SUBS=1; shift ;;
    --whisper) WHISPER_ONLY=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

[ $# -eq 1 ] || { usage >&2; exit 2; }
INPUT="$1"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1 — $2" >&2; exit 1; }; }

case "$INPUT" in
  http://*|https://*) IS_URL=1 ;;
  *) IS_URL=0; [ -f "$INPUT" ] || { echo "no such file: $INPUT" >&2; exit 1; } ;;
esac

# Stable work dir per input, so a re-run is free.
KEY="$(printf '%s' "$INPUT" | shasum | cut -c1-10)"
WORK="${OUT:-${TMPDIR:-/tmp}/video-brief/$KEY}"
mkdir -p "$WORK"
TRANSCRIPT="$WORK/transcript.txt"

if [ -s "$TRANSCRIPT" ] && [ "$FORCE" -eq 0 ]; then
  echo "Already transcribed (--force to redo)."
  [ -s "$WORK/source.txt" ] && cat "$WORK/source.txt"
  echo "transcript: $TRANSCRIPT"
  exit 0
fi

need python3 "install python3"

# A .vtt/.srt handed in directly needs none of the machinery below.
case "$INPUT" in
  *.vtt|*.srt)
    python3 "$SCRIPT_DIR/subs_to_text.py" --window "$WINDOW" "$INPUT" > "$TRANSCRIPT"
    printf 'source: %s\nmethod: subtitle file\n' "$INPUT" > "$WORK/source.txt"
    cat "$WORK/source.txt"
    echo "transcript: $TRANSCRIPT ($(wc -w < "$TRANSCRIPT" | tr -d ' ') words)"
    exit 0
    ;;
esac

SUB_FILE=""
METHOD=""
TITLE=""
UPLOADER="-"
DURATION="-"
MEDIA=""

# ------------------------------------------------------------------ fetch text
if [ "$IS_URL" -eq 1 ]; then
  need yt-dlp "brew install yt-dlp"
  echo "Fetching metadata..." >&2
  yt-dlp -J --no-warnings "$INPUT" > "$WORK/meta.json"

  { read -r TITLE; read -r UPLOADER; read -r DURATION; } < <(
    python3 "$SCRIPT_DIR/probe_meta.py" fields "$WORK/meta.json"
  )

  AUTO_FLAG=""
  [ "$AUTO_SUBS" -eq 1 ] && AUTO_FLAG=--auto
  PICK="$(python3 "$SCRIPT_DIR/probe_meta.py" track "$WORK/meta.json" "$LANG_OPT" $AUTO_FLAG)"

  if [ -n "$PICK" ] && [ "$WHISPER_ONLY" -eq 0 ]; then
    SUB_LANG="${PICK% *}"
    SUB_KIND="${PICK#* }"
    echo "Downloading $SUB_KIND subtitles ($SUB_LANG)..." >&2
    SUB_FLAG=--write-subs
    [ "$SUB_KIND" = auto ] && SUB_FLAG=--write-auto-subs
    yt-dlp --skip-download "$SUB_FLAG" --sub-langs "$SUB_LANG" --sub-format vtt \
           --no-warnings -o "$WORK/sub.%(ext)s" "$INPUT" >&2
    SUB_FILE="$(find "$WORK" -name 'sub*.vtt' -print -quit)"
    [ -n "$SUB_FILE" ] && METHOD="$SUB_KIND subtitles ($SUB_LANG)"
  fi

  if [ -z "$SUB_FILE" ]; then
    echo "No usable subtitles — transcribing locally." >&2
    [ -s "$WORK/audio.m4a" ] || \
      yt-dlp -f 'bestaudio/best' -x --audio-format m4a --no-warnings \
             -o "$WORK/audio.%(ext)s" "$INPUT" >&2
    MEDIA="$WORK/audio.m4a"
  fi
else
  MEDIA="$INPUT"
  TITLE="$(basename "$INPUT")"
  DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null | cut -d. -f1 || echo -)"
fi

# --------------------------------------------------------------------- whisper
if [ -z "$SUB_FILE" ]; then
  need ffmpeg "brew install ffmpeg"
  WAV="$WORK/audio16k.wav"
  [ -s "$WAV" ] || ffmpeg -nostdin -loglevel error -y -i "$MEDIA" -ac 1 -ar 16000 "$WAV"

  VENV="$CACHE/venv"
  if [ ! -x "$VENV/bin/python" ]; then
    echo "First run: creating the Whisper venv at $VENV..." >&2
    mkdir -p "$CACHE"
    if command -v uv >/dev/null 2>&1; then
      uv venv --python 3.12 "$VENV" >&2
    else
      python3 -m venv "$VENV" >&2
    fi
  fi

  # Apple Silicon runs Whisper on the GPU via MLX (measured 25-90x realtime);
  # everything else falls back to the reference implementation on CPU (~1x).
  # A model directory dropped into $CACHE/models wins over the hub — handy on a
  # link where pulling 1.6 GB is the slowest part of the whole exercise.
  LOCAL_MODEL="$CACHE/models/whisper-large-v3-turbo"

  if [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]; then
    BIN="$VENV/bin/mlx_whisper"; PKG=mlx-whisper
    if [ -z "$MODEL" ] && [ -d "$LOCAL_MODEL" ]; then MODEL="$LOCAL_MODEL"; fi
    MODEL="${MODEL:-mlx-community/whisper-large-v3-turbo}"
    set -- "$WAV" --model "$MODEL" --output-dir "$WORK" --output-format srt
    [ -n "$LANG_OPT" ] && set -- "$@" --language "$LANG_OPT"
  else
    BIN="$VENV/bin/whisper"; PKG=openai-whisper
    MODEL="${MODEL:-large-v3-turbo}"
    set -- "$WAV" --model "$MODEL" --output_dir "$WORK" --output_format srt
    [ -n "$LANG_OPT" ] && set -- "$@" --language "$LANG_OPT"
  fi

  if [ ! -x "$BIN" ]; then
    echo "Installing $PKG (one-off, a few minutes)..." >&2
    if command -v uv >/dev/null 2>&1; then
      VIRTUAL_ENV="$VENV" uv pip install --quiet "$PKG" >&2
    else
      "$VENV/bin/pip" install --quiet "$PKG" >&2
    fi
  fi

  # A cold model cache means a ~1.6 GB download before a single word gets
  # transcribed, and the progress for it lands in whisper.log where nobody is
  # looking — so say it out loud first.
  if [ ! -d "$MODEL" ] && \
     [ ! -d "$HOME/.cache/huggingface/hub/models--$(printf '%s' "$MODEL" | tr / -)/snapshots" ]; then
    echo "First run with $MODEL: downloading ~1.6 GB before transcription starts." >&2
  fi

  echo "Transcribing with $PKG ($MODEL)..." >&2
  "$BIN" "$@" >"$WORK/whisper.log" 2>&1 || { tail -30 "$WORK/whisper.log" >&2; exit 1; }

  SUB_FILE="$WORK/audio16k.srt"
  METHOD="local Whisper ($MODEL)"
fi

# ---------------------------------------------------------------------- output
python3 "$SCRIPT_DIR/subs_to_text.py" --window "$WINDOW" "$SUB_FILE" > "$TRANSCRIPT"

{
  printf 'title: %s\n' "$TITLE"
  printf 'source: %s\n' "$INPUT"
  [ "$UPLOADER" != "-" ] && printf 'uploader: %s\n' "$UPLOADER"
  case "$DURATION" in ''|-) : ;; *) printf 'duration: %dm\n' $((DURATION / 60)) ;; esac
  printf 'method: %s\n' "$METHOD"
} > "$WORK/source.txt"

cat "$WORK/source.txt"
echo "transcript: $TRANSCRIPT ($(wc -w < "$TRANSCRIPT" | tr -d ' ') words)"
echo "raw: $SUB_FILE"
