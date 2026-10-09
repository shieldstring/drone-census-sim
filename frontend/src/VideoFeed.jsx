export default function VideoFeed({ data, zone, altitude }) {
  if (!data?.frame_b64) {
    return (
      <div className="video-shell">
        <div className="video-empty">
          <div>
            <strong>Awaiting aerial feed</strong>
            <p>The AI pipeline will stream annotated frames once detection starts.</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="video-shell">
      <img
        src={`data:image/jpeg;base64,${data.frame_b64}`}
        alt="Annotated aerial census feed"
      />
      <div className="hud-tag">
        <span className="hud-pill">{zone || "Survey"}</span>
        <span className="hud-pill">{altitude ?? "-"} m AGL</span>
        <span className="hud-pill">{data.current_frame_count ?? 0} in frame</span>
      </div>
    </div>
  );
}
