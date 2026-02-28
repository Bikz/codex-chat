import { describe, expect, it } from 'vitest';
import { buildRouteHash, normalizeProjectID, parseRouteHash } from '@/lib/navigation/hash-route';

describe('hash route parsing', () => {
  it('normalizes invalid view to home and missing pid to all', () => {
    const route = parseRouteHash('#view=unknown');
    expect(route.view).toBe('home');
    expect(route.projectID).toBe('all');
  });

  it('parses thread route with tid and pid', () => {
    const route = parseRouteHash('#view=thread&tid=t1&pid=p2');
    expect(route).toEqual({
      view: 'thread',
      threadID: 't1',
      projectID: 'p2'
    });
  });

  it('builds canonical hash', () => {
    const hash = buildRouteHash({
      view: 'thread',
      threadID: 'abc',
      projectID: 'all'
    });
    expect(hash).toBe('#view=thread&tid=abc&pid=all');
  });

  it('normalizes blank project IDs to all', () => {
    expect(normalizeProjectID('')).toBe('all');
    expect(normalizeProjectID(undefined)).toBe('all');
  });
});
