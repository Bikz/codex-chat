const state = {
  sessionID: null,
  joinToken: null,
  deviceID: null,
  relayBaseURL: null,
  deviceSessionToken: null,
  wsURL: null,
  socket: null,
  reconnectAttempts: 0,
  reconnectTimer: null,
  lastIncomingSeq: null,
  nextOutgoingSeq: 1,
  canApproveRemotely: false,
  projects: [],
  threads: [],
  pendingApprovals: [],
  selectedProjectID: null,
  selectedThreadID: null,
  messagesByThreadID: new Map()
};

const dom = {
  connectionBadge: document.getElementById("connectionBadge"),
  pairingHint: document.getElementById("pairingHint"),
  sessionValue: document.getElementById("sessionValue"),
  seqValue: document.getElementById("seqValue"),
  statusText: document.getElementById("statusText"),
  pairButton: document.getElementById("pairButton"),
  reconnectButton: document.getElementById("reconnectButton"),
  snapshotButton: document.getElementById("snapshotButton"),
  projectList: document.getElementById("projectList"),
  threadList: document.getElementById("threadList"),
  approvalList: document.getElementById("approvalList"),
  threadTitle: document.getElementById("threadTitle"),
  messageList: document.getElementById("messageList"),
  composerForm: document.getElementById("composerForm"),
  composerInput: document.getElementById("composerInput")
};

function setStatus(text, level = "info") {
  dom.statusText.textContent = text;
  dom.statusText.style.color = level === "error" ? "var(--danger)" : level === "warn" ? "var(--warning)" : "var(--muted)";
}

function setConnectionBadge(isConnected) {
  dom.connectionBadge.textContent = isConnected ? "Connected" : "Disconnected";
  dom.connectionBadge.classList.toggle("connected", isConnected);
}

function parseJoinFromHash() {
  const hash = window.location.hash.replace(/^#/, "");
  const params = new URLSearchParams(hash);
  const sessionID = params.get("sid");
  const joinToken = params.get("jt");
  const relayBaseURL = normalizeRelayBaseURL(params.get("relay"));
  if (sessionID && joinToken) {
    state.sessionID = sessionID;
    state.joinToken = joinToken;
    state.relayBaseURL = relayBaseURL;
    dom.sessionValue.textContent = sessionID;
    const relayHint = relayBaseURL ? ` Relay: ${relayBaseURL}` : "";
    dom.pairingHint.textContent = `Session and one-time join token detected from QR link.${relayHint}`;
    window.history.replaceState({}, document.title, `${window.location.pathname}${window.location.search}`);
  }
}

function baseRelayURL() {
  return state.relayBaseURL || `${window.location.protocol}//${window.location.host}`;
}

function normalizeRelayBaseURL(rawValue) {
  if (typeof rawValue !== "string" || rawValue.trim() === "") {
    return null;
  }
  try {
    const parsed = new URL(rawValue);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return null;
    }
    parsed.pathname = "";
    parsed.search = "";
    parsed.hash = "";
    return parsed.toString().replace(/\/$/, "");
  } catch {
    return null;
  }
}

function renderProjects() {
  dom.projectList.innerHTML = "";
  if (state.projects.length === 0) {
    const li = document.createElement("li");
    li.textContent = "No projects yet";
    dom.projectList.appendChild(li);
    return;
  }

  for (const project of state.projects) {
    const li = document.createElement("li");
    li.textContent = project.name;
    li.classList.toggle("active", project.id === state.selectedProjectID);
    li.addEventListener("click", () => {
      state.selectedProjectID = project.id;
      sendCommand("project.select", { projectID: project.id });
      renderProjects();
      renderThreads();
    });
    dom.projectList.appendChild(li);
  }
}

function renderThreads() {
  dom.threadList.innerHTML = "";
  const visibleThreads = state.selectedProjectID
    ? state.threads.filter((thread) => thread.projectID === state.selectedProjectID)
    : state.threads;

  if (visibleThreads.length === 0) {
    const li = document.createElement("li");
    li.textContent = "No threads yet";
    dom.threadList.appendChild(li);
    return;
  }

  for (const thread of visibleThreads) {
    const li = document.createElement("li");
    li.textContent = thread.title;
    li.classList.toggle("active", thread.id === state.selectedThreadID);
    li.addEventListener("click", () => {
      state.selectedThreadID = thread.id;
      dom.threadTitle.textContent = thread.title;
      sendCommand("thread.select", { threadID: thread.id });
      renderThreads();
      renderMessages();
    });
    dom.threadList.appendChild(li);
  }
}

