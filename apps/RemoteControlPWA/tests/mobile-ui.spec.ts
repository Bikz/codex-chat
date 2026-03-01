import { expect, test } from "@playwright/test";

const longMessage = Array.from({ length: 12 }, (_, index) => `line ${index + 1} with verbose mobile text`).join("\n");
const longToken = "A".repeat(200);

const snapshotPayload = {
  projects: [
    { id: "p1", name: "General" },
    { id: "p2", name: "StarBeam" },
    { id: "p3", name: "Voice-App" }
  ],
  threads: [
    { id: "t1", projectID: "p1", title: "Daily sync", isPinned: false },
    { id: "t2", projectID: "p2", title: "Long output diagnostics", isPinned: false }
  ],
  selectedProjectID: "p1",
  selectedThreadID: "t1",
  messages: [
    { id: "m1", threadID: "t1", role: "assistant", text: "Short summary", createdAt: "2026-02-28T15:00:00.000Z" },
    { id: "m2", threadID: "t2", role: "assistant", text: longMessage, createdAt: "2026-02-28T15:01:00.000Z" }
  ],
  turnState: { threadID: "t1", isTurnInProgress: true, isAwaitingApproval: false },
  pendingApprovals: [
    { requestID: "a1", threadID: "t1", summary: "Allow command execution?" },
    { requestID: "a2", threadID: null, summary: "Allow session-level action?" }
  ]
};

function createLargeProjectPayload() {
  const projects = Array.from({ length: 12 }, (_, index) => ({
    id: `p${index + 1}`,
    name: `Project${index + 1}${"X".repeat(60)}`
  }));
  return {
    projects,
    threads: projects.map((project, index) => ({
      id: `t${index + 1}`,
      projectID: project.id,
      title: `Thread ${index + 1}`,
      isPinned: false
    })),
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [
      {
        id: "m1",
        threadID: "t1",
        role: "assistant",
        text: "User-visible message",
        createdAt: "2026-02-28T15:00:00.000Z"
      }
    ],
    pendingApprovals: []
  };
}

function createLongTokenOverflowPayload() {
  const projects = Array.from({ length: 10 }, (_, index) => ({
    id: `lp${index + 1}`,
    name: `project_${index + 1}_${"Q".repeat(72)}`
  }));

  return {
    projects,
    threads: [
      {
        id: "lt1",
        projectID: projects[0].id,
        title: `thread_${"T".repeat(220)}`,
        isPinned: false
      }
    ],
    selectedProjectID: projects[0].id,
    selectedThreadID: "lt1",
    messages: [
      {
        id: "ltm1",
        threadID: "lt1",
        role: "assistant",
        text: `Completed commandExecution:\n{"command":"echo ok","durationMs":22,"stdout":"${"S".repeat(900)}"}`,
        createdAt: "2026-02-28T15:00:00.000Z"
      }
    ],
    pendingApprovals: []
  };
}

function createSystemHeavyPayload(reasoningStatus: "started" | "completed" = "started") {
  const reasoningPrefix = reasoningStatus === "started" ? "Started" : "Completed";
  return {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t1", projectID: "p1", title: "Simple greeting", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [
      {
        id: "m1",
        threadID: "t1",
        role: "system",
        text: 'Started userMessage: {"id":"msg_123","type":"userMessage"}',
        createdAt: "2026-02-28T15:00:00.000Z"
      },
      {
        id: "m2",
        threadID: "t1",
        role: "assistant",
        text: "Hey! What can I help you with today?",
        createdAt: "2026-02-28T15:00:01.000Z"
      },
      {
        id: "m3",
        threadID: "t1",
        role: "system",
        text: `${reasoningPrefix} reasoning:\n{"summary":["thinking"]}`,
        createdAt: "2026-02-28T15:00:02.000Z"
      },
      {
        id: "m4",
        threadID: "t1",
        role: "system",
        text: 'Completed userMessage: {"id":"msg_123","type":"userMessage"}',
        createdAt: "2026-02-28T15:00:03.000Z"
      }
    ],
    pendingApprovals: []
  };
}

