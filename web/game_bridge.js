// Bridge injected into the Godot web export (build/web/game/index.html) by
// scripts/deploy_web.sh. It reports load progress, readiness and failure to the
// root loader page via postMessage so the loader's bar stays in sync with the
// engine without the parent having to reach into the iframe.
(function () {
	"use strict";

	var done = false;
	var lastProgress = -1;
	var observer = null;

	function post(type, data) {
		try {
			window.parent.postMessage(Object.assign({ type: type }, data || {}), "*");
		} catch (error) { /* parent may be gone */ }
	}

	function stop() {
		done = true;
		if (observer) observer.disconnect();
	}

	function readRatio() {
		var progress = document.getElementById("status-progress");
		if (!progress) return 0;
		var value = parseFloat(progress.value);
		var max = parseFloat(progress.max);
		if (value > 0 && max > 1) return Math.max(0, Math.min(1, value / max));
		return 0;
	}

	function check() {
		if (done) return;
		var notice = document.getElementById("status-notice");
		if (notice && notice.style.display !== "none" && notice.textContent.trim()) {
			stop();
			post("nocaps-failure", { message: notice.textContent.trim() });
			return;
		}
		// The Godot runtime removes #status once the engine has started.
		if (!document.getElementById("status")) {
			stop();
			post("nocaps-ready");
			return;
		}
		var ratio = readRatio();
		if (ratio > 0 && ratio !== lastProgress) {
			lastProgress = ratio;
			post("nocaps-progress", { value: ratio });
		}
	}

	check();

	observer = new MutationObserver(check);
	observer.observe(document.documentElement, {
		subtree: true,
		childList: true,
		attributes: true,
		attributeFilter: ["value", "max", "style"]
	});

	if (document.readyState !== "complete") {
		document.addEventListener("load", check);
	}
}());
