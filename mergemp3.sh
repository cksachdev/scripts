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

# Temp directory
tmpdir=$(mktemp -d)
listfile="$tmpdir/list.txt"
> "$listfile"

# Process files (ensure stereo)
for f in "${files[@]}"; do
  channels=$("$FFPROBE" -v error -select_streams a:0 \
    -show_entries stream=channels \
    -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo "0")

  out="$tmpdir/$(basename "$f")"

  if [[ "$channels" == "1" ]]; then
    "$FFMPEG" -loglevel error -y -i "$f" -ac 2 -c:a libmp3lame -q:a 2 "$out"
  else
    cp "$f" "$out"
  fi

  esc=$(printf "%s\n" "$out" | sed "s/'/'\\\\''/g")
  echo "file '$esc'" >> "$listfile"
done

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
  rm -rf "$tmpdir"
  exit 0
fi

output="$dir/${filename}.mp3"
temp_output="$tmpdir/temp_merged.mp3"

# Prevent overwrite
if [[ -f "$output" ]]; then
  osascript -e 'display alert "File already exists!"'
  rm -rf "$tmpdir"
  exit 1
fi

# Step 1: concat (no re-encode)
"$FFMPEG" -loglevel error -y -f concat -safe 0 -i "$listfile" -c copy "$temp_output"
concat_exit=$?

if [[ $concat_exit -ne 0 ]]; then
  osascript -e "display alert \"Concat failed\""
  rm -rf "$tmpdir"
  exit 1
fi

# Step 2: re-encode (your requirement)
"$FFMPEG" -loglevel error -y -i "$temp_output" -c:a libmp3lame -b:a 192k "$output"
final_exit=$?

# Cleanup
rm -rf "$tmpdir"

# Notify
if [[ $final_exit -eq 0 ]]; then
  osascript -e "display notification \"MP3 merged & re-encoded (192 kbps)\" with title \"FFmpeg\""
else
  osascript -e "display alert \"Re-encoding failed\""
fi

exit 0