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
  arrivedFromQRCode: false,
  reconnectAttempts: 0,
  reconnectTimer: null,
  reconnectDisabledReason: null,
  installPromptEvent: null,
  welcomeDismissed: false,
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
  selectedProjectFilterID: "all",
  selectedThreadID: null,
  currentView: "home",
  isProjectSheetOpen: false,
  isAccountSheetOpen: false,
  approvalsExpanded: false,
  messagesByThreadID: new Map(),
  turnStateByThreadID: new Map(),
  unreadByThreadID: new Map(),
  expandedMessageIDs: new Set(),
  focusTrapCleanup: null,
  visualViewportCleanup: null,
  isE2EMode: typeof window !== "undefined" && new URLSearchParams(window.location.search).get("e2e") === "1"
};

const MAX_QUEUED_COMMANDS = 64;
const MAX_QUEUED_COMMAND_BYTES = 256 * 1024;
const PERSISTED_PAIRING_KEY = "codexchat.remote.pairedDevice.v1";
const RECONNECT_DISABLED_REASONS = new Set([
  "device_revoked",
  "stopped_by_desktop",
  "idle_timeout",
  "session_expired",
  "replaced_by_new_pair_start"
]);

const dom = {
  accountButton: document.getElementById("accountButton"),
  connectionBadge: document.getElementById("connectionBadge"),
  pairingHint: document.getElementById("pairingHint"),
  sessionValue: document.getElementById("sessionValue"),
  seqValue: document.getElementById("seqValue"),
  lastSyncedValue: document.getElementById("lastSyncedValue"),
  statusText: document.getElementById("statusText"),
  pairButton: document.getElementById("pairButton"),
  preconnectPairButton: document.getElementById("preconnectPairButton"),
  reconnectButton: document.getElementById("reconnectButton"),
  snapshotButton: document.getElementById("snapshotButton"),
  forgetButton: document.getElementById("forgetButton"),
  preConnectPanel: document.getElementById("preConnectPanel"),
  welcomePanel: document.getElementById("welcomePanel"),
  installButton: document.getElementById("installButton"),
  dismissWelcomeButton: document.getElementById("dismissWelcomeButton"),
  installHint: document.getElementById("installHint"),
  workspacePanel: document.getElementById("workspacePanel"),
  homeView: document.getElementById("homeView"),
  chatView: document.getElementById("chatView"),
  viewAllProjectsButton: document.getElementById("viewAllProjectsButton"),
  projectCircleStrip: document.getElementById("projectCircleStrip"),
  chatList: document.getElementById("chatList"),
  chatListEmpty: document.getElementById("chatListEmpty"),
  threadTitle: document.getElementById("threadTitle"),
  threadStatusChip: document.getElementById("threadStatusChip"),
  chatBackButton: document.getElementById("chatBackButton"),
  toggleApprovalsButton: document.getElementById("toggleApprovalsButton"),
  approvalGlobalSummary: document.getElementById("approvalGlobalSummary"),
  approvalTray: document.getElementById("approvalTray"),
  messageList: document.getElementById("messageList"),
  composerForm: document.getElementById("composerForm"),
  composerInput: document.getElementById("composerInput"),
  projectSheet: document.getElementById("projectSheet"),
  projectSheetList: document.getElementById("projectSheetList"),
  closeProjectSheetButton: document.getElementById("closeProjectSheetButton"),
  accountSheet: document.getElementById("accountSheet"),
  closeAccountSheetButton: document.getElementById("closeAccountSheetButton")
};

function setStatus(text, level = "info") {
  dom.statusText.textContent = text;
  const color = level === "error" ? "var(--danger)" : level === "warn" ? "var(--warning)" : "var(--muted)";
  dom.statusText.style.color = color;
}

function setRootCSSVar(name, value) {
  document.documentElement.style.setProperty(name, value);
}

function syncVisualViewportMetrics() {
  const vv = window.visualViewport;
  const viewportHeight = vv ? vv.height : window.innerHeight;
  const keyboardOffset = vv ? Math.max(0, window.innerHeight - vv.height - vv.offsetTop) : 0;

  setRootCSSVar("--vvh", `${Math.max(1, Math.round(viewportHeight))}px`);
  setRootCSSVar("--keyboard-offset", `${Math.max(0, Math.round(keyboardOffset))}px`);
}

function canUseStorage() {
  try {
    return typeof window !== "undefined" && typeof window.localStorage !== "undefined";
  } catch {
    return false;
  }
}

