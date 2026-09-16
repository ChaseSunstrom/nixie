# Shot list

Every file here was produced by `nix run .#media` at commit 74194c8 (2026-09-16T03:01Z) from a real run in a VM;
nothing is mocked. Regenerate with the same command. Stills are PNG, video is webm (1280 wide,
at most 45 s, VP9), GIFs only for loops under 8 s. The whole gallery is kept under 100 MB and
each video under 8 MB so it lives in git with no large-file storage.

| asset | produced by |
|---|---|
| `panel-walkthrough.webm` | `mediaTests.panel` (recorded in the session, ffmpeg to vp9 under the size budget) |
