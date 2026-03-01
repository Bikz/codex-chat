'use client';

import { buildRouteHash, normalizeProjectID, parseRouteHash, type HashRoute } from '@/lib/navigation/hash-route';
import { buildJoinLink, parseJoinLink, type ParsedJoinLink } from '@/lib/remote/join-link';
import { processIncomingSequence, queueEnvelopeWithLimits } from '@/lib/remote/logic';
import { messageIsCollapsible } from '@/lib/remote/selectors';
import { createInitialState, remoteStoreApi } from '@/lib/remote/store';
import type { BeforeInstallPromptEvent, RemoteMessage, RemoteSnapshot, StatusLevel } from '@/lib/remote/types';

const MAX_QUEUED_COMMANDS = 64;
const MAX_QUEUED_COMMAND_BYTES = 256 * 1024;
const PERSISTED_PAIRING_KEY = 'codexchat.remote.pairedDevice.v1';

const RECONNECT_DISABLED_REASONS = new Set([
  'device_revoked',
  'stopped_by_desktop',
  'idle_timeout',
  'session_expired',
  'replaced_by_new_pair_start'
]);

type ApprovalDecision = 'approve_once' | 'approve_for_session' | 'decline';

class RemoteClient {
  private initialized = false;

  private refreshInterval: number | null = null;

  private hashChangeListener: (() => void) | null = null;

  private visibilityListener: (() => void) | null = null;

  private beforeInstallListener: ((event: Event) => void) | null = null;

  private appInstalledListener: (() => void) | null = null;

  private focusTrapCleanup: (() => void) | null = null;

  init() {
    if (this.initialized || typeof window === 'undefined') {
      return;
    }
    this.initialized = true;

    const e2e = new URLSearchParams(window.location.search).get('e2e') === '1';
    const isStandaloneMode = this.isStandaloneDisplayMode();
    remoteStoreApi.setState({
      isE2EMode: e2e,
      deviceName: this.inferredDeviceName(),
      isStandaloneMode
    });

    const restored = this.restorePersistedPairedDeviceState();
    this.parseJoinFromHash();

    this.hashChangeListener = () => {
      this.applyRoute(parseRouteHash(window.location.hash), false);
    };
    window.addEventListener('hashchange', this.hashChangeListener);

    this.visibilityListener = () => {
      if (document.visibilityState !== 'visible') {
        return;
      }

      const state = remoteStoreApi.getState();
      if (state.socket?.readyState !== WebSocket.OPEN) {
        this.connectSocket();
        return;
      }

      this.setStatus('Resyncing after returning to foreground...');
      this.requestSnapshot('visibility_resume');
    };
    document.addEventListener('visibilitychange', this.visibilityListener);

    this.beforeInstallListener = (event) => {
      event.preventDefault();
      remoteStoreApi.setState({ installPromptEvent: event as BeforeInstallPromptEvent });
    };
    window.addEventListener('beforeinstallprompt', this.beforeInstallListener);

    this.appInstalledListener = () => {
      remoteStoreApi.setState({
        installPromptEvent: null,
        welcomeDismissed: true
      });
      this.setStatus('Installed to home screen. Pair once to keep this device connected.');
    };
    window.addEventListener('appinstalled', this.appInstalledListener);

    this.refreshInterval = window.setInterval(() => this.refreshSyncFreshness(), 5_000);

    this.updateWorkspaceVisibility();
    this.refreshSyncFreshness();
    this.registerServiceWorker();
    this.applyRoute(parseRouteHash(window.location.hash), true);

    if (restored) {
      const state = remoteStoreApi.getState();
      if (!state.joinToken && state.deviceSessionToken && state.wsURL) {
        this.setStatus('Restored saved pairing. Reconnecting...');
        this.connectSocket();
      }
    }
  }

  destroy() {
    if (!this.initialized || typeof window === 'undefined') {
      return;
    }

    this.initialized = false;

    if (this.hashChangeListener) {
      window.removeEventListener('hashchange', this.hashChangeListener);
      this.hashChangeListener = null;
    }
    if (this.visibilityListener) {
      document.removeEventListener('visibilitychange', this.visibilityListener);
      this.visibilityListener = null;
    }
    if (this.beforeInstallListener) {
      window.removeEventListener('beforeinstallprompt', this.beforeInstallListener);
      this.beforeInstallListener = null;
    }
    if (this.appInstalledListener) {
      window.removeEventListener('appinstalled', this.appInstalledListener);
      this.appInstalledListener = null;
    }
    if (this.refreshInterval !== null) {
      window.clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }

    this.closeSocket();
  }

  resetForE2E() {
    remoteStoreApi.setState(createInitialState());
  }

  setStatus(text: string, level: StatusLevel = 'info') {
    remoteStoreApi.setState({
      connectionStatusText: text,
      statusLevel: level
    });
  }

  getThreadByID(threadID: string | null) {
    if (!threadID) {
      return null;
    }
    const state = remoteStoreApi.getState();
    return state.threads.find((thread) => thread.id === threadID) || null;
  }

  private canUseStorage() {
    try {
      return typeof window !== 'undefined' && typeof window.localStorage !== 'undefined';
    } catch {
      return false;
    }
  }

