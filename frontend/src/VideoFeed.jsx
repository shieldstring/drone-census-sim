export default function VideoFeed({ data, zone, altitude }) {
  if (!data?.frame_b64) {
    return (
      <div className="video-shell">
        <div className="video-empty">
          <div>
            <strong>Awaiting aerial feed</strong>
            <p>
              The dashboard is open, but the AI pipeline is not sending frames yet. In a project
              terminal run <code>python -m ai_pipeline.counter</code> (or{" "}
              <code>python -m ai_pipeline.demo_stream</code> for a quick demo), then refresh this
              page.
            </p>
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
        <span className="hud-pill">{altitude ?? "—"} m AGL</span>
        <span className="hud-pill">{data.current_frame_count ?? 0} in frame</span>
        {data.density_estimate != null && (
          <span className="hud-pill">density ~{data.density_estimate}</span>
        )}
      </div>
    </div>
  );
}
