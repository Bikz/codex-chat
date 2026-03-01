import { describe, expect, it } from 'vitest';
import {
  getUserVisibleThreadPreview,
  getVisibleMessageWindow,
  getVisibleThreads,
  getVisibleTranscriptMessages,
  messageIsCollapsible,
  sortedProjectsByActivity
} from '@/lib/remote/selectors';

describe('selectors', () => {
  it('filters visible threads by selected project', () => {
    const threads = [
      { id: 't1', projectID: 'p1', title: 'A' },
      { id: 't2', projectID: 'p2', title: 'B' }
    ];

    expect(getVisibleThreads(threads, 'all')).toHaveLength(2);
    expect(getVisibleThreads(threads, 'p1').map((thread) => thread.id)).toEqual(['t1']);
  });

  it('sorts projects by thread count then name', () => {
    const projects = [
      { id: 'p2', name: 'Bravo' },
      { id: 'p1', name: 'Alpha' },
      { id: 'p3', name: 'Charlie' }
    ];
    const threads = [
      { id: 't1', projectID: 'p2', title: 'T1' },
      { id: 't2', projectID: 'p2', title: 'T2' },
      { id: 't3', projectID: 'p1', title: 'T3' }
    ];

    expect(sortedProjectsByActivity(projects, threads).map((project) => project.id)).toEqual(['p2', 'p1', 'p3']);
  });

  it('marks long messages collapsible', () => {
    expect(messageIsCollapsible('short')).toBe(false);
    expect(messageIsCollapsible('x'.repeat(481))).toBe(true);
    expect(messageIsCollapsible(Array.from({ length: 9 }, () => 'line').join('\n'))).toBe(true);
  });

  it('returns the newest message window and hidden count', () => {
    const messages = ['m1', 'm2', 'm3', 'm4', 'm5'];
    const windowed = getVisibleMessageWindow(messages, 3);

    expect(windowed.items).toEqual(['m3', 'm4', 'm5']);
    expect(windowed.hiddenCount).toBe(2);
  });

  it('returns latest non-system, non-technical preview text', () => {
    const messages = [
      { id: 'm1', threadID: 't1', role: 'system', text: 'Started userMessage: {"id":"123"}', createdAt: '2026-01-01T00:00:00.000Z' },
      { id: 'm2', threadID: 't1', role: 'assistant', text: 'Completed commandExecution: {"command":"echo hi"}', createdAt: '2026-01-01T00:00:01.000Z' },
      { id: 'm3', threadID: 't1', role: 'assistant', text: 'Visible summary for users', createdAt: '2026-01-01T00:00:02.000Z' }
    ];

    expect(getUserVisibleThreadPreview(messages)).toBe('Visible summary for users');
  });

  it('falls back when no user-visible messages exist', () => {
    const messages = [
      { id: 'm1', threadID: 't1', role: 'system', text: 'Completed reasoning: {"summary":[]}', createdAt: '2026-01-01T00:00:00.000Z' }
    ];
    expect(getUserVisibleThreadPreview(messages)).toBe('No user-visible messages yet');
  });

  it('filters system messages from transcript', () => {
    const messages = [
      { id: 'm1', threadID: 't1', role: 'assistant', text: 'Hello', createdAt: '2026-01-01T00:00:00.000Z' },
      { id: 'm2', threadID: 't1', role: 'system', text: 'Started reasoning: {}', createdAt: '2026-01-01T00:00:01.000Z' },
      { id: 'm3', threadID: 't1', role: 'user', text: 'hey', createdAt: '2026-01-01T00:00:02.000Z' }
    ];

    expect(getVisibleTranscriptMessages(messages).map((message) => message.id)).toEqual(['m1', 'm3']);
  });
});
