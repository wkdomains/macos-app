# wkdomains Recording Skill

Use this when an agent needs to record the visible macOS desktop while driving the wkdomains browser through the local API.

## Goal

Record only visible action. Pause recording while the agent reads, thinks, extracts DOM, plans the next move, or generates narration. Resume recording for user-visible actions such as scrolling, navigation, viewport changes, console-panel display, and UI interaction.

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

5. Generate the next narration line while still paused.
6. Resume recording.
7. Perform one visible action.
8. Wait for the visible action to finish.
9. Pause recording.
10. Leave a short pause delay so the segment has time to finalize.
11. Repeat.
12. Resume briefly before stop, then stop through the API.

## Important Timing Lesson

The browser action API often returns after scheduling an action, not after the visual motion has finished. For example, a human-style scroll can return immediately with `status: "started"` while the page is still scrolling.

Correct pattern:

```sh
curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/resume
sleep 1

curl -sS -X POST http://127.0.0.1:9001/api/v1/action \
  -H 'Content-Type: application/json' \
  -d '{"type":"scroll","direction":"down","style":"human","durationMs":6200}'

sleep 7
curl -sS -X POST http://127.0.0.1:9001/api/v1/recording/pause
sleep 3
```

The extra sleep after pause matters. It gives the ScreenCaptureKit recording output time to finish the segment before the next resume starts another segment.

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

6. Mobile scroll: check headline, nav, CTA, overflow, text wrapping.
7. Switch back to desktop and return near the top.
8. Stop recording.

## Narration With VoxCPM

Generate audio while recording is paused:

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

Maintain a manifest:

```text
label<TAB>wav_path<TAB>visible_segment_duration_seconds
home-scroll<TAB>/Users/aa/os/VoxCPM/outputs/http/line_001.wav<TAB>6
product<TAB>/Users/aa/os/VoxCPM/outputs/http/line_002.wav<TAB>5
mobile-scroll<TAB>/Users/aa/os/VoxCPM/outputs/http/line_003.wav<TAB>7
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

Use the manifest to calculate the `adelay` values. The first delay should usually skip the intro/orientation seconds.

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
- If final assembly fails with `Cannot Open`, suspect an unfinalized segment file.
- Pause should wait for the recording output to finish writing before starting the next segment.
- After `pause`, include a short delay before `resume`; 2 to 3 seconds is a practical safe value for demos.

## Verification

After stop:

```sh
curl -sS http://127.0.0.1:9001/api/v1/recording | jq .
ffprobe -v error -show_entries format=duration,size -of json final.mov | jq .
```

Expected:

- `recording: false`
- `paused: false`
- `lastError: null`
- A real `outputPath`
- `ffprobe` can open the file
- Video dimensions should match full display capture quality

## Demo Notes

- State what the agent is doing: reading while paused, recording only visible action, generating a narration line, then resuming.
- Show desktop first, then mobile, then back to desktop.
- Scroll down, pause briefly near the bottom or a meaningful section, then return to the top quickly.
- Keep the final view near the top of the site.
- The strongest demo is not raw speed. It is showing an agent that can see, think, narrate, control recording, and produce a clean edited result.