function createSystemPolicyPayload() {
  return {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t1", projectID: "p1", title: "Policy thread", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [
      {
        id: "m-tech",
        threadID: "t1",
        role: "system",
        text: 'Started userMessage: {"id":"msg_123","type":"userMessage"}',
        createdAt: "2026-02-28T15:00:00.000Z"
      },
      {
        id: "m-approval",
        threadID: "t1",
        role: "system",
        text: "Approval required: Allow command execution?",
        createdAt: "2026-02-28T15:00:01.000Z"
      },
      {
        id: "m-error",
        threadID: "t1",
        role: "system",
        text: "Turn failed to start",
        createdAt: "2026-02-28T15:00:02.000Z"
      }
    ],
    pendingApprovals: []
  };
}

async function seedDemo(page: Parameters<typeof test>[0]["page"]) {
  await page.goto("/?e2e=1#view=home&pid=all");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);
  await page.evaluate((payload) => {
    (window as any).__codexRemotePWAHarness.resetStorage();
    (window as any).__codexRemotePWAHarness.seed(payload, { authenticated: true });
  }, snapshotPayload);
  await expect(page.locator("#workspacePanel")).toBeVisible();
  await expect.poll(async () => page.locator("#chatList .chat-row").count()).toBeGreaterThan(0);
}

async function seedCustom(page: Parameters<typeof test>[0]["page"], payload: unknown) {
  await page.goto("/?e2e=1#view=home&pid=all");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);
  await page.evaluate((nextPayload) => {
    (window as any).__codexRemotePWAHarness.resetStorage();
    (window as any).__codexRemotePWAHarness.seed(nextPayload, { authenticated: true });
  }, payload);
  await expect(page.locator("#workspacePanel")).toBeVisible();

  const hasThreads = await page.evaluate((nextPayload) => {
    if (!nextPayload || typeof nextPayload !== "object") {
      return false;
    }
    const candidate = nextPayload as { threads?: unknown };
    return Array.isArray(candidate.threads) && candidate.threads.length > 0;
  }, payload);
  if (hasThreads) {
    await expect.poll(async () => page.locator("#chatList .chat-row").count()).toBeGreaterThan(0);
  }
}

async function injectEnvelope(page: Parameters<typeof test>[0]["page"], message: unknown) {
  await page.evaluate((nextMessage) => {
    (window as any).__codexRemotePWAHarness.injectMessage(nextMessage as Record<string, unknown>);
  }, message);
}

async function expectNoPageHorizontalOverflow(page: Parameters<typeof test>[0]["page"]) {
  const dimensions = await page.evaluate(() => ({
    htmlScrollWidth: document.documentElement.scrollWidth,
    htmlClientWidth: document.documentElement.clientWidth,
    bodyScrollWidth: document.body.scrollWidth,
    bodyClientWidth: document.body.clientWidth
  }));

  const hasHTMLOverflow = dimensions.htmlScrollWidth > dimensions.htmlClientWidth + 1;
  const hasBodyOverflow = dimensions.bodyScrollWidth > dimensions.bodyClientWidth + 1;
  if (hasHTMLOverflow || hasBodyOverflow) {
    const offenders = await page.evaluate(() => {
      const nodes = Array.from(document.querySelectorAll<HTMLElement>("body *"));
      return nodes
        .filter((node) => node.scrollWidth > node.clientWidth + 1)
        .slice(0, 15)
        .map((node) => ({
          tag: node.tagName.toLowerCase(),
          id: node.id || null,
          className: node.className || null,
          scrollWidth: node.scrollWidth,
          clientWidth: node.clientWidth
        }));
    });
    throw new Error(
      `Horizontal overflow detected: ${JSON.stringify({
        dimensions,
        offenders
      })}`
    );
  }
}

