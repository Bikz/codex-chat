export type StatusLevel = 'info' | 'warn' | 'error';

export interface Project {
  id: string;
  name: string;
}

export interface Thread {
  id: string;
  projectID: string;
  title: string;
  isPinned?: boolean;
}

export type RuntimeRequestKind = 'approval' | 'permissionsApproval' | 'userInput' | 'mcpElicitation' | 'dynamicToolCall';

export interface RuntimeRequestResponseOption {
  id: string;
  label: string;
}

export interface RuntimeRequestOption {
  id: string;
  label: string;
  description?: string | null;
}

export interface RuntimeRequest {
  requestID: string;
  kind: RuntimeRequestKind;
  threadID: string | null;
  title: string;
  summary: string;
  responseOptions: RuntimeRequestResponseOption[];
  permissions: string[];
  options: RuntimeRequestOption[];
  scopeHint: string | null;
  toolName: string | null;
  serverName: string | null;
}

export interface LegacyApproval {
  requestID: string;
  threadID: string | null;
  summary: string;
}

export interface RuntimeRequestResponse {
  decision?: string | null;
  permissions?: string[] | null;
  scope?: string | null;
  text?: string | null;
  optionID?: string | null;
  approved?: boolean | null;
}

export type MessageRole = 'assistant' | 'user' | 'system';

export interface RemoteMessage {
  id: string;
  threadID: string;
  role: MessageRole;
  text: string;
  createdAt: string;
}

export interface RemoteSnapshot {
  projects?: Project[];
  threads?: Thread[];
  pendingRuntimeRequests?: RuntimeRequest[];
  pendingApprovals?: LegacyApproval[];
  selectedProjectID?: string | null;
  selectedThreadID?: string | null;
  messages?: RemoteMessage[];
  turnState?: {
    threadID?: string;
    isTurnInProgress?: boolean;
    isAwaitingRuntimeRequest?: boolean;
    isAwaitingApproval?: boolean;
  };
}

export interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
}
