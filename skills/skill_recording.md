# wkdomains Recording Skill

Use this when an agent needs to record the visible macOS desktop while driving the wkdomains browser through the local API.

## Goal

Record only visible action. Pause recording while the agent reads, thinks, extracts DOM, or plans the next move. Resume recording for user-visible actions such as scrolling, navigation, viewport changes, console-panel display, and UI interaction.

For longer exploratory reviews, prefer writing narration notes during the recording and generating VoxCPM audio after the recording is stopped. This keeps speech synthesis latency out of the pause/resume timing problem.

For short polished videos, use the stricter segment-first edit flow: inspect the site first, write a few site-specific lines, generate the WAV files before recording, measure their exact durations, record one matching browser segment per WAV, mux each segment with its own audio, then concatenate the finished clips.

## Required Local Services

- wkdomains Local API: `http://127.0.0.1:9001`
- VoxCPM speech API, when narration is needed: `http://127.0.0.1:9002`

Check readiness:

```sh
curl -sS http://127.0.0.1:9001/api/v1/page | jq .
curl -sS http://127.0.0.1:9002/health | jq .
```

## Recording API

```sh
curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/start
curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/pause
curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/resume
curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/stop
curl -sS http://127.0.0.1:9001/api/v1/recording | jq .
```

The status response includes:

- `recording`
- `paused`
- `outputPath`
- `lastError`

Always verify state after start, pause, resume, and stop. Do not assume the state changed just because the endpoint returned.

## Correct Flow

1. Prepare the browser before recording:

```sh
curl -sS -X POST http://127.0.0.1:9001/api/v1/viewport \
  -H 'Content-Type: application/json' \
  -d '{"mode":"desktop"}'

curl -sS -X POST http://127.0.0.1:9001/api/v1/navigate \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/","mode":"hard"}'
```

2. Start recording and capture a short orienting segment.
3. Pause recording before reading DOM or thinking.
4. While paused, inspect the page:

```sh
curl -sS http://127.0.0.1:9001/api/v1/dom | jq .
curl -sS http://127.0.0.1:9001/api/v1/links | jq .
curl -sS http://127.0.0.1:9001/api/v1/console | jq .
```

5. Write the next narration line, voice, and segment label into a manifest while still paused.
6. Resume recording.
7. Perform one visible action.
8. Wait for the visible action to finish.
9. Pause recording.
10. Leave a short pause delay so the segment has time to finalize.
11. Repeat.
12. Resume briefly before stop, then stop through the API.
13. Generate all VoxCPM WAV files after the video exists.
14. Mux the WAV files into the final video using the segment manifest.

## Short Polished Segment Flow

Use this when the goal is a short video the website owner would actually like: focused, funny, and about their product.

1. Inspect the site before recording:

```sh
curl -sS http://127.0.0.1:9001/api/v1/page | jq .
curl -sS http://127.0.0.1:9001/api/v1/dom | jq .
curl -sS http://127.0.0.1:9001/api/v1/snapshot | jq .
curl -sS http://127.0.0.1:9001/api/v1/links | jq .
```

2. Write only 3 to 5 narration lines.
3. Make every line about the website content, not the recording process.
4. Use one voice unless the demo specifically needs character variety.
5. Generate the WAV files before recording.
6. Measure each WAV duration with `ffprobe`.
7. Record one browser segment per WAV, slightly longer than the WAV.
8. Extract each segment to exactly the WAV duration.
9. Mux each extracted video segment with its matching WAV.
10. Concatenate the muxed clips.

This produces a final structure like:

```text
clip1 video + clip1 audio
then clip2 video + clip2 audio
then clip3 video + clip3 audio
```

This avoids the overlapping-audio failure mode caused by delayed audio tracks stacked over one long video.

Good narration content:

- Explain what the company appears to do.
- React to concrete claims, numbers, product names, app names, or demos visible on the page.
- Include one useful open question the website raises but does not fully answer.
- Keep the tone entertaining, but make the company look understandable and interesting.

Bad narration content:

- Describing the recording process.
- Saying that the agent is scrolling or switching viewports.
- Generic praise that could fit any SaaS homepage.
- Jokes that are not anchored to visible page content.

Example lines for `withone.ai`:

```text
Looking at With One dot AI, I think I just found mission control for AI agents: one CLI, one login, and every app lined up like it heard the boss music.
Sixty two thousand tools, seventeen thousand developers, and teams from Google to Figma? That is either serious traction, or the most organized guest list in software.
The open question I still have is permissions: when an agent can touch Slack, HubSpot, Shopify, and Gmail, show me the audit trail before I hand it the keys.
```

