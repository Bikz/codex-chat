import { describe, expect, it } from 'vitest';
import { getVisibleMessageWindow, getVisibleThreads, messageIsCollapsible, sortedProjectsByActivity } from '@/lib/remote/selectors';

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
});
