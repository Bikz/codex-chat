import crypto from "node:crypto";

const RELAY_HTTP = process.env.REMOTE_RELAY_HTTP || "https://remote.bikz.cc";
const RELAY_WS = process.env.REMOTE_RELAY_WS || "wss://remote.bikz.cc/ws";
const JOIN_BASE = process.env.REMOTE_JOIN_BASE || "https://remote.bikz.cc/rc";
const SESSION_TTL_MS = Number.parseInt(process.env.REMOTE_RELIABILITY_SESSION_TTL_MS || "120000", 10);
const IDLE_TIMEOUT_SECONDS = Number.parseInt(process.env.REMOTE_RELIABILITY_IDLE_TIMEOUT_SECONDS || "1800", 10);
const DEVICES_POLL_INTERVAL_MS = Number.parseInt(process.env.REMOTE_RELIABILITY_DEVICES_POLL_INTERVAL_MS || "15000", 10);
const SUMMARY_INTERVAL_MS = Number.parseInt(process.env.REMOTE_RELIABILITY_SUMMARY_INTERVAL_MS || "5000", 10);

const sessionID = opaqueToken(16);
const joinToken = opaqueToken(32);
const desktopSessionToken = opaqueToken(32);
const joinTokenExpiresAt = new Date(Date.now() + SESSION_TTL_MS).toISOString();
const projectID = "proj-e2e";
const threadID = "thread-e2e";
const joinURL = buildJoinURL();

let ws;
let desktopSeq = 1;
let authenticated = false;
let stopRequested = false;
let devicesPollTimer = null;
let summaryTimer = null;
const commands = [];
const messages = [message("assistant", "Remote reliability harness ready.")];

function opaqueToken(byteCount) {
  return crypto.randomBytes(byteCount).toString("base64url");
}

function buildJoinURL() {
  const url = new URL(JOIN_BASE);
  const fragment = new URLSearchParams({
    sid: sessionID,
    jt: joinToken,
    relay: RELAY_HTTP
  });
  url.hash = fragment.toString();
  return url.toString();
}

function message(role, text) {
  return {
    id: `msg-${opaqueToken(8)}`,
    threadID,
    role,
    text,
    createdAt: new Date().toISOString()
  };
}

function snapshotPayload() {
  return {
    projects: [{ id: projectID, name: "Remote Reliability Project" }],
    threads: [{ id: threadID, projectID, title: "Reliability Thread", isPinned: false }],
    selectedProjectID: projectID,
    selectedThreadID: threadID,
    messages,
    turnState: { threadID, isTurnInProgress: false, isAwaitingRuntimeRequest: false },
    pendingRuntimeRequests: []
  };
}

function envelope(type, payload) {
  return {
    schemaVersion: 2,
    sessionID,
    seq: desktopSeq++,
    timestamp: new Date().toISOString(),
    payload: { type, payload }
  };
}

function sendJSON(payload) {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    throw new Error("desktop websocket is not open");
  }
  ws.send(JSON.stringify(payload));
}

function sendEnvelope(type, payload) {
  const packet = envelope(type, payload);
  sendJSON(packet);
  console.log(JSON.stringify({ kind: "sent_envelope", type, seq: packet.seq }));
}

function sendSnapshot(reason = "manual") {
  sendEnvelope("snapshot", snapshotPayload());
  console.log(JSON.stringify({ kind: "snapshot_sent", reason, messageCount: messages.length }));
}

function sendHello() {
  sendEnvelope("hello", {
    role: "desktop",
    clientName: "Reliability Harness",
    supportsRuntimeRequests: true
  });
}

function sendEvent(name, role, body) {
  sendEnvelope("event", {
    name,
    threadID,
    body,
    messageID: `event-${opaqueToken(8)}`,
    role,
    createdAt: new Date().toISOString()
  });
}

function sendAck(command, commandSeq, status = "accepted", reason = null) {
  sendEnvelope("command_ack", {
    commandSeq,
    commandID: command.commandID,
    commandName: command.name,
    status,
    reason,
    threadID: command.threadID || threadID
  });
}

async function startPairing() {
  const response = await fetch(`${RELAY_HTTP}/pair/start`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      schemaVersion: 2,
      sessionID,
      relayWebSocketURL: RELAY_WS,
      joinToken,
      joinTokenExpiresAt,
      desktopSessionToken,
      idleTimeoutSeconds: IDLE_TIMEOUT_SECONDS
    })
  });
  const payload = await response.json();
  if (!response.ok || !payload.accepted) {
    throw new Error(`pair/start failed: ${response.status} ${JSON.stringify(payload)}`);
  }
  return payload.wsURL || RELAY_WS;
}

async function listDevices() {
  const response = await fetch(`${RELAY_HTTP}/devices/list`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      schemaVersion: 2,
      sessionID,
      desktopSessionToken
    })
  });
  const text = await response.text();
  let payload = null;
  try {
    payload = JSON.parse(text);
  } catch {
    payload = { raw: text };
  }
  return { status: response.status, payload };
}

async function stopPairing() {
  if (stopRequested) return;
  stopRequested = true;
  if (devicesPollTimer) clearInterval(devicesPollTimer);
  if (summaryTimer) clearInterval(summaryTimer);
  try {
    await fetch(`${RELAY_HTTP}/pair/stop`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        schemaVersion: 2,
        sessionID,
        desktopSessionToken
      })
    });
  } catch {}
}