function persistPairedDeviceState() {
  if (!canUseStorage()) {
    return;
  }
  if (!state.sessionID || !state.deviceSessionToken || !state.wsURL) {
    return;
  }

  const payload = {
    sessionID: state.sessionID,
    deviceID: state.deviceID,
    deviceName: state.deviceName,
    relayBaseURL: state.relayBaseURL,
    deviceSessionToken: state.deviceSessionToken,
    wsURL: state.wsURL,
    storedAt: new Date().toISOString()
  };
  window.localStorage.setItem(PERSISTED_PAIRING_KEY, JSON.stringify(payload));
}

function clearPersistedPairedDeviceState() {
  if (!canUseStorage()) {
    return;
  }
  window.localStorage.removeItem(PERSISTED_PAIRING_KEY);
}

function restorePersistedPairedDeviceState() {
  if (!canUseStorage()) {
    return false;
  }

  let parsed = null;
  try {
    const raw = window.localStorage.getItem(PERSISTED_PAIRING_KEY);
    if (!raw) {
      return false;
    }
    parsed = JSON.parse(raw);
  } catch {
    clearPersistedPairedDeviceState();
    return false;
  }

  const validSessionID = typeof parsed?.sessionID === "string" && parsed.sessionID.length > 0;
  const validToken = typeof parsed?.deviceSessionToken === "string" && parsed.deviceSessionToken.length > 0;
  const validWSURL = typeof parsed?.wsURL === "string" && parsed.wsURL.length > 0;

  if (!validSessionID || !validToken || !validWSURL) {
    clearPersistedPairedDeviceState();
    return false;
  }

  state.sessionID = parsed.sessionID;
  state.deviceSessionToken = parsed.deviceSessionToken;
  state.wsURL = parsed.wsURL;
  state.deviceID = typeof parsed?.deviceID === "string" && parsed.deviceID.length > 0 ? parsed.deviceID : null;
  if (typeof parsed?.relayBaseURL === "string" && parsed.relayBaseURL.length > 0) {
    state.relayBaseURL = normalizeRelayBaseURL(parsed.relayBaseURL);
  }
  dom.sessionValue.textContent = state.sessionID;
  dom.pairingHint.textContent = "Restored saved pairing for this browser. Reconnect to resume remote control.";
  return true;
}

function isStandaloneDisplayMode() {
  const displayModeStandalone = window.matchMedia?.("(display-mode: standalone)")?.matches === true;
  const iOSStandalone = typeof navigator !== "undefined" && navigator.standalone === true;
  return displayModeStandalone || iOSStandalone;
}

function isIOSDevice() {
  const ua = navigator.userAgent || "";
  return /iPhone|iPad|iPod/i.test(ua);
}

function refreshWelcomePanel() {
  const showWelcome = Boolean(state.arrivedFromQRCode && !state.isAuthenticated && !state.welcomeDismissed);
  dom.welcomePanel.hidden = !showWelcome;
  if (!showWelcome) {
    return;
  }

  const canShowInstallPrompt = Boolean(state.installPromptEvent) && !isStandaloneDisplayMode();
  dom.installButton.hidden = !canShowInstallPrompt;
  dom.installHint.hidden = false;

  if (isStandaloneDisplayMode()) {
    dom.installHint.textContent = "Installed app mode detected. Pair once and this device can reconnect automatically.";
    return;
  }

  if (canShowInstallPrompt) {
    dom.installHint.textContent = "Tip: install now for faster launch and better background reconnect behavior.";
    return;
  }

  if (isIOSDevice()) {
    dom.installHint.textContent = "On iPhone/iPad: tap Share, then Add to Home Screen.";
    return;
  }

  dom.installHint.textContent = "If your browser supports install, use the browser menu to add this app to your home screen.";
}

function refreshRememberedDeviceStateUI() {
  const hasRememberedDevice = Boolean(state.deviceSessionToken && state.wsURL);
  dom.forgetButton.hidden = !hasRememberedDevice;
}

function forgetRememberedDevice() {
  clearPersistedPairedDeviceState();
  closeSocket();
  state.deviceSessionToken = null;
  state.wsURL = null;
  state.deviceID = null;
  state.reconnectDisabledReason = null;
  state.pendingSnapshotReason = null;
  state.queuedCommands = [];
  state.queuedCommandsBytes = 0;
  state.awaitingGapSnapshot = false;
  state.lastIncomingSeq = null;
  dom.seqValue.textContent = "-";
  if (!state.joinToken) {
    state.sessionID = null;
    dom.sessionValue.textContent = "Not paired";
    dom.pairingHint.textContent = "Open via desktop QR link to auto-fill session details.";
  }
  refreshPairButtonState();
  updateWorkspaceVisibility();
  renderAll();
  setStatus("Removed saved pairing from this browser. Scan the QR code again to pair.", "warn");
}

