'use client';

export interface ReasoningCardProps {
  status: 'started' | 'completed' | 'unknown';
  summary: string;
  collapsed: boolean;
  onToggle: () => void;
}

function statusLabel(status: ReasoningCardProps['status']) {
  if (status === 'started') return 'Started';
  if (status === 'completed') return 'Completed';
  return 'Update';
}

export function ReasoningCard({ status, summary, collapsed, onToggle }: ReasoningCardProps) {
  return (
    <section className="tool-card reasoning-card">
      <button className="tool-card-toggle" type="button" aria-expanded={!collapsed} onClick={onToggle}>
        <span className="tool-card-title">Reasoning</span>
        <span className="tool-card-chips">
          <span className={`tool-chip ${status}`}>{statusLabel(status)}</span>
          <span className="tool-chip">{collapsed ? 'Show' : 'Hide'}</span>
        </span>
      </button>

      {!collapsed ? (
        <div className="tool-card-body">
          <div className="tool-section">
            <h4>Summary</h4>
            <pre>{summary || 'No summary provided'}</pre>
          </div>
        </div>
      ) : null}
    </section>
  );
}