function createLongThreadPayload(messageCount: number) {
  return {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t-long", projectID: "p1", title: "Scroll anchor thread", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t-long",
    messages: Array.from({ length: messageCount }, (_, index) => ({
      id: `ml-${index + 1}`,
      threadID: "t-long",
      role: "assistant",
      text: `message ${index + 1}`,
      createdAt: `2026-02-28T15:${String(index % 59).padStart(2, "0")}:00.000Z`
    })),
    pendingApprovals: []
  };
}

test("mobile-home-view-renders", async ({ page }) => {
  await seedDemo(page);

  await expect(page.locator("#workspacePanel")).toBeVisible();
  await expect(page.locator("#projectCircleStrip .project-circle")).toHaveCount(4);
  await expect(page.locator("#chatList .chat-row")).toHaveCount(2);
});

test("mobile-no-horizontal-overflow-home", async ({ page }) => {
  await seedCustom(page, createLargeProjectPayload());
  await expectNoPageHorizontalOverflow(page);
});

test("mobile-no-horizontal-overflow-thread", async ({ page }) => {
  await seedCustom(page, {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t1", projectID: "p1", title: "Very Long Thread Name Very Long Thread Name", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [
      {
        id: "m1",
        threadID: "t1",
        role: "assistant",
        text: "A".repeat(1800),
        createdAt: "2026-02-28T15:00:00.000Z"
      }
    ],
    pendingApprovals: []
  });
  await page.locator("#chatList .chat-row").first().click();
  await expectNoPageHorizontalOverflow(page);
});

test("mobile-long-unbroken-strings-stay-contained", async ({ page }) => {
  await seedCustom(page, createLongTokenOverflowPayload());

  const longSessionID = `sid_${longToken}`;
  const longDeviceName = `device_${"D".repeat(180)}`;
  await page.evaluate(
    ({ sessionID, deviceName }) => {
      const harness = (window as any).__codexRemotePWAHarness;
      harness.setSessionID(sessionID);
      harness.setDeviceName(deviceName);
    },
    { sessionID: longSessionID, deviceName: longDeviceName }
  );

  await page.getByRole("button", { name: "Open account and connection controls" }).click();
  await expect(page.locator("#accountSheet")).toBeVisible();
  await expect(page.locator("#sessionValue")).toContainText("sid_");
  await expectNoPageHorizontalOverflow(page);
  await page.locator("#closeAccountSheetButton").click();
  await expect(page.locator("#accountSheet")).toBeHidden();

  await expect(page.locator("#projectStripViewAllButton")).toBeVisible();
  await page.locator("#projectStripViewAllButton").click();
  await expect(page.locator("#projectSheet")).toBeVisible();
  await expectNoPageHorizontalOverflow(page);
  await page.locator("#closeProjectSheetButton").click();
  await expect(page.locator("#projectSheet")).toBeHidden();

  await page.locator("#chatList .chat-row").first().click();
  await expect(page.locator("#chatView")).toBeVisible();
  await page.locator(".tool-card-toggle").first().click();
  await expectNoPageHorizontalOverflow(page);
});

