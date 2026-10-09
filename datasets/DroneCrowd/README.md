# DroneCrowd sample footage

Default video source for the AI pipeline:

```
video:datasets/DroneCrowd/sample.mp4
```

`sample.mp4` is bundled with this project (a short people-detection clip) so
the Windows one-command launcher works out of the box. Replace it with any
aerial / crowd footage under the same filename, or point `--source` /
`VIDEO_SOURCE` at a different path.

The DroneCrowd dataset (4.8M annotated head positions across drone footage)
is described at https://arxiv.org/abs/2105.02440 and is a good source of
realistic validation footage if you want to benchmark against it.
