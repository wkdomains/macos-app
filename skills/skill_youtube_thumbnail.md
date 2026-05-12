# YouTube Thumbnail Skill

Use this with `skills/skill_recording.md` or `skills/skill_fast_mode.md` when creating a thumbnail for a recorded wkdomains demo video.

The goal is a 1280x720 thumbnail that reads instantly on mobile, uses a real still from the final video, and makes the wkdomains browser/agent demo feel concrete and clickable.

## Sources

Current baseline guidance:

- YouTube Help recommends custom thumbnails at `1280 x 720`, minimum width `640`, JPG/GIF/PNG, under `2 MB` for videos, and `16:9` aspect ratio: https://support.google.com/youtube/answer/72431
- Thumbnail text should be readable at small mobile/sidebar sizes. Practical current advice is 3 to 5 words, bold sans-serif fonts, high contrast, and testing near `168 x 94`: https://www.notelm.ai/blog/youtube-thumbnail-text-tips
- Good thumbnail fonts have high x-height, open letterforms, and consistent stroke weight. Practical options available on this machine include `Montserrat Bold`, `Impact`, `Avenir Next Condensed Heavy`, and `Helvetica Neue Condensed Black`: https://thumbmentor.com/en/blog/youtube-thumbnail-font-guide

## Default Concept

For wkdomains demo videos, use a “tilted evidence card” layout:

- Full-bleed dark or saturated background.
- A still frame from the final video as the main visual.
- Rotate the still frame slightly, usually `-4` to `-8` degrees.
- Add a thick bright border and subtle shadow around the still.
- Add the wkdomains logo as a badge, preferably pinned to the still frame or headline cluster.
- Add 2 to 5 words of bold headline text.
- Add one short sublabel only if it improves clarity.
- Keep every sticker, badge, and headline fully inside the canvas. Never leave partial words clipped at the edge.

This makes the thumbnail feel like a captured artifact from the demo, not a generic SaaS graphic.

## Assets

wkdomains logo:

```text
macos-app/Assets.xcassets/AppIcon.appiconset/logo.png
```

It is currently `256 x 256` PNG with transparency. Use it as a circular or rounded badge, usually `72` to `110` pixels wide in the thumbnail.

## Thumbnail Specs

Canvas:

```text
1280 x 720
16:9
RGB
PNG or high-quality JPG
Prefer final export under 2 MB
```

Safe design assumptions:

- Keep important text away from the bottom-right corner where YouTube may overlay duration.
- Leave at least `48 px` outer margin.
- Test at `320 x 180` and `168 x 94`.
- If it is not readable at `168 x 94`, reduce words or increase type size.

## Text

Use very short, punchy copy.

Good examples for wkdomains videos:

```text
AI READS A WEBSITE
AI SPEED REVIEW
AGENT WATCHES WEB
60 SEC SITE DIGEST
READS THE WHOLE SITE
CODING AGENT BROWSER
```

Prefer a specific viewer-facing angle over generic labels. `AI READS A WEBSITE` is usually stronger than `AI SITE REVIEW` because it describes the surprising action in plain words.

Avoid:

```text
Complete demonstration of autonomous website inspection and narration
Watch this system browse and record a marketing website
```

Typography:

- Preferred: `Montserrat Bold` or `Montserrat SemiBold`.
- Strong alternatives: `Impact`, `Avenir Next Condensed Heavy`, `Helvetica Neue Condensed Black`.
- Use all caps for 1 to 4 word headline text.
- Use `96 px` to `170 px` for the main headline at 1280x720.
- Use a thick outline or shadow if text sits over video.
- Letter spacing should be normal or slightly tight only if it remains readable.

Good text styling:

```text
white fill + black stroke
yellow fill + black stroke
white fill + cyan shadow
```

Do not use thin script fonts, small paragraph text, or low-contrast gray-on-gray text.

## Still Frame Selection

Use a real frame from the final video.

Pick frames where:

- The browser is clearly visible.
- The page content is meaningful: FAQ, metrics, docs, route list, or a distinctive product section.
- The composition has recognizably “web browsing” content.
- Motion blur is minimal.
- The frame is not mostly blank, transition, or loading state.

Extract candidates:

```sh
mkdir -p /tmp/thumb_frames

ffmpeg -y -i final.mov \
  -vf "fps=1/8,scale=1280:-1" \
  /tmp/thumb_frames/frame_%03d.png
```

