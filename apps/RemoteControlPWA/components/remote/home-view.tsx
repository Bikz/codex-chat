'use client';

import { ChatList } from '@/components/remote/chat-list';
import { ProjectStrip } from '@/components/remote/project-strip';

export function HomeView({ hidden }: { hidden: boolean }) {
  return (
    <section id="homeView" className="home-view" aria-label="Chat home" hidden={hidden}>
      <section className="panel projects-panel" aria-labelledby="projectsHeading">
        <h2 id="projectsHeading">Projects</h2>
        <ProjectStrip />
      </section>

      <section className="panel chats-panel" aria-labelledby="chatsHeading">
        <h2 id="chatsHeading">Chats</h2>
        <ChatList />
      </section>
    </section>
  );
}
