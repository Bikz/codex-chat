'use client';

import { ChatList } from '@/components/remote/chat-list';
import { ProjectStrip } from '@/components/remote/project-strip';

export function HomeView({ hidden }: { hidden: boolean }) {
  return (
    <section 
      id="homeView" 
      className="grid gap-4 min-w-0 max-w-full md:grid-cols-[320px_minmax(0,1fr)] md:items-start" 
      aria-label="Chat home" 
      hidden={hidden}
    >
      <section className="bg-surface rounded-[20px] border border-line shadow-sm p-4 md:sticky md:top-[80px]" aria-labelledby="projectsHeading">
        <div className="flex items-center justify-between mb-3 px-1">
          <h2 id="projectsHeading" className="text-[13px] uppercase tracking-wider text-muted font-bold">Projects</h2>
        </div>
        <ProjectStrip />
      </section>

      <section className="bg-surface rounded-[20px] border border-line shadow-sm p-4" aria-labelledby="chatsHeading">
        <div className="flex items-center justify-between mb-3 px-1">
          <h2 id="chatsHeading" className="text-[13px] uppercase tracking-wider text-muted font-bold">Recent Chats</h2>
        </div>
        <ChatList />
      </section>
    </section>
  );
}