function refreshPairButtonState() {
  const disabled = state.isPairingInFlight || !state.joinToken;
  dom.pairButton.disabled = disabled;
  dom.preconnectPairButton.disabled = disabled;
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

  if (!showWorkspace) {
    state.currentView = "home";
  }

  refreshWelcomePanel();
  refreshRememberedDeviceStateUI();
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
    renderChatDetail();
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
    state.arrivedFromQRCode = true;
    state.welcomeDismissed = false;
    state.sessionID = sessionID;
    state.joinToken = joinToken;
    state.relayBaseURL = relayBaseURL || state.relayBaseURL;
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

function parseRouteHash() {
  const hash = window.location.hash.replace(/^#/, "");
  const params = new URLSearchParams(hash);
  const view = params.get("view");
  const tid = params.get("tid");
  const pid = params.get("pid");
  return {
    view: view === "thread" ? "thread" : "home",
    threadID: tid || null,
    projectID: pid || "all"
  };
}

function updateRouteHash(view, options = {}) {
  const params = new URLSearchParams();
  params.set("view", view);
  if (view === "thread" && options.threadID) {
    params.set("tid", options.threadID);
  }
  if (options.projectID) {
    params.set("pid", options.projectID);
  }
  const nextHash = `#${params.toString()}`;
  if (window.location.hash !== nextHash) {
    window.location.hash = nextHash;
  }
}

function applyRoute(route, shouldNormalize = true) {
  const normalizedProjectID = route.projectID === "all" ? "all" : route.projectID;
  const hasProject = normalizedProjectID === "all" || state.projects.some((project) => project.id === normalizedProjectID);
  if (hasProject) {
    state.selectedProjectFilterID = normalizedProjectID;
  }

  if (route.view === "thread" && route.threadID && state.threads.some((thread) => thread.id === route.threadID)) {
    state.selectedThreadID = route.threadID;
    state.unreadByThreadID.set(route.threadID, false);
    state.currentView = "thread";
  } else {
    state.currentView = "home";
  }

  if (shouldNormalize) {
    if (state.currentView === "thread" && state.selectedThreadID) {
      updateRouteHash("thread", { threadID: state.selectedThreadID, projectID: state.selectedProjectFilterID });
    } else {
      updateRouteHash("home", { projectID: state.selectedProjectFilterID });
    }
  }

  renderAll();
}

function getThreadByID(threadID) {
  return state.threads.find((thread) => thread.id === threadID) || null;
}

function getVisibleThreads() {
  if (state.selectedProjectFilterID === "all") {
    return state.threads;
  }
  return state.threads.filter((thread) => thread.projectID === state.selectedProjectFilterID);
}

function threadPreview(threadID) {
  const messages = state.messagesByThreadID.get(threadID) || [];
  if (!messages.length) {
    return "No messages yet";
  }
  const latest = messages[messages.length - 1];
  return latest.text || "No messages yet";
}

function pendingApprovalsByThread() {
  const counts = new Map();
  for (const approval of state.pendingApprovals) {
    if (!approval?.threadID) {
      continue;
    }
    counts.set(approval.threadID, (counts.get(approval.threadID) || 0) + 1);
  }
  return counts;
}

function sortedProjectsByActivity() {
  const countByProject = new Map();
  for (const project of state.projects) {
    countByProject.set(project.id, 0);
  }
  for (const thread of state.threads) {
    countByProject.set(thread.projectID, (countByProject.get(thread.projectID) || 0) + 1);
  }

  return state.projects
    .slice()
    .sort((a, b) => {
      const countDiff = (countByProject.get(b.id) || 0) - (countByProject.get(a.id) || 0);
      if (countDiff !== 0) {
        return countDiff;
      }
      return a.name.localeCompare(b.name);
    });
}

function selectProjectFilter(projectID, shouldSendSelectCommand = true) {
  const nextID = projectID || "all";
  state.selectedProjectFilterID = nextID;
  if (shouldSendSelectCommand && nextID !== "all") {
    sendCommand("project.select", { projectID: nextID });
  }
  if (state.currentView === "thread" && state.selectedThreadID) {
    const thread = getThreadByID(state.selectedThreadID);
    if (thread && nextID !== "all" && thread.projectID !== nextID) {
      state.currentView = "home";
    }
  }
  updateRouteHash(state.currentView === "thread" ? "thread" : "home", {
    threadID: state.currentView === "thread" ? state.selectedThreadID : null,
    projectID: state.selectedProjectFilterID
  });
  renderHome();
  renderNavigation();
}

function navigateHome() {
  state.currentView = "home";
  updateRouteHash("home", { projectID: state.selectedProjectFilterID });
  renderNavigation();
}

function navigateToThread(threadID) {
  const thread = getThreadByID(threadID);
  if (!thread) {
    return;
  }

  state.selectedThreadID = threadID;
  state.unreadByThreadID.set(threadID, false);
  state.currentView = "thread";
  sendCommand("thread.select", { threadID });
  updateRouteHash("thread", { threadID, projectID: state.selectedProjectFilterID });
  renderAll();
}

function ensureCurrentRouteIsValid() {
  if (state.currentView === "thread") {
    if (!state.selectedThreadID || !getThreadByID(state.selectedThreadID)) {
      state.currentView = "home";
      state.selectedThreadID = null;
      updateRouteHash("home", { projectID: state.selectedProjectFilterID });
    }
  }
}

function renderProjectStrip() {
  dom.projectCircleStrip.innerHTML = "";

  const allButton = document.createElement("button");
  allButton.type = "button";
  allButton.className = "project-circle";
  allButton.textContent = "All";
  allButton.setAttribute("role", "listitem");
  allButton.classList.toggle("active", state.selectedProjectFilterID === "all");
  allButton.setAttribute("aria-label", "Show all projects");
  allButton.addEventListener("click", () => {
    selectProjectFilter("all", false);
  });
  dom.projectCircleStrip.appendChild(allButton);

  const topProjects = sortedProjectsByActivity().slice(0, 6);
  for (const project of topProjects) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "project-circle";
    button.textContent = project.name;
    button.setAttribute("role", "listitem");
    button.classList.toggle("active", project.id === state.selectedProjectFilterID);
    button.setAttribute("aria-label", `Show chats for ${project.name}`);
    button.addEventListener("click", () => {
      selectProjectFilter(project.id, true);
    });
    dom.projectCircleStrip.appendChild(button);
  }
}

function renderProjectSheet() {
  dom.projectSheetList.innerHTML = "";

  const options = [{ id: "all", name: "All projects" }, ...sortedProjectsByActivity()];
  for (const project of options) {
    const li = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = project.name;
    button.classList.toggle("primary", project.id === state.selectedProjectFilterID);
    button.addEventListener("click", () => {
      selectProjectFilter(project.id, project.id !== "all");
      closeProjectSheet();
    });
    li.appendChild(button);
    dom.projectSheetList.appendChild(li);
  }
}

function renderChatList() {
  dom.chatList.innerHTML = "";

  const visibleThreads = getVisibleThreads();
  const approvalsByThread = pendingApprovalsByThread();

  let emptyMessage = "";
  if (state.threads.length === 0 && state.projects.length === 0) {
    emptyMessage = "No projects yet";
  } else if (state.threads.length === 0) {
    emptyMessage = "No chats yet";
  } else if (visibleThreads.length === 0 && state.selectedProjectFilterID !== "all") {
    emptyMessage = "No chats in this project";
  }

  if (emptyMessage) {
    dom.chatListEmpty.textContent = emptyMessage;
    dom.chatListEmpty.hidden = false;
    return;
  }
  dom.chatListEmpty.hidden = true;

  for (const thread of visibleThreads) {
    const li = document.createElement("li");
    const row = document.createElement("button");
    row.type = "button";
    row.className = "chat-row";
    row.classList.toggle("active", thread.id === state.selectedThreadID);
    row.setAttribute("aria-label", `Open chat ${thread.title}`);

    const main = document.createElement("div");
    main.className = "chat-main";

    const title = document.createElement("span");
    title.className = "chat-title";
    title.textContent = thread.title;

    const badges = document.createElement("span");
    badges.className = "chat-badges";

    const running = state.turnStateByThreadID.get(thread.id) === true;
    if (running) {
      const runningBadge = document.createElement("span");
      runningBadge.className = "mini-badge running";
      runningBadge.textContent = "Running";
      badges.appendChild(runningBadge);
    }

    const approvalCount = approvalsByThread.get(thread.id) || 0;
    if (approvalCount > 0) {
      const approvalBadge = document.createElement("span");
      approvalBadge.className = "mini-badge approval";
      approvalBadge.textContent = approvalCount === 1 ? "1 approval" : `${approvalCount} approvals`;
      badges.appendChild(approvalBadge);
    }

    const hasUnread = state.unreadByThreadID.get(thread.id) === true;
    if (hasUnread && thread.id !== state.selectedThreadID) {
      const unreadBadge = document.createElement("span");
      unreadBadge.className = "mini-badge unread";
      unreadBadge.textContent = "New";
      badges.appendChild(unreadBadge);
    }

    const preview = document.createElement("div");
    preview.className = "chat-preview";
    preview.textContent = threadPreview(thread.id);

    main.append(title, badges);
    row.append(main, preview);

    row.addEventListener("click", () => {
      navigateToThread(thread.id);
    });

    li.appendChild(row);
    dom.chatList.appendChild(li);
  }
}

function roleClass(role) {
  if (role === "user") {
    return "role-user";
  }
  if (role === "system") {
    return "role-system";
  }
  return "role-assistant";
}

function messageIsCollapsible(text) {
  if (!text) {
    return false;
  }
  const lineCount = text.split(/\r?\n/).length;
  return lineCount > 8 || text.length > 480;
}

function renderMessages() {
  dom.messageList.innerHTML = "";
  const threadID = state.selectedThreadID;
  const messages = threadID ? state.messagesByThreadID.get(threadID) || [] : [];

  if (!threadID) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "Select a chat to view conversation updates.";
    dom.messageList.appendChild(empty);
    return;
  }

  if (messages.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No messages yet.";
    dom.messageList.appendChild(empty);
    return;
  }

  for (const message of messages) {
    const messageID = message.id || `${message.threadID}-${message.createdAt || Date.now()}-${message.role || "assistant"}`;
    const wrapper = document.createElement("article");
    wrapper.className = `message ${roleClass(message.role)}`;

    const meta = document.createElement("div");
    meta.className = "message-meta";
    const timestamp = new Date(message.createdAt || Date.now()).toLocaleTimeString();
    meta.textContent = `${message.role || "assistant"} · ${timestamp}`;

    const body = document.createElement("div");
    body.className = "message-body";
    body.textContent = message.text || "";

    const collapsible = messageIsCollapsible(message.text || "");
    if (collapsible && !state.expandedMessageIDs.has(messageID)) {
      body.classList.add("collapsed");
    }

    wrapper.append(meta, body);

    if (collapsible) {
      const toggle = document.createElement("button");
      toggle.type = "button";
      toggle.className = "expand-toggle";
      const expanded = state.expandedMessageIDs.has(messageID);
      toggle.textContent = expanded ? "Show less" : "Show more";
      toggle.addEventListener("click", () => {
        if (state.expandedMessageIDs.has(messageID)) {
          state.expandedMessageIDs.delete(messageID);
        } else {
          state.expandedMessageIDs.add(messageID);
        }
        renderMessages();
      });
      wrapper.appendChild(toggle);
    }

    dom.messageList.appendChild(wrapper);
  }

  dom.messageList.scrollTop = dom.messageList.scrollHeight;
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

function renderApprovalsTray() {
  dom.approvalTray.innerHTML = "";
  const threadID = state.selectedThreadID;
  const threadApprovals = state.pendingApprovals.filter((approval) => approval.threadID === threadID);
  const globalApprovals = state.pendingApprovals.filter((approval) => !approval.threadID);

  if (globalApprovals.length > 0) {
    const label =
      globalApprovals.length === 1
        ? "1 session approval is pending outside this chat."
        : `${globalApprovals.length} session approvals are pending outside this chat.`;
    dom.approvalGlobalSummary.textContent = label;
    dom.approvalGlobalSummary.hidden = false;
  } else {
    dom.approvalGlobalSummary.hidden = true;
  }

  const allVisibleApprovals = [...threadApprovals, ...globalApprovals];
  if (allVisibleApprovals.length === 0) {
    const empty = document.createElement("div");
    empty.className = "approval-summary-line";
    empty.textContent = "No pending approvals.";
    dom.approvalTray.appendChild(empty);
    return;
  }

  for (const approval of allVisibleApprovals) {
    const card = document.createElement("article");
    card.className = "approval-card";

    const title = document.createElement("div");
    title.className = "approval-title";
    title.textContent = `#${approval.requestID || "?"}`;

    const text = document.createElement("div");
    text.className = "approval-text";
    text.textContent = approval.summary || "Pending approval request";

    card.append(title, text);

    if (state.canApproveRemotely) {
      const actions = document.createElement("div");
      actions.className = "approval-actions";
      actions.append(
        approvalButton("Approve once", approval, "approve_once", true),
        approvalButton("Approve session", approval, "approve_for_session"),
        approvalButton("Decline", approval, "decline")
      );
      card.appendChild(actions);
    }

    dom.approvalTray.appendChild(card);
  }
}

function renderChatDetail() {
  const thread = state.selectedThreadID ? getThreadByID(state.selectedThreadID) : null;
  dom.threadTitle.textContent = thread ? thread.title : "Thread";

  if (!thread) {
    dom.threadStatusChip.hidden = true;
    renderMessages();
    renderApprovalsTray();
    return;
  }

  const isRunning = state.turnStateByThreadID.get(thread.id) === true;
  if (isRunning) {
    dom.threadStatusChip.hidden = false;
    dom.threadStatusChip.textContent = "Running";
  } else if (state.isSyncStale) {
    dom.threadStatusChip.hidden = false;
    dom.threadStatusChip.textContent = "Sync stale";
  } else {
    dom.threadStatusChip.hidden = true;
  }

  dom.approvalTray.hidden = !state.approvalsExpanded;
  dom.toggleApprovalsButton.setAttribute("aria-expanded", state.approvalsExpanded ? "true" : "false");
  dom.toggleApprovalsButton.textContent = state.approvalsExpanded ? "Hide" : "Show";

  renderMessages();
  renderApprovalsTray();
}

function renderHome() {
  renderProjectStrip();
  renderProjectSheet();
  renderChatList();
}

function renderNavigation() {
  ensureCurrentRouteIsValid();
  const showChat = state.currentView === "thread" && Boolean(state.selectedThreadID);
  dom.homeView.hidden = showChat;
  dom.chatView.hidden = !showChat;
}

function renderAccountSheet() {
  dom.accountSheet.hidden = !state.isAccountSheetOpen;
  dom.projectSheet.hidden = !state.isProjectSheetOpen;
}

function renderAll() {
  renderHome();
  renderChatDetail();
  renderNavigation();
  renderAccountSheet();
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
  if (state.selectedProjectFilterID !== "all" && !state.projects.some((project) => project.id === state.selectedProjectFilterID)) {
    state.selectedProjectFilterID = "all";
  }

  if (snapshot.selectedThreadID && state.threads.some((thread) => thread.id === snapshot.selectedThreadID)) {
    state.selectedThreadID = snapshot.selectedThreadID;
    state.unreadByThreadID.set(snapshot.selectedThreadID, false);
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

  ensureCurrentRouteIsValid();
  renderAll();
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

  renderAll();
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
    persistPairedDeviceState();
    setStatus("WebSocket authenticated.");
    flushQueuedCommands();
    requestSnapshot(state.pendingSnapshotReason || "initial_sync");
    renderAll();
    return;
  }

  if (message.type === "disconnect") {
    state.isAuthenticated = false;
    const reason = typeof message.reason === "string" ? message.reason : "unknown";
    if (RECONNECT_DISABLED_REASONS.has(reason)) {
      state.reconnectDisabledReason = reason;
      state.deviceSessionToken = null;
      state.wsURL = null;
      state.deviceID = null;
      state.joinToken = null;
      state.queuedCommands = [];
      state.queuedCommandsBytes = 0;
      state.pendingSnapshotReason = null;
      clearPersistedPairedDeviceState();
      refreshPairButtonState();
    }
    updateWorkspaceVisibility();
    renderAll();
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
  if (sequenceDecision === "stale" || sequenceDecision === "ignored") {
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
    renderApprovalsTray();
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
      renderAll();
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
    case "session_expired":
      return "Remote session expired. Start a new session on desktop and pair again.";
    case "replaced_by_new_pair_start":
      return "Desktop started a new remote session. Scan the latest QR code to reconnect.";
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

  if (!force && state.socket && (state.socket.readyState === WebSocket.OPEN || state.socket.readyState === WebSocket.CONNECTING)) {
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
    renderAll();
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
    openAccountSheet();
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
    state.welcomeDismissed = true;
    state.queuedCommands = [];
    state.queuedCommandsBytes = 0;
    state.pendingSnapshotReason = null;
    state.awaitingGapSnapshot = false;
    dom.sessionValue.textContent = state.sessionID;
    refreshPairButtonState();
    persistPairedDeviceState();
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

async function promptInstall() {
  if (isStandaloneDisplayMode()) {
    setStatus("App is already running in home-screen mode.");
    state.welcomeDismissed = true;
    refreshWelcomePanel();
    return;
  }

  if (!state.installPromptEvent) {
    if (isIOSDevice()) {
      setStatus("On iPhone/iPad, use Share -> Add to Home Screen.", "warn");
    } else {
      setStatus("Install prompt not available yet. Use your browser menu to install this app.", "warn");
    }
    return;
  }

  const installPrompt = state.installPromptEvent;
  state.installPromptEvent = null;
  try {
    await installPrompt.prompt();
    const result = await installPrompt.userChoice;
    if (result?.outcome === "accepted") {
      state.welcomeDismissed = true;
      setStatus("Installed. Pair once and this device will reconnect automatically.");
    }
  } catch {
    setStatus("Install prompt could not be completed. You can continue in browser.", "warn");
  }
  refreshWelcomePanel();
}

function getFocusableElements(container) {
  return [...container.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')].filter(
    (el) => !el.hasAttribute("disabled") && el.offsetParent !== null
  );
}

function trapFocus(sheetElement) {
  if (state.focusTrapCleanup) {
    state.focusTrapCleanup();
  }

  const keyListener = (event) => {
    if (event.key === "Escape") {
      if (sheetElement === dom.accountSheet) {
        closeAccountSheet();
      } else if (sheetElement === dom.projectSheet) {
        closeProjectSheet();
      }
      return;
    }

    if (event.key !== "Tab") {
      return;
    }

    const focusables = getFocusableElements(sheetElement);
    if (!focusables.length) {
      return;
    }

    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    const active = document.activeElement;

    if (event.shiftKey && active === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && active === last) {
      event.preventDefault();
      first.focus();
    }
  };

  document.addEventListener("keydown", keyListener);
  state.focusTrapCleanup = () => {
    document.removeEventListener("keydown", keyListener);
    state.focusTrapCleanup = null;
  };
}

function openAccountSheet() {
  state.isAccountSheetOpen = true;
  state.isProjectSheetOpen = false;
  renderAccountSheet();
  trapFocus(dom.accountSheet);
  dom.closeAccountSheetButton.focus();
}

function closeAccountSheet() {
  state.isAccountSheetOpen = false;
  renderAccountSheet();
  if (state.focusTrapCleanup) {
    state.focusTrapCleanup();
  }
}

function openProjectSheet() {
  state.isProjectSheetOpen = true;
  state.isAccountSheetOpen = false;
  renderAccountSheet();
  trapFocus(dom.projectSheet);
  dom.closeProjectSheetButton.focus();
}

function closeProjectSheet() {
  state.isProjectSheetOpen = false;
  renderAccountSheet();
  if (state.focusTrapCleanup) {
    state.focusTrapCleanup();
  }
}

function wireVisualViewport() {
  syncVisualViewportMetrics();

  const onResize = () => syncVisualViewportMetrics();
  window.addEventListener("resize", onResize);
  window.addEventListener("orientationchange", onResize);

  const vv = window.visualViewport;
  if (vv) {
    vv.addEventListener("resize", onResize);
    vv.addEventListener("scroll", onResize);
  }

  state.visualViewportCleanup = () => {
    window.removeEventListener("resize", onResize);
    window.removeEventListener("orientationchange", onResize);
    if (vv) {
      vv.removeEventListener("resize", onResize);
      vv.removeEventListener("scroll", onResize);
    }
    state.visualViewportCleanup = null;
  };
}

function wireComposer() {
  dom.composerInput.addEventListener("focus", () => {
    window.setTimeout(() => {
      dom.composerInput.scrollIntoView({ block: "nearest" });
    }, 120);
  });

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
  dom.accountButton.addEventListener("click", () => {
    openAccountSheet();
  });

  dom.pairButton.addEventListener("click", pairDevice);
  dom.preconnectPairButton.addEventListener("click", () => {
    openAccountSheet();
    pairDevice();
  });

  dom.reconnectButton.addEventListener("click", () => {
    connectSocket(true);
  });
  dom.snapshotButton.addEventListener("click", () => {
    requestSnapshot("manual_request");
  });
  dom.forgetButton.addEventListener("click", forgetRememberedDevice);

  dom.chatBackButton.addEventListener("click", () => {
    navigateHome();
  });

  dom.toggleApprovalsButton.addEventListener("click", () => {
    state.approvalsExpanded = !state.approvalsExpanded;
    renderChatDetail();
  });

  dom.viewAllProjectsButton.addEventListener("click", () => {
    openProjectSheet();
  });

  dom.closeAccountSheetButton.addEventListener("click", () => {
    closeAccountSheet();
  });
  dom.closeProjectSheetButton.addEventListener("click", () => {
    closeProjectSheet();
  });

  document.querySelectorAll(".sheet-backdrop").forEach((backdrop) => {
    backdrop.addEventListener("click", () => {
      const sheetType = backdrop.getAttribute("data-close-sheet");
      if (sheetType === "project") {
        closeProjectSheet();
      } else {
        closeAccountSheet();
      }
    });
  });

  dom.installButton.addEventListener("click", () => {
    promptInstall();
  });
  dom.dismissWelcomeButton.addEventListener("click", () => {
    state.welcomeDismissed = true;
    refreshWelcomePanel();
  });

  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    state.installPromptEvent = event;
    refreshWelcomePanel();
  });

  window.addEventListener("appinstalled", () => {
    state.installPromptEvent = null;
    state.welcomeDismissed = true;
    refreshWelcomePanel();
    setStatus("Installed to home screen. Pair once to keep this device connected.");
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

  window.addEventListener("hashchange", () => {
    applyRoute(parseRouteHash(), false);
  });
}

function updateThemeColorMeta() {
  const meta = document.querySelector('meta[name="theme-color"]');
  if (!meta) {
    return;
  }
  const prefersLight = window.matchMedia?.("(prefers-color-scheme: light)")?.matches === true;
  meta.setAttribute("content", prefersLight ? "#ffffff" : "#000000");
}

function wireThemeColorMeta() {
  updateThemeColorMeta();
  const media = window.matchMedia?.("(prefers-color-scheme: light)");
  if (!media) {
    return;
  }
  const onChange = () => updateThemeColorMeta();
  if (typeof media.addEventListener === "function") {
    media.addEventListener("change", onChange);
  } else if (typeof media.addListener === "function") {
    media.addListener(onChange);
  }
}

function registerServiceWorker() {
  if (state.isE2EMode) {
    return;
  }
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {
      setStatus("Service worker registration failed.", "warn");
    });
  }
}

function exposeE2EHarness() {
  if (!state.isE2EMode) {
    return;
  }

  const harness = {
    seed(snapshot, options = {}) {
      state.isAuthenticated = options.authenticated !== false;
      updateWorkspaceVisibility();
      applySnapshot(snapshot || {});
      if (options.expandApprovals) {
        state.approvalsExpanded = true;
      }
      renderAll();
    },
    openThread(threadID) {
      navigateToThread(threadID);
    },
    openAccountSheet() {
      openAccountSheet();
    },
    closeAccountSheet() {
      closeAccountSheet();
    },
    setApprovalsExpanded(expanded) {
      state.approvalsExpanded = Boolean(expanded);
      renderChatDetail();
    },
    resetStorage() {
      if (canUseStorage()) {
        window.localStorage.clear();
      }
    },
    getState() {
      return {
        currentView: state.currentView,
        selectedProjectFilterID: state.selectedProjectFilterID,
        selectedThreadID: state.selectedThreadID,
        approvalsExpanded: state.approvalsExpanded
      };
    }
  };

  Object.defineProperty(window, "__codexRemotePWAHarness", {
    value: harness,
    configurable: true
  });
}

function init() {
  state.deviceName = inferredDeviceName();
  const restored = restorePersistedPairedDeviceState();
  parseJoinFromHash();
  wireVisualViewport();
  wireButtons();
  wireComposer();
  wireThemeColorMeta();
  exposeE2EHarness();
  renderAll();
  updateWorkspaceVisibility();
  refreshPairButtonState();
  refreshWelcomePanel();
  refreshRememberedDeviceStateUI();
  refreshSyncFreshness();
  setInterval(refreshSyncFreshness, 5_000);
  registerServiceWorker();

  applyRoute(parseRouteHash(), true);

  if (restored && !state.joinToken && state.deviceSessionToken && state.wsURL) {
    setStatus("Restored saved pairing. Reconnecting...");
    connectSocket();
  }
}

init();
