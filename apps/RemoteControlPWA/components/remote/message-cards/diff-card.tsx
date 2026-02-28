'use client';

export interface DiffCardProps {
  title: string;
  diff: string;
  collapsed: boolean;
  onToggle: () => void;
}

export function DiffCard({ title, diff, collapsed, onToggle }: DiffCardProps) {
  return (
    <section className="tool-card diff-card">
      <button className="tool-card-toggle" type="button" aria-expanded={!collapsed} onClick={onToggle}>
        <span className="tool-card-title" title={title}>
          {title || 'Code diff'}
        </span>
        <span className="tool-card-chips">
          <span className="tool-chip">Diff</span>
          <span className="tool-chip">{collapsed ? 'Show' : 'Hide'}</span>
        </span>
      </button>

      {!collapsed ? (
        <div className="tool-card-body">
          <div className="tool-section">
            <h4>Patch</h4>
            <pre>{diff}</pre>
          </div>
        </div>
      ) : null}
    </section>
  );
}
