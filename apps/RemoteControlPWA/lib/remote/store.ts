import { create } from 'zustand';
import type { HashRoute, RemoteView } from '@/lib/navigation/hash-route';
import type {
  Approval,
  BeforeInstallPromptEvent,
  Project,
  RemoteMessage,
  StatusLevel,
  Thread
} from '@/lib/remote/types';

export interface RemoteStoreState {
  sessionID: string | null;
  joinToken: string | null;
  deviceID: string | null;
  deviceName: string | null;
  relayBaseURL: string | null;
  deviceSessionToken: string | null;
  wsURL: string | null;
  socket: WebSocket | null;
  isAuthenticated: boolean;
  arrivedFromQRCode: boolean;
  reconnectAttempts: number;
  reconnectTimer: number | null;
  reconnectDisabledReason: string | null;
  installPromptEvent: BeforeInstallPromptEvent | null;
  welcomeDismissed: boolean;
  isPairingInFlight: boolean;
  isQRScannerOpen: boolean;
  isStandaloneMode: boolean;
  pairingLinkURL: string | null;
  lastIncomingSeq: number | null;
  lastSyncedAt: number | null;
  isSyncStale: boolean;
  pendingSnapshotReason: string | null;
  nextOutgoingSeq: number;
  awaitingGapSnapshot: boolean;
  canApproveRemotely: boolean;
  queuedCommands: Array<{ envelope: unknown; bytes: number }>;
  queuedCommandsBytes: number;
  projects: Project[];
  threads: Thread[];
  pendingApprovals: Approval[];
  selectedProjectID: string | null;
  selectedProjectFilterID: string;
  selectedThreadID: string | null;
  currentView: RemoteView;
  isProjectSheetOpen: boolean;
  isAccountSheetOpen: boolean;
  approvalsExpanded: boolean;
  messagesByThreadID: Map<string, RemoteMessage[]>;
  turnStateByThreadID: Map<string, boolean>;
  unreadByThreadID: Map<string, boolean>;
  expandedMessageIDs: Set<string>;
  reasoningStateByThreadID: Map<string, 'idle' | 'started' | 'completed'>;
  reasoningUpdatedAtByThreadID: Map<string, number>;
  isChatAtBottom: boolean;
  showJumpToLatest: boolean;
  userDetachedFromBottomAt: number | null;
  visibleMessageLimit: number;
  isComposerDispatching: boolean;
  isE2EMode: boolean;
  keyboardOffset: number;
  visualViewportHeight: number;
  connectionStatusText: string;
  statusLevel: StatusLevel;
  route: HashRoute;
}

export function createInitialState(): RemoteStoreState {
  return {
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
    isQRScannerOpen: false,
    isStandaloneMode: false,
    pairingLinkURL: null,
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
    selectedProjectFilterID: 'all',
    selectedThreadID: null,
    currentView: 'home',
    isProjectSheetOpen: false,
    isAccountSheetOpen: false,
    approvalsExpanded: false,
    messagesByThreadID: new Map(),
    turnStateByThreadID: new Map(),
    unreadByThreadID: new Map(),
    expandedMessageIDs: new Set(),
    reasoningStateByThreadID: new Map(),
    reasoningUpdatedAtByThreadID: new Map(),
    isChatAtBottom: true,
    showJumpToLatest: false,
    userDetachedFromBottomAt: null,
    visibleMessageLimit: 90,
    isComposerDispatching: false,
    isE2EMode: false,
    keyboardOffset: 0,
    visualViewportHeight: 0,
    connectionStatusText: 'Waiting to pair.',
    statusLevel: 'info',
    route: {
      view: 'home',
      threadID: null,
      projectID: 'all'
    }
  };
}

export const useRemoteStore = create<RemoteStoreState>(() => createInitialState());

export const remoteStoreApi = {
  getState: useRemoteStore.getState,
  setState: useRemoteStore.setState
};
