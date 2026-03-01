'use client';

import { getRemoteClient } from '@/lib/remote/client';
import { sortedProjectsByActivity } from '@/lib/remote/selectors';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

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

  return (
    <div id="projectCircleStrip" className="project-strip" role="list" aria-label="Projects">
      <button
        type="button"
        className={`project-circle ${selectedProjectFilterID === 'all' ? 'active' : ''}`}
        role="listitem"
        aria-label="Show all projects"
        onClick={() => client.selectProjectFilter('all', false)}
      >
        <span className="project-circle-label">All</span>
      </button>
      {visibleProjects.map((project) => (
        <button
          key={project.id}
          type="button"
          className={`project-circle ${project.id === selectedProjectFilterID ? 'active' : ''}`}
          role="listitem"
          aria-label={`Show chats for ${project.name}`}
          onClick={() => client.selectProjectFilter(project.id, true)}
        >
          <span className="project-circle-label">{project.name}</span>
        </button>
      ))}
      {shouldShowViewAll ? (
        <button
          id="projectStripViewAllButton"
          type="button"
          className="project-circle project-circle-view-all"
          role="listitem"
          aria-label="View all projects"
          onClick={() => client.openProjectSheet()}
        >
          <span className="project-circle-label">View all</span>
        </button>
      ) : null}
    </div>
  );
}
