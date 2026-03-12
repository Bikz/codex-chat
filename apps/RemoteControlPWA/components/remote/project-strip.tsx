'use client';

import { getRemoteClient } from '@/lib/remote/client';
import { sortedProjectsByActivity } from '@/lib/remote/selectors';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';
import { cn } from '@/lib/utils';

export function ProjectStrip() {
  const client = getRemoteClient();
  const { projects, threads, selectedProjectFilterID } = useRemoteStore(
    useShallow((state) => ({
      projects: state.projects,
      threads: state.threads,
      selectedProjectFilterID: state.selectedProjectFilterID
    }))
  );

  const rankedProjects = sortedProjectsByActivity(projects, threads);
  const maxTiles = 8;
  const reservedSlots = 1; // "All"
  const maxProjectsWhenViewAll = maxTiles - reservedSlots - 1; // reserve one slot for View all
  const maxProjectsWithoutViewAll = maxTiles - reservedSlots;
  const shouldShowViewAll = rankedProjects.length > maxProjectsWithoutViewAll;
  const visibleProjects = shouldShowViewAll ? rankedProjects.slice(0, maxProjectsWhenViewAll) : rankedProjects.slice(0, maxProjectsWithoutViewAll);

  const circleClasses = "project-circle w-full min-h-[64px] rounded-2xl border border-line bg-surface-alt p-2 flex items-center justify-center text-center text-xs font-semibold leading-tight text-fg overflow-hidden break-words transition-colors active:scale-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent";

  return (
    <div id="projectCircleStrip" className="grid grid-cols-4 auto-rows-auto gap-2 w-full min-w-0" role="list" aria-label="Projects">
      <button
        type="button"
        className={cn(circleClasses, selectedProjectFilterID === 'all' && "border-accent text-accent bg-accent/5 ring-1 ring-accent/20")}
        role="listitem"
        aria-label="Show all projects"
        onClick={() => client.selectProjectFilter('all', false)}
      >
        <span className="line-clamp-2">All</span>
      </button>
      {visibleProjects.map((project) => (
        <button
          key={project.id}
          type="button"
          className={cn(circleClasses, project.id === selectedProjectFilterID && "border-accent text-accent bg-accent/5 ring-1 ring-accent/20")}
          role="listitem"
          aria-label={`Show chats for ${project.name}`}
          onClick={() => client.selectProjectFilter(project.id, true)}
        >
          <span className="line-clamp-2">{project.name}</span>
        </button>
      ))}
      {shouldShowViewAll ? (
        <button
          id="projectStripViewAllButton"
          type="button"
          className={cn(circleClasses, "border-dashed text-muted hover:text-fg")}
          role="listitem"
          aria-label="View all projects"
          onClick={() => client.openProjectSheet()}
        >
          <span className="line-clamp-2">View all</span>
        </button>
      ) : null}
    </div>
  );
}
