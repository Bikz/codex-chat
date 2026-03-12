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
          toolName: 'shell', serverName: null
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

  it('builds permission declines without granting requested permissions', () => {
    const response = buildRuntimeRequestResponseForOption(
      {
        requestID: '10',
        kind: 'permissionsApproval',
        threadID: 'thread-1',
        title: 'Permissions',
        summary: 'Need project.write',
        responseOptions: [
          { id: 'grant', label: 'Grant' },
          { id: 'decline', label: 'Decline' }
        ],
        permissions: ['project.write'],
        options: [],
        scopeHint: 'workspace',
        toolName: null,
        serverName: null
      },
      'decline'
    );

    expect(response).toEqual({
      optionID: 'decline',
      approved: false,
      permissions: [],
      scope: undefined
    });
  });

  it('builds user-input responses from draft text and selected choice', () => {
    const response = buildRuntimeRequestResponseForOption(
      {
        requestID: '11',
        kind: 'userInput',
        threadID: 'thread-1',
        title: 'Question',
        summary: 'Choose and explain',
        responseOptions: [
          { id: 'submit', label: 'Submit' },
          { id: 'dismiss', label: 'Dismiss' }
        ],
        permissions: [],
        options: [
          { id: 'choice-a', label: 'Choice A', description: null }
        ],
        scopeHint: null,
        toolName: null,
        serverName: null
      },
      'submit',
      {
        text: 'Because it is safer.',
        optionID: 'choice-a'
      }
    );

    expect(response).toEqual({
      text: 'Because it is safer.',
      optionID: 'choice-a'
    });
  });

  it('builds MCP elicitation responses from typed text', () => {
    const response = buildRuntimeRequestResponseForOption(
      {
        requestID: '12',
        kind: 'mcpElicitation',
        threadID: 'thread-1',
        title: 'MCP',
        summary: 'Provide input',
        responseOptions: [
          { id: 'submit', label: 'Submit' },
          { id: 'dismiss', label: 'Dismiss' }
        ],
        permissions: [],
        options: [],
        scopeHint: null,
        toolName: null,
        serverName: 'filesystem'
      },
      'submit',
      {
        text: 'Use the cached token.'
      }
    );

    expect(response).toEqual({
      text: 'Use the cached token.'
    });
  });
});
