export type ParsedMessageMode = 'plain' | 'command_execution' | 'diff_patch' | 'reasoning_summary';

interface ParsedBase {
  mode: ParsedMessageMode;
  raw: string;
}

export interface ParsedPlainMessage extends ParsedBase {
  mode: 'plain';
}

export interface ParsedCommandExecutionMessage extends ParsedBase {
  mode: 'command_execution';
  status: 'started' | 'completed' | 'unknown';
  command: string | null;
  details: string;
  durationMs: number | null;
}

export interface ParsedDiffPatchMessage extends ParsedBase {
  mode: 'diff_patch';
  title: string;
  diff: string;
}

export interface ParsedReasoningSummaryMessage extends ParsedBase {
  mode: 'reasoning_summary';
  status: 'started' | 'completed' | 'unknown';
  summary: string;
}

export type ParsedMessage =
  | ParsedPlainMessage
  | ParsedCommandExecutionMessage
  | ParsedDiffPatchMessage
  | ParsedReasoningSummaryMessage;

function parseJSONStringField(payload: string, field: string): string | null {
  const match = payload.match(new RegExp(`"${field}"\\s*:\\s*"([^"\\\\]*(?:\\\\.[^"\\\\]*)*)"`));
  if (!match || typeof match[1] !== 'string') {
    return null;
  }

  try {
    return JSON.parse(`"${match[1]}"`) as string;
  } catch {
    return match[1];
  }
}

function parseJSONNumberField(payload: string, field: string): number | null {
  const match = payload.match(new RegExp(`"${field}"\\s*:\\s*(\\d+)`));
  if (!match) {
    return null;
  }
  const value = Number.parseInt(match[1], 10);
  return Number.isFinite(value) ? value : null;
}

function parseJSONSummaryField(payload: string): string | null {
  const asString = parseJSONStringField(payload, 'summary');
  if (asString) {
    return asString;
  }

  const arrayMatch = payload.match(/"summary"\s*:\s*\[([\s\S]*?)\]/);
  if (!arrayMatch?.[1]) {
    return null;
  }

  const segments: string[] = [];
  const quoted = /"((?:[^"\\]|\\.)*)"/g;
  for (const match of arrayMatch[1].matchAll(quoted)) {
    if (!match[1]) continue;
    try {
      segments.push(JSON.parse(`"${match[1]}"`) as string);
    } catch {
      segments.push(match[1]);
    }
  }

  if (segments.length === 0) {
    return null;
  }
  return segments.join(' ').trim();
}

function parseCommandExecution(text: string): ParsedCommandExecutionMessage | null {
  const firstLine = text.split(/\r?\n/, 1)[0] || '';
  const isCommandExecution = /^(Started|Completed)\s+commandExecution:/i.test(firstLine.trim());
  if (!isCommandExecution) {
    return null;
  }

  const status: ParsedCommandExecutionMessage['status'] = /^Started\s+/i.test(firstLine)
    ? 'started'
    : /^Completed\s+/i.test(firstLine)
      ? 'completed'
      : 'unknown';

  const command = parseJSONStringField(text, 'command');
  const durationMs = parseJSONNumberField(text, 'durationMs');
  const details = text.slice(firstLine.length).trim() || text;

  return {
    mode: 'command_execution',
    raw: text,
    status,
    command,
    details,
    durationMs
  };
}

function extractDiffBody(text: string): string | null {
  const fencedDiff = text.match(/```diff\s*\n([\s\S]*?)```/i);
  if (fencedDiff?.[1]) {
    return fencedDiff[1].trim();
  }

  const patchBlock = text.match(/\*\*\* Begin Patch([\s\S]*?)\*\*\* End Patch/);
  if (patchBlock?.[0]) {
    return patchBlock[0].trim();
  }

  if (/^diff --git\s+/m.test(text) || /^@@\s/m.test(text)) {
    return text.trim();
  }

  return null;
}

function parseDiffPatch(text: string): ParsedDiffPatchMessage | null {
  const diff = extractDiffBody(text);
  if (!diff) {
    return null;
  }

  const title = text.split(/\r?\n/, 1)[0]?.trim() || 'Code diff';
  return {
    mode: 'diff_patch',
    raw: text,
    title,
    diff
  };
}

function parseReasoningSummary(text: string): ParsedReasoningSummaryMessage | null {
  const firstLine = text.split(/\r?\n/, 1)[0] || '';
  const isReasoning = /^(Started|Completed)\s+reasoning:/i.test(firstLine.trim());
  if (!isReasoning) {
    return null;
  }

  const status: ParsedReasoningSummaryMessage['status'] = /^Started\s+/i.test(firstLine)
    ? 'started'
    : /^Completed\s+/i.test(firstLine)
      ? 'completed'
      : 'unknown';

  const explicitSummary = parseJSONSummaryField(text);
  const body = text.slice(firstLine.length).trim();
  const summary = explicitSummary || body || text;

  return {
    mode: 'reasoning_summary',
    raw: text,
    status,
    summary
  };
}

export function parseMessageText(rawText: string): ParsedMessage {
  const text = typeof rawText === 'string' ? rawText : '';
  if (!text.trim()) {
    return {
      mode: 'plain',
      raw: text
    };
  }

  const commandExecution = parseCommandExecution(text);
  if (commandExecution) {
    return commandExecution;
  }

  const diffPatch = parseDiffPatch(text);
  if (diffPatch) {
    return diffPatch;
  }

  const reasoningSummary = parseReasoningSummary(text);
  if (reasoningSummary) {
    return reasoningSummary;
  }

  return {
    mode: 'plain',
    raw: text
  };
}
