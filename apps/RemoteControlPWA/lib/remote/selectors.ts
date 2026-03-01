import { parseMessageText } from '@/lib/remote/message-parser';
import type { Approval, Project, RemoteMessage, Thread } from '@/lib/remote/types';

export function getVisibleThreads(threads: Thread[], selectedProjectFilterID: string): Thread[] {
  if (selectedProjectFilterID === 'all') {
    return threads;
  }
  return threads.filter((thread) => thread.projectID === selectedProjectFilterID);
}

export function sortedProjectsByActivity(projects: Project[], threads: Thread[]): Project[] {
  const countByProject = new Map<string, number>();
  for (const project of projects) {
    countByProject.set(project.id, 0);
  }
  for (const thread of threads) {
    countByProject.set(thread.projectID, (countByProject.get(thread.projectID) || 0) + 1);
  }

  return projects.slice().sort((a, b) => {
    const countDiff = (countByProject.get(b.id) || 0) - (countByProject.get(a.id) || 0);
    if (countDiff !== 0) {
      return countDiff;
    }
    return a.name.localeCompare(b.name);
  });
}

export function pendingApprovalsByThread(pendingApprovals: Approval[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const approval of pendingApprovals) {
    if (!approval?.threadID) {
      continue;
    }
    counts.set(approval.threadID, (counts.get(approval.threadID) || 0) + 1);
  }
  return counts;
}

const TECHNICAL_EVENT_PREFIX = /^(Started|Completed)\s+(userMessage|agentMessage|commandExecution|reasoning):/i;
const TECHNICAL_PAYLOAD_MARKERS = /"type"\s*:\s*"(agentMessage|userMessage|commandExecution|reasoning)"/i;

function compactPreviewText(rawText: string): string {
  const collapsed = rawText.replace(/\s+/g, ' ').trim();
  if (!collapsed) {
    return '';
  }

  const jsonStart = collapsed.indexOf('{');
  if (jsonStart >= 0 && collapsed.includes('"text"')) {
    try {
      const parsed = JSON.parse(collapsed.slice(jsonStart)) as { text?: string };
      if (typeof parsed?.text === 'string' && parsed.text.trim().length > 0) {
        return parsed.text.trim();
      }
    } catch {
      // Ignore parse failures and continue with plain cleanup.
    }
  }

  return collapsed;
}

function isTechnicalMessageText(rawText: string): boolean {
  const collapsed = rawText.replace(/\s+/g, ' ').trim();
  if (!collapsed) {
    return true;
  }

  if (TECHNICAL_EVENT_PREFIX.test(collapsed) || TECHNICAL_PAYLOAD_MARKERS.test(collapsed)) {
    return true;
  }

  const parsed = parseMessageText(rawText);
  return parsed.mode !== 'plain';
}

export function getVisibleTranscriptMessages(messages: RemoteMessage[]): RemoteMessage[] {
  return messages.filter((message) => message.role !== 'system');
}

export function getUserVisibleThreadPreview(messages: RemoteMessage[]): string {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (!message || message.role === 'system') {
      continue;
    }

    if (isTechnicalMessageText(message.text || '')) {
      continue;
    }

    const preview = compactPreviewText(message.text || '');
    if (!preview) {
      continue;
    }

    return preview.length <= 160 ? preview : `${preview.slice(0, 157)}...`;
  }

  return 'No user-visible messages yet';
}

export function messageIsCollapsible(text: string): boolean {
  if (!text) {
    return false;
  }
  const lineCount = text.split(/\r?\n/).length;
  return lineCount > 8 || text.length > 480;
}

export function getVisibleMessageWindow<T>(messages: T[], limit: number): { items: T[]; hiddenCount: number } {
  if (!Array.isArray(messages) || messages.length === 0) {
    return { items: [], hiddenCount: 0 };
  }

  const normalizedLimit = Number.isFinite(limit) ? Math.max(1, Math.floor(limit)) : messages.length;
  const startIndex = Math.max(0, messages.length - normalizedLimit);
  return {
    items: messages.slice(startIndex),
    hiddenCount: startIndex
  };
}
