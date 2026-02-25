import { createServer } from "node:http";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { URL } from "node:url";
import { WebSocketServer } from "ws";

const PORT = Number(process.env.PORT || "8787");
const HOST = process.env.HOST || "0.0.0.0";
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || `http://localhost:${PORT}`;
const MAX_JSON_BYTES = Number(process.env.MAX_JSON_BYTES || "65536");
const MAX_PAIR_REQUESTS_PER_MINUTE = Number(process.env.MAX_PAIR_REQUESTS_PER_MINUTE || "60");
const MAX_DEVICES_PER_SESSION = Number(process.env.MAX_DEVICES_PER_SESSION || "2");
const SESSION_RETENTION_MS = Number(process.env.SESSION_RETENTION_MS || "600000");
const DEFAULT_ALLOWED_ORIGINS = [
  new URL(PUBLIC_BASE_URL).origin,
  "http://localhost:4173",
  "http://127.0.0.1:4173"
];
const ALLOWED_ORIGINS = parseAllowedOrigins(process.env.ALLOWED_ORIGINS || DEFAULT_ALLOWED_ORIGINS.join(","));

const sessions = new Map();
const deviceTokenIndex = new Map();
const rateBuckets = new Map();

function respondJSON(res, statusCode, payload, extraHeaders = {}) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
    ...extraHeaders
  });
  res.end(body);
}

function nowMs() {
  return Date.now();
}

function readBody(req, maxBytes) {
  return new Promise((resolve, reject) => {
    let total = 0;
    const chunks = [];

    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > maxBytes) {
        reject(new Error("Request body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });

    req.on("end", () => {
      try {
        const raw = Buffer.concat(chunks).toString("utf8");
        resolve(raw.length ? JSON.parse(raw) : {});
      } catch {
        reject(new Error("Invalid JSON body"));
      }
    });

    req.on("error", (error) => reject(error));
  });
}

function parseAllowedOrigins(raw) {
  if (typeof raw !== "string" || raw.trim() === "") {
    return new Set();
  }

  return new Set(
    raw
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean)
      .map((value) => {
        if (value === "*") {
          return "*";
        }

        try {
          return new URL(value).origin;
        } catch {
          return null;
        }
      })
      .filter(Boolean)
  );
}

function requestOrigin(req) {
  const origin = req.headers.origin;
  return typeof origin === "string" ? origin : null;
}

function isAllowedOrigin(origin) {
  if (!origin) {
    return false;
  }
  if (ALLOWED_ORIGINS.has("*")) {
    return true;
  }

  let normalized;
  try {
    normalized = new URL(origin).origin;
  } catch {
    return false;
  }
  return ALLOWED_ORIGINS.has(normalized);
}

function corsHeadersForOrigin(origin) {
  if (!origin || !isAllowedOrigin(origin)) {
    return {};
  }
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "300",
    Vary: "Origin"
  };
}

function randomToken(byteCount = 32) {
  return randomBytes(byteCount).toString("base64url");
}

function isOpaqueToken(value, minChars = 22) {
  if (typeof value !== "string") {
    return false;
  }
  if (value.length < minChars || value.length > 512) {
    return false;
  }
  return /^[A-Za-z0-9_-]+$/.test(value);
}

function safeTokenEquals(lhs, rhs) {
  if (!isOpaqueToken(lhs, 1) || !isOpaqueToken(rhs, 1)) {
    return false;
  }
  const lhsBuffer = Buffer.from(lhs);
  const rhsBuffer = Buffer.from(rhs);
  if (lhsBuffer.length !== rhsBuffer.length) {
    return false;
  }
  return timingSafeEqual(lhsBuffer, rhsBuffer);
}

function clientIP(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return req.socket.remoteAddress || "unknown";
}

function isRateLimited(ip) {
  const key = ip || "unknown";
  const bucket = rateBuckets.get(key);
  const now = nowMs();

  if (!bucket || now >= bucket.windowEndsAt) {
    rateBuckets.set(key, {
      count: 1,
      windowEndsAt: now + 60_000
    });
    return false;
  }

  bucket.count += 1;
  if (bucket.count > MAX_PAIR_REQUESTS_PER_MINUTE) {
    return true;
  }

  return false;
}

function sessionLogID(sessionId) {
  if (typeof sessionId !== "string" || sessionId.length < 10) {
    return sessionId;
  }
  return `${sessionId.slice(0, 6)}...${sessionId.slice(-4)}`;
}

