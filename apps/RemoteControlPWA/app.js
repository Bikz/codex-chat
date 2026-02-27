const state = {
  sessionID: null,
  joinToken: null,
  deviceID: null,
  deviceName: null,
  relayBaseURL: null,
  deviceSessionToken: null,
  wsURL: null,
  socket: null,
  isAuthenticated: false,
  reconnectAttempts: 0,
  reconnectTimer: null,
  reconnectDisabledReason: null,
  isPairingInFlight: false,
  lastIncomingSeq: null,
  lastSyncedAt: null,
  isSyncStale: false,
  pendingSnapshotReason: null,
  nextOutgoingSeq: 1,
  awaitingGapSnapshot: false,
  canApproveRemotely: false,
  queuedCommands: [],
  queuedCommandsBytes: 0,
  projects: [],
  threads: [],
  pendingApprovals: [],
  selectedProjectID: null,
  selectedThreadID: null,
  messagesByThreadID: new Map(),
  turnStateByThreadID: new Map(),
  unreadByThreadID: new Map()
};

const MAX_QUEUED_COMMANDS = 64;
const MAX_QUEUED_COMMAND_BYTES = 256 * 1024;

const dom = {
  connectionBadge: document.getElementById("connectionBadge"),
  pairingHint: document.getElementById("pairingHint"),
  sessionValue: document.getElementById("sessionValue"),
  seqValue: document.getElementById("seqValue"),
  lastSyncedValue: document.getElementById("lastSyncedValue"),
  statusText: document.getElementById("statusText"),
  pairButton: document.getElementById("pairButton"),
  reconnectButton: document.getElementById("reconnectButton"),
  snapshotButton: document.getElementById("snapshotButton"),
  preConnectPanel: document.getElementById("preConnectPanel"),
  workspacePanel: document.getElementById("workspacePanel"),
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

function refreshPairButtonState() {
  dom.pairButton.disabled = state.isPairingInFlight || !state.joinToken;
}

function setConnectionBadge(isConnected) {
  dom.connectionBadge.textContent = isConnected ? (state.isSyncStale ? "Stale" : "Connected") : "Disconnected";
  dom.connectionBadge.classList.toggle("connected", isConnected);
  dom.connectionBadge.classList.toggle("stale", isConnected && state.isSyncStale);
}

function updateLastSyncedLabel() {
  if (!state.lastSyncedAt) {
    dom.lastSyncedValue.textContent = "Never";
    return;
  }

  const deltaMs = Date.now() - state.lastSyncedAt;
  if (deltaMs < 5_000) {
    dom.lastSyncedValue.textContent = "Just now";
    return;
  }

  const deltaSeconds = Math.floor(deltaMs / 1_000);
  if (deltaSeconds < 60) {
    dom.lastSyncedValue.textContent = `${deltaSeconds}s ago`;
    return;
  }

  const deltaMinutes = Math.floor(deltaSeconds / 60);
  if (deltaMinutes < 60) {
    dom.lastSyncedValue.textContent = `${deltaMinutes}m ago`;
    return;
  }

  dom.lastSyncedValue.textContent = new Date(state.lastSyncedAt).toLocaleTimeString();
}

function updateWorkspaceVisibility() {
  const showWorkspace = state.isAuthenticated;
  dom.workspacePanel.hidden = !showWorkspace;
  dom.preConnectPanel.hidden = showWorkspace;
}

function markSynced() {
  state.lastSyncedAt = Date.now();
  state.isSyncStale = false;
  updateLastSyncedLabel();
  setConnectionBadge(state.isAuthenticated);
}

function refreshSyncFreshness() {
  updateLastSyncedLabel();
  if (state.socket?.readyState !== WebSocket.OPEN || !state.lastSyncedAt) {
    return;
  }

  const staleThresholdMs = 45_000;
  const isStale = Date.now() - state.lastSyncedAt >= staleThresholdMs;
  if (isStale && !state.isSyncStale) {
    state.isSyncStale = true;
    setConnectionBadge(true);
    setStatus("Connection is live but may be stale. Use Request Snapshot to resync.", "warn");
  }
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
  refreshPairButtonState();
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

function inferredDeviceName() {
  if (typeof navigator === "undefined") {
    return "Remote Device";
  }

  const userAgentData = navigator.userAgentData;
  if (userAgentData && typeof userAgentData.platform === "string" && userAgentData.platform.trim() !== "") {
    const platform = userAgentData.platform.trim();
    return platform === "macOS" ? "Mac Browser" : `${platform} Browser`;
  }

  const ua = navigator.userAgent || "";
  if (/iPhone/i.test(ua)) {
    return "iPhone";
  }
  if (/iPad/i.test(ua)) {
    return "iPad";
  }
  if (/Android/i.test(ua)) {
    return "Android Device";
  }
  if (/Macintosh|Mac OS X/i.test(ua)) {
    return "Mac Browser";
  }
  if (/Windows/i.test(ua)) {
    return "Windows Browser";
  }

  return "Remote Device";
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
  const pendingApprovalsByThreadID = new Map();
  for (const approval of state.pendingApprovals) {
    if (!approval?.threadID) {
      continue;
    }
    pendingApprovalsByThreadID.set(
      approval.threadID,
      (pendingApprovalsByThreadID.get(approval.threadID) || 0) + 1
    );
  }

  if (visibleThreads.length === 0) {
    const li = document.createElement("li");
    li.textContent = "No threads yet";
    dom.threadList.appendChild(li);
    return;
  }

  for (const thread of visibleThreads) {
    const li = document.createElement("li");
    const row = document.createElement("div");
    row.className = "thread-row";

    const title = document.createElement("span");
    title.className = "thread-title";
    title.textContent = thread.title;

    const badges = document.createElement("span");
    badges.className = "thread-badges";

    const isRunning = state.turnStateByThreadID.get(thread.id) === true;
    if (isRunning) {
      const runningBadge = document.createElement("span");
      runningBadge.className = "thread-badge running";
      runningBadge.textContent = "Running";
      badges.appendChild(runningBadge);
    }

    const approvalCount = pendingApprovalsByThreadID.get(thread.id) || 0;
    if (approvalCount > 0) {
      const approvalBadge = document.createElement("span");
      approvalBadge.className = "thread-badge approval";
      approvalBadge.textContent = approvalCount === 1 ? "1 approval" : `${approvalCount} approvals`;
      badges.appendChild(approvalBadge);
    }

    const hasUnread = state.unreadByThreadID.get(thread.id) === true;
    if (hasUnread && thread.id !== state.selectedThreadID) {
      const unreadBadge = document.createElement("span");
      unreadBadge.className = "thread-badge unread";
      unreadBadge.textContent = "New";
      badges.appendChild(unreadBadge);
    }

    row.append(title, badges);
    li.appendChild(row);
    li.classList.toggle("active", thread.id === state.selectedThreadID);
    li.addEventListener("click", () => {
      state.selectedThreadID = thread.id;
      state.unreadByThreadID.set(thread.id, false);
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

function messageSignature(messages) {
  if (!Array.isArray(messages) || messages.length === 0) {
    return "";
  }
  const lastMessage = messages[messages.length - 1];
  return `${lastMessage.id || ""}:${lastMessage.createdAt || ""}:${lastMessage.text || ""}`;
}

function applySnapshot(snapshot) {
  state.projects = Array.isArray(snapshot.projects) ? snapshot.projects : [];
  state.threads = Array.isArray(snapshot.threads) ? snapshot.threads : [];
  state.pendingApprovals = Array.isArray(snapshot.pendingApprovals) ? snapshot.pendingApprovals : [];
  state.selectedProjectID = snapshot.selectedProjectID || state.selectedProjectID;
  state.selectedThreadID = snapshot.selectedThreadID || state.selectedThreadID;
  if (state.selectedThreadID) {
    state.unreadByThreadID.set(state.selectedThreadID, false);
  }
  if (snapshot.turnState?.threadID) {
    state.turnStateByThreadID.set(snapshot.turnState.threadID, Boolean(snapshot.turnState.isTurnInProgress));
  }

  const messages = Array.isArray(snapshot.messages) ? snapshot.messages : [];
  const nextByThread = new Map();
  for (const message of messages) {
    const threadID = message.threadID;
    if (!threadID) {
      continue;
    }
    const bucket = nextByThread.get(threadID) || [];
    bucket.push(message);
    nextByThread.set(threadID, bucket);
  }

  for (const [threadID, bucket] of nextByThread.entries()) {
    const previousBucket = state.messagesByThreadID.get(threadID) || [];
    const normalizedBucket = bucket.slice(-240);
    const didChange = messageSignature(previousBucket) !== messageSignature(normalizedBucket);
    if (didChange && threadID !== state.selectedThreadID) {
      state.unreadByThreadID.set(threadID, true);
    }
    state.messagesByThreadID.set(threadID, normalizedBucket);
  }

  const knownThreadIDs = new Set(state.threads.map((thread) => thread.id));
  for (const threadID of state.turnStateByThreadID.keys()) {
    if (!knownThreadIDs.has(threadID)) {
      state.turnStateByThreadID.delete(threadID);
    }
  }
  for (const threadID of state.unreadByThreadID.keys()) {
    if (!knownThreadIDs.has(threadID)) {
      state.unreadByThreadID.delete(threadID);
    }
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
  if (bucket.length > 240) {
    bucket.splice(0, bucket.length - 240);
  }
  state.messagesByThreadID.set(threadID, bucket);

  if (!state.selectedThreadID) {
    state.selectedThreadID = threadID;
  } else if (state.selectedThreadID !== threadID) {
    state.unreadByThreadID.set(threadID, true);
  }

  if (state.selectedThreadID === threadID) {
    state.unreadByThreadID.set(threadID, false);
  }

  renderThreads();
  renderMessages();
}

function processSequence(seq) {
  if (typeof seq !== "number") {
    return "accepted";
  }
  if (!Number.isSafeInteger(seq) || seq < 0) {
    return "ignored";
  }

  if (state.lastIncomingSeq === null) {
    state.lastIncomingSeq = seq;
    dom.seqValue.textContent = String(seq);
    return "accepted";
  }

  const expectedNext = state.lastIncomingSeq + 1;
  if (seq === expectedNext) {
    state.lastIncomingSeq = seq;
    dom.seqValue.textContent = String(seq);
    return "accepted";
  }

  if (seq > expectedNext) {
    return "gap";
  }

  return "stale";
}

function onSocketMessage(event) {
  let message;
  try {
    message = JSON.parse(event.data);
  } catch {
    setStatus("Received invalid socket payload.", "warn");
    return;
  }

  if (message.type === "auth_ok") {
    state.isAuthenticated = true;
    state.reconnectDisabledReason = null;
    if (typeof message.nextDeviceSessionToken === "string" && message.nextDeviceSessionToken.length > 0) {
      state.deviceSessionToken = message.nextDeviceSessionToken;
    }
    if (typeof message.deviceID === "string" && message.deviceID.length > 0) {
      state.deviceID = message.deviceID;
    }
    state.awaitingGapSnapshot = false;
    updateWorkspaceVisibility();
    markSynced();
    setStatus("WebSocket authenticated.");
    flushQueuedCommands();
    requestSnapshot(state.pendingSnapshotReason || "initial_sync");
    return;
  }

  if (message.type === "disconnect") {
    state.isAuthenticated = false;
    const reason = typeof message.reason === "string" ? message.reason : "unknown";
    if (reason === "device_revoked" || reason === "stopped_by_desktop") {
      state.reconnectDisabledReason = reason;
      state.deviceSessionToken = null;
      state.joinToken = null;
      state.queuedCommands = [];
      state.queuedCommandsBytes = 0;
      state.pendingSnapshotReason = null;
      refreshPairButtonState();
    }
    updateWorkspaceVisibility();
    setStatus(disconnectMessageForReason(reason), "warn");
    return;
  }

  if (message.type === "relay.error") {
    const errorCode = typeof message.error === "string" ? message.error : "relay_error";
    const errorMessage = typeof message.message === "string" ? message.message : "Relay rejected the latest request.";
    if (errorCode === "command_rate_limited") {
      setStatus("Too many commands too quickly. Wait a moment and try again.", "warn");
      return;
    }
    if (errorCode === "replayed_command") {
      setStatus("Out-of-order command detected. Resyncing snapshot now...", "warn");
      requestSnapshot("command_replay_rejected");
      return;
    }
    if (errorCode === "snapshot_rate_limited") {
      setStatus("Sync requests are happening too often. Waiting before requesting another snapshot.", "warn");
      return;
    }
    setStatus(errorMessage, "warn");
    return;
  }

  if (message.sessionID && state.sessionID && message.sessionID !== state.sessionID) {
    setStatus("Ignored message for mismatched session.", "warn");
    return;
  }

  if (typeof message.schemaVersion === "number" && message.schemaVersion !== 1) {
    setStatus("Ignored message with unsupported schema version.", "warn");
    return;
  }

  const payload = message.payload;
  const isSnapshotPayload = Boolean(payload && typeof payload === "object" && payload.type === "snapshot");
  const sequenceDecision = processSequence(message.seq);
  if (sequenceDecision === "stale") {
    return;
  }
  if (sequenceDecision === "ignored") {
    return;
  }
  if (sequenceDecision === "gap") {
    if (!state.awaitingGapSnapshot) {
      state.awaitingGapSnapshot = true;
      setStatus("Detected missing updates. Requesting snapshot...", "warn");
      requestSnapshot("gap_detected");
    }
    if (!isSnapshotPayload) {
      return;
    }
    if (typeof message.seq === "number" && Number.isSafeInteger(message.seq) && message.seq >= 0) {
      state.lastIncomingSeq = message.seq;
      dom.seqValue.textContent = String(message.seq);
    }
    state.awaitingGapSnapshot = false;
  } else if (isSnapshotPayload) {
    state.awaitingGapSnapshot = false;
  }
  if (!payload || typeof payload !== "object") {
    return;
  }

  if (payload.type === "snapshot") {
    markSynced();
    applySnapshot(payload.payload || {});
    setStatus("Snapshot synced.");
    return;
  }

  if (payload.type === "hello") {
    markSynced();
    state.canApproveRemotely = Boolean(payload.payload?.supportsApprovals);
    renderApprovals();
    if (!state.canApproveRemotely) {
      setStatus("Connected. Remote approvals are disabled on desktop.", "warn");
    }
    return;
  }

  if (payload.type === "event") {
    markSynced();
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
      const stateLabel = eventPayload.body || "updated";
      if (eventPayload.threadID) {
        state.turnStateByThreadID.set(eventPayload.threadID, stateLabel === "running");
      }
      renderThreads();
      const threadLabel = eventPayload.threadID ? ` (${eventPayload.threadID.slice(0, 8)})` : "";
      setStatus(`Turn status${threadLabel}: ${stateLabel}.`);
      return;
    }
  }
}

function disconnectMessageForReason(reason) {
  switch (reason) {
    case "device_revoked":
      return "This device was revoked from desktop. Pair again to reconnect.";
    case "stopped_by_desktop":
      return "Desktop ended the remote session. Scan a new QR code to reconnect.";
    case "device_reconnected":
      return "Another tab or device reconnected. Attempting to resume...";
    case "idle_timeout":
      return "Remote session timed out due to inactivity. Start a new session on desktop.";
    case "relay_over_capacity":
      return "Relay is currently at connection capacity. Retrying shortly.";
    default:
      return "Disconnected from relay.";
  }
}

function closeSocket() {
  state.isAuthenticated = false;
  updateWorkspaceVisibility();
  if (state.socket) {
    state.socket.onopen = null;
    state.socket.onclose = null;
    state.socket.onmessage = null;
    state.socket.onerror = null;
    state.socket.close();
    state.socket = null;
  }
}

function connectSocket(force = false) {
  if (!state.wsURL || !state.deviceSessionToken) {
    setStatus("Missing WebSocket URL or device token.", "error");
    return;
  }

  if (
    !force &&
    state.socket &&
    (state.socket.readyState === WebSocket.OPEN || state.socket.readyState === WebSocket.CONNECTING)
  ) {
    return;
  }

  if (state.reconnectTimer) {
    clearTimeout(state.reconnectTimer);
    state.reconnectTimer = null;
  }

  closeSocket();
  const socket = new WebSocket(state.wsURL);
  state.socket = socket;

  socket.onopen = () => {
    state.reconnectAttempts = 0;
    state.isSyncStale = false;
    setConnectionBadge(false);
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
    state.isAuthenticated = false;
    state.isSyncStale = false;
    updateWorkspaceVisibility();
    setConnectionBadge(false);
    if (state.reconnectDisabledReason) {
      setStatus(disconnectMessageForReason(state.reconnectDisabledReason), "warn");
      return;
    }
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
    return false;
  }
  state.socket.send(JSON.stringify(payload));
  return true;
}

function flushQueuedCommands() {
  if (!state.queuedCommands.length) {
    return;
  }

  if (!state.socket || state.socket.readyState !== WebSocket.OPEN) {
    return;
  }

  let sentCount = 0;
  while (state.queuedCommands.length > 0) {
    const next = state.queuedCommands[0];
    if (!sendRaw(next.envelope)) {
      break;
    }
    state.queuedCommands.shift();
    state.queuedCommandsBytes = Math.max(0, state.queuedCommandsBytes - next.bytes);
    sentCount += 1;
  }

  if (sentCount > 0) {
    setStatus(`Sent ${sentCount} queued command${sentCount === 1 ? "" : "s"} after reconnect.`);
  }
}

function queueCommandEnvelope(envelope) {
  const encoded = JSON.stringify(envelope);
  const bytes = new TextEncoder().encode(encoded).length;
  if (bytes > MAX_QUEUED_COMMAND_BYTES) {
    return { ok: false, dropped: 0, reason: "too_large" };
  }

  let dropped = 0;
  while (
    state.queuedCommands.length > 0 &&
    (state.queuedCommands.length >= MAX_QUEUED_COMMANDS || state.queuedCommandsBytes + bytes > MAX_QUEUED_COMMAND_BYTES)
  ) {
    const evicted = state.queuedCommands.shift();
    state.queuedCommandsBytes = Math.max(0, state.queuedCommandsBytes - evicted.bytes);
    dropped += 1;
  }

  state.queuedCommands.push({ envelope, bytes });
  state.queuedCommandsBytes += bytes;
  return { ok: true, dropped, reason: null };
}

function sendCommand(name, options = {}) {
  if (!state.sessionID) {
    return false;
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

  if (!state.socket || state.socket.readyState !== WebSocket.OPEN) {
    if (state.reconnectDisabledReason) {
      setStatus(`${disconnectMessageForReason(state.reconnectDisabledReason)} Re-pair before sending new commands.`, "warn");
      return false;
    }
    const queueableCommand = name === "thread.send_message" || name === "approval.respond";
    if (!queueableCommand) {
      setStatus("Not connected. Reconnect to sync this action.", "warn");
      return false;
    }
    const queueResult = queueCommandEnvelope(envelope);
    if (!queueResult.ok) {
      setStatus("Command is too large to queue offline. Reconnect and retry.", "error");
      return false;
    }
    const droppedSuffix =
      queueResult.dropped > 0 ? ` Dropped ${queueResult.dropped} oldest queued command${queueResult.dropped === 1 ? "" : "s"}.` : "";
    setStatus(
      `Offline. Queued ${state.queuedCommands.length} command${state.queuedCommands.length === 1 ? "" : "s"} for reconnect.${droppedSuffix}`,
      "warn"
    );
    if (!state.reconnectDisabledReason) {
      connectSocket();
    }
    return true;
  }

  return sendRaw(envelope);
}

function requestSnapshot(reason) {
  if (!state.sessionID) {
    return;
  }

  if (!state.socket || state.socket.readyState !== WebSocket.OPEN || !state.isAuthenticated) {
    state.pendingSnapshotReason = reason;
    if (state.reconnectDisabledReason) {
      setStatus(`${disconnectMessageForReason(state.reconnectDisabledReason)} Re-pair to sync again.`, "warn");
      return;
    }
    setStatus("Snapshot requested. Reconnecting to sync...", "warn");
    connectSocket();
    return;
  }

  state.pendingSnapshotReason = null;
  const payload = {
    type: "relay.snapshot_request",
    sessionID: state.sessionID,
    reason
  };
  if (Number.isSafeInteger(state.lastIncomingSeq) && state.lastIncomingSeq >= 0) {
    payload.lastSeq = state.lastIncomingSeq;
  }
  sendRaw(payload);
}

async function pairDevice() {
  if (!state.sessionID || !state.joinToken) {
    setStatus("Missing session data. Re-open from QR link.", "error");
    return;
  }
  if (state.isPairingInFlight) {
    return;
  }

  try {
    state.isPairingInFlight = true;
    refreshPairButtonState();
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
          joinToken: state.joinToken,
          deviceName: state.deviceName
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
    state.isAuthenticated = false;
    state.joinToken = null;
    state.reconnectDisabledReason = null;
    state.queuedCommands = [];
    state.queuedCommandsBytes = 0;
    state.pendingSnapshotReason = null;
    state.awaitingGapSnapshot = false;
    dom.sessionValue.textContent = state.sessionID;
    refreshPairButtonState();
    setStatus("Pairing successful. Connecting...");
    connectSocket();
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      setStatus("Pairing timed out while waiting for desktop approval.", "warn");
      return;
    }
    setStatus(`Pairing request failed: ${error instanceof Error ? error.message : "unknown error"}`, "error");
  } finally {
    state.isPairingInFlight = false;
    refreshPairButtonState();
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

    const wasConnected = state.socket?.readyState === WebSocket.OPEN;
    const sent = sendCommand("thread.send_message", {
      threadID: state.selectedThreadID,
      text
    });
    if (!sent) {
      return;
    }
    dom.composerInput.value = "";
    if (wasConnected) {
      setStatus("Message sent to relay. Waiting for desktop confirmation...");
    } else {
      setStatus("Message queued locally. It will send after reconnect.", "warn");
    }
  });
}

function wireButtons() {
  dom.pairButton.addEventListener("click", pairDevice);
  dom.reconnectButton.addEventListener("click", () => {
    connectSocket(true);
  });
  dom.snapshotButton.addEventListener("click", () => {
    requestSnapshot("manual_request");
  });

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible") {
      return;
    }

    if (state.socket?.readyState !== WebSocket.OPEN) {
      connectSocket();
      return;
    }

    setStatus("Resyncing after returning to foreground...");
    requestSnapshot("visibility_resume");
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
  state.deviceName = inferredDeviceName();
  parseJoinFromHash();
  wireButtons();
  wireComposer();
  renderProjects();
  renderThreads();
  renderMessages();
  renderApprovals();
  updateWorkspaceVisibility();
  refreshPairButtonState();
  refreshSyncFreshness();
  setInterval(refreshSyncFreshness, 5_000);
  registerServiceWorker();
}

init();