  private persistPairedDeviceState() {
    if (!this.canUseStorage()) {
      return;
    }

    const state = remoteStoreApi.getState();
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

  private clearPersistedPairedDeviceState() {
    if (!this.canUseStorage()) {
      return;
    }
    window.localStorage.removeItem(PERSISTED_PAIRING_KEY);
  }

  private restorePersistedPairedDeviceState() {
    if (!this.canUseStorage()) {
      return false;
    }

    let parsed: Record<string, unknown> | null = null;
    try {
      const raw = window.localStorage.getItem(PERSISTED_PAIRING_KEY);
      if (!raw) {
        return false;
      }
      parsed = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      this.clearPersistedPairedDeviceState();
      return false;
    }

    const validSessionID = typeof parsed?.sessionID === 'string' && parsed.sessionID.length > 0;
    const validToken = typeof parsed?.deviceSessionToken === 'string' && parsed.deviceSessionToken.length > 0;
    const validWSURL = typeof parsed?.wsURL === 'string' && parsed.wsURL.length > 0;

    if (!validSessionID || !validToken || !validWSURL) {
      this.clearPersistedPairedDeviceState();
      return false;
    }

    remoteStoreApi.setState((state) => ({
      ...state,
      sessionID: parsed?.sessionID as string,
      deviceSessionToken: parsed?.deviceSessionToken as string,
      wsURL: parsed?.wsURL as string,
      deviceID: typeof parsed?.deviceID === 'string' && parsed.deviceID.length > 0 ? parsed.deviceID : null,
      relayBaseURL:
        typeof parsed?.relayBaseURL === 'string' && parsed.relayBaseURL.length > 0
          ? this.normalizeRelayBaseURL(parsed.relayBaseURL)
          : state.relayBaseURL
    }));

    return true;
  }

  private isStandaloneDisplayMode() {
    const displayModeStandalone = window.matchMedia?.('(display-mode: standalone)')?.matches === true;
    const navigatorWithStandalone = navigator as Navigator & { standalone?: boolean };
    const iOSStandalone = navigatorWithStandalone.standalone === true;
    return displayModeStandalone || iOSStandalone;
  }

  private isIOSDevice() {
    const ua = navigator.userAgent || '';
    return /iPhone|iPad|iPod/i.test(ua);
  }

  dismissWelcome() {
    remoteStoreApi.setState({ welcomeDismissed: true });
  }

  async promptInstall() {
    const state = remoteStoreApi.getState();

    if (this.isStandaloneDisplayMode()) {
      this.setStatus('App is already running in home-screen mode.');
      remoteStoreApi.setState({ welcomeDismissed: true });
      return;
    }

    if (!state.installPromptEvent) {
      if (this.isIOSDevice()) {
        this.setStatus('On iPhone/iPad, use Share -> Add to Home Screen.', 'warn');
      } else {
        this.setStatus('Install prompt not available yet. Use your browser menu to install this app.', 'warn');
      }
      return;
    }

    const installPrompt = state.installPromptEvent;
    remoteStoreApi.setState({ installPromptEvent: null });

    try {
      await installPrompt.prompt();
      const result = await installPrompt.userChoice;
      if (result?.outcome === 'accepted') {
        remoteStoreApi.setState({ welcomeDismissed: true });
        this.setStatus('Installed. Pair once and this device will reconnect automatically.');
      }
    } catch {
      this.setStatus('Install prompt could not be completed. You can continue in browser.', 'warn');
    }
  }

  private normalizeRelayBaseURL(rawValue: unknown) {
    if (typeof rawValue !== 'string' || rawValue.trim() === '') {
      return null;
    }
    try {
      const parsed = new URL(rawValue);
      if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
        return null;
      }
      parsed.pathname = '';
      parsed.search = '';
      parsed.hash = '';
      return parsed.toString().replace(/\/$/, '');
    } catch {
      return null;
    }
  }

  private parseJoinFromHash() {
    const parsed = parseJoinLink(window.location.hash);
    if (!parsed) {
      return;
    }

    const currentURL = window.location.href;
    this.applyJoinDetails(parsed, {
      pairLinkURL: currentURL,
      source: this.isStandaloneDisplayMode() ? 'in_app_qr' : 'browser_qr'
    });

    window.history.replaceState({}, document.title, `${window.location.pathname}${window.location.search}`);
  }

  private applyJoinDetails(
    join: ParsedJoinLink,
    options: { pairLinkURL?: string; source: 'scanner' | 'clipboard' | 'manual' | 'in_app_qr' | 'browser_qr' }
  ) {
    const state = remoteStoreApi.getState();
    const hasSessionChanged = Boolean(state.sessionID && state.sessionID !== join.sessionID);
    if (hasSessionChanged) {
      this.clearPersistedPairedDeviceState();
      this.closeSocket();
    }

    const fallbackPairLink = buildJoinLink(`${window.location.origin}${window.location.pathname}`, join);
    remoteStoreApi.setState((current) => ({
      ...current,
      arrivedFromQRCode: true,
      welcomeDismissed: false,
      sessionID: join.sessionID,
      joinToken: join.joinToken,
      relayBaseURL: join.relayBaseURL || current.relayBaseURL,
      pairingLinkURL: options.pairLinkURL || fallbackPairLink,
      reconnectDisabledReason: null,
      isQRScannerOpen: false,
      ...(hasSessionChanged
        ? {
            deviceSessionToken: null,
            wsURL: null,
            deviceID: null,
            isAuthenticated: false,
            queuedCommands: [],
            queuedCommandsBytes: 0,
            pendingSnapshotReason: null,
            awaitingGapSnapshot: false,
            lastIncomingSeq: null
          }
        : {})
    }));

    if (options.source === 'browser_qr') {
      this.setStatus(
        'QR opened in browser. To continue in installed app, open the app and use Scan QR or Paste Pair Link.',
        'warn'
      );
      return;
    }

    if (options.source === 'scanner') {
      this.setStatus('QR scanned. Tap Pair Device and approve on desktop.');
      return;
    }

    if (options.source === 'clipboard') {
      this.setStatus('Pair link imported from clipboard. Tap Pair Device to continue.');
      return;
    }

    if (options.source === 'manual') {
      this.setStatus('Pair link imported. Tap Pair Device to continue.');
      return;
    }

    this.setStatus('Pair link loaded. Tap Pair Device and approve on desktop.');
  }

  private baseRelayURL() {
    const state = remoteStoreApi.getState();
    return state.relayBaseURL || `${window.location.protocol}//${window.location.host}`;
  }

