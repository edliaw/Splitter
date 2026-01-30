OSX app to concat and split mp4 files into 10 minute segments.  Requires ffmpeg to be installed.

The program is a drag-and-drop wrapper around:
```
ffmpeg -f concat \
    -safe 0 \
    -i $(files) \
    -c copy \
    -map 0 \
    -f segment \
    -segment_time 600 \
    -reset_timestamps 1 \
    "$(outputDir)/$(prefix)_%03d.mp4"
```
