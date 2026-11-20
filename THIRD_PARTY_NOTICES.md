# Third-party notices

Jukto's own source code is MIT-licensed (see `LICENSE`). The released app bundles the following programs,
which are downloaded by `scripts/fetch-binaries.sh` and run as separate processes. Each keeps its own license.

| Component | Project | License |
|-----------|---------|---------|
| yt-dlp | https://github.com/yt-dlp/yt-dlp | Unlicense (public domain) |
| FFmpeg / ffprobe | https://ffmpeg.org — static builds from https://github.com/shaka-project/static-ffmpeg-binaries | LGPL 2.1+ or GPL 2+, depending on how the build was configured |
| Deno | https://github.com/denoland/deno | MIT |
| Ad-server list (`Jukto/Resources/adblock.json`, used only in the capture browser) | Derived from EasyList's ad-server list, https://easylist.to — https://github.com/easylist/easylist | GPLv3+ or CC BY-SA 3.0+ (dual-licensed) |

If you publish release builds that include FFmpeg, check the license of the exact build bundled in that release
(see the release notes of the `static-ffmpeg-binaries` tag recorded in `Jukto/Resources/ffmpeg-tag.txt`)
and meet its source-availability requirements, for example by linking to the FFmpeg source for that version.
