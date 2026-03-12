import type {
  RemoteSnapshot,
  RuntimeRequest,
  RuntimeRequestKind,
  RuntimeRequestResponse,
  RuntimeRequestResponseOption
} from '@/lib/remote/types';

export type CanonicalRuntimeDecision = 'accept' | 'acceptForSession' | 'decline' | 'cancel';
export interface RuntimeRequestResponseDraft {
  text?: string | null;
  optionID?: string | null;
}

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
  const nextRequests = Array.isArray(snapshot.pendingRuntimeRequests) ? snapshot.pendingRuntimeRequests : [];
  return nextRequests.map((entry) => normalizeRuntimeRequest(entry)).filter((entry): entry is RuntimeRequest => entry !== null);
}

export function normalizeCanRespondToRuntimeRequests(payload: Record<string, unknown> | undefined): boolean {
  if (!payload) {
    return false;
  }

  return payload.canRespondToRuntimeRequests === true || payload.supportsRuntimeRequests === true;
}

export function isRuntimeRequestEventName(name: string | null | undefined): boolean {
  return name === 'runtime_request.requested' || name === 'runtime_request.resolved' || name === 'runtime_request.responded';
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

function optionLooksAffirmative(optionID: string) {
  return /^(accept|allow|approve|yes|confirm|continue|grant|proceed|submit|ok)/i.test(optionID);
}

function optionLooksNegative(optionID: string) {
  return /^(decline|deny|reject|cancel|no|stop|dismiss)/i.test(optionID);
}

function normalizeResponseText(value: string | null | undefined): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeSelectedRequestOptionID(request: RuntimeRequest, candidate: string | null | undefined): string | null {
  const normalizedCandidate = readString(candidate);
  if (!normalizedCandidate) {
    return null;
  }
  return request.options.some((option) => option.id === normalizedCandidate) ? normalizedCandidate : null;
}

export function buildRuntimeRequestResponseForOption(
  request: RuntimeRequest,
  responseOptionID: string,
  draft: RuntimeRequestResponseDraft = {}
): RuntimeRequestResponse {
  switch (request.kind) {
    case 'approval': {
      const canonicalDecision = normalizeRuntimeRequestDecision(responseOptionID);
      if (canonicalDecision) {
        return {
          decision: canonicalDecision,
          optionID: responseOptionID
        };
      }
      return { optionID: responseOptionID };
    }
    case 'permissionsApproval':
      if (optionLooksNegative(responseOptionID)) {
        return {
          optionID: responseOptionID,
          approved: false,
          permissions: [],
          scope: undefined
        };
      }
      return {
        optionID: responseOptionID,
        approved: optionLooksAffirmative(responseOptionID) ? true : optionLooksNegative(responseOptionID) ? false : null,
        permissions: request.permissions.length > 0 ? request.permissions : undefined,
        scope: request.scopeHint ?? undefined
      };
    case 'userInput':
      if (optionLooksNegative(responseOptionID)) {
        return {
          text: null,
          optionID: null
        };
      }
      return {
        text: normalizeResponseText(draft.text),
        optionID: normalizeSelectedRequestOptionID(request, draft.optionID)
      };
    case 'mcpElicitation':
      if (optionLooksNegative(responseOptionID)) {
        return {
          text: null
        };
      }
      return {
        text: normalizeResponseText(draft.text)
      };
    case 'dynamicToolCall':
      return {
        optionID: responseOptionID,
        approved: optionLooksAffirmative(responseOptionID) ? true : optionLooksNegative(responseOptionID) ? false : null
      };
    default:
      return { optionID: responseOptionID };
  }
}
