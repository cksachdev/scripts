#!/bin/bash

set -eo pipefail

FFMPEG="/opt/homebrew/bin/ffmpeg"
FFPROBE="/opt/homebrew/bin/ffprobe"

# Validate tools
if [[ ! -x "$FFMPEG" || ! -x "$FFPROBE" ]]; then
  osascript -e 'display alert "FFmpeg or FFprobe not found at /opt/homebrew/bin"'
  exit 1
fi

# Collect MP3 files
files=()
for f in "$@"; do
  ext="${f##*.}"
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  if [[ "$ext_lower" == "mp3" ]]; then
    files+=("$f")
  fi
done

# Validate input
if [[ ${#files[@]} -lt 2 ]]; then
  osascript -e 'display alert "Select at least 2 MP3 files"'
  exit 1
fi

# Build preview list
sequence=""
i=1
for f in "${files[@]}"; do
  name=$(basename "$f")
  sequence="${sequence}${i}. ${name}\n"
  ((i++))
done

# Confirm order
confirmed=$(osascript -e "
try
  button returned of (display dialog \"Merge these files in order:\n\n$sequence\" buttons {\"Cancel\", \"Merge\"} default button \"Merge\")
on error number -128
  return \"Cancel\"
end try
")

if [[ "$confirmed" != "Merge" ]]; then
  exit 0
fi

# Get first file safely
first_file=""
for f in "${files[@]}"; do
  first_file="$f"
  break
done

dir=$(dirname "$first_file")
base=$(basename "$first_file" .mp3)

# Ask filename
filename=$(osascript -e "
try
  text returned of (display dialog \"Enter output file name:\" default answer \"${base}_merged\")
on error number -128
  return \"\"
end try
")

if [[ -z "$filename" ]]; then
  exit 0
fi

output="$dir/${filename}.mp3"

# Prevent overwrite
if [[ -f "$output" ]]; then
  osascript -e 'display alert "File already exists!"'
  exit 1
fi

# -------------------------------
# 🎯 NEW SAFE MERGE APPROACH
# -------------------------------

inputs=()
filters=""
index=0

for f in "${files[@]}"; do
  inputs+=("-i" "$f")

  channels=$("$FFPROBE" -v error -select_streams a:0 \
    -show_entries stream=channels \
    -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo "0")

  if [[ "$channels" == "1" ]]; then
    filters="${filters}[$index:a]aformat=channel_layouts=mono,pan=stereo|c0=c0|c1=c0[a$index];"
  else
    filters="${filters}[$index:a]aformat=channel_layouts=stereo[a$index];"
  fi

  ((index++))
done

# Build concat part
concat_inputs=""
for ((i=0; i<index; i++)); do
  concat_inputs="${concat_inputs}[a$i]"
done

filters="${filters}${concat_inputs}concat=n=${index}:v=0:a=1[out]"

# 🚀 Merge + encode in one pass
"$FFMPEG" -loglevel error -y \
  "${inputs[@]}" \
  -filter_complex "$filters" \
  -map "[out]" \
  -c:a libmp3lame -b:a 192k \
  "$output"

exit_code=$?

# Notify
if [[ $exit_code -eq 0 ]]; then
  osascript -e "display notification \"MP3 merged cleanly (192 kbps)\" with title \"FFmpeg\""
else
  osascript -e "display alert \"Merge failed\""
fi

exit 0