#!/bin/bash
set -euo pipefail

REPO="kzahel/tilefun-devlog"
DEVLOG_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX="$DEVLOG_DIR/index.html"

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
DATE_DISPLAY=$(date +"%B %-d, %Y")
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

# Build the new entry HTML
ENTRY=$(cat <<ENTRY_EOF

    <div class="entry">
      <div class="date">$DATE_DISPLAY</div>
      <p>$TEXT</p>
      <video controls playsinline>
        <source src="$VIDEO_URL" type="video/mp4">
      </video>
    </div>
ENTRY_EOF
)

# Insert after <main>
sed -i '' "s|<main>|<main>$ENTRY|" "$INDEX"

# Commit and push
cd "$DEVLOG_DIR"
git add index.html
git commit -m "$TAG: $TEXT"
git push

echo ""
echo "Posted! $VIDEO_URL"
echo "Site will update shortly at https://kyle.graehl.org/tilefun-devlog/"
