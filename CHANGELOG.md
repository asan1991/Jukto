# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.3]

### Fixed
- YouTube: **Max** and 1080p-and-below now pick H.264 + AAC streams first, so the file plays in Finder / Quick Look / QuickTime with no conversion at all. An explicit 1440p / 4K / 8K keeps the original streams (YouTube offers those only as VP9 / AV1).
- 8K from YouTube: analysis now asks for every client's formats (default + android_vr), and a failed download is retried with other client sets and finally as MKV, so 8K is fetched whenever it exists.
- Trimmed clips: no more black or silent parts. The cut is checked after download and, only if the video and sound do not line up, the common part is cut out exactly (hardware encoder, a few seconds).
- Instagram stories (and other sign-in pages): if Jukto's own sign-in is refused, the sign-in of Chrome, Brave, Edge, Firefox or Safari is tried.
- Links yt-dlp cannot read: Chrome imitation, then browser sign-in, are tried before giving up.
- The Keychain prompt "Jukto WebCrypto Master Key" in the page browser: pages can no longer ask WebKit for that key.
- The SHA-256 shown in the app now has a matching line (same hash, same build) in `Jukto-<ver>-in-app.sha256` and in the release-notes table the release script writes.
- Download status: percent, speed and time left no longer disappear between updates; when the total size is unknown the size so far is shown. Trimmed clips and streams ffmpeg downloads show size and speed too.

### Added
- A link button next to every finished download and every history entry: opens the page in your default browser and copies the link.
- Text size: ⌘+ / ⌘− / ⌘0, or Settings → Appearance. The window grows and shrinks with it.
- A free-form window: any size (down to a narrow strip), drag any edge, snap to screen edges or full screen; Window menu: Snap to Left / Right Half, Fill Screen, Center.
- Unfinished downloads continue when Jukto opens (Settings → General can turn this off). Each download keeps its file name, so yt-dlp carries on from the partial file.

### Changed
- Faster: analysis skips hundreds of translated captions and reads the video once; YouTube downloads use 10 MB chunks and a 1 MB buffer; trimmed clips start ffmpeg with a shorter probe and keep-alive; ffprobe runs once instead of up to four times.
- Smaller: stripped symbols, no debug info.

## [1.0.2]

### Added
- New Jukto versions are published on GitHub Releases and downloaded from inside the app: click **yt-dlp** in the footer (or Settings → Check for Updates), then **Update**. The disk image for your Mac is checked against the release's SHA-256, saved in Downloads and opened. Nothing is checked in the background.
- A link with no particular video in it (a home page, channel or profile): **Analyze** now opens the page at once so you can open the video you want and press **Download this video**.
- Ads are blocked in that browser window only, with a built-in rule list. Nothing is loaded at launch, nothing is downloaded or updated over the network.

### Changed
- MP4 / MOV files that QuickTime can't play (VP9 / AV1 video or Opus sound, the usual case for 4K / 8K on YouTube) are now converted automatically with the Mac's hardware encoder. Files that already play are untouched.
- At most 2 downloads run at the same time; the rest wait in the queue.
- Instagram stories are tried without signing in first; the sign-in window opens only if Instagram refuses.
- The light theme is translucent in the same way as the dark one.

## [1.0.1]

### Added
- Day / night switch (top right of the window and in Settings) and a native-looking light theme.
- Click "Jukto v…" in the footer to show the app's SHA-256 at the bottom of the window and copy it to the clipboard.
- Trimming now shows progress.

### Changed
- Downloads start much faster: the analysis result is reused, so the page is no longer extracted a second time.
- Trimming is a stream copy (no re-encoding): far faster and no CPU load; the clip starts at the nearest keyframe.
- Instagram downloads prefer H.264 so Finder / Quick Look (space bar) can play them.
- The trim control is called "Trim" and sits right under the resolution.

## [1.0.0] — first public release

### Added
- Native SwiftUI interface for yt-dlp (macOS 14+, Apple Silicon and Intel builds).
- Downloads up to the maximum resolution offered (including 4K / 8K); MP4, MOV, WebM, MP3.
- Frame-accurate trimming; any blank tail left by a cut is removed with a lossless stream copy.
- Constant-frame-rate fix for variable-frame-rate files (only when needed).
- Subtitles (embedded, `.srt`, `.vtt`), extra audio tracks, cover art.
- Capture browser for pages yt-dlp can't read; DRM-protected streams are refused.
- Menu-bar status with progress arc, completion sound and notification.
- Optional "target size" compression.
- Updates for yt-dlp / ffmpeg only when you click — checked against publisher SHA-256 and self-tested.

### Privacy and performance
- No telemetry, no install counter, no automatic update checks.
- English-only interface, no language switcher.
- Opaque windows, no blur: the window and the thank-you card open and close instantly.
- Nothing heavy runs at launch (no hashing, no Keychain access, no GPU work).
- Throttled progress updates and a low-frequency clipboard watcher keep CPU and power use down.
