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

  const topProjects = sortedProjectsByActivity(projects, threads).slice(0, 6);

  return (
    <>
      <div id="projectCircleStrip" className="project-strip" role="list" aria-label="Projects">
        <button
          type="button"
          className={`project-circle ${selectedProjectFilterID === 'all' ? 'active' : ''}`}
          role="listitem"
          aria-label="Show all projects"
          onClick={() => client.selectProjectFilter('all', false)}
        >
          All
        </button>
        {topProjects.map((project) => (
          <button
            key={project.id}
            type="button"
            className={`project-circle ${project.id === selectedProjectFilterID ? 'active' : ''}`}
            role="listitem"
            aria-label={`Show chats for ${project.name}`}
            onClick={() => client.selectProjectFilter(project.id, true)}
          >
            {project.name}
          </button>
        ))}
      </div>
      <button id="viewAllProjectsButton" className="ghost" type="button" onClick={() => client.openProjectSheet()}>
        View all
      </button>
    </>
  );
}
