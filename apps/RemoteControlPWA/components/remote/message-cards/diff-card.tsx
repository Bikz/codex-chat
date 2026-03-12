'use client';

export interface DiffCardProps {
  title: string;
  diff: string;
  collapsed: boolean;
  onToggle: () => void;
}

export function DiffCard({ title, diff, collapsed, onToggle }: DiffCardProps) {
  return (
    <section className="bg-surface border border-line rounded-2xl overflow-hidden mt-1 max-w-full">
      <button 
        className="tool-card-toggle w-full border-0 min-h-[44px] p-3 bg-transparent flex items-center justify-between gap-3 text-left active:bg-surface-alt transition-colors" 
        type="button" 
        aria-expanded={!collapsed} 
        onClick={onToggle}
      >
        <span className="min-w-0 overflow-hidden whitespace-nowrap text-ellipsis text-[13px] font-semibold text-fg" title={title}>
          {title || 'Code diff'}
        </span>
        <span className="flex items-center justify-end gap-1.5 flex-wrap flex-shrink-0">
          <span className="border border-line bg-surface-alt rounded-full px-2 min-h-[22px] inline-flex items-center text-[10px] font-bold text-muted uppercase">Diff</span>
          <span className="border border-line bg-surface-alt rounded-full px-2 min-h-[22px] inline-flex items-center text-[10px] font-bold text-muted uppercase">{collapsed ? 'Show' : 'Hide'}</span>
        </span>
      </button>

      {!collapsed ? (
        <div className="border-t border-line p-3 flex flex-col gap-3 bg-surface-alt/50">
          <div className="flex flex-col gap-1.5">
            <h4 className="m-0 text-muted text-[10px] uppercase tracking-wider font-bold">Patch</h4>
            <pre className="m-0 bg-surface border border-line rounded-xl p-3 whitespace-pre-wrap break-words text-xs leading-relaxed font-mono overflow-x-auto max-h-[300px]">{diff}</pre>
          </div>
        </div>
      ) : null}
    </section>
  );
}