function closeSession(sessionId, reason) {
  const session = sessions.get(sessionId);
  if (!session) {
    return;
  }

  for (const token of session.deviceSessionTokens) {
    deviceTokenIndex.delete(token);
  }

  if (session.desktopSocket && session.desktopSocket.readyState === 1) {
    session.desktopSocket.close(1000, reason);
  }

  for (const [, mobileSocket] of session.mobileSockets) {
    if (mobileSocket.readyState === 1) {
      mobileSocket.close(1000, reason);
    }
  }

  sessions.delete(sessionId);
  console.info(`[relay] closed session=${sessionLogID(sessionId)} reason=${reason}`);
}

function scheduleSessionSweep() {
  const now = nowMs();
  for (const [sessionId, session] of sessions) {
    const idleLimitMs = Math.max(60, session.idleTimeoutSeconds) * 1000;
    if (now - session.lastActivityAt >= idleLimitMs) {
      closeSession(sessionId, "idle_timeout");
      continue;
    }

    const isPastRetention = now - session.createdAt > SESSION_RETENTION_MS;
    const hasNoConnections = !session.desktopSocket && session.mobileSockets.size === 0;
    if (isPastRetention && hasNoConnections) {
      closeSession(sessionId, "retention_expired");
      continue;
    }
  }
}

function sendJSON(socket, payload) {
  if (socket.readyState !== 1) {
    return;
  }
  socket.send(JSON.stringify(payload));
}

function relayDeviceCount(session) {
  if (!session.desktopSocket || session.desktopSocket.readyState !== 1) {
    return;
  }
  sendJSON(session.desktopSocket, {
    type: "relay.device_count",
    sessionID: session.sessionID,
    connectedDeviceCount: session.mobileSockets.size
  });
}

function resolveWebSocketAuth(token) {
  if (!isOpaqueToken(token, 22)) {
    return null;
  }

  for (const session of sessions.values()) {
    if (safeTokenEquals(session.desktopSessionToken, token)) {
      return { role: "desktop", sessionID: session.sessionID };
    }
  }

  const sessionID = deviceTokenIndex.get(token);
  if (sessionID) {
    return { role: "mobile", sessionID };
  }

  return null;
}

function buildWebSocketURL() {
  const base = new URL(PUBLIC_BASE_URL);
  base.protocol = base.protocol === "https:" ? "wss:" : "ws:";
  base.pathname = "/ws";
  base.search = "";
  base.hash = "";
  return base.toString();
}

function normalizeRelayWebSocketURL(rawValue) {
  if (typeof rawValue !== "string" || rawValue.trim() === "") {
    return null;
  }

  try {
    const parsed = new URL(rawValue);
    if (parsed.protocol !== "ws:" && parsed.protocol !== "wss:") {
      return null;
    }
    if (!parsed.pathname || parsed.pathname === "/") {
      parsed.pathname = "/ws";
    }
    parsed.search = "";
    parsed.hash = "";
    return parsed.toString();
  } catch {
    return null;
  }
}

