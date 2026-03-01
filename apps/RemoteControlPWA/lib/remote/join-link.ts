export interface ParsedJoinLink {
  sessionID: string;
  joinToken: string;
  relayBaseURL: string | null;
}

function normalizeRelayBaseURL(rawValue: string | null) {
  if (!rawValue || rawValue.trim() === '') {
    return null;
  }
  try {
    const parsed = new URL(rawValue);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null;
    }
    parsed.pathname = '';
    parsed.search = '';
    parsed.hash = '';
    return parsed.toString().replace(/\/$/, '');
  } catch {
    return null;
  }
}

function fromParams(rawParams: string) {
  const params = new URLSearchParams(rawParams.replace(/^[#?]/, ''));
  const sessionID = params.get('sid');
  const joinToken = params.get('jt');
  if (!sessionID || !joinToken) {
    return null;
  }
  return {
    sessionID,
    joinToken,
    relayBaseURL: normalizeRelayBaseURL(params.get('relay'))
  } satisfies ParsedJoinLink;
}

export function parseJoinLink(raw: string) {
  const trimmed = raw.trim();
  if (!trimmed) {
    return null;
  }

  const direct = fromParams(trimmed);
  if (direct) {
    return direct;
  }

  if (trimmed.startsWith('#') || trimmed.startsWith('?')) {
    return null;
  }

  let parsedURL: URL | null = null;
  try {
    parsedURL = new URL(trimmed);
  } catch {
    parsedURL = null;
  }

  if (parsedURL) {
    const fromHash = fromParams(parsedURL.hash);
    if (fromHash) {
      return fromHash;
    }

    const fromQuery = fromParams(parsedURL.search);
    if (fromQuery) {
      return fromQuery;
    }

    return null;
  }

  const hashStart = trimmed.indexOf('#');
  if (hashStart >= 0) {
    const fromHash = fromParams(trimmed.slice(hashStart + 1));
    if (fromHash) {
      return fromHash;
    }
  }

  const queryStart = trimmed.indexOf('?');
  if (queryStart >= 0) {
    const fromQuery = fromParams(trimmed.slice(queryStart + 1));
    if (fromQuery) {
      return fromQuery;
    }
  }

  return null;
}

export function buildJoinLink(pathBase: string, join: ParsedJoinLink) {
  const params = new URLSearchParams();
  params.set('sid', join.sessionID);
  params.set('jt', join.joinToken);
  if (join.relayBaseURL) {
    params.set('relay', join.relayBaseURL);
  }
  return `${pathBase}#${params.toString()}`;
}