For faster manual selection, grab specific timestamps:

```sh
ffmpeg -y -ss 00:00:42 -i final.mov -frames:v 1 /tmp/thumb_frame.png
```

Prefer a frame with a clear content hook. For a fast-mode WithOne video, good candidates are:

- FAQ section.
- Metrics band with tool/developer/uptime numbers.
- `llms.txt` or docs page, because it shows the “AI reading fast” idea.
- Knowledge directory with many categories.

## Layout Recipe

Default 1280x720 composition:

```text
Background:
  dark gradient or blurred/enlarged copy of the still frame

Left/top headline:
  2-5 words
  giant bold font
  high contrast

Main visual:
  still frame at 760-900 px wide
  rotated -5 degrees
  thick border, 8-14 px
  subtle drop shadow
  fully readable unless a deliberate crop adds energy without cutting text

Logo:
  wk logo badge near one corner of the still or headline
  do not cover important page text
  avoid isolated floating placement with no relationship to the composition

Accent:
  one bright color: yellow, cyan, or green
  use it for border, highlight word, or small badge
```

For this product, a good recurring palette:

```text
background: #07110f or #101316
primary text: #ffffff
accent yellow: #ffd84d
accent cyan: #3de7ff
accent green: #6cff8d
shadow: rgba(0,0,0,.45)
```

Do not use too many accent colors in one thumbnail. One strong accent is enough.

## Rendering Quality

Do not render the final thumbnail directly at `1280 x 720` when it includes rotated cards, rounded badges, outlines, or diagonal background texture. Those elements will look jagged and cheap.

Preferred render pipeline:

```text
1. Compose at 3x or 4x size, such as 5120 x 2880.
2. Draw rounded rectangles, badges, strokes, shadows, and rotated cards at that larger size.
3. Use bicubic/Lanczos resampling for rotated screenshots and logos.
4. Downsample once to 1280 x 720 with Lanczos.
5. Export the final PNG from the downsampled image.
```

Polish rules:

- Avoid tight diagonal stripes or tiny texture. They shimmer and look pixelated in YouTube previews.
- Use broad, low-opacity background bands or smooth gradients instead.
- Keep rounded badges simple. Hard black outlines at final resolution make corners look crunchy.
- Use softer shadows plus thinner strokes instead of huge text outlines.
- If a tilted screenshot card is used, keep the full card inside the canvas unless the crop is clearly intentional and no text is cut off.
- Build the screenshot card from the highest-resolution video frame available, then downsample. Do not upscale a 1280px still.
- After rendering, inspect both full size and `320 x 180`; jagged corners that are invisible in code are obvious in the image.

## Iteration Lessons From the WithOne Thumbnail

The first WithOne thumbnail was directionally useful but needed these fixes:

- Replace generic headlines with concrete action. `AI READS / A WEBSITE` read better than `AI SITE / REVIEW`.
- Do not clip stickers or text. A cut-off `WATCHING THE` badge looked unfinished.
- Do not push the tilted still so far right that the main proof disappears. Keep enough of the browser/site visible.
- Brighten the still frame or add a subtle overlay so the website content is recognizable.
- Crop noisy terminal content unless it supports the story. The browser/site should be the evidence.
- Pin the WK logo to the tilted card or headline area. A logo floating alone in the corner feels detached.
- Keep the bottom-right corner free for YouTube's duration overlay. Avoid important pills, labels, or logo marks there.
- Use fewer accents. Yellow border plus cyan underline is enough; adding green can make the design feel scattered.
- Badges should be close to the idea they label. A bottom badge detached from the title/card feels decorative.
- If corners or edges look pixelated, the fix is usually rendering technique, not more decoration: rerender at 4x, use rounded masks at 4x, rotate at 4x, then downsample.

A strong recurring layout for site-review videos:

```text
Headline: AI READS / A WEBSITE
Sublabel: 10 SECTIONS / WITHONE.AI
Badge: REAL BROWSER
Visual: tilted browser still, bright enough to read, yellow border
Logo: WK badge attached to the still-card corner
Optional tag: AI SPEED, placed fully inside the still card
```

## Example Concepts

Fast-mode website digest:

```text
Headline: AI SPEED REVIEW
Sublabel: 10 pages. 2 minutes.
Visual: tilted still from FAQ or llms.txt page
Logo: wk badge in upper-left
Accent: yellow border around tilted still
```

