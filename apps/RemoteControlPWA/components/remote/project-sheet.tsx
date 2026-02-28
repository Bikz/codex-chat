'use client';

import * as Dialog from '@radix-ui/react-dialog';
import { getRemoteClient } from '@/lib/remote/client';
import { sortedProjectsByActivity } from '@/lib/remote/selectors';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

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
        <Dialog.Content id="projectSheet" className="sheet-card" aria-labelledby="projectSheetTitle">
          <div className="sheet-head">
            <Dialog.Title asChild>
              <h2 id="projectSheetTitle">All projects</h2>
            </Dialog.Title>
            <Dialog.Close asChild>
              <button id="closeProjectSheetButton" className="ghost" type="button" aria-label="Close project list">
                Close
              </button>
            </Dialog.Close>
          </div>

          <ul id="projectSheetList" className="sheet-list" aria-label="All projects">
            {options.map((project) => (
              <li key={project.id}>
                <button
                  type="button"
                  className={project.id === selectedProjectFilterID ? 'primary' : ''}
                  onClick={() => {
                    client.selectProjectFilter(project.id, project.id !== 'all');
                    client.closeProjectSheet();
                  }}
                >
                  {project.name}
                </button>
              </li>
            ))}
          </ul>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