async function handleControlMessage(message) {
  if (message.type === "auth_ok") {
    authenticated = true;
    console.log(JSON.stringify({ kind: "auth_ok" }));
    sendHello();
    sendSnapshot("auth_ok");
    return;
  }

  if (message.type === "relay.pair_request") {
    console.log(
      JSON.stringify({
        kind: "pair_request",
        requestID: message.requestID,
        deviceName: message.deviceName || null,
        requesterIP: message.requesterIP || null
      })
    );
    sendJSON({
      type: "relay.pair_decision",
      sessionID,
      requestID: message.requestID,
      approved: true
    });
    console.log(
      JSON.stringify({ kind: "pair_decision_sent", requestID: message.requestID, approved: true })
    );
    return;
  }

  if (message.type === "relay.pair_result") {
    console.log(
      JSON.stringify({
        kind: "pair_result",
        approved: message.approved ?? null,
        requestID: message.requestID ?? null
      })
    );
    if (message.approved) {
      sendHello();
      sendSnapshot("pair_result");
    }
    return;
  }

  if (message.type === "relay.snapshot_request") {
    console.log(JSON.stringify({ kind: "snapshot_requested", reason: message.reason || null }));
    sendSnapshot(message.reason || "relay.snapshot_request");
    return;
  }

  if (message.type === "relay.device_count") {
    console.log(
      JSON.stringify({ kind: "device_count", connectedDeviceCount: message.connectedDeviceCount ?? null })
    );
    if ((message.connectedDeviceCount || 0) > 0) {
      sendHello();
      sendSnapshot("device_count");
    }
    return;
  }

  if (message.type === "disconnect") {
    console.log(JSON.stringify({ kind: "disconnect", reason: message.reason || null }));
    return;
  }

  console.log(JSON.stringify({ kind: "control_unknown", type: message.type || null, raw: message }));
}

function handleCommandEnvelope(packet) {
  const command = packet.payload?.payload;
  if (!command || packet.payload?.type !== "command") {
    console.log(JSON.stringify({ kind: "envelope_ignored", type: packet.payload?.type || null }));
    return;
  }

  console.log(
    JSON.stringify({
      kind: "command_received",
      name: command.name,
      commandID: command.commandID,
      commandSeq: packet.seq,
      text: command.text || null,
      threadID: command.threadID || null
    })
  );

  commands.push({
    at: new Date().toISOString(),
    commandSeq: packet.seq,
    commandID: command.commandID || null,
    name: command.name || null,
    text: command.text || null
  });

  sendAck(command, packet.seq);

  if (command.name === "thread.select") {
    sendSnapshot("thread.select");
    return;
  }

  if (command.name === "thread.send_message" && typeof command.text === "string") {
    messages.push(message("user", command.text));
    sendEvent("thread.message.append", "user", command.text);
    const replyText = `Harness received: ${command.text}`;
    messages.push(message("assistant", replyText));
    setTimeout(() => {
      sendEvent("thread.message.append", "assistant", replyText);
    }, 250);
    return;
  }

  if (command.name === "runtime_request.respond") {
    sendEvent("runtime.request.responded", "system", command.runtimeRequestID || "runtime_request.respond");
    return;
  }

  sendEvent("harness.unhandled_command", "system", command.name || "unknown");
}

function printSummary() {
  const latestCommand = commands.length > 0 ? commands[commands.length - 1] : null;
  console.log(
    JSON.stringify({
      kind: "summary",
      authenticated,
      commandsReceived: commands.length,
      latestCommand,
      messageCount: messages.length
    })
  );
}

async function pollDevices() {
  try {
    const { status, payload } = await listDevices();
    if (status >= 400) {
      console.log(JSON.stringify({ kind: "devices_list_error", status, payload }));
      return;
    }
    console.log(
      JSON.stringify({
        kind: "devices_list",
        status,
        devices: Array.isArray(payload.devices) ? payload.devices : []
      })
    );
  } catch (error) {
    console.log(JSON.stringify({ kind: "devices_list_error", error: String(error) }));
  }
}

async function main() {
  const effectiveWSURL = await startPairing();
  console.log(JSON.stringify({ kind: "session_started", sessionID, joinURL, wsURL: effectiveWSURL }));

  ws = new WebSocket(effectiveWSURL);

  ws.addEventListener("open", () => {
    console.log(JSON.stringify({ kind: "desktop_socket_open" }));
    sendJSON({ type: "relay.auth", token: desktopSessionToken });
    console.log(JSON.stringify({ kind: "desktop_auth_sent" }));
  });

  ws.addEventListener("message", (event) => {
    const raw = typeof event.data === "string" ? event.data : Buffer.from(event.data).toString("utf8");
    let parsed = null;
    try {
      parsed = JSON.parse(raw);
    } catch {
      console.log(JSON.stringify({ kind: "message_non_json", raw }));
      return;
    }

    if (parsed && typeof parsed.type === "string") {
      void handleControlMessage(parsed);
      return;
    }

    if (parsed && typeof parsed.schemaVersion === "number") {
      handleCommandEnvelope(parsed);
      return;
    }

    console.log(JSON.stringify({ kind: "message_unknown", raw: parsed }));
  });

  ws.addEventListener("close", (event) => {
    console.log(JSON.stringify({ kind: "desktop_socket_close", code: event.code, reason: event.reason || null }));
  });

  ws.addEventListener("error", (event) => {
    console.log(JSON.stringify({ kind: "desktop_socket_error", error: String(event.message || "unknown") }));
  });

  devicesPollTimer = setInterval(() => {
    void pollDevices();
  }, DEVICES_POLL_INTERVAL_MS);
  summaryTimer = setInterval(printSummary, SUMMARY_INTERVAL_MS);
}

process.on("SIGINT", async () => {
  printSummary();
  await stopPairing();
  process.exit(0);
});

process.on("SIGTERM", async () => {
  printSummary();
  await stopPairing();
  process.exit(0);
});

main().catch(async (error) => {
  console.error(JSON.stringify({ kind: "fatal", error: error?.stack || String(error) }));
  await stopPairing();
  process.exit(1);
});