Recording/browser-agent demo:

```text
Headline: AGENT WATCHES WEB
Sublabel: real browser, real recording
Visual: tilted still showing browser + site content
Logo: wk badge pinned to still frame
Accent: cyan glow behind still
```

Site teardown:

```text
Headline: READS THE WHOLE SITE
Sublabel: AI-speed website digest
Visual: tilted still of metrics or FAQ
Logo: wk badge
Accent: green marker highlight behind one word
```

## ImageMagick Implementation Pattern

If ImageMagick is installed, use it for deterministic thumbnails.

Example:

```sh
magick -size 1280x720 gradient:'#07110f-#18211d' \
  \( still.png -resize 860x -bordercolor '#ffd84d' -border 12 -background none -rotate -6 \) \
  -gravity east -geometry +40+20 -composite \
  \( logo.png -resize 88x88 \) \
  -gravity northwest -geometry +54+48 -composite \
  -font "$HOME/Library/Fonts/Montserrat-Bold.ttf" \
  -fill white -stroke black -strokewidth 7 \
  -pointsize 118 -gravity west -annotate +58-70 'AI SPEED' \
  -fill '#ffd84d' -stroke black -strokewidth 7 \
  -pointsize 118 -gravity west -annotate +58+58 'REVIEW' \
  thumbnail.png
```

If the text is too long, rewrite it. Do not shrink below readability.

## Python/Pillow Implementation Pattern

Use Pillow when ImageMagick is unavailable or more control is needed.

Core steps:

1. Open canvas `1280x720`.
2. Create a dark gradient or blurred background from the still frame.
3. Resize still frame to around `820-900 px` wide.
4. Add border by placing it on a larger rectangle.
5. Rotate the bordered still by `-5` degrees with bicubic resampling.
6. Composite it on the right or center-right.
7. Add text with `Montserrat-Bold.ttf`.
8. Add stroke using `ImageDraw.text(..., stroke_width=...)`.
9. Add logo badge.
10. Save as PNG and optionally compress to JPG if over 2 MB.

Font paths available on this machine:

```text
/Users/aa/Library/Fonts/Montserrat-Bold.ttf
/Users/aa/Library/Fonts/Montserrat-SemiBold.ttf
/System/Library/Fonts/Supplemental/Impact.ttf
/System/Library/Fonts/Avenir Next Condensed.ttc
/System/Library/Fonts/HelveticaNeue.ttc
```

## Quality Checks

After creating `thumbnail.png`:

```sh
sips -g pixelWidth -g pixelHeight thumbnail.png
ls -lh thumbnail.png
```

Create small previews:

```sh
magick thumbnail.png -resize 320x180 /tmp/thumb_320.png
magick thumbnail.png -resize 168x94 /tmp/thumb_168.png
```

Check:

- Is the headline readable at `168 x 94`?
- Does the still frame read as a browser/site, not abstract noise?
- Does the logo help brand recognition without stealing focus?
- Is there one obvious idea?
- Is the YouTube duration overlay area free of critical text?
- Is file size under YouTube’s limit?
- Are all sticker and badge labels fully visible, with no accidental edge clipping?
- Does the composition still work if viewed for one second at small size?
- Is the still frame designed into the thumbnail rather than pasted in as a raw screenshot?

## Common Mistakes

- Too many words.
- Text placed on busy page content without stroke.
- Still frame is too small or unrecognizable.
- Thumbnail looks like a screenshot instead of a designed image.
- Logo is tiny or hidden.
- Logo is isolated from the rest of the layout.
- No contrast when scaled down.
- Important text under the bottom-right duration badge.
- Decorative stickers are clipped or use partial words.
- The tilted card is cropped so aggressively that the actual website is hard to inspect.
- The headline names the format instead of the hook.
- Exporting a huge file that YouTube recompresses harshly.

## Final Output

Default output filename:

```text
thumbnail.png
```

For variants:

```text
thumbnail_a.png
thumbnail_b.png
thumbnail_c.png
```

Make 2 or 3 variants when time allows:

- A: big text, tilted browser frame.
- B: fewer words, larger still frame.
- C: more dramatic color accent or logo badge.

Pick the one that is clearest at mobile size, not the one that looks most detailed at full size.