function renderMessages() {
  dom.messageList.innerHTML = "";
  const threadID = state.selectedThreadID;
  const messages = threadID ? state.messagesByThreadID.get(threadID) || [] : [];

  if (!threadID) {
    const div = document.createElement("div");
    div.className = "message";
    div.textContent = "Select a thread to view conversation updates.";
    dom.messageList.appendChild(div);
    return;
  }

  if (messages.length === 0) {
    const div = document.createElement("div");
    div.className = "message";
    div.textContent = "No messages yet.";
    dom.messageList.appendChild(div);
    return;
  }

  for (const message of messages) {
    const wrapper = document.createElement("div");
    wrapper.className = "message";

    const meta = document.createElement("div");
    meta.className = "meta";
    const timestamp = new Date(message.createdAt || Date.now()).toLocaleTimeString();
    meta.textContent = `${message.role || "system"} · ${timestamp}`;

    const body = document.createElement("div");
    body.textContent = message.text || "";

    wrapper.append(meta, body);
    dom.messageList.appendChild(wrapper);
  }

  dom.messageList.scrollTop = dom.messageList.scrollHeight;
}

function renderApprovals() {
  dom.approvalList.innerHTML = "";
  if (!Array.isArray(state.pendingApprovals) || state.pendingApprovals.length === 0) {
    const li = document.createElement("li");
    li.textContent = "No pending approvals";
    dom.approvalList.appendChild(li);
    return;
  }

  for (const approval of state.pendingApprovals) {
    const li = document.createElement("li");
    const row = document.createElement("div");
    row.className = "approval-row";

    const title = document.createElement("strong");
    title.textContent = `#${approval.requestID || "?"}`;

    const summary = document.createElement("div");
    summary.className = "approval-summary";
    summary.textContent = approval.summary || "Pending approval request";

    row.append(title, summary);

    if (state.canApproveRemotely) {
      const actions = document.createElement("div");
      actions.className = "approval-actions";
      actions.append(
        approvalButton("Approve once", approval, "approve_once", true),
        approvalButton("Approve session", approval, "approve_for_session"),
        approvalButton("Decline", approval, "decline")
      );
      row.append(actions);
    }

    li.append(row);
    dom.approvalList.appendChild(li);
  }
}

function approvalButton(label, approval, decision, isPrimary = false) {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  if (isPrimary) {
    button.classList.add("primary");
  }
  button.addEventListener("click", () => {
    sendCommand("approval.respond", {
      approvalRequestID: approval.requestID,
      approvalDecision: decision
    });
  });
  return button;
}

function applySnapshot(snapshot) {
  state.projects = Array.isArray(snapshot.projects) ? snapshot.projects : [];
  state.threads = Array.isArray(snapshot.threads) ? snapshot.threads : [];
  state.pendingApprovals = Array.isArray(snapshot.pendingApprovals) ? snapshot.pendingApprovals : [];
  state.selectedProjectID = snapshot.selectedProjectID || state.selectedProjectID;
  state.selectedThreadID = snapshot.selectedThreadID || state.selectedThreadID;

  state.messagesByThreadID.clear();
  const messages = Array.isArray(snapshot.messages) ? snapshot.messages : [];
  for (const message of messages) {
    const threadID = message.threadID;
    if (!threadID) {
      continue;
    }
    const bucket = state.messagesByThreadID.get(threadID) || [];
    bucket.push(message);
    state.messagesByThreadID.set(threadID, bucket);
  }

  renderProjects();
  renderThreads();
  renderMessages();
  renderApprovals();
}

