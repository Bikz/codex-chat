'use client';

import { cn } from '@/lib/utils';

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
    <section className="bg-surface border border-line rounded-2xl overflow-hidden mt-1 max-w-full">
      <button 
        className="tool-card-toggle w-full border-0 min-h-[44px] p-3 bg-transparent flex items-center justify-between gap-3 text-left active:bg-surface-alt transition-colors" 
        type="button" 
        aria-expanded={!collapsed} 
        onClick={onToggle}
      >
        <span className="min-w-0 overflow-hidden whitespace-nowrap text-ellipsis text-[13px] font-semibold text-fg" title={title}>
          {title}
        </span>
        <span className="flex items-center justify-end gap-1.5 flex-wrap flex-shrink-0">
          <span className={cn(
            "border rounded-full px-2 min-h-[22px] inline-flex items-center text-[10px] font-bold uppercase tracking-wider",
            status === 'started' ? "text-warning border-warning/50 bg-warning/10" : 
            status === 'completed' ? "text-success border-success/50 bg-success/10" : "text-muted border-line bg-surface-alt"
          )}>
            {statusLabel(status)}
          </span>
          {typeof durationMs === 'number' ? <span className="border border-line bg-surface-alt rounded-full px-2 min-h-[22px] inline-flex items-center text-[10px] font-bold text-muted uppercase">{durationMs}ms</span> : null}
          <span className="border border-line bg-surface-alt rounded-full px-2 min-h-[22px] inline-flex items-center text-[10px] font-bold text-muted uppercase">{collapsed ? 'Show' : 'Hide'}</span>
        </span>
      </button>

      {!collapsed ? (
        <div className="border-t border-line p-3 flex flex-col gap-3 bg-surface-alt/50">
          <div className="flex flex-col gap-1.5">
            <h4 className="m-0 text-muted text-[10px] uppercase tracking-wider font-bold">Command</h4>
            <pre className="m-0 bg-surface border border-line rounded-xl p-3 whitespace-pre-wrap break-words text-xs leading-relaxed font-mono overflow-x-auto">{command || 'Unavailable'}</pre>
          </div>
          <div className="flex flex-col gap-1.5">
            <h4 className="m-0 text-muted text-[10px] uppercase tracking-wider font-bold">Details</h4>
            <pre className="m-0 bg-surface border border-line rounded-xl p-3 whitespace-pre-wrap break-words text-xs leading-relaxed font-mono overflow-x-auto max-h-[300px]">{details || 'No output provided'}</pre>
          </div>
        </div>
      ) : null}
    </section>
  );
}
