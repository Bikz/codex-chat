import type {
  LegacyApproval,
  RemoteSnapshot,
  RuntimeRequest,
  RuntimeRequestKind,
  RuntimeRequestResponse,
  RuntimeRequestResponseOption
} from '@/lib/remote/types';

export type CanonicalRuntimeDecision = 'accept' | 'acceptForSession' | 'decline' | 'cancel';

const DEFAULT_APPROVAL_RESPONSE_OPTIONS: RuntimeRequestResponseOption[] = [
  { id: 'accept', label: 'Approve once' },
  { id: 'acceptForSession', label: 'Approve session' },
  { id: 'decline', label: 'Decline' }
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function readString(value: unknown): string | null {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }
  return null;
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((entry) => readString(entry))
    .filter((entry): entry is string => entry !== null);
}

function normalizeKind(value: unknown): RuntimeRequestKind {
  const candidate = readString(value);
  if (
    candidate === 'approval' ||
    candidate === 'permissionsApproval' ||
    candidate === 'userInput' ||
    candidate === 'mcpElicitation' ||
    candidate === 'dynamicToolCall'
  ) {
    return candidate;
  }
  return 'approval';
}

function normalizeResponseOptions(value: unknown, kind: RuntimeRequestKind): RuntimeRequestResponseOption[] {
  if (!Array.isArray(value)) {
    return kind === 'approval' ? DEFAULT_APPROVAL_RESPONSE_OPTIONS.slice() : [];
  }

  const normalized = value
    .map((entry) => {
      if (!isRecord(entry)) {
        return null;
      }
      const id = readString(entry.id);
      const label = readString(entry.label);
      if (!id || !label) {
        return null;
      }
      return { id, label };
    })
    .filter((entry): entry is RuntimeRequestResponseOption => entry !== null);

  if (normalized.length === 0 && kind === 'approval') {
    return DEFAULT_APPROVAL_RESPONSE_OPTIONS.slice();
  }

  return normalized;
}

function normalizeRuntimeRequest(value: unknown): RuntimeRequest | null {
  if (!isRecord(value)) {
    return null;
  }

  const requestID = readString(value.requestID ?? value.requestId);
  if (!requestID) {
    return null;
  }

  const kind = normalizeKind(value.kind);
  const title = readString(value.title) ?? readString(value.summary) ?? 'Runtime request';
  const summary = readString(value.summary) ?? title;

  const options: RuntimeRequest['options'] = [];
  if (Array.isArray(value.options)) {
    for (const entry of value.options) {
      if (!isRecord(entry)) {
        continue;
      }
      const id = readString(entry.id);
      const label = readString(entry.label);
      if (!id || !label) {
        continue;
      }
      options.push({
        id,
        label,
        description: readString(entry.description)
      });
    }
  }

  return {
    requestID,
    kind,
    threadID: readString(value.threadID ?? value.threadId),
    title,
    summary,
    responseOptions: normalizeResponseOptions(value.responseOptions, kind),
    permissions: readStringArray(value.permissions),
    options,
    scopeHint: readString(value.scopeHint),
    toolName: readString(value.toolName),
    serverName: readString(value.serverName)
  };
}

export function normalizeRuntimeRequests(snapshot: RemoteSnapshot): RuntimeRequest[] {
  const nextRequests = Array.isArray(snapshot.pendingRuntimeRequests) ? snapshot.pendingRuntimeRequests : null;
  if (nextRequests) {
    return nextRequests.map((entry) => normalizeRuntimeRequest(entry)).filter((entry): entry is RuntimeRequest => entry !== null);
  }

  const legacyApprovals = Array.isArray(snapshot.pendingApprovals) ? snapshot.pendingApprovals : [];
  return legacyApprovals.map((entry) => normalizeLegacyApproval(entry)).filter((entry): entry is RuntimeRequest => entry !== null);
}

export function normalizeCanRespondToRuntimeRequests(payload: Record<string, unknown> | undefined): boolean {
  if (!payload) {
    return false;
  }

  return (
    payload.canRespondToRuntimeRequests === true ||
    payload.supportsRuntimeRequests === true ||
    payload.canApproveRemotely === true ||
    payload.supportsApprovals === true
  );
}

export function isRuntimeRequestEventName(name: string | null | undefined): boolean {
  return (
    name === 'runtime_request.requested' ||
    name === 'runtime_request.resolved' ||
    name === 'runtime_request.responded' ||
    name === 'approval.requested' ||
    name === 'approval.resolved'
  );
}

export function normalizeRuntimeRequestDecision(decision: string | null | undefined): CanonicalRuntimeDecision | null {
  const candidate = readString(decision);
  if (!candidate) {
    return null;
  }

  switch (candidate.toLowerCase()) {
    case 'accept':
    case 'approve_once':
    case 'approveonce':
      return 'accept';
    case 'acceptforsession':
    case 'approve_for_session':
    case 'approveforsession':
      return 'acceptForSession';
    case 'decline':
      return 'decline';
    case 'cancel':
      return 'cancel';
    default:
      return null;
  }
}

function normalizeLegacyApproval(value: LegacyApproval | unknown): RuntimeRequest | null {
  if (!isRecord(value)) {
    return null;
  }

  const requestID = readString(value.requestID ?? value.requestId);
  if (!requestID) {
    return null;
  }

  const summary = readString(value.summary) ?? 'Pending runtime request';

  return {
    requestID,
    kind: 'approval',
    threadID: readString(value.threadID ?? value.threadId),
    title: 'Approval request',
    summary,
    responseOptions: DEFAULT_APPROVAL_RESPONSE_OPTIONS.slice(),
    permissions: [],
    options: [],
    scopeHint: null,
    toolName: null,
    serverName: null
  };
}

function optionLooksAffirmative(optionID: string) {
  return /^(accept|allow|approve|yes|confirm|continue|grant|proceed|submit|ok)/i.test(optionID);
}

function optionLooksNegative(optionID: string) {
  return /^(decline|deny|reject|cancel|no|stop|dismiss)/i.test(optionID);
}

export function buildRuntimeRequestResponseForOption(request: RuntimeRequest, optionID: string): RuntimeRequestResponse {
  const canonicalDecision = normalizeRuntimeRequestDecision(optionID);
  if (canonicalDecision) {
    return {
      decision: canonicalDecision,
      optionID
    };
  }

  switch (request.kind) {
    case 'permissionsApproval':
      return {
        optionID,
        approved: optionLooksAffirmative(optionID) ? true : optionLooksNegative(optionID) ? false : null,
        permissions: request.permissions.length > 0 ? request.permissions : undefined,
        scope: request.scopeHint ?? undefined
      };
    case 'dynamicToolCall':
      return {
        optionID,
        approved: optionLooksAffirmative(optionID) ? true : optionLooksNegative(optionID) ? false : null
      };
    default:
      return { optionID };
  }
}