test("mobile-all-sheets-no-horizontal-overflow", async ({ page }) => {
  await page.goto("/?e2e=1#view=home&pid=all");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);

  await page.getByRole("button", { name: "Scan QR" }).first().click();
  await expect(page.locator("#qrScannerSheet")).toBeVisible();
  await page.locator("#manualPairLinkInput").fill(
    `https://remote.bikz.cc/#sid=${`s${"L".repeat(160)}`}&jt=test-join&relay=https://remote.bikz.cc`
  );
  await expectNoPageHorizontalOverflow(page);
  await page.locator("#closeQRScannerButton").click();
  await expect(page.locator("#qrScannerSheet")).toBeHidden();

  await page.evaluate((payload) => {
    const harness = (window as any).__codexRemotePWAHarness;
    harness.resetStorage();
    harness.seed(payload, { authenticated: true });
  }, createLongTokenOverflowPayload());
  await expect(page.locator("#workspacePanel")).toBeVisible();
  await expect(page.locator("#projectStripViewAllButton")).toBeVisible();

  await page.getByRole("button", { name: "Open account and connection controls" }).click();
  await expect(page.locator("#accountSheet")).toBeVisible();
  await expectNoPageHorizontalOverflow(page);
  await page.locator("#closeAccountSheetButton").click();
  await expect(page.locator("#accountSheet")).toBeHidden();

  await page.locator("#projectStripViewAllButton").click();
  await expect(page.locator("#projectSheet")).toBeVisible();
  await expectNoPageHorizontalOverflow(page);
  await page.locator("#closeProjectSheetButton").click();
  await expect(page.locator("#projectSheet")).toBeHidden();
});

test("mobile-orientation-resize-preserves-layout-containment", async ({ page }) => {
  await seedCustom(page, createLongTokenOverflowPayload());
  await page.locator("#chatList .chat-row").first().click();
  await expect(page.locator("#chatView")).toBeVisible();

  const viewports = [
    { width: 844, height: 390 },
    { width: 390, height: 844 }
  ];

  for (const viewport of viewports) {
    await page.setViewportSize(viewport);
    await page.waitForTimeout(120);
    await expectNoPageHorizontalOverflow(page);
  }
});

test("mobile-project-grid-two-rows", async ({ page }) => {
  await seedCustom(page, createLargeProjectPayload());

  await expect(page.locator("#projectCircleStrip .project-circle")).toHaveCount(8);
  await expect(page.locator("#projectStripViewAllButton")).toBeVisible();

  const rowCount = await page.evaluate(() => {
    const circles = Array.from(document.querySelectorAll<HTMLElement>("#projectCircleStrip .project-circle"));
    const rowTops = new Set(circles.map((circle) => Math.round(circle.getBoundingClientRect().top)));
    return rowTops.size;
  });
  expect(rowCount).toBeGreaterThanOrEqual(2);
});

test("mobile-chat-preview-hides-technical", async ({ page }) => {
  await seedCustom(page, createSystemHeavyPayload("started"));
  await expect(page.locator("#chatList .chat-preview").first()).toHaveText("Hey! What can I help you with today?");
});

test("mobile-thread-navigation-back", async ({ page }) => {
  await seedDemo(page);

  await page.getByRole("button", { name: "Open chat Daily sync" }).click();
  await expect(page).toHaveURL(/view=thread/);
  await expect(page.locator("#chatView")).toBeVisible();

  await page.goBack();
  await expect(page).toHaveURL(/view=home/);
  await expect(page.locator("#homeView")).toBeVisible();
});

test("mobile-transcript-hides-system", async ({ page }) => {
  await seedCustom(page, createSystemHeavyPayload("started"));
  await page.getByRole("button", { name: "Open chat Simple greeting" }).click();

  await expect(page.locator(".message")).toHaveCount(1);
  await expect(page.getByText("Started userMessage")).toHaveCount(0);
  await expect(page.getByText("Completed userMessage")).toHaveCount(0);
});

test("mobile-transcript-default-shows-user-relevant-system-notices", async ({ page }) => {
  await seedCustom(page, createSystemPolicyPayload());
  await page.locator("#chatList .chat-row").first().click();

  await expect(page.getByText("Approval required: Allow command execution?")).toBeVisible();
  await expect(page.getByText("Turn failed to start")).toBeVisible();
  await expect(page.getByText("Started userMessage")).toHaveCount(0);
});

test("mobile-transcript-toggle-can-show-all-system-messages", async ({ page }) => {
  await seedCustom(page, createSystemPolicyPayload());
  await page.getByRole("button", { name: "Open chat Policy thread" }).click();
  await expect(page.getByText("Started userMessage")).toHaveCount(0);

  await page.getByRole("button", { name: "Open account and connection controls" }).click();
  await page.locator("#showSystemMessagesToggle").check();
  await page.keyboard.press("Escape");

  await expect(page.getByText("Started userMessage")).toBeVisible();
});