const server = createServer(async (req, res) => {
  const requestURL = new URL(req.url || "/", PUBLIC_BASE_URL);
  const path = requestURL.pathname;
  const origin = requestOrigin(req);
  const corsHeaders = corsHeadersForOrigin(origin);

  if (req.method === "OPTIONS" && (path === "/pair/start" || path === "/pair/join")) {
    if (origin && !isAllowedOrigin(origin)) {
      return respondJSON(res, 403, {
        error: "origin_not_allowed",
        message: "Origin is not allowed."
      });
    }
    res.writeHead(204, corsHeaders);
    res.end();
    return;
  }

  if (req.method === "GET" && path === "/healthz") {
    return respondJSON(res, 200, {
      ok: true,
      sessions: sessions.size,
      now: new Date().toISOString()
    });
  }

  if (req.method === "POST" && (path === "/pair/start" || path === "/pair/join")) {
    if (origin && !isAllowedOrigin(origin)) {
      return respondJSON(res, 403, {
        error: "origin_not_allowed",
        message: "Origin is not allowed."
      }, corsHeaders);
    }

    if (isRateLimited(clientIP(req))) {
      return respondJSON(res, 429, {
        error: "rate_limited",
        message: "Too many pairing attempts. Try again in a minute."
      }, corsHeaders);
    }
  }

  if (req.method === "POST" && path === "/pair/start") {
    try {
      const body = await readBody(req, MAX_JSON_BYTES);
      const sessionID = body.sessionID;
      const joinToken = body.joinToken;
      const desktopSessionToken = body.desktopSessionToken;
      const joinTokenExpiresAtMs = Date.parse(body.joinTokenExpiresAt);
      const idleTimeoutSeconds = Number(body.idleTimeoutSeconds || 1800);
      const resolvedRelayWebSocketURL = normalizeRelayWebSocketURL(body.relayWebSocketURL) || buildWebSocketURL();

      if (!isOpaqueToken(sessionID, 16) || !isOpaqueToken(joinToken, 22) || !isOpaqueToken(desktopSessionToken, 22)) {
        return respondJSON(res, 400, {
          error: "invalid_pair_start",
          message: "sessionID, joinToken, and desktopSessionToken must be high-entropy opaque identifiers."
        }, corsHeaders);
      }

      if (!Number.isFinite(joinTokenExpiresAtMs) || joinTokenExpiresAtMs <= nowMs()) {
        return respondJSON(res, 400, {
          error: "expired_join_token",
          message: "joinTokenExpiresAt must be in the future."
        }, corsHeaders);
      }

      const existing = sessions.get(sessionID);
      if (existing) {
        closeSession(sessionID, "replaced_by_new_pair_start");
      }

      sessions.set(sessionID, {
        sessionID,
        joinToken,
        joinTokenExpiresAtMs,
        joinTokenUsedAtMs: null,
        desktopSessionToken,
        deviceSessionTokens: new Set(),
        mobileSockets: new Map(),
        desktopSocket: null,
        relayWebSocketURL: resolvedRelayWebSocketURL,
        idleTimeoutSeconds: Math.max(60, Math.min(idleTimeoutSeconds, 86_400)),
        createdAt: nowMs(),
        lastActivityAt: nowMs()
      });

      console.info(`[relay] pair_start session=${sessionLogID(sessionID)}`);
      return respondJSON(res, 200, {
        accepted: true,
        sessionID,
        wsURL: resolvedRelayWebSocketURL
      }, corsHeaders);
    } catch (error) {
      return respondJSON(res, 400, {
        error: "invalid_request",
        message: error instanceof Error ? error.message : "Invalid request body"
      }, corsHeaders);
    }
  }

  if (req.method === "POST" && path === "/pair/join") {
    try {
      const body = await readBody(req, MAX_JSON_BYTES);
      const sessionID = body.sessionID;
      const joinToken = body.joinToken;

      if (!isOpaqueToken(sessionID, 16) || !isOpaqueToken(joinToken, 22)) {
        return respondJSON(res, 400, {
          error: "invalid_pair_join",
          message: "sessionID and joinToken are required."
        }, corsHeaders);
      }

      const session = sessions.get(sessionID);
      if (!session) {
        return respondJSON(res, 404, {
          error: "session_not_found",
          message: "Remote session not found."
        }, corsHeaders);
      }

      if (nowMs() >= session.joinTokenExpiresAtMs) {
        return respondJSON(res, 410, {
          error: "join_token_expired",
          message: "Join token has expired."
        }, corsHeaders);
      }

      if (session.joinTokenUsedAtMs !== null) {
        return respondJSON(res, 409, {
          error: "join_token_already_used",
          message: "Join token has already been redeemed. Start a new session from desktop."
        }, corsHeaders);
      }

      if (!safeTokenEquals(session.joinToken, joinToken)) {
        return respondJSON(res, 403, {
          error: "invalid_join_token",
          message: "Join token is invalid."
        }, corsHeaders);
      }

      if (session.deviceSessionTokens.size >= MAX_DEVICES_PER_SESSION) {
        return respondJSON(res, 409, {
          error: "device_cap_reached",
          message: `This session allows at most ${MAX_DEVICES_PER_SESSION} connected devices.`
        }, corsHeaders);
      }

      const deviceSessionToken = randomToken(32);
      session.joinTokenUsedAtMs = nowMs();
      session.deviceSessionTokens.add(deviceSessionToken);
      session.lastActivityAt = nowMs();
      deviceTokenIndex.set(deviceSessionToken, sessionID);

      console.info(`[relay] pair_join session=${sessionLogID(sessionID)}`);
      return respondJSON(res, 200, {
        accepted: true,
        sessionID,
        deviceSessionToken,
        wsURL: session.relayWebSocketURL || buildWebSocketURL()
      }, corsHeaders);
    } catch (error) {
      return respondJSON(res, 400, {
        error: "invalid_request",
        message: error instanceof Error ? error.message : "Invalid request body"
      }, corsHeaders);
    }
  }

  respondJSON(res, 404, {
    error: "not_found"
  });
});

