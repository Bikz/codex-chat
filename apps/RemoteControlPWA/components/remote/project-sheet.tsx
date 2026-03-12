'use client';

import * as Dialog from '@radix-ui/react-dialog';
import { getRemoteClient } from '@/lib/remote/client';
import { sortedProjectsByActivity } from '@/lib/remote/selectors';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

export function ProjectSheet() {
  const client = getRemoteClient();
  const { isProjectSheetOpen, projects, threads, selectedProjectFilterID } = useRemoteStore(
    useShallow((state) => ({
      isProjectSheetOpen: state.isProjectSheetOpen,
      projects: state.projects,
      threads: state.threads,
      selectedProjectFilterID: state.selectedProjectFilterID
    }))
  );

  const options = [{ id: 'all', name: 'All projects' }, ...sortedProjectsByActivity(projects, threads)];

  return (
    <Dialog.Root open={isProjectSheetOpen} onOpenChange={(open) => (open ? client.openProjectSheet() : client.closeProjectSheet())}>
      <Dialog.Portal>
        <Dialog.Overlay className="sheet-backdrop" />
        <Dialog.Content id="projectSheet" className="sheet-card flex flex-col gap-4" aria-labelledby="projectSheetTitle">
          <div className="flex items-center justify-between mb-2">
            <Dialog.Title asChild>
              <h2 id="projectSheetTitle" className="text-xl font-bold tracking-tight text-fg truncate">All projects</h2>
            </Dialog.Title>
            <Dialog.Close asChild>
              <Button id="closeProjectSheetButton" variant="ghost" size="sm" type="button" aria-label="Close project list" className="h-8 px-3 rounded-full text-[13px] bg-surface-alt">
                Done
              </Button>
            </Dialog.Close>
          </div>

          <ul id="projectSheetList" className="flex flex-col gap-2 m-0 p-0 list-none" aria-label="All projects">
            {options.map((project) => {
              const isActive = project.id === selectedProjectFilterID;
              return (
                <li key={project.id}>
                  <button
                    type="button"
                    className={cn(
                      "w-full text-left px-4 py-3 rounded-2xl min-w-0 break-words transition-all active:scale-[0.98] font-medium text-[15px] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent",
                      isActive ? "bg-accent text-accent-fg border border-accent shadow-sm" : "bg-surface-alt text-fg border border-line hover:bg-surface-subtle"
                    )}
                    onClick={() => {
                      client.selectProjectFilter(project.id, project.id !== 'all');
                      client.closeProjectSheet();
                    }}
                  >
                    <span className="line-clamp-2">{project.name}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