test("mobile-event-injection-updates-transcript-immediately", async ({ page }) => {
  await seedCustom(page, {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t1", projectID: "p1", title: "Latency thread", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [],
    pendingApprovals: []
  });
  await page.getByRole("button", { name: "Open chat Latency thread" }).click();

  const start = Date.now();
  await injectEnvelope(page, {
    schemaVersion: 1,
    sessionID: "e2e-session",
    seq: 1,
    timestamp: new Date().toISOString(),
    payload: {
      type: "event",
      payload: {
        name: "thread.message.append",
        threadID: "t1",
        body: "Remote event message",
        messageID: "evt-1",
        role: "assistant",
        createdAt: new Date().toISOString()
      }
    }
  });

  const transcript = page.getByLabel("Transcript");
  await expect(transcript.getByText("Remote event message")).toBeVisible({ timeout: 350 });
  const elapsed = Date.now() - start;
  expect(elapsed).toBeLessThan(350);
});

test("mobile-mac-offline-state-disables-composer-send", async ({ page }) => {
  await seedCustom(page, snapshotPayload);
  await page.getByRole("button", { name: "Open chat Daily sync" }).click();

  await injectEnvelope(page, {
    type: "relay.desktop_status",
    sessionID: "e2e-session",
    desktopConnected: false
  });

  await expect(page.locator("#connectionBadge")).toContainText("Mac offline");
  await expect(page.locator("#desktopOfflineBanner")).toBeVisible();
  await expect(page.locator("#composerReconnectButton")).toBeVisible();

  await page.locator("#composerInput").fill("offline attempt");
  await expect(page.getByRole("button", { name: "Send message" })).toBeDisabled();
  await page.evaluate(() => {
    const form = document.querySelector<HTMLFormElement>("#composerForm");
    form?.requestSubmit();
  });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().queuedCommandsCount)).toBe(0);
});

test("mobile-mac-reconnect-event-clears-offline-indicator", async ({ page }) => {
  await seedCustom(page, snapshotPayload);
  await page.getByRole("button", { name: "Open chat Daily sync" }).click();

  await injectEnvelope(page, {
    type: "relay.desktop_status",
    sessionID: "e2e-session",
    desktopConnected: false
  });
  await expect(page.locator("#desktopOfflineBanner")).toBeVisible();

  await injectEnvelope(page, {
    type: "relay.desktop_status",
    sessionID: "e2e-session",
    desktopConnected: true
  });
  await expect(page.locator("#desktopOfflineBanner")).toBeHidden();
  await expect(page.locator("#connectionBadge")).toContainText("Connected");
});

