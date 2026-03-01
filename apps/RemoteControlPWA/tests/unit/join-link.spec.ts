import { buildJoinLink, parseJoinLink } from '@/lib/remote/join-link';
import { describe, expect, it } from 'vitest';

describe('join link parsing', () => {
  it('parses sid/jt from a direct hash payload', () => {
    const parsed = parseJoinLink('#sid=s1&jt=j1&relay=https://remote.bikz.cc');
    expect(parsed).toEqual({
      sessionID: 's1',
      joinToken: 'j1',
      relayBaseURL: 'https://remote.bikz.cc'
    });
  });

  it('parses sid/jt from full URL hash', () => {
    const parsed = parseJoinLink('https://remote.bikz.cc/#sid=s2&jt=j2&relay=https%3A%2F%2Fremote.bikz.cc');
    expect(parsed?.sessionID).toBe('s2');
    expect(parsed?.joinToken).toBe('j2');
    expect(parsed?.relayBaseURL).toBe('https://remote.bikz.cc');
  });

  it('returns null for unrelated text', () => {
    expect(parseJoinLink('hello world')).toBeNull();
    expect(parseJoinLink('#view=home&pid=all')).toBeNull();
  });

  it('builds canonical join links', () => {
    const link = buildJoinLink('https://remote.bikz.cc', {
      sessionID: 's3',
      joinToken: 'j3',
      relayBaseURL: 'https://remote.bikz.cc'
    });
    expect(link).toBe('https://remote.bikz.cc#sid=s3&jt=j3&relay=https%3A%2F%2Fremote.bikz.cc');
  });
});
