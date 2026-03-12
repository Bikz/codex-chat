import { describe, expect, it } from 'vitest';
import {
  buildRuntimeRequestResponseForOption,
  isRuntimeRequestEventName,
  normalizeCanRespondToRuntimeRequests,
  normalizeRuntimeRequestDecision,
  normalizeRuntimeRequests
} from '@/lib/remote/runtime-request';

describe('runtime-request helpers', () => {
  it('normalizes schema v2 runtime request snapshots', () => {
    const requests = normalizeRuntimeRequests({
      pendingRuntimeRequests: [
        {
          requestID: '42',
          kind: 'approval',
          threadID: 'thread-1',
          title: 'Command approval',
          summary: 'Allow command execution?',
          responseOptions: [{ id: 'accept', label: 'Approve once' }],
          permissions: ['workspace.write'],
          options: [],
          scopeHint: 'session',
          toolName: 'shell'
        }
      ]
    });

    expect(requests).toEqual([
      {
        requestID: '42',
        kind: 'approval',
        threadID: 'thread-1',
        title: 'Command approval',
        summary: 'Allow command execution?',
        responseOptions: [{ id: 'accept', label: 'Approve once' }],
        permissions: ['workspace.write'],
        options: [],
        scopeHint: 'session',
        toolName: 'shell',
        serverName: null
      }
    ]);
  });

  it('normalizes runtime request capabilities from schema v2 payloads', () => {
    expect(normalizeCanRespondToRuntimeRequests({ canRespondToRuntimeRequests: true })).toBe(true);
    expect(normalizeCanRespondToRuntimeRequests({ supportsRuntimeRequests: true })).toBe(true);
    expect(normalizeCanRespondToRuntimeRequests(undefined)).toBe(false);
  });

  it('recognizes runtime request lifecycle events', () => {
    expect(isRuntimeRequestEventName('runtime_request.requested')).toBe(true);
    expect(isRuntimeRequestEventName('runtime_request.resolved')).toBe(true);
    expect(isRuntimeRequestEventName('runtime_request.responded')).toBe(true);
    expect(isRuntimeRequestEventName('thread.message.append')).toBe(false);
  });

  it('canonicalizes runtime request decisions', () => {
    expect(normalizeRuntimeRequestDecision('accept')).toBe('accept');
    expect(normalizeRuntimeRequestDecision('approve_once')).toBe('accept');
    expect(normalizeRuntimeRequestDecision('approve_for_session')).toBe('acceptForSession');
  });

  it('builds approval decisions from response options', () => {
    const response = buildRuntimeRequestResponseForOption(
      {
        requestID: '9',
        kind: 'approval',
        threadID: 'thread-1',
        title: 'Approval',
        summary: 'Allow command execution?',
        responseOptions: [{ id: 'accept', label: 'Approve once' }],
        permissions: [],
        options: [],
        scopeHint: null,
        toolName: null,
        serverName: null
      },
      'accept'
    );

    expect(response).toEqual({
      decision: 'accept',
      optionID: 'accept'
    });
  });
});