function appendMessageFromEvent(eventPayload) {
  const threadID = eventPayload.threadID;
  if (!threadID) {
    return;
  }

  const bucket = state.messagesByThreadID.get(threadID) || [];
  const messageID = eventPayload.messageID || `event-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const exists = bucket.some((message) => message.id === messageID);
  if (exists) {
    return;
  }

  const text = eventPayload.body || "";
  bucket.push({
    id: messageID,
    threadID,
    role: eventPayload.role || "assistant",
    text,
    createdAt: eventPayload.createdAt || new Date().toISOString()
  });
  state.messagesByThreadID.set(threadID, bucket);

  if (!state.selectedThreadID) {
    state.selectedThreadID = threadID;
  }

  renderMessages();
}

function processSequence(seq) {
  if (typeof seq !== "number") {
    return;
  }

  if (state.lastIncomingSeq === null) {
    state.lastIncomingSeq = seq;
    dom.seqValue.textContent = String(seq);
    return;
  }

  const expectedNext = state.lastIncomingSeq + 1;
  if (seq === expectedNext) {
    state.lastIncomingSeq = seq;
    dom.seqValue.textContent = String(seq);
    return;
  }

  if (seq > expectedNext) {
    state.lastIncomingSeq = seq;
    dom.seqValue.textContent = String(seq);
    requestSnapshot("gap_detected");
  }
}

function onSocketMessage(event) {
  let message;
  try {
    message = JSON.parse(event.data);
  } catch {
    setStatus("Received invalid socket payload.", "warn");
    return;
  }

  if (typeof message.seq === "number") {
    processSequence(message.seq);
  }

  if (message.type === "auth_ok") {
    if (typeof message.nextDeviceSessionToken === "string" && message.nextDeviceSessionToken.length > 0) {
      state.deviceSessionToken = message.nextDeviceSessionToken;
    }
    if (typeof message.deviceID === "string" && message.deviceID.length > 0) {
      state.deviceID = message.deviceID;
    }
    setStatus("WebSocket authenticated.");
    requestSnapshot("initial_sync");
    return;
  }

  const payload = message.payload;
  if (!payload || typeof payload !== "object") {
    return;
  }

  if (payload.type === "snapshot") {
    applySnapshot(payload.payload || {});
    setStatus("Snapshot synced.");
    return;
  }

  if (payload.type === "hello") {
    state.canApproveRemotely = Boolean(payload.payload?.supportsApprovals);
    renderApprovals();
    if (!state.canApproveRemotely) {
      setStatus("Connected. Remote approvals are disabled on desktop.", "warn");
    }
    return;
  }

  if (payload.type === "event") {
    const eventPayload = payload.payload || {};
    if (eventPayload.name === "thread.message.append") {
      appendMessageFromEvent(eventPayload);
      return;
    }
    if (eventPayload.name === "approval.requested" || eventPayload.name === "approval.resolved") {
      requestSnapshot("approval_event");
      return;
    }
    if (eventPayload.name === "turn.status.update") {
      const threadLabel = eventPayload.threadID ? ` (${eventPayload.threadID.slice(0, 8)})` : "";
      const stateLabel = eventPayload.body || "updated";
      setStatus(`Turn status${threadLabel}: ${stateLabel}.`);
      return;
    }
  }
}

function closeSocket() {
  if (state.socket) {
    state.socket.onopen = null;
    state.socket.onclose = null;
    state.socket.onmessage = null;
    state.socket.onerror = null;
    state.socket.close();
    state.socket = null;
  }
}

function connectSocket() {
  if (!state.wsURL || !state.deviceSessionToken) {
    setStatus("Missing WebSocket URL or device token.", "error");
    return;
  }

  closeSocket();
  const socket = new WebSocket(state.wsURL);
  state.socket = socket;

  socket.onopen = () => {
    state.reconnectAttempts = 0;
    setConnectionBadge(true);
    setStatus("Connected. Authenticating...");
    socket.send(
      JSON.stringify({
        type: "relay.auth",
        token: state.deviceSessionToken
      })
    );
  };

  socket.onmessage = onSocketMessage;

  socket.onclose = () => {
    setConnectionBadge(false);
    scheduleReconnect();
  };

  socket.onerror = () => {
    setStatus("WebSocket connection error.", "warn");
  };
}

function scheduleReconnect() {
  if (state.reconnectTimer) {
    clearTimeout(state.reconnectTimer);
  }

  const delayMs = Math.min(15_000, 1_000 * 2 ** state.reconnectAttempts);
  state.reconnectAttempts += 1;
  setStatus(`Disconnected. Reconnecting in ${Math.round(delayMs / 1000)}s...`, "warn");

  state.reconnectTimer = setTimeout(() => {
    connectSocket();
  }, delayMs);
}

function sendRaw(payload) {
  if (!state.socket || state.socket.readyState !== WebSocket.OPEN) {
    setStatus("Not connected. Unable to send command.", "warn");
    return;
  }
  state.socket.send(JSON.stringify(payload));
}

function sendCommand(name, options = {}) {
  if (!state.sessionID) {
    return;
  }

  const envelope = {
    schemaVersion: 1,
    sessionID: state.sessionID,
    seq: state.nextOutgoingSeq++,
    timestamp: new Date().toISOString(),
    payload: {
      type: "command",
      payload: {
        name,
        threadID: options.threadID || null,
        projectID: options.projectID || null,
        text: options.text || null,
        approvalRequestID: options.approvalRequestID || null,
        approvalDecision: options.approvalDecision || null
      }
    }
  };

  sendRaw(envelope);
}

function requestSnapshot(reason) {
  sendRaw({
    type: "relay.snapshot_request",
    sessionID: state.sessionID,
    reason,
    lastSeq: state.lastIncomingSeq
  });
}

async function pairDevice() {
  if (!state.sessionID || !state.joinToken) {
    setStatus("Missing session data. Re-open from QR link.", "error");
    return;
  }

  try {
    setStatus("Waiting for desktop pairing approval...");
    const abortController = new AbortController();
    const timeout = setTimeout(() => abortController.abort(), 60_000);
    let response;
    try {
      response = await fetch(`${baseRelayURL()}/pair/join`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          sessionID: state.sessionID,
          joinToken: state.joinToken
        }),
        signal: abortController.signal
      });
    } finally {
      clearTimeout(timeout);
    }

    const payload = await response.json();
    if (!response.ok) {
      if (payload?.error === "pair_request_in_progress") {
        setStatus("Pairing request already pending on desktop. Approve or deny it there first.", "warn");
        return;
      }
      if (payload?.error === "pair_request_timed_out") {
        setStatus("Desktop approval timed out. Request pairing again.", "warn");
        return;
      }
      if (payload?.error === "pair_request_denied") {
        setStatus("Desktop denied this pairing request.", "error");
        return;
      }
      setStatus(payload.message || "Pairing failed.", "error");
      return;
    }

    state.deviceSessionToken = payload.deviceSessionToken;
    state.deviceID = payload.deviceID || state.deviceID;
    state.wsURL = payload.wsURL;
    state.sessionID = payload.sessionID;
    dom.sessionValue.textContent = state.sessionID;
    setStatus("Pairing successful. Connecting...");
    connectSocket();
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      setStatus("Pairing timed out while waiting for desktop approval.", "warn");
      return;
    }
    setStatus(`Pairing request failed: ${error instanceof Error ? error.message : "unknown error"}`, "error");
  }
}

function wireComposer() {
  dom.composerForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const text = dom.composerInput.value.trim();
    if (!text) {
      return;
    }

    if (!state.selectedThreadID) {
      setStatus("Select a thread before sending a message.", "warn");
      return;
    }

    sendCommand("thread.send_message", {
      threadID: state.selectedThreadID,
      text
    });

    const bucket = state.messagesByThreadID.get(state.selectedThreadID) || [];
    bucket.push({
      id: `local-${Date.now()}`,
      threadID: state.selectedThreadID,
      role: "user",
      text,
      createdAt: new Date().toISOString()
    });
    state.messagesByThreadID.set(state.selectedThreadID, bucket);
    dom.composerInput.value = "";
    renderMessages();
  });
}

function wireButtons() {
  dom.pairButton.addEventListener("click", pairDevice);
  dom.reconnectButton.addEventListener("click", () => {
    connectSocket();
  });
  dom.snapshotButton.addEventListener("click", () => {
    requestSnapshot("manual_request");
  });

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && state.socket?.readyState !== WebSocket.OPEN) {
      connectSocket();
    }
  });
}

function registerServiceWorker() {
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {
      setStatus("Service worker registration failed.", "warn");
    });
  }
}

function init() {
  parseJoinFromHash();
  wireButtons();
  wireComposer();
  renderProjects();
  renderThreads();
  renderMessages();
  renderApprovals();
  registerServiceWorker();
}

init();
