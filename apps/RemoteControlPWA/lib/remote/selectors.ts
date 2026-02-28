import type { Approval, Project, Thread } from '@/lib/remote/types';

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