Generate and measure:

```sh
curl -sS -X POST http://127.0.0.1:9002/say \
  -H 'Content-Type: application/json' \
  -d '{"voice":"cinematic_trailer","text":"Looking at With One dot AI, I think I just found mission control for AI agents.","filename":"seg1.wav"}'

ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 seg1.wav
```

When recording, use the WAV duration as the target visual length. Record a little extra, then trim in ffmpeg.

Assemble without overlapping audio:

```sh
ffmpeg -y -ss 0.00 -t 12.800 -i raw.mov -i seg1.wav \
  -map 0:v:0 -map 1:a:0 \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -shortest clip1.mov

ffmpeg -y -ss 15.00 -t 13.760 -i raw.mov -i seg2.wav \
  -map 0:v:0 -map 1:a:0 \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -shortest clip2.mov

printf "file '%s'\nfile '%s'\n" clip1.mov clip2.mov > concat.txt

ffmpeg -y -f concat -safe 0 -i concat.txt -c copy -movflags +faststart final.mov
```

Use this flow for short 30 to 60 second demos. Use the manifest/delayed-audio flow only when a single continuous recording is more important than exact segment-level narration.

## Section-By-Section Review Flow

Use this when the user wants a review that follows a landing page section by section, such as 10 clips before the FAQ.

1. Inspect the page content with DOM, markdown routes, and screenshots.
2. Identify the main sections before the FAQ.
3. Scroll to candidate positions and make a contact sheet.
4. Write one narration line per visible section.
5. Generate every WAV before recording.
6. Record each section as its own raw movie.
7. Trim each raw movie to the matching WAV duration.
8. Mux each trimmed movie with exactly one WAV.
9. Concatenate the muxed clips.

This is slower than recording one long video, but it avoids cumulative timing drift and makes each clip easier to re-do.

Useful section discovery calls:

```sh
curl -sS http://127.0.0.1:9001/api/v1/dom | jq -r '(.text // .bodyText // .visibleText // "")'
curl -sSL https://www.example.com/md
curl -sS http://127.0.0.1:9001/api/v1/layout | jq .
```

For sites that expose clean markdown routes, prefer those for the section outline, then verify visually in the browser. For `withone.ai`, `/md` exposed a clean outline:

```text
Hero
By the numbers
One CLI
Auth
Agent Capabilities
Use Cases
Flows
Agents
Production Infrastructure
Bridge / Open Source
FAQ
```

Stop before FAQ if the user asks for pre-FAQ sections.

Candidate section map example:

```text
01_hero                 y=0
02_metrics              y=760
03_cli                  y=1180
04_auth                 y=2680
05_capabilities         y=4550
06_use_cases            y=5600
07_flows                y=7000
08_agents               y=8450
09_production           y=9650
10_bridge_open_source   y=11150
```

Always verify these positions visually. Use screenshots or a contact sheet before committing to recording.

Contact-sheet pattern:

```sh
mkdir -p /tmp/site_section_screens

while IFS=$'\t' read -r label y; do
  curl -sS -X POST http://127.0.0.1:9001/api/v1/action \
    -H 'Content-Type: application/json' \
    -d '{"type":"scroll","direction":"top","durationMs":100}' >/dev/null
  sleep 0.2

  curl -sS -X POST http://127.0.0.1:9001/api/v1/action \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --argjson y "$y" '{type:"scroll",y:$y,durationMs:100}')" >/dev/null
  sleep 0.6

  curl -sS http://127.0.0.1:9001/api/v1/screenshot > "/tmp/site_section_screens/$label.png"
done < sections.tsv
```

Narration should comment on what is visible in that section. It can be skeptical or lightly snarky, but it should help a real user understand the value proposition.

Good section-by-section narration examples:

```text
Command center for your AI workforce. Okay With One, that is a big promise; I am hearing air traffic control, but for agents with app permissions.
Sixty two thousand tools, seventeen thousand developers, ninety nine point nine percent uptime, and under one hundred milliseconds. Subtle? No. Effective? Annoyingly, yes.
One login. One CLI. Every app. I respect the confidence, though every app is the kind of phrase that makes a developer quietly reach for the audit logs.
Now we get One login, every integration. That is a little repetitive, but the actual point is useful: OAuth, token refresh, and credentials handled before the agent breaks something.
Connect all your apps through a single prompt. That sounds magical, and also like exactly where I want to see constraints, previews, and a very clear undo button.
```

