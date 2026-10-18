/* Optional chapter shortcuts. Native playback, captions and transcript work without JS. */
(() => {
  "use strict";
  const video = document.getElementById("demo-player");
  const chapters = document.querySelector(".demo-chapters");
  const status = document.getElementById("video-status");
  if (!video || !chapters || !status) return;

  const playButton = document.querySelector(".demo-play");
  let pendingTime = null;
  const loadError = "The video couldn’t load. You can read the transcript below or open the video directly.";
  const report = (message) => {
    status.textContent = message;
    status.hidden = !message;
  };
  const seek = () => {
    if (pendingTime === null) return;
    video.currentTime = pendingTime;
    pendingTime = null;
  };
  video.addEventListener("loadedmetadata", seek);
  video.addEventListener("error", () => {
    pendingTime = null;
    report(loadError);
  });
  // Some browsers report source failures only on the <source> element.
  video.querySelector("source")?.addEventListener("error", () => {
    report(loadError);
  });
  chapters.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-demo-time]");
    if (!button) return;
    const time = Number(button.dataset.demoTime);
    if (!Number.isFinite(time) || time < 0) return;
    pendingTime = time;
    report("");
    if (video.readyState >= 1) seek();
    video.scrollIntoView({ block: "center" });
    video.focus({ preventScroll: true });
    video.play().catch(() => {
      if (video.error) { pendingTime = null; report(loadError); return; }
      report("Press Play on the video to start this chapter, or read the transcript below.");
    });
  });
  if (playButton) {
    playButton.hidden = false;
    playButton.addEventListener("click", () => {
      report("");
      video.focus({ preventScroll: true });
      video.play().catch(() => report(video.error ? loadError : "Press Play on the video, or read the transcript below."));
    });
    video.addEventListener("play", () => { playButton.hidden = true; });
    video.addEventListener("ended", () => { playButton.hidden = false; });
  }
  chapters.hidden = false;
})();
