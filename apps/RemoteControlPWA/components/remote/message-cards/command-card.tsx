'use client';

export interface CommandCardProps {
  title: string;
  status: 'started' | 'completed' | 'unknown';
  command: string | null;
  details: string;
  durationMs: number | null;
  collapsed: boolean;
  onToggle: () => void;
}

function statusLabel(status: CommandCardProps['status']) {
  if (status === 'started') return 'Started';
  if (status === 'completed') return 'Completed';
  return 'Update';
}

export function CommandCard({ title, status, command, details, durationMs, collapsed, onToggle }: CommandCardProps) {
  return (
    <section className="tool-card command-card">
      <button className="tool-card-toggle" type="button" aria-expanded={!collapsed} onClick={onToggle}>
        <span className="tool-card-title" title={title}>
          {title}
        </span>
        <span className="tool-card-chips">
          <span className={`tool-chip ${status}`}>{statusLabel(status)}</span>
          {typeof durationMs === 'number' ? <span className="tool-chip">{durationMs}ms</span> : null}
          <span className="tool-chip">{collapsed ? 'Show' : 'Hide'}</span>
        </span>
      </button>

      {!collapsed ? (
        <div className="tool-card-body">
          <div className="tool-section">
            <h4>Command</h4>
            <pre>{command || 'Unavailable'}</pre>
          </div>
          <div className="tool-section">
            <h4>Details</h4>
            <pre>{details || 'No output provided'}</pre>
          </div>
        </div>
      ) : null}
    </section>
  );
}