test("mobile-dedupes-message-on-reconnect-resync", async ({ page }) => {
  await seedCustom(page, {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t1", projectID: "p1", title: "Dedupe thread", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [
      { id: "m1", threadID: "t1", role: "assistant", text: "First", createdAt: "2026-02-28T15:00:00.000Z" }
    ],
    pendingApprovals: []
  });
  await page.getByRole("button", { name: "Open chat Dedupe thread" }).click();

  await injectEnvelope(page, {
    schemaVersion: 1,
    sessionID: "e2e-session",
    seq: 1,
    timestamp: new Date().toISOString(),
    payload: {
      type: "event",
      payload: {
        name: "thread.message.append",
        threadID: "t1",
        body: "Second",
        messageID: "m2",
        role: "assistant",
        createdAt: "2026-02-28T15:00:01.000Z"
      }
    }
  });
  await injectEnvelope(page, {
    schemaVersion: 1,
    sessionID: "e2e-session",
    seq: 2,
    timestamp: new Date().toISOString(),
    payload: {
      type: "event",
      payload: {
        name: "thread.message.append",
        threadID: "t1",
        body: "Second (duplicate)",
        messageID: "m2",
        role: "assistant",
        createdAt: "2026-02-28T15:00:02.000Z"
      }
    }
  });

  await injectEnvelope(page, {
    schemaVersion: 1,
    sessionID: "e2e-session",
    seq: 3,
    timestamp: new Date().toISOString(),
    payload: {
      type: "snapshot",
      payload: {
        projects: [{ id: "p1", name: "General" }],
        threads: [{ id: "t1", projectID: "p1", title: "Dedupe thread", isPinned: false }],
        selectedProjectID: "p1",
        selectedThreadID: "t1",
        messages: [
          { id: "m1", threadID: "t1", role: "assistant", text: "First", createdAt: "2026-02-28T15:00:00.000Z" },
          { id: "m2", threadID: "t1", role: "assistant", text: "Second", createdAt: "2026-02-28T15:00:01.000Z" }
        ],
        pendingApprovals: []
      }
    }
  });

  const transcript = page.getByLabel("Transcript");
  await expect(transcript.getByText("First")).toBeVisible();
  await expect(transcript.getByText("Second")).toBeVisible();
  await expect(transcript.getByText("Second (duplicate)")).toHaveCount(0);
});

test("mobile-command-ack-rejection-surfaces-status-immediately", async ({ page }) => {
  await seedCustom(page, snapshotPayload);
  await page.getByRole("button", { name: "Open chat Daily sync" }).click();
  const transcript = page.getByLabel("Transcript");

  await injectEnvelope(page, {
    schemaVersion: 1,
    sessionID: "e2e-session",
    seq: 10,
    timestamp: new Date().toISOString(),
    payload: {
      type: "command_ack",
      payload: {
        commandSeq: 4,
        commandID: "cmd-4",
        commandName: "thread.send_message",
        status: "rejected",
        reason: "desktop_busy"
      }
    }
  });

  await expect(transcript.getByText("Desktop is busy and could not apply this command yet.")).toBeVisible({ timeout: 350 });

  await page.getByRole("button", { name: "Open account and connection controls" }).click();
  await expect(page.locator("#statusText")).toBeVisible();
  await expect(page.locator("#statusText")).toContainText(/desktop is busy/i, { timeout: 350 });
});

test("mobile-command-ack-rejection-without-threadid-stays-on-origin-thread", async ({ page }) => {
  await seedCustom(page, {
    projects: [{ id: "p1", name: "General" }],
    threads: [
      { id: "t1", projectID: "p1", title: "Origin thread", isPinned: false },
      { id: "t2", projectID: "p1", title: "Other thread", isPinned: false }
    ],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [],
    pendingApprovals: []
  });

  await page.evaluate(() => {
    window.location.hash = "#view=thread&tid=t1&pid=all";
  });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().selectedThreadID)).toBe("t1");

  await page.locator("#composerInput").fill("queued command from origin thread");
  await page.evaluate(() => {
    const form = document.querySelector<HTMLFormElement>("#composerForm");
    form?.requestSubmit();
  });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().queuedCommandsCount)).toBe(1);

  await page.evaluate(() => {
    window.location.hash = "#view=thread&tid=t2&pid=all";
  });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().selectedThreadID)).toBe("t2");

  await injectEnvelope(page, {
    schemaVersion: 1,
    sessionID: "e2e-session",
    seq: 10,
    timestamp: new Date().toISOString(),
    payload: {
      type: "command_ack",
      payload: {
        commandSeq: 1,
        commandID: "cmd-1",
        commandName: "thread.send_message",
        status: "rejected",
        reason: "unknown_thread"
      }
    }
  });

  const rejectionText = "Desktop could not resolve the target thread for this command.";
  await expect(page.getByLabel("Transcript").getByText(rejectionText)).toHaveCount(0);

  await page.evaluate(() => {
    window.location.hash = "#view=thread&tid=t1&pid=all";
  });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().selectedThreadID)).toBe("t1");
  await expect(page.getByLabel("Transcript").getByText(rejectionText)).toBeVisible({ timeout: 350 });
});

