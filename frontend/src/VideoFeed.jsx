import { useEffect, useRef } from "react";

export default function VideoFeed({ data, zone, altitude }) {
  const lastFrameRef = useRef(null);

  useEffect(() => {
    if (data?.frame_b64) {
      lastFrameRef.current = data.frame_b64;
    }
  }, [data?.frame_b64]);

  const frame = data?.frame_b64 || lastFrameRef.current;

  if (!frame) {
    return (
      <div className="video-shell">
        <div className="video-empty">
          <div>
            <strong>Awaiting aerial feed</strong>
            <p>
              Waiting for the AI pipeline. If <code>start.ps1</code> already finished, give it 10–20
              seconds for the first YOLO model download, then refresh.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="video-shell">
      <img
        src={`data:image/jpeg;base64,${frame}`}
        alt="Annotated aerial census feed"
        decoding="async"
      />
      <div className="hud-tag">
        <span className="hud-pill">{zone || "Survey"}</span>
        <span className="hud-pill">{altitude ?? "—"} m AGL</span>
        <span className="hud-pill">{data?.current_frame_count ?? 0} in frame</span>
        {data?.density_estimate != null && (
          <span className="hud-pill">density ~{data.density_estimate}</span>
        )}
      </div>
    </div>
  );
}
