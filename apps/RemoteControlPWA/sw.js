const CACHE_PREFIX = "codex-remote-";
const CACHE_NAME = `${CACHE_PREFIX}v2`;

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key.startsWith(CACHE_PREFIX))
          .map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});