  private inferredDeviceName() {
    const userAgentData = (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData;
    if (userAgentData && typeof userAgentData.platform === 'string' && userAgentData.platform.trim() !== '') {
      const platform = userAgentData.platform.trim();
      return platform === 'macOS' ? 'Mac Browser' : `${platform} Browser`;
    }

    const ua = navigator.userAgent || '';
    if (/iPhone/i.test(ua)) return 'iPhone';
    if (/iPad/i.test(ua)) return 'iPad';
    if (/Android/i.test(ua)) return 'Android Device';
    if (/Macintosh|Mac OS X/i.test(ua)) return 'Mac Browser';
    if (/Windows/i.test(ua)) return 'Windows Browser';
    return 'Remote Device';
  }

  importJoinLink(rawText: string, source: 'scanner' | 'clipboard' | 'manual' = 'manual') {
    const parsed = parseJoinLink(rawText);
    if (!parsed) {
      this.setStatus('No valid pairing link found. Scan the latest QR code from desktop.', 'error');
      return false;
    }

    this.applyJoinDetails(parsed, { source });
    return true;
  }

  async pasteJoinLinkFromClipboard() {
    if (!navigator.clipboard || typeof navigator.clipboard.readText !== 'function') {
      this.setStatus('Clipboard access is unavailable. Paste the pair link manually instead.', 'warn');
      return false;
    }

    try {
      const clipboardText = await navigator.clipboard.readText();
      if (!clipboardText.trim()) {
        this.setStatus('Clipboard is empty. Copy the pair link first.', 'warn');
        return false;
      }
      return this.importJoinLink(clipboardText, 'clipboard');
    } catch {
      this.setStatus('Clipboard permission denied. Paste the pair link manually.', 'warn');
      return false;
    }
  }

  async copyPairingLinkToClipboard() {
    const state = remoteStoreApi.getState();
    if (!state.pairingLinkURL) {
      this.setStatus('No pairing link available to copy yet.', 'warn');
      return false;
    }

    if (!navigator.clipboard || typeof navigator.clipboard.writeText !== 'function') {
      this.setStatus('Clipboard write is unavailable on this browser.', 'warn');
      return false;
    }

    try {
      await navigator.clipboard.writeText(state.pairingLinkURL);
      this.setStatus('Pair link copied. Open the installed app and tap Paste Pair Link.');
      return true;
    } catch {
      this.setStatus('Unable to copy pair link. Select and copy it manually.', 'warn');
      return false;
    }
  }

  private updateRouteHash(view: 'home' | 'thread', options: { threadID?: string | null; projectID?: string }) {
    const state = remoteStoreApi.getState();
    const hash = buildRouteHash({
      view,
      threadID: view === 'thread' ? options.threadID || null : null,
      projectID: normalizeProjectID(options.projectID || state.selectedProjectFilterID)
    });

    if (window.location.hash !== hash) {
      window.location.hash = hash;
    }

    remoteStoreApi.setState({
      route: parseRouteHash(hash)
    });
  }

  applyRoute(route: HashRoute, shouldNormalize = true) {
    const state = remoteStoreApi.getState();
    const normalizedProjectID = normalizeProjectID(route.projectID);
    const hasProject = normalizedProjectID === 'all' || state.projects.some((project) => project.id === normalizedProjectID);

    const nextPartial: Partial<ReturnType<typeof remoteStoreApi.getState>> = {
      route,
      selectedProjectFilterID: hasProject ? normalizedProjectID : state.selectedProjectFilterID
    };

    if (route.view === 'thread' && route.threadID && state.threads.some((thread) => thread.id === route.threadID)) {
      const unread = new Map(state.unreadByThreadID);
      unread.set(route.threadID, false);
      nextPartial.selectedThreadID = route.threadID;
      nextPartial.unreadByThreadID = unread;
      nextPartial.currentView = 'thread';
      nextPartial.isChatAtBottom = true;
      nextPartial.showJumpToLatest = false;
      nextPartial.userDetachedFromBottomAt = null;
      nextPartial.visibleMessageLimit = 90;
    } else {
      nextPartial.currentView = 'home';
    }

    remoteStoreApi.setState(nextPartial);

    const next = remoteStoreApi.getState();
    if (shouldNormalize) {
      if (next.currentView === 'thread' && next.selectedThreadID) {
        this.updateRouteHash('thread', {
          threadID: next.selectedThreadID,
          projectID: next.selectedProjectFilterID
        });
      } else {
        this.updateRouteHash('home', { projectID: next.selectedProjectFilterID });
      }
    }
  }

  private ensureCurrentRouteIsValid() {
    const state = remoteStoreApi.getState();
    if (state.currentView !== 'thread') {
      return;
    }

    if (!state.selectedThreadID || !this.getThreadByID(state.selectedThreadID)) {
      remoteStoreApi.setState({
        currentView: 'home',
        selectedThreadID: null
      });
      this.updateRouteHash('home', { projectID: state.selectedProjectFilterID });
    }
  }

  navigateHome() {
    const state = remoteStoreApi.getState();
    remoteStoreApi.setState({ currentView: 'home' });
    this.updateRouteHash('home', { projectID: state.selectedProjectFilterID });
  }

  navigateToThread(threadID: string) {
    const thread = this.getThreadByID(threadID);
    if (!thread) {
      return;
    }

    const state = remoteStoreApi.getState();
    const unread = new Map(state.unreadByThreadID);
    unread.set(threadID, false);

    remoteStoreApi.setState({
      selectedThreadID: threadID,
      unreadByThreadID: unread,
      currentView: 'thread',
      isChatAtBottom: true,
      showJumpToLatest: false,
      userDetachedFromBottomAt: null,
      visibleMessageLimit: 90
    });

    this.sendCommand('thread.select', { threadID });
    this.updateRouteHash('thread', {
      threadID,
      projectID: state.selectedProjectFilterID
    });
  }

  selectProjectFilter(projectID: string, shouldSendSelectCommand = true) {
    const state = remoteStoreApi.getState();
    const nextID = projectID || 'all';

    const partial: Partial<ReturnType<typeof remoteStoreApi.getState>> = {
      selectedProjectFilterID: nextID
    };

    if (state.currentView === 'thread' && state.selectedThreadID) {
      const thread = this.getThreadByID(state.selectedThreadID);
      if (thread && nextID !== 'all' && thread.projectID !== nextID) {
        partial.currentView = 'home';
      }
    }

    remoteStoreApi.setState(partial);

    if (shouldSendSelectCommand && nextID !== 'all') {
      this.sendCommand('project.select', { projectID: nextID });
    }

    const next = remoteStoreApi.getState();
    this.updateRouteHash(next.currentView === 'thread' ? 'thread' : 'home', {
      threadID: next.currentView === 'thread' ? next.selectedThreadID : null,
      projectID: next.selectedProjectFilterID
    });
  }

  toggleApprovalsExpanded() {
    const state = remoteStoreApi.getState();
    remoteStoreApi.setState({ approvalsExpanded: !state.approvalsExpanded });
  }

  toggleMessageExpanded(messageID: string) {
    const state = remoteStoreApi.getState();
    const next = new Set(state.expandedMessageIDs);
    if (next.has(messageID)) {
      next.delete(messageID);
    } else {
      next.add(messageID);
    }
    remoteStoreApi.setState({ expandedMessageIDs: next });
  }

  threadPreview(threadID: string) {
    const state = remoteStoreApi.getState();
    const messages = state.messagesByThreadID.get(threadID) || [];
    if (!messages.length) {
      return 'No messages yet';
    }
    const latest = messages[messages.length - 1];
    return this.compactPreviewText(latest.text || '');
  }

  private compactPreviewText(rawText: string) {
    const collapsed = rawText.replace(/\s+/g, ' ').trim();
    if (!collapsed) {
      return 'No messages yet';
    }

    const jsonStart = collapsed.indexOf('{');
    if (jsonStart >= 0 && collapsed.includes('"text"')) {
      try {
        const parsed = JSON.parse(collapsed.slice(jsonStart)) as { text?: string };
        if (typeof parsed?.text === 'string' && parsed.text.trim().length > 0) {
          return parsed.text.trim();
        }
      } catch {
        // Ignore parse failures and fall back to plain text cleanup.
      }
    }

    const clean = collapsed
      .replace(/^Completed\s+agentMessage:\s*/i, '')
      .replace(/^Started\s+reasoning:\s*/i, '')
      .replace(/^Completed\s+reasoning:\s*/i, '')
      .replace(/^Completed\s+commandExecution:\s*/i, '');

    if (clean.length <= 160) {
      return clean;
    }

    return `${clean.slice(0, 157)}...`;
  }

  private updateWorkspaceVisibility() {
    const state = remoteStoreApi.getState();
    if (!state.isAuthenticated) {
      remoteStoreApi.setState({ currentView: 'home' });
    }
  }

  private markSynced() {
    remoteStoreApi.setState({
      lastSyncedAt: Date.now(),
      isSyncStale: false
    });
  }

  updateLastSyncedLabel() {
    const state = remoteStoreApi.getState();
    if (!state.lastSyncedAt) {
      return 'Never';
    }

    const deltaMs = Date.now() - state.lastSyncedAt;
    if (deltaMs < 5_000) {
      return 'Just now';
    }

    const deltaSeconds = Math.floor(deltaMs / 1000);
    if (deltaSeconds < 60) {
      return `${deltaSeconds}s ago`;
    }

    const deltaMinutes = Math.floor(deltaSeconds / 60);
    if (deltaMinutes < 60) {
      return `${deltaMinutes}m ago`;
    }

    return new Date(state.lastSyncedAt).toLocaleTimeString();
  }

  private refreshSyncFreshness() {
    const state = remoteStoreApi.getState();
    if (state.socket?.readyState !== WebSocket.OPEN || !state.lastSyncedAt) {
      return;
    }

    const staleThresholdMs = 45_000;
    const isStale = Date.now() - state.lastSyncedAt >= staleThresholdMs;
    if (isStale && !state.isSyncStale) {
      remoteStoreApi.setState({ isSyncStale: true });
      this.setStatus('Connection is live but may be stale. Use Request Snapshot to resync.', 'warn');
    }
  }

  private messageSignature(messages: RemoteMessage[]) {
    if (!Array.isArray(messages) || messages.length === 0) {
      return '';
    }
    const lastMessage = messages[messages.length - 1];
    return `${lastMessage.id || ''}:${lastMessage.createdAt || ''}:${lastMessage.text || ''}`;
  }

  applySnapshot(snapshot: RemoteSnapshot) {
    const state = remoteStoreApi.getState();
    const projects = Array.isArray(snapshot.projects) ? snapshot.projects : [];
    const threads = Array.isArray(snapshot.threads) ? snapshot.threads : [];
    const pendingApprovals = Array.isArray(snapshot.pendingApprovals) ? snapshot.pendingApprovals : [];

    const nextSelectedFilter =
      state.selectedProjectFilterID !== 'all' && !projects.some((project) => project.id === state.selectedProjectFilterID)
        ? 'all'
        : state.selectedProjectFilterID;

    const unread = new Map(state.unreadByThreadID);
    let selectedThreadID = state.selectedThreadID;

    if (snapshot.selectedThreadID && threads.some((thread) => thread.id === snapshot.selectedThreadID)) {
      selectedThreadID = snapshot.selectedThreadID;
      unread.set(snapshot.selectedThreadID, false);
    }

    const nextTurnState = new Map(state.turnStateByThreadID);
    if (snapshot.turnState?.threadID) {
      nextTurnState.set(snapshot.turnState.threadID, Boolean(snapshot.turnState.isTurnInProgress));
    }

    const messages = Array.isArray(snapshot.messages) ? snapshot.messages : [];
    const nextByThread = new Map<string, RemoteMessage[]>();
    for (const message of messages) {
      const threadID = message.threadID;
      if (!threadID) {
        continue;
      }
      const bucket = nextByThread.get(threadID) || [];
      bucket.push(message);
      nextByThread.set(threadID, bucket);
    }

    const nextMessagesByThread = new Map(state.messagesByThreadID);
    for (const [threadID, bucket] of nextByThread.entries()) {
      const previousBucket = state.messagesByThreadID.get(threadID) || [];
      const normalizedBucket = bucket.slice(-240);
      const didChange = this.messageSignature(previousBucket) !== this.messageSignature(normalizedBucket);
      if (didChange && threadID !== selectedThreadID) {
        unread.set(threadID, true);
      }
      nextMessagesByThread.set(threadID, normalizedBucket);
    }

    const knownThreadIDs = new Set(threads.map((thread) => thread.id));
    for (const threadID of nextTurnState.keys()) {
      if (!knownThreadIDs.has(threadID)) {
        nextTurnState.delete(threadID);
      }
    }

    for (const threadID of unread.keys()) {
      if (!knownThreadIDs.has(threadID)) {
        unread.delete(threadID);
      }
    }

    remoteStoreApi.setState({
      projects,
      threads,
      pendingApprovals,
      selectedProjectID: snapshot.selectedProjectID || state.selectedProjectID,
      selectedProjectFilterID: nextSelectedFilter,
      selectedThreadID,
      turnStateByThreadID: nextTurnState,
      unreadByThreadID: unread,
      messagesByThreadID: nextMessagesByThread
    });

    this.ensureCurrentRouteIsValid();
  }

  private appendMessageFromEvent(eventPayload: Record<string, unknown>) {
    const threadID = typeof eventPayload.threadID === 'string' ? eventPayload.threadID : null;
    if (!threadID) {
      return;
    }

    const state = remoteStoreApi.getState();
    const nextMessagesByThread = new Map(state.messagesByThreadID);
    const bucket = (nextMessagesByThread.get(threadID) || []).slice();

    const messageID =
      typeof eventPayload.messageID === 'string'
        ? eventPayload.messageID
        : `event-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

    const exists = bucket.some((message) => message.id === messageID);
    if (exists) {
      return;
    }

    const text = typeof eventPayload.body === 'string' ? eventPayload.body : '';
    const role = typeof eventPayload.role === 'string' ? eventPayload.role : 'assistant';
    const createdAt = typeof eventPayload.createdAt === 'string' ? eventPayload.createdAt : new Date().toISOString();

    bucket.push({
      id: messageID,
      threadID,
      role: role === 'user' || role === 'system' ? role : 'assistant',
      text,
      createdAt
    });

    if (bucket.length > 240) {
      bucket.splice(0, bucket.length - 240);
    }

    nextMessagesByThread.set(threadID, bucket);

    const unread = new Map(state.unreadByThreadID);
    let selectedThreadID = state.selectedThreadID;
    if (!selectedThreadID) {
      selectedThreadID = threadID;
    } else if (selectedThreadID !== threadID) {
      unread.set(threadID, true);
    }

    if (selectedThreadID === threadID) {
      unread.set(threadID, false);
    }

    remoteStoreApi.setState({
      messagesByThreadID: nextMessagesByThread,
      unreadByThreadID: unread,
      selectedThreadID
    });
  }

  private processSequence(seq: unknown): 'accepted' | 'ignored' | 'gap' | 'stale' {
    const state = remoteStoreApi.getState();
    const result = processIncomingSequence(state.lastIncomingSeq, seq);
    if (result.nextLastIncomingSeq !== state.lastIncomingSeq) {
      remoteStoreApi.setState({ lastIncomingSeq: result.nextLastIncomingSeq });
    }
    return result.decision;
  }

  private onSocketMessage = (event: MessageEvent<string>) => {
    let message: Record<string, unknown>;
    try {
      message = JSON.parse(event.data) as Record<string, unknown>;
    } catch {
      this.setStatus('Received invalid socket payload.', 'warn');
      return;
    }

    if (message.type === 'auth_ok') {
      const payload = message as {
        nextDeviceSessionToken?: string;
        deviceID?: string;
      };
      remoteStoreApi.setState((state) => ({
        ...state,
        isAuthenticated: true,
        reconnectDisabledReason: null,
        deviceSessionToken:
          typeof payload.nextDeviceSessionToken === 'string' && payload.nextDeviceSessionToken.length > 0
            ? payload.nextDeviceSessionToken
            : state.deviceSessionToken,
        deviceID: typeof payload.deviceID === 'string' && payload.deviceID.length > 0 ? payload.deviceID : state.deviceID,
        awaitingGapSnapshot: false
      }));

      this.updateWorkspaceVisibility();
      this.markSynced();
      this.persistPairedDeviceState();
      this.setStatus('WebSocket authenticated.');
      this.flushQueuedCommands();
      const state = remoteStoreApi.getState();
      this.requestSnapshot(state.pendingSnapshotReason || 'initial_sync');
      return;
    }

    if (message.type === 'disconnect') {
      const reason = typeof message.reason === 'string' ? message.reason : 'unknown';

      remoteStoreApi.setState((state) => {
        const shouldDisable = RECONNECT_DISABLED_REASONS.has(reason);
        return {
          ...state,
          isAuthenticated: false,
          reconnectDisabledReason: shouldDisable ? reason : state.reconnectDisabledReason,
          deviceSessionToken: shouldDisable ? null : state.deviceSessionToken,
          wsURL: shouldDisable ? null : state.wsURL,
          deviceID: shouldDisable ? null : state.deviceID,
          joinToken: shouldDisable ? null : state.joinToken,
          queuedCommands: shouldDisable ? [] : state.queuedCommands,
          queuedCommandsBytes: shouldDisable ? 0 : state.queuedCommandsBytes,
          pendingSnapshotReason: shouldDisable ? null : state.pendingSnapshotReason
        };
      });

      if (RECONNECT_DISABLED_REASONS.has(reason)) {
        this.clearPersistedPairedDeviceState();
      }

      this.updateWorkspaceVisibility();
      this.setStatus(this.disconnectMessageForReason(reason), 'warn');
      return;
    }

    if (message.type === 'relay.error') {
      const errorCode = typeof message.error === 'string' ? message.error : 'relay_error';
      const errorMessage = typeof message.message === 'string' ? message.message : 'Relay rejected the latest request.';

      if (errorCode === 'command_rate_limited') {
        this.setStatus('Too many commands too quickly. Wait a moment and try again.', 'warn');
        return;
      }
      if (errorCode === 'replayed_command') {
        this.setStatus('Out-of-order command detected. Resyncing snapshot now...', 'warn');
        this.requestSnapshot('command_replay_rejected');
        return;
      }
      if (errorCode === 'snapshot_rate_limited') {
        this.setStatus('Sync requests are happening too often. Waiting before requesting another snapshot.', 'warn');
        return;
      }

      this.setStatus(errorMessage, 'warn');
      return;
    }

    const state = remoteStoreApi.getState();
    if (typeof message.sessionID === 'string' && state.sessionID && message.sessionID !== state.sessionID) {
      this.setStatus('Ignored message for mismatched session.', 'warn');
      return;
    }

    if (typeof message.schemaVersion === 'number' && message.schemaVersion !== 1) {
      this.setStatus('Ignored message with unsupported schema version.', 'warn');
      return;
    }

    const payload = message.payload as Record<string, unknown> | undefined;
    const isSnapshotPayload = Boolean(payload && payload.type === 'snapshot');

    const sequenceDecision = this.processSequence(message.seq);
    if (sequenceDecision === 'stale' || sequenceDecision === 'ignored') {
      return;
    }

    if (sequenceDecision === 'gap') {
      const current = remoteStoreApi.getState();
      if (!current.awaitingGapSnapshot) {
        remoteStoreApi.setState({ awaitingGapSnapshot: true });
        this.setStatus('Detected missing updates. Requesting snapshot...', 'warn');
        this.requestSnapshot('gap_detected');
      }

      if (!isSnapshotPayload) {
        return;
      }

      if (typeof message.seq === 'number' && Number.isSafeInteger(message.seq) && message.seq >= 0) {
        remoteStoreApi.setState({ lastIncomingSeq: message.seq });
      }
      remoteStoreApi.setState({ awaitingGapSnapshot: false });
    } else if (isSnapshotPayload) {
      remoteStoreApi.setState({ awaitingGapSnapshot: false });
    }

    if (!payload || typeof payload !== 'object') {
      return;
    }

    if (payload.type === 'snapshot') {
      this.markSynced();
      this.applySnapshot((payload.payload as RemoteSnapshot) || {});
      this.setStatus('Snapshot synced.');
      return;
    }

    if (payload.type === 'hello') {
      this.markSynced();
      const supportsApprovals = Boolean((payload.payload as Record<string, unknown> | undefined)?.supportsApprovals);
      remoteStoreApi.setState({ canApproveRemotely: supportsApprovals });
      if (!supportsApprovals) {
        this.setStatus('Connected. Remote approvals are disabled on desktop.', 'warn');
      }
      return;
    }

    if (payload.type === 'event') {
      this.markSynced();
      const eventPayload = (payload.payload as Record<string, unknown>) || {};
      if (eventPayload.name === 'thread.message.append') {
        this.appendMessageFromEvent(eventPayload);
        return;
      }
      if (eventPayload.name === 'approval.requested' || eventPayload.name === 'approval.resolved') {
        this.requestSnapshot('approval_event');
        return;
      }
      if (eventPayload.name === 'turn.status.update') {
        const stateLabel = typeof eventPayload.body === 'string' ? eventPayload.body : 'updated';
        if (typeof eventPayload.threadID === 'string') {
          const turnState = new Map(remoteStoreApi.getState().turnStateByThreadID);
          turnState.set(eventPayload.threadID, stateLabel === 'running');
          remoteStoreApi.setState({ turnStateByThreadID: turnState });
        }
        const threadLabel = typeof eventPayload.threadID === 'string' ? ` (${eventPayload.threadID.slice(0, 8)})` : '';
        this.setStatus(`Turn status${threadLabel}: ${stateLabel}.`);
      }
    }
  };

  private disconnectMessageForReason(reason: string) {
    switch (reason) {
      case 'device_revoked':
        return 'This device was revoked from desktop. Pair again to reconnect.';
      case 'stopped_by_desktop':
        return 'Desktop ended the remote session. Scan a new QR code to reconnect.';
      case 'device_reconnected':
        return 'Another tab or device reconnected. Attempting to resume...';
      case 'idle_timeout':
        return 'Remote session timed out due to inactivity. Start a new session on desktop.';
      case 'session_expired':
        return 'Remote session expired. Start a new session on desktop and pair again.';
      case 'replaced_by_new_pair_start':
        return 'Desktop started a new remote session. Scan the latest QR code to reconnect.';
      case 'relay_over_capacity':
        return 'Relay is currently at connection capacity. Retrying shortly.';
      default:
        return 'Disconnected from relay.';
    }
  }

  closeSocket() {
    const state = remoteStoreApi.getState();
    remoteStoreApi.setState({ isAuthenticated: false });
    if (state.socket) {
      state.socket.onopen = null;
      state.socket.onclose = null;
      state.socket.onmessage = null;
      state.socket.onerror = null;
      state.socket.close();
      remoteStoreApi.setState({ socket: null });
    }
  }

  connectSocket(force = false) {
    const state = remoteStoreApi.getState();
    if (!state.wsURL || !state.deviceSessionToken) {
      this.setStatus('Missing WebSocket URL or device token.', 'error');
      return;
    }

    if (!force && state.socket && (state.socket.readyState === WebSocket.OPEN || state.socket.readyState === WebSocket.CONNECTING)) {
      return;
    }

    if (state.reconnectTimer) {
      window.clearTimeout(state.reconnectTimer);
      remoteStoreApi.setState({ reconnectTimer: null });
    }

    this.closeSocket();

    const socket = new WebSocket(state.wsURL);
    remoteStoreApi.setState({ socket });

    socket.onopen = () => {
      remoteStoreApi.setState({
        reconnectAttempts: 0,
        isSyncStale: false
      });
      this.setStatus('Connected. Authenticating...');
      socket.send(
        JSON.stringify({
          type: 'relay.auth',
          token: remoteStoreApi.getState().deviceSessionToken
        })
      );
    };

    socket.onmessage = this.onSocketMessage;

    socket.onclose = () => {
      const latest = remoteStoreApi.getState();
      remoteStoreApi.setState({
        isAuthenticated: false,
        isSyncStale: false
      });

      this.updateWorkspaceVisibility();

      if (latest.reconnectDisabledReason) {
        this.setStatus(this.disconnectMessageForReason(latest.reconnectDisabledReason), 'warn');
        return;
      }

      this.scheduleReconnect();
    };

    socket.onerror = () => {
      this.setStatus('WebSocket connection error.', 'warn');
    };
  }

  private scheduleReconnect() {
    const state = remoteStoreApi.getState();
    if (state.reconnectTimer) {
      window.clearTimeout(state.reconnectTimer);
    }

    const delayMs = Math.min(15_000, 1_000 * 2 ** state.reconnectAttempts);
    const timer = window.setTimeout(() => {
      this.connectSocket();
    }, delayMs);

    remoteStoreApi.setState({
      reconnectAttempts: state.reconnectAttempts + 1,
      reconnectTimer: timer
    });

    this.setStatus(`Disconnected. Reconnecting in ${Math.round(delayMs / 1000)}s...`, 'warn');
  }

  private sendRaw(payload: unknown) {
    const state = remoteStoreApi.getState();
    if (!state.socket || state.socket.readyState !== WebSocket.OPEN) {
      this.setStatus('Not connected. Unable to send command.', 'warn');
      return false;
    }
    state.socket.send(JSON.stringify(payload));
    return true;
  }

  private flushQueuedCommands() {
    const state = remoteStoreApi.getState();
    if (!state.queuedCommands.length || !state.socket || state.socket.readyState !== WebSocket.OPEN) {
      return;
    }

    const queue = state.queuedCommands.slice();
    let queuedBytes = state.queuedCommandsBytes;
    let sentCount = 0;

    while (queue.length > 0) {
      const next = queue[0];
      if (!this.sendRaw(next.envelope)) {
        break;
      }
      queue.shift();
      queuedBytes = Math.max(0, queuedBytes - next.bytes);
      sentCount += 1;
    }

    remoteStoreApi.setState({
      queuedCommands: queue,
      queuedCommandsBytes: queuedBytes
    });

    if (sentCount > 0) {
      this.setStatus(`Sent ${sentCount} queued command${sentCount === 1 ? '' : 's'} after reconnect.`);
    }
  }

  private queueCommandEnvelope(envelope: unknown) {
    const state = remoteStoreApi.getState();
    const result = queueEnvelopeWithLimits(
      state.queuedCommands,
      state.queuedCommandsBytes,
      envelope,
      MAX_QUEUED_COMMANDS,
      MAX_QUEUED_COMMAND_BYTES
    );

    remoteStoreApi.setState({
      queuedCommands: result.queue,
      queuedCommandsBytes: result.bytes
    });

    return {
      ok: result.ok,
      dropped: result.dropped,
      reason: result.reason
    };
  }

  private sendCommand(
    name: string,
    options: {
      threadID?: string | null;
      projectID?: string | null;
      text?: string | null;
      approvalRequestID?: string | null;
      approvalDecision?: ApprovalDecision | null;
    } = {}
  ) {
    const state = remoteStoreApi.getState();
    if (!state.sessionID) {
      return false;
    }

    const envelope = {
      schemaVersion: 1,
      sessionID: state.sessionID,
      seq: state.nextOutgoingSeq,
      timestamp: new Date().toISOString(),
      payload: {
        type: 'command',
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

    remoteStoreApi.setState({ nextOutgoingSeq: state.nextOutgoingSeq + 1 });

    const latest = remoteStoreApi.getState();
    if (!latest.socket || latest.socket.readyState !== WebSocket.OPEN) {
      if (latest.reconnectDisabledReason) {
        this.setStatus(`${this.disconnectMessageForReason(latest.reconnectDisabledReason)} Re-pair before sending new commands.`, 'warn');
        return false;
      }

      const queueableCommand = name === 'thread.send_message' || name === 'approval.respond';
      if (!queueableCommand) {
        this.setStatus('Not connected. Reconnect to sync this action.', 'warn');
        return false;
      }

      const queueResult = this.queueCommandEnvelope(envelope);
      if (!queueResult.ok) {
        this.setStatus('Command is too large to queue offline. Reconnect and retry.', 'error');
        return false;
      }

      const now = remoteStoreApi.getState();
      const droppedSuffix =
        queueResult.dropped > 0 ? ` Dropped ${queueResult.dropped} oldest queued command${queueResult.dropped === 1 ? '' : 's'}.` : '';
      this.setStatus(
        `Offline. Queued ${now.queuedCommands.length} command${now.queuedCommands.length === 1 ? '' : 's'} for reconnect.${droppedSuffix}`,
        'warn'
      );

      this.connectSocket();
      return true;
    }

    return this.sendRaw(envelope);
  }

  requestSnapshot(reason: string) {
    const state = remoteStoreApi.getState();
    if (!state.sessionID) {
      return;
    }

    if (!state.socket || state.socket.readyState !== WebSocket.OPEN || !state.isAuthenticated) {
      remoteStoreApi.setState({ pendingSnapshotReason: reason });
      if (state.reconnectDisabledReason) {
        this.setStatus(`${this.disconnectMessageForReason(state.reconnectDisabledReason)} Re-pair to sync again.`, 'warn');
        return;
      }
      this.setStatus('Snapshot requested. Reconnecting to sync...', 'warn');
      this.connectSocket();
      return;
    }

    remoteStoreApi.setState({ pendingSnapshotReason: null });
    const payload: Record<string, unknown> = {
      type: 'relay.snapshot_request',
      sessionID: state.sessionID,
      reason
    };

    if (Number.isSafeInteger(state.lastIncomingSeq) && (state.lastIncomingSeq || 0) >= 0) {
      payload.lastSeq = state.lastIncomingSeq;
    }

    this.sendRaw(payload);
  }

  async pairDevice() {
    const state = remoteStoreApi.getState();
    if (!state.sessionID || !state.joinToken) {
      this.setStatus('Missing session data. Use Scan QR or Paste Pair Link first.', 'error');
      return;
    }

    if (state.isPairingInFlight) {
      return;
    }

    try {
      remoteStoreApi.setState({ isPairingInFlight: true });
      this.setStatus('Waiting for desktop pairing approval...');

      const abortController = new AbortController();
      const timeout = window.setTimeout(() => abortController.abort(), 60_000);
      let response: Response;
      try {
        response = await fetch(`${this.baseRelayURL()}/pair/join`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            sessionID: state.sessionID,
            joinToken: state.joinToken,
            deviceName: state.deviceName
          }),
          signal: abortController.signal
        });
      } finally {
        window.clearTimeout(timeout);
      }

      const payload = (await response.json()) as Record<string, unknown>;
      if (!response.ok) {
        if (payload?.error === 'pair_request_in_progress') {
          this.setStatus('Pairing request already pending on desktop. Approve or deny it there first.', 'warn');
          return;
        }
        if (payload?.error === 'pair_request_timed_out') {
          this.setStatus('Desktop approval timed out. Request pairing again.', 'warn');
          return;
        }
        if (payload?.error === 'pair_request_denied') {
          this.setStatus('Desktop denied this pairing request.', 'error');
          return;
        }
        this.setStatus(typeof payload.message === 'string' ? payload.message : 'Pairing failed.', 'error');
        return;
      }

      remoteStoreApi.setState((current) => ({
        ...current,
        deviceSessionToken: payload.deviceSessionToken as string,
        deviceID: (payload.deviceID as string) || current.deviceID,
        wsURL: payload.wsURL as string,
        sessionID: payload.sessionID as string,
        isAuthenticated: false,
        joinToken: null,
        reconnectDisabledReason: null,
        welcomeDismissed: true,
        queuedCommands: [],
        queuedCommandsBytes: 0,
        pendingSnapshotReason: null,
        awaitingGapSnapshot: false
      }));

      this.persistPairedDeviceState();
      this.setStatus('Pairing successful. Connecting...');
      this.connectSocket();
    } catch (error: unknown) {
      if (error instanceof DOMException && error.name === 'AbortError') {
        this.setStatus('Pairing timed out while waiting for desktop approval.', 'warn');
        return;
      }
      this.setStatus(`Pairing request failed: ${error instanceof Error ? error.message : 'unknown error'}`, 'error');
    } finally {
      remoteStoreApi.setState({ isPairingInFlight: false });
    }
  }

  forgetRememberedDevice() {
    this.clearPersistedPairedDeviceState();
    this.closeSocket();

    const state = remoteStoreApi.getState();
    const patch: Partial<ReturnType<typeof remoteStoreApi.getState>> = {
      deviceSessionToken: null,
      wsURL: null,
      deviceID: null,
      reconnectDisabledReason: null,
      pendingSnapshotReason: null,
      queuedCommands: [],
      queuedCommandsBytes: 0,
      awaitingGapSnapshot: false,
      lastIncomingSeq: null,
      currentView: 'home'
    };

    if (!state.joinToken) {
      patch.sessionID = null;
    }

    remoteStoreApi.setState(patch);
    this.setStatus('Removed saved pairing from this browser. Scan the QR code again to pair.', 'warn');
  }

  reconnect() {
    this.connectSocket(true);
  }

  sendComposerMessage(text: string) {
    const state = remoteStoreApi.getState();
    if (!state.selectedThreadID) {
      this.setStatus('Select a thread before sending a message.', 'warn');
      return false;
    }

    remoteStoreApi.setState({ isComposerDispatching: true });
    const wasConnected = state.socket?.readyState === WebSocket.OPEN;
    const sent = this.sendCommand('thread.send_message', {
      threadID: state.selectedThreadID,
      text
    });

    if (!sent) {
      remoteStoreApi.setState({ isComposerDispatching: false });
      return false;
    }

    window.setTimeout(() => {
      remoteStoreApi.setState({ isComposerDispatching: false });
    }, 280);

    if (wasConnected) {
      this.setStatus('Message sent to relay. Waiting for desktop confirmation...');
    } else {
      this.setStatus('Message queued locally. It will send after reconnect.', 'warn');
    }

    return true;
  }

  respondApproval(approvalRequestID: string, approvalDecision: ApprovalDecision) {
    this.sendCommand('approval.respond', {
      approvalRequestID,
      approvalDecision
    });
  }

  openQRScanner() {
    remoteStoreApi.setState({
      isQRScannerOpen: true,
      isAccountSheetOpen: false,
      isProjectSheetOpen: false
    });
  }

  closeQRScanner() {
    remoteStoreApi.setState({ isQRScannerOpen: false });
    this.releaseFocusTrap();
  }

  openAccountSheet() {
    remoteStoreApi.setState({
      isAccountSheetOpen: true,
      isProjectSheetOpen: false,
      isQRScannerOpen: false
    });
  }

  closeAccountSheet() {
    remoteStoreApi.setState({ isAccountSheetOpen: false });
    this.releaseFocusTrap();
  }

  openProjectSheet() {
    remoteStoreApi.setState({
      isProjectSheetOpen: true,
      isAccountSheetOpen: false,
      isQRScannerOpen: false
    });
  }

  closeProjectSheet() {
    remoteStoreApi.setState({ isProjectSheetOpen: false });
    this.releaseFocusTrap();
  }

  trapFocus(sheetElement: HTMLElement | null, close: () => void) {
    this.releaseFocusTrap();
    if (!sheetElement) {
      return;
    }

    const getFocusableElements = (container: HTMLElement) =>
      [...container.querySelectorAll<HTMLElement>('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')].filter(
        (el) => !el.hasAttribute('disabled') && el.offsetParent !== null
      );

    const keyListener = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        close();
        return;
      }

      if (event.key !== 'Tab') {
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

    document.addEventListener('keydown', keyListener);
    this.focusTrapCleanup = () => {
      document.removeEventListener('keydown', keyListener);
      this.focusTrapCleanup = null;
    };
  }

  private releaseFocusTrap() {
    if (this.focusTrapCleanup) {
      this.focusTrapCleanup();
    }
  }

  registerSheetContainer(sheetElement: HTMLElement | null, type: 'account' | 'project') {
    if (!sheetElement) {
      return;
    }

    const state = remoteStoreApi.getState();
    if (type === 'account' && state.isAccountSheetOpen) {
      this.trapFocus(sheetElement, () => this.closeAccountSheet());
    }
    if (type === 'project' && state.isProjectSheetOpen) {
      this.trapFocus(sheetElement, () => this.closeProjectSheet());
    }
  }

  isMessageCollapsed(messageID: string, text: string) {
    const state = remoteStoreApi.getState();
    return messageIsCollapsible(text) && !state.expandedMessageIDs.has(messageID);
  }

  private registerServiceWorker() {
    const state = remoteStoreApi.getState();
    if (state.isE2EMode) {
      return;
    }

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js').catch(() => {
        this.setStatus('Service worker registration failed.', 'warn');
      });
    }
  }
}

let singletonClient: RemoteClient | null = null;

export function getRemoteClient() {
  if (!singletonClient) {
    singletonClient = new RemoteClient();
  }
  return singletonClient;
}