test("mobile-reasoning-rail", async ({ page }) => {
  await seedCustom(page, createSystemHeavyPayload("started"));
  await page.getByRole("button", { name: "Open chat Simple greeting" }).click();
  await expect(page.locator("#reasoningRail")).toBeVisible();
  await expect(page.locator("#reasoningRail")).toContainText("Reasoning in progress");

  await page.evaluate((payload) => {
    (window as any).__codexRemotePWAHarness.seed(payload, { authenticated: true });
  }, createSystemHeavyPayload("completed"));
  await expect(page.locator("#reasoningRail")).toContainText("Reasoning complete");
});

test("mobile-account-sheet-focus-trap", async ({ page }) => {
  await seedDemo(page);

  await page.getByRole("button", { name: "Open account and connection controls" }).click();
  await expect(page.locator("#accountSheet")).toBeVisible();

  const activeInSheet = await page.evaluate(() => {
    const sheet = document.querySelector("#accountSheet");
    return Boolean(sheet && sheet.contains(document.activeElement));
  });
  expect(activeInSheet).toBe(true);

  await page.keyboard.press("Escape");
  await expect(page.locator("#accountSheet")).toBeHidden();
});

test("mobile-approvals-tray", async ({ page }) => {
  await seedDemo(page);

  await page.getByRole("button", { name: "Open chat Daily sync" }).click();
  const toggle = page.getByRole("button", { name: "Show" });
  await toggle.click();

  await expect(page.locator("#toggleApprovalsButton")).toHaveAttribute("aria-expanded", "true");
  await expect(page.locator("#approvalTray")).toBeVisible();
  await expect(page.getByText("Allow command execution?")).toBeVisible();
});

test("mobile-approvals-long-unbroken-content-no-overflow", async ({ page }) => {
  await seedCustom(page, {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t1", projectID: "p1", title: "Approval stress thread", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [
      {
        id: "m1",
        threadID: "t1",
        role: "assistant",
        text: "Approval queue check",
        createdAt: "2026-02-28T15:00:00.000Z"
      }
    ],
    pendingApprovals: [
      {
        requestID: `req_${"R".repeat(140)}`,
        threadID: "t1",
        summary: `summary_${"S".repeat(900)}`
      }
    ]
  });

  await page.getByRole("button", { name: "Open chat Approval stress thread" }).click();
  await page.locator("#toggleApprovalsButton").click();
  await expect(page.locator("#approvalTray")).toBeVisible();
  await expectNoPageHorizontalOverflow(page);
});

test("mobile-long-message-collapse", async ({ page }) => {
  await seedDemo(page);

  await page.getByRole("button", { name: "Open chat Long output diagnostics" }).click();
  const collapsedBody = page.locator(".message-body.collapsed").first();
  await expect(collapsedBody).toBeVisible();

  await page.getByRole("button", { name: "Show more" }).first().click();
  await expect(page.getByRole("button", { name: "Show less" }).first()).toBeVisible();
});

test("mobile-theme-color-meta", async ({ page }) => {
  await page.goto("/?e2e=1#view=home");
  await page.emulateMedia({ colorScheme: "light" });
  await expect
    .poll(async () => page.locator('meta[name="theme-color"]').getAttribute("content"))
    .toBe("#ffffff");

  await page.emulateMedia({ colorScheme: "dark" });
  await expect
    .poll(async () => page.locator('meta[name="theme-color"]').getAttribute("content"))
    .toBe("#000000");
});

test("mobile-scanner-sheet-open-close", async ({ page }) => {
  await page.goto("/?e2e=1");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);
  await page.getByRole("button", { name: "Scan QR" }).first().click();
  await expect(page.locator("#qrScannerSheet")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator("#qrScannerSheet")).toBeHidden();
});

