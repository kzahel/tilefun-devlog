#!/bin/bash
set -euo pipefail

REPO="kzahel/tilefun-devlog"
DEVLOG_DIR="$(cd "$(dirname "$0")" && pwd)"
POSTS_DIR="$DEVLOG_DIR/posts"

usage() {
  echo "Usage: post.sh <video-file> <text>"
  echo ""
  echo "Example:"
  echo "  ./post.sh ~/Desktop/Screen\\ Recording*.mov \"Terrain editing and cow riding\""
  exit 1
}

if [ $# -lt 2 ]; then
  usage
fi

VIDEO="$1"
TEXT="$2"

if [ ! -f "$VIDEO" ]; then
  echo "Error: file not found: $VIDEO"
  exit 1
fi

DATE=$(date +%Y-%m-%d)
TAG="devlog-$DATE"
MP4="/tmp/$TAG.mp4"

# Check if tag already exists, append a number if so
COUNTER=1
while gh release view "$TAG" --repo "$REPO" &>/dev/null; do
  COUNTER=$((COUNTER + 1))
  TAG="devlog-$DATE-$COUNTER"
  MP4="/tmp/$TAG.mp4"
done

echo "Compressing video..."
ffmpeg -y -i "$VIDEO" -vcodec libx264 -crf 28 -preset fast -vf "scale=1280:-2" -an "$MP4" 2>&1 | tail -1

SIZE=$(du -h "$MP4" | cut -f1)
echo "Compressed to $SIZE: $MP4"

echo "Uploading to GitHub release $TAG..."
gh release create "$TAG" "$MP4" --repo "$REPO" --title "$TAG" --notes "$TEXT"

VIDEO_URL="https://github.com/$REPO/releases/download/$TAG/$TAG.mp4"

# Extract dimensions from compressed video
DIMENSIONS=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$MP4")
WIDTH=$(echo "$DIMENSIONS" | cut -d',' -f1)
HEIGHT=$(echo "$DIMENSIONS" | cut -d',' -f2)
echo "Video dimensions: ${WIDTH}x${HEIGHT}"

# Determine post filename (handle multiple posts per day)
POST_FILE="$POSTS_DIR/$DATE.md"
if [ -f "$POST_FILE" ]; then
  POST_FILE="$POSTS_DIR/$DATE-$COUNTER.md"
fi

# Write markdown post
cat > "$POST_FILE" <<EOF
$TEXT

[video ${WIDTH}x${HEIGHT}]($VIDEO_URL)
EOF

# Commit and push (GitHub Action builds the HTML)
cd "$DEVLOG_DIR"
git add posts/
git commit -m "$TAG: $TEXT"
git push

echo ""
echo "Posted! Site will rebuild automatically."
echo "https://kyle.graehl.org/tilefun-devlog/"
