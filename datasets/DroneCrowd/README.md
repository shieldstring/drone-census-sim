# Aerial census sample footage

Default video source for the AI pipeline:

```
video:datasets/DroneCrowd/sample.mp4
```

`sample.mp4` is a bundled aerial/high-angle demo reel suited to population
census work:

1. Elevated urban intersection with dense pedestrian crossings
2. Top-down recreational riverside scene with many people in view
3. High-altitude open-air gathering / park crowd

Clips are free Mixkit stock footage, joined into one looping demo for the
Windows one-command launcher. Replace this file with your own drone survey
footage under the same name, or point `--source` / `VIDEO_SOURCE` at another path.

The academic DroneCrowd dataset (4.8M annotated head positions across drone
footage) is described at https://arxiv.org/abs/2105.02440 if you want a
heavier validation set.