test("mobile-import-join-link-enables-pair", async ({ page }) => {
  await page.goto("/?e2e=1");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);

  await expect(page.locator("#preconnectPairButton")).toBeDisabled();
  await page.evaluate(() => {
    (window as any).__codexRemotePWAHarness.importJoinLink("https://remote.bikz.cc/#sid=test-session&jt=test-join&relay=https://remote.bikz.cc");
  });

  await expect
    .poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().joinToken))
    .toBe("test-join");
  await expect(page.locator("#preconnectPairButton")).toBeEnabled();
});

test("mobile-standalone-mode-hides-install-and-handoff-cards", async ({ page }) => {
  await page.goto("/?e2e=1");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);

  await page.evaluate(() => {
    (window as any).__codexRemotePWAHarness.importJoinLink("https://remote.bikz.cc/#sid=test-session&jt=test-join&relay=https://remote.bikz.cc");
  });
  await expect(page.getByRole("heading", { name: "Install to Home Screen" })).toBeVisible();
  await expect(page.locator("#copyPairLinkButton")).toBeVisible();

  await page.evaluate(() => {
    (window as any).__codexRemotePWAHarness.setStandaloneMode(true);
  });
  await expect(page.getByRole("heading", { name: "Install to Home Screen" })).toBeHidden();
  await expect(page.locator("#copyPairLinkButton")).toBeHidden();
  await expect(page.locator("#preconnectPairButton")).toBeVisible();
});

test("mobile-smart-scroll-jump-to-latest", async ({ page }) => {
  await seedCustom(page, createLongThreadPayload(140));

  await page.getByRole("button", { name: "Open chat Scroll anchor thread" }).click();
  await expect(page.locator("#messageList")).toBeVisible();

  await page.evaluate(() => {
    const list = document.querySelector<HTMLElement>("#messageList");
    if (!list) return;
    list.scrollTop = 0;
    (window as any).__codexRemotePWAHarness.setChatDetached(true);
  });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().isChatAtBottom)).toBe(false);

  await page.evaluate((payload) => {
    (window as any).__codexRemotePWAHarness.seed(payload, { authenticated: true });
  }, createLongThreadPayload(141));

  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().showJumpToLatest)).toBe(true);
  await expect(page.locator("#jumpToLatestButton")).toBeVisible();

  await page.locator("#jumpToLatestButton").click();
  await expect(page.locator("#jumpToLatestButton")).toBeHidden();

  const distance = await page.evaluate(() => {
    const list = document.querySelector<HTMLElement>("#messageList");
    if (!list) return 999;
    return list.scrollHeight - list.scrollTop - list.clientHeight;
  });
  expect(distance).toBeLessThan(12);
});

test("mobile-composer-autoresize-and-send", async ({ page }) => {
  await seedDemo(page);
  await page.evaluate(() => {
    (window as any).__codexRemotePWAHarness.openThread("t1");
  });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().selectedThreadID)).toBe("t1");
  await expect(page).toHaveURL(/view=thread/);

  const composerInput = page.locator("#composerInput");
  const initialHeight = await composerInput.evaluate((element) => element.getBoundingClientRect().height);

  const longText = Array.from({ length: 20 }, (_, index) => `line ${index + 1}`).join("\\n");
  await composerInput.fill(longText);

  const grownHeight = await composerInput.evaluate((element) => element.getBoundingClientRect().height);
  expect(grownHeight).toBeGreaterThan(initialHeight);
  expect(grownHeight).toBeLessThanOrEqual(205);

  await composerInput.fill("shortcut send");
  await expect(page.getByRole("button", { name: "Send message" })).toBeEnabled();
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().queuedCommandsCount)).toBe(0);

  await page.evaluate(() => {
    const form = document.querySelector<HTMLFormElement>("#composerForm");
    form?.requestSubmit();
  });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().queuedCommandsCount)).toBeGreaterThan(0);
});