Raw recording pattern for one section per file:

```sh
# Reset page and scroll to the previous section first.
curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/start
sleep 0.8

# If this section needs movement, scroll during the recording.
curl -sS -X POST http://127.0.0.1:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","y":760,"style":"human","durationMs":3500}'

# Keep recording slightly longer than the WAV duration.
sleep 14.8

curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/stop
sleep 4
curl -sS http://127.0.0.1:9001/api/v1/recording | jq .
```

Store a raw manifest:

```text
label<TAB>target_y<TAB>wav_duration<TAB>raw_mov<TAB>scroll_ms
01_hero<TAB>0<TAB>11.520<TAB>/path/raw1.mov<TAB>0
02_metrics<TAB>760<TAB>13.920<TAB>/path/raw2.mov<TAB>3500
03_cli<TAB>1180<TAB>11.840<TAB>/path/raw3.mov<TAB>2600
```

Then assemble:

```sh
ffmpeg -y -ss 0 -t "$duration" -i "$raw" -i "$wav" \
  -map 0:v:0 -map 1:a:0 \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -shortest "$clip"

printf "file '%s'\n" "$clip" >> concat.txt

ffmpeg -y -f concat -safe 0 -i concat.txt -c copy -movflags +faststart final.mov
```

Verification for section-by-section clips:

```sh
ffprobe -v error -show_entries format=duration,size -show_streams -of json final.mov | jq .
for clip in clip_*.mov; do
  printf '%s ' "$clip"
  ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$clip"
done
```

Expected:

- One audio stream in each clip.
- No delayed audio stack.
- Final duration equals the sum of the WAV durations, within small encoder rounding.
- Section clips visibly land on the intended content.
- The commentary references the visible section, not the mechanics of scrolling.

## Important Timing Lesson

The browser action API often returns after scheduling an action, not after the visual motion has finished. For example, a human-style scroll can return immediately with `status: "started"` while the page is still scrolling.

Correct pattern:

```sh
curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/resume
sleep 1

curl -sS -X POST http://127.0.0.1:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","direction":"bottom","style":"human","durationMs":32000}'

sleep 34
curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/pause
sleep 3
```

The extra sleep after pause matters. It gives the ScreenCaptureKit recording output time to finish the segment before the next resume starts another segment.

Use `direction:"bottom"` for a real full-page pass. `direction:"down"` is a single page-sized move and can look like the agent barely inspected anything.

## Human-Style Website Review

A useful 3-minute inspection flow:

1. Desktop hero: pause to read, resume for a short top-of-page segment.
2. Desktop scroll: resume for a human-style scroll, pause at a meaningful section.
3. Same-site navigation: open Product, Pricing, Docs, About, or Customers.
4. Product/detail scroll: resume and scroll like a person.
5. Switch to small mobile:

```sh
curl -sS -X POST http://127.0.0.1:9001/api/v1/viewport \
  -H 'Content-Type: application/json' \
  -d '{"mode":"mobileSmall"}'
```

6. Verify the viewport actually changed before scrolling:

```sh
curl -sS http://127.0.0.1:9001/api/v1/viewport | jq '{mode,width,height}'
```

Expected mobile state:

```json
{ "mode": "mobileSmall", "width": 390, "height": 720 }
```

7. Mobile scroll: use `direction:"bottom"` with a long enough `durationMs` to reach the page bottom.
8. Switch back to desktop and verify `mode:"desktop"`.
9. Return near the top.
10. Stop recording.

## Narration With VoxCPM

Best default: do not generate audio while recording. Write notes first, then call VoxCPM after the final video exists.

Generate one WAV per narration note:

```sh
curl -sS -X POST http://127.0.0.1:9002/say \
  -H 'Content-Type: application/json' \
  -d '{"voice":"noir_detective","text":"This homepage is where vague security words either become architecture or fog.","filename":"line_001.wav"}'
```

Useful voices:

- `booming_radio`
- `cinematic_trailer`
- `luxury_brand`
- `friendly_support`
- `science_documentary`
- `noir_detective`
- `global_airport`
- `sleep_story`

Keep each line around 2 to 8 seconds. Funny is good, but it should be anchored to something just found on the page.

## Audio Strategy

Do not attach audio to each temp video segment during recording. Let the recorder keep video-only segments and add all narration at the end.

