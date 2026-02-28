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

export interface Approval {
  requestID: string;
  threadID: string | null;
  summary: string;
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
  pendingApprovals?: Approval[];
  selectedProjectID?: string | null;
  selectedThreadID?: string | null;
  messages?: RemoteMessage[];
  turnState?: {
    threadID?: string;
    isTurnInProgress?: boolean;
  };
}

export interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
}
