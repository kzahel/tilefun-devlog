#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
POSTS_DIR="$DIR/posts"
OUT="$DIR/index.html"
REPO="kzahel/tilefun-devlog"

# Start HTML
cat > "$OUT" <<'HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Tilefun Devlog</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: #222;
      background: #fafafa;
      max-width: 720px;
      margin: 0 auto;
      padding: 2rem 1rem;
    }
    header {
      margin-bottom: 3rem;
      border-bottom: 2px solid #222;
      padding-bottom: 1rem;
    }
    header h1 { font-size: 1.8rem; font-weight: 700; }
    header p { color: #666; margin-top: 0.25rem; }
    header nav { margin-top: 0.5rem; }
    header nav a { color: #444; text-decoration: none; margin-right: 1rem; }
    header nav a:hover { text-decoration: underline; }
    .entry { margin-bottom: 3rem; padding-bottom: 2rem; border-bottom: 1px solid #ddd; }
    .entry:last-child { border-bottom: none; }
    .entry h2 { font-size: 1.3rem; font-weight: 600; margin-bottom: 0.25rem; }
    .entry .date { color: #888; font-size: 0.9rem; margin-bottom: 1rem; }
    .entry p { margin-bottom: 1rem; }
    .entry video, .entry img { max-width: 100%; max-height: 70vh; border-radius: 4px; margin: 1rem 0; }
    .entry video { background: #000; }
    a { color: #0066cc; }
  </style>
</head>
<body>
  <header>
    <h1>Tilefun Devlog</h1>
    <p>Building a creative-mode 2D tile game</p>
    <nav>
      <a href="https://github.com/kzahel/tilefun">Source</a>
    </nav>
  </header>
  <main>
HEAD

# Process posts in reverse date order (newest first)
for post in $(ls -r "$POSTS_DIR"/*.md 2>/dev/null); do
  filename=$(basename "$post" .md)

  # Parse date from filename (YYYY-MM-DD, with optional -N suffix)
  date_part=$(echo "$filename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
  # macOS uses -j -f, Linux uses -d
  date_display=$(date -j -f "%Y-%m-%d" "$date_part" "+%B %-d, %Y" 2>/dev/null \
    || date -d "$date_part" "+%B %-d, %Y" 2>/dev/null \
    || echo "$date_part")

  # Extract optional title (first line starting with #)
  title=""
  if head -1 "$post" | grep -q '^# '; then
    title=$(head -1 "$post" | sed 's/^# //')
  fi

  echo '    <div class="entry">' >> "$OUT"
  if [ -n "$title" ]; then
    echo "      <h2>$title</h2>" >> "$OUT"
  fi
  echo "      <div class=\"date\">$date_display</div>" >> "$OUT"

  # Process body (skip title line if present)
  start_line=1
  if [ -n "$title" ]; then
    start_line=2
  fi

  tail -n +$start_line "$post" | while IFS= read -r line; do
    # Skip empty lines
    if [ -z "$line" ]; then
      continue
    fi

    # [video WxH](url) or [video](url) -> <video> tag
    if echo "$line" | grep -qE '^\[video[ ]?.*\]\(.*\)$'; then
      url=$(echo "$line" | sed -E 's/^\[video[^]]*\]\((.*)\)$/\1/')
      dims=$(echo "$line" | sed -E 's/^\[video ?([0-9]+x[0-9]+)?\]\(.*\)$/\1/')
      style=""
      if [ -n "$dims" ]; then
        w=$(echo "$dims" | cut -dx -f1)
        h=$(echo "$dims" | cut -dx -f2)
        style=" style=\"aspect-ratio: $w/$h\""
      fi
      echo "      <video controls playsinline${style}>" >> "$OUT"
      echo "        <source src=\"$url\" type=\"video/mp4\">" >> "$OUT"
      echo '      </video>' >> "$OUT"
    # ![alt](url) -> <img> tag
    elif echo "$line" | grep -qE '^!\[.*\]\(.*\)$'; then
      alt=$(echo "$line" | sed -E 's/^!\[(.*)\]\(.*\)$/\1/')
      url=$(echo "$line" | sed -E 's/^!\[.*\]\((.*)\)$/\1/')
      echo "      <img src=\"$url\" alt=\"$alt\">" >> "$OUT"
    # Regular text -> <p> tag
    else
      echo "      <p>$line</p>" >> "$OUT"
    fi
  done

  echo '    </div>' >> "$OUT"
done

# Close HTML
cat >> "$OUT" <<'FOOT'
  </main>
</body>
</html>
FOOT

echo "Built index.html with $(ls "$POSTS_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ') posts"
