# Image rendering check

This document references a local image **relative to this file**:

![Relative local image](pic.png)

- If you can see the purple-and-blue graphic above, embedded-image rendering works.
- If a broken-image icon or blank space appears instead, rendering is broken.

## Notes for the test

- The image file must sit next to this `.md` file (`pic.png`).
- Absolute `file://` links and remote `http(s)` images are *not* loaded by the
  preview (local-file access is blocked in the renderer by design); only
  relative local images (embedded inline) and `data:` URIs display.
