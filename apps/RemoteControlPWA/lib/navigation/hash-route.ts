export type RemoteView = 'home' | 'thread';

export interface HashRoute {
  view: RemoteView;
  threadID: string | null;
  projectID: string;
}

export function parseRouteHash(hash: string): HashRoute {
  const normalizedHash = hash.replace(/^#/, '');
  const params = new URLSearchParams(normalizedHash);
  const view = params.get('view') === 'thread' ? 'thread' : 'home';
  const threadID = params.get('tid');
  const projectID = params.get('pid') || 'all';

  return {
    view,
    threadID: threadID && threadID.length > 0 ? threadID : null,
    projectID
  };
}

export function buildRouteHash(route: HashRoute): string {
  const params = new URLSearchParams();
  params.set('view', route.view);
  if (route.view === 'thread' && route.threadID) {
    params.set('tid', route.threadID);
  }
  params.set('pid', route.projectID || 'all');
  return `#${params.toString()}`;
}

export function normalizeProjectID(projectID: string | null | undefined): string {
  if (!projectID || projectID.trim() === '') {
    return 'all';
  }
  return projectID;
}