For short polished videos, do not use `adelay`/`amix`. Instead, create separate muxed clips and concatenate them. The output should never have multiple narration tracks active at once.

Maintain two manifests while recording:

```text
segments.tsv
label<TAB>visible_segment_duration_seconds
intro<TAB>4
home-desktop-scroll<TAB>34
home-mobile-scroll<TAB>34
```

```text
narration_notes.tsv
label<TAB>voice<TAB>text
intro<TAB>cinematic_trailer<TAB>Record the browser flow first, generate audio later.
home-desktop-scroll<TAB>noir_detective<TAB>Full desktop scroll. This is where the page has to prove the product is real.
home-mobile-scroll<TAB>luxury_brand<TAB>Mobile full-page scroll. The viewport is smaller and less forgiving.
```

Then mux narration onto the final `.mov` with delayed audio tracks:

```sh
ffmpeg -y \
  -i final-video.mov \
  -i line_001.wav \
  -i line_002.wav \
  -filter_complex '[1:a]adelay=3000:all=1[a1];[2:a]adelay=12000:all=1[a2];[a1][a2]amix=inputs=2:duration=longest:normalize=0[a]' \
  -map 0:v:0 -map '[a]' \
  -c:v copy -c:a aac -b:a 192k \
  narrated.mov
```

Use `segments.tsv` to calculate cumulative segment start times for `adelay`. Generate the WAV files only after recording has stopped, then write a third manifest with the generated WAV paths.

For short polished videos, keep a simpler manifest:

```text
label<TAB>wav_path<TAB>wav_duration<TAB>raw_video_start
seg1_hero<TAB>/path/seg1.wav<TAB>12.800<TAB>0.00
seg2_stats<TAB>/path/seg2.wav<TAB>13.760<TAB>15.00
seg3_question<TAB>/path/seg3.wav<TAB>11.520<TAB>30.60
```

Then cut and mux each row independently.

## Recorder Temp Files

During pause/resume recording, temporary segment files are created under:

```text
/tmp/wkdomains-recording-<UUID>/
```

They are named like:

```text
segment-1.mov
segment-2.mov
segment-3.mov
```

The app assembles them into the final `.mov`, then removes the temp directory. If debugging segment assembly, inspect `/tmp/wkdomains-recording-*` before stop cleanup or temporarily disable cleanup.

## Failure Modes Learned

- If `resume` is followed by `pause` too quickly, the segment may be empty.
- If the script records only the API call duration, not the visible action duration, the final movie misses the scroll/navigation.
- macOS `date +%s%3N` does not provide millisecond timing like GNU date. Use fixed known durations, Python, Perl, or another reliable timer.
- Do not let speech generation happen during the recording unless the demo specifically needs to show it. It makes timing harder and adds long non-visual waits.
- For short polished videos, generate speech before recording so the visual segment can be planned around the exact WAV duration.
- Do not stack multiple delayed narration tracks for a short segmented edit. Mux one audio file per video clip and concatenate the clips.
- If narration is about the mechanics of recording instead of the website, rewrite it before generating audio.
- Always verify viewport mode after `POST /api/v1/viewport`. If the viewport is not `mobileSmall`, do not record the mobile scroll.
- Avoid brittle shell helper names. In zsh, a local variable named `path` can interfere with command lookup because `path` is tied to `PATH`; prefer names like `endpoint`.
- If final assembly fails with `Cannot Open`, suspect an unfinalized segment file.
- Pause should wait for the recording output to finish writing before starting the next segment.
- After `pause`, include a short delay before `resume`; 2 to 3 seconds is a practical safe value for demos.

## Verification

After stop:

```sh
curl -sS http://127.0.0.1:9001/api/v1/recording | jq .
ffprobe -v error -show_entries format=duration,size -of json final.mov | jq .
curl -sS http://127.0.0.1:9001/api/v1/scroll | jq .
```

Expected:

- `recording: false`
- `paused: false`
- `lastError: null`
- A real `outputPath`
- `ffprobe` can open the file
- Video dimensions should match full display capture quality
- Full-page scroll traces should end with `status:"completed"` and `position.y` close to `maxY`.

## Demo Notes

- State what the agent is doing: reading while paused, recording only visible action, generating a narration line, then resuming.
- Show desktop first, then mobile, then back to desktop.
- Scroll down, pause briefly near the bottom or a meaningful section, then return to the top quickly.
- Keep the final view near the top of the site.
- The strongest demo is not raw speed. It is showing an agent that can see, think, narrate, control recording, and produce a clean edited result.
