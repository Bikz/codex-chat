'use client';

import { ChatList } from '@/components/remote/chat-list';
import { ProjectStrip } from '@/components/remote/project-strip';
import { getRemoteClient } from '@/lib/remote/client';

export function HomeView({ hidden }: { hidden: boolean }) {
  const client = getRemoteClient();

  return (
    <section id="homeView" className="home-view" aria-label="Chat home" hidden={hidden}>
      <section className="panel projects-panel" aria-labelledby="projectsHeading">
        <div className="section-head">
          <h2 id="projectsHeading">Projects</h2>
          <button id="viewAllProjectsButton" className="ghost compact-button" type="button" onClick={() => client.openProjectSheet()}>
            View all
          </button>
        </div>
        <ProjectStrip />
      </section>

      <section className="panel chats-panel" aria-labelledby="chatsHeading">
        <h2 id="chatsHeading">Chats</h2>
        <ChatList />
      </section>
    </section>
  );
}