const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_JSON_BYTES });

wss.on("connection", (socket, request, authContext) => {
  const { sessionID, role } = authContext;
  const session = sessions.get(sessionID);
  if (!session) {
    socket.close(1008, "session_not_found");
    return;
  }

  session.lastActivityAt = nowMs();

  if (role === "desktop") {
    if (session.desktopSocket && session.desktopSocket.readyState === 1) {
      session.desktopSocket.close(1000, "desktop_reconnected");
    }
    session.desktopSocket = socket;
    sendJSON(socket, {
      type: "auth_ok",
      role,
      sessionID,
      connectedDeviceCount: session.mobileSockets.size
    });
    console.info(`[relay] desktop_connected session=${sessionLogID(sessionID)}`);
  } else {
    if (session.mobileSockets.size >= MAX_DEVICES_PER_SESSION) {
      socket.close(1008, "device_cap_reached");
      return;
    }

    const connectionID = randomToken(10);
    socket.connectionID = connectionID;
    session.mobileSockets.set(connectionID, socket);
    sendJSON(socket, {
      type: "auth_ok",
      role,
      sessionID,
      connectedDeviceCount: session.mobileSockets.size
    });
    relayDeviceCount(session);
    console.info(`[relay] mobile_connected session=${sessionLogID(sessionID)} devices=${session.mobileSockets.size}`);
  }

  socket.on("message", (data, isBinary) => {
    if (isBinary) {
      socket.close(1003, "binary_not_supported");
      return;
    }

    let parsed;
    try {
      parsed = JSON.parse(data.toString("utf8"));
    } catch {
      socket.close(1003, "invalid_json");
      return;
    }

    session.lastActivityAt = nowMs();
    if (parsed && typeof parsed === "object" && parsed.sessionID && parsed.sessionID !== sessionID) {
      socket.close(1008, "session_mismatch");
      return;
    }

    if (role === "desktop") {
      for (const [, mobileSocket] of session.mobileSockets) {
        sendJSON(mobileSocket, parsed);
      }
      return;
    }

    if (session.desktopSocket && session.desktopSocket.readyState === 1) {
      sendJSON(session.desktopSocket, parsed);
    }
  });

  socket.on("close", () => {
    const liveSession = sessions.get(sessionID);
    if (!liveSession) {
      return;
    }

    liveSession.lastActivityAt = nowMs();

    if (role === "desktop") {
      if (liveSession.desktopSocket === socket) {
        liveSession.desktopSocket = null;
      }
      console.info(`[relay] desktop_disconnected session=${sessionLogID(sessionID)}`);
      return;
    }

    if (socket.connectionID) {
      liveSession.mobileSockets.delete(socket.connectionID);
    }
    relayDeviceCount(liveSession);
    console.info(`[relay] mobile_disconnected session=${sessionLogID(sessionID)} devices=${liveSession.mobileSockets.size}`);
  });
});

server.on("upgrade", (request, socket, head) => {
  const requestURL = new URL(request.url || "/", PUBLIC_BASE_URL);
  if (requestURL.pathname !== "/ws") {
    socket.destroy();
    return;
  }

  const token = requestURL.searchParams.get("token") || "";
  const authContext = resolveWebSocketAuth(token);
  if (!authContext) {
    socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
    socket.destroy();
    return;
  }
  if (authContext.role === "mobile") {
    const origin = requestOrigin(request);
    if (!origin || !isAllowedOrigin(origin)) {
      socket.write("HTTP/1.1 403 Forbidden\r\n\r\n");
      socket.destroy();
      return;
    }
  }

  wss.handleUpgrade(request, socket, head, (webSocket) => {
    wss.emit("connection", webSocket, request, authContext);
  });
});

setInterval(scheduleSessionSweep, 30_000).unref();

server.listen(PORT, HOST, () => {
  console.info(`[relay] listening on ${HOST}:${PORT}`);
  console.info(`[relay] public base URL: ${PUBLIC_BASE_URL}`);
  if (ALLOWED_ORIGINS.has("*")) {
    console.info("[relay] allowed origins: *");
  } else {
    console.info(`[relay] allowed origins: ${Array.from(ALLOWED_ORIGINS).join(", ")}`);
  }
});
