import { expect, test } from "@playwright/test";

const longMessage = Array.from({ length: 12 }, (_, index) => `line ${index + 1} with verbose mobile text`).join("\n");
const longToken = "A".repeat(200);
const approvalResponseOptions = [
  { id: "accept", label: "Approve once" },
  { id: "acceptForSession", label: "Approve session" },
  { id: "decline", label: "Decline" }
];

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
  turnState: { threadID: "t1", isTurnInProgress: true, isAwaitingRuntimeRequest: false },
  pendingRuntimeRequests: [
    {
      requestID: "a1",
      kind: "approval",
      threadID: "t1",
      title: "Command approval",
      summary: "Allow command execution?",
      responseOptions: approvalResponseOptions,
      permissions: [],
      options: []
    },
    {
      requestID: "a2",
      kind: "approval",
      threadID: null,
      title: "Session approval",
      summary: "Allow session-level action?",
      responseOptions: approvalResponseOptions,
      permissions: [],
      options: []
    }
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
    pendingRuntimeRequests: []
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
    pendingRuntimeRequests: []
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
    pendingRuntimeRequests: []
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
        text: "Runtime request required: Allow command execution?",
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
    pendingRuntimeRequests: []
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

async function seedCustom(
  page: Parameters<typeof test>[0]["page"],
  payload: unknown,
  options: { canRespondToRuntimeRequests?: boolean } = {}
) {
  await page.goto("/?e2e=1#view=home&pid=all");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);
  await page.evaluate(({ nextPayload, nextOptions }) => {
    (window as any).__codexRemotePWAHarness.resetStorage();
    (window as any).__codexRemotePWAHarness.seed(nextPayload, {
      authenticated: true,
      canRespondToRuntimeRequests: nextOptions.canRespondToRuntimeRequests === true
    });
  }, { nextPayload: payload, nextOptions: options });
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
    pendingRuntimeRequests: []
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
    pendingRuntimeRequests: []
  }, { canRespondToRuntimeRequests: true });
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

  await expect(page.getByText("Runtime request required: Allow command execution?")).toBeVisible();
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
    pendingRuntimeRequests: []
  }, { canRespondToRuntimeRequests: true });
  await page.getByRole("button", { name: "Open chat Latency thread" }).click();

  const start = Date.now();
  await injectEnvelope(page, {
    schemaVersion: 2,
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

test("mobile-auth-ok-token-rotation-persists-latest-device-token", async ({ page }) => {
  await seedCustom(page, snapshotPayload);

  await page.evaluate(() => {
    (window as any).__codexRemotePWAHarness.setPairedCredentials({
      sessionID: "e2e-session",
      wsURL: "wss://remote.bikz.cc/ws",
      deviceSessionToken: "device-token-seed",
      deviceID: "device-1"
    });
  });

  await injectEnvelope(page, {
    type: "auth_ok",
    role: "mobile",
    sessionID: "e2e-session",
    deviceID: "device-1",
    nextDeviceSessionToken: "device-token-1",
    desktopConnected: false
  });

  await expect.poll(async () => {
    return page.evaluate(() => {
      const raw = window.localStorage.getItem("codexchat.remote.pairedDevice.v1");
      if (!raw) {
        return null;
      }
      try {
        return JSON.parse(raw).deviceSessionToken ?? null;
      } catch {
        return "invalid";
      }
    });
  }).toBe("device-token-1");

  await injectEnvelope(page, {
    type: "auth_ok",
    role: "mobile",
    sessionID: "e2e-session",
    deviceID: "device-1",
    nextDeviceSessionToken: "device-token-2",
    desktopConnected: false
  });

  await expect.poll(async () => {
    return page.evaluate(() => {
      const raw = window.localStorage.getItem("codexchat.remote.pairedDevice.v1");
      if (!raw) {
        return null;
      }
      try {
        return JSON.parse(raw).deviceSessionToken ?? null;
      } catch {
        return "invalid";
      }
    });
  }).toBe("device-token-2");
});

test("mobile-restores-persisted-pairing-after-reload-without-qr", async ({ page }) => {
  await page.goto("/?e2e=1#view=home&pid=all");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);

  await page.evaluate(() => {
    window.localStorage.setItem(
      "codexchat.remote.pairedDevice.v1",
      JSON.stringify({
        sessionID: "e2e-session",
        deviceID: "device-1",
        deviceName: "Test iPhone",
        relayBaseURL: "https://remote.bikz.cc",
        deviceSessionToken: "device-token-restored",
        wsURL: "wss://remote.bikz.cc/ws",
        storedAt: new Date().toISOString()
      })
    );
  });

  await page.reload();
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);

  await expect
    .poll(async () => {
      return page.evaluate(() => (window as any).__codexRemotePWAHarness.getState());
    })
    .toMatchObject({
      sessionID: "e2e-session",
      deviceSessionToken: "device-token-restored",
      wsURL: "wss://remote.bikz.cc/ws",
      joinToken: null
    });

  await page.evaluate((payload) => {
    (window as any).__codexRemotePWAHarness.seed(payload, { authenticated: false });
  }, snapshotPayload);
  const didQueue = await page.evaluate(() => (window as any).__codexRemotePWAHarness.sendComposerMessage("restored pairing send"));
  expect(didQueue).toBe(true);

  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().queuedCommandsCount)).toBe(
    1
  );
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
    pendingRuntimeRequests: []
  });
  await page.getByRole("button", { name: "Open chat Dedupe thread" }).click();

  await injectEnvelope(page, {
    schemaVersion: 2,
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
    schemaVersion: 2,
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
    schemaVersion: 2,
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
        pendingRuntimeRequests: []
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
    schemaVersion: 2,
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
    pendingRuntimeRequests: []
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
    schemaVersion: 2,
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

test("mobile-runtime-requests-tray", async ({ page }) => {
  await seedDemo(page);

  await page.getByRole("button", { name: "Open chat Daily sync" }).click();
  const toggle = page.getByRole("button", { name: "Show" });
  await toggle.click();

  await expect(page.locator("#toggleApprovalsButton")).toHaveAttribute("aria-expanded", "true");
  await expect(page.locator("#approvalTray")).toBeVisible();
  await expect(page.getByText("Allow command execution?")).toBeVisible();
});

test("mobile-runtime-request-permission-decline-queues-deny-payload", async ({ page }) => {
  await seedCustom(page, {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t1", projectID: "p1", title: "Permission thread", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [],
    pendingRuntimeRequests: [
      {
        requestID: "perm-1",
        kind: "permissionsApproval",
        threadID: "t1",
        title: "Permission request pending",
        summary: "Need project.write",
        responseOptions: [
          { id: "grant", label: "Grant" },
          { id: "decline", label: "Decline" }
        ],
        permissions: ["project.write"],
        options: [],
        scopeHint: "workspace"
      }
    ]
  }, { canRespondToRuntimeRequests: true });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().canRespondToRuntimeRequests)).toBe(true);

  await page.getByRole("button", { name: "Open chat Permission thread" }).click();
  await page.locator("#toggleApprovalsButton").click();
  await page.getByRole("button", { name: "Decline" }).click();

  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().queuedCommandsCount)).toBe(1);

  const command = await page.evaluate(() => {
    const state = (window as any).__codexRemotePWAHarness.getState();
    return state.queuedCommands[0];
  });

  expect(command.payload.payload.runtimeRequestKind).toBe("permissionsApproval");
  expect(command.payload.payload.runtimeRequestResponse).toEqual({
    optionID: "decline",
    approved: false,
    permissions: []
  });
});

test("mobile-runtime-request-user-input-submit-queues-text-and-choice", async ({ page }) => {
  await seedCustom(page, {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t1", projectID: "p1", title: "Question thread", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [],
    pendingRuntimeRequests: [
      {
        requestID: "input-1",
        kind: "userInput",
        threadID: "t1",
        title: "Input request pending",
        summary: "Choose one option and explain why.",
        responseOptions: [
          { id: "submit", label: "Submit" },
          { id: "dismiss", label: "Dismiss" }
        ],
        permissions: [],
        options: [
          { id: "choice-a", label: "Choice A", description: "First path" },
          { id: "choice-b", label: "Choice B", description: "Safer path" }
        ]
      }
    ]
  }, { canRespondToRuntimeRequests: true });
  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().canRespondToRuntimeRequests)).toBe(true);

  await page.getByRole("button", { name: "Open chat Question thread" }).click();
  await page.locator("#toggleApprovalsButton").click();
  await page.getByLabel("Choice for Input request pending").selectOption("choice-b");
  await page.getByLabel("Response for Input request pending").fill("Choice B keeps the rollout safer.");
  await page.getByRole("button", { name: "Submit" }).click();

  await expect.poll(async () => page.evaluate(() => (window as any).__codexRemotePWAHarness.getState().queuedCommandsCount)).toBe(1);

  const command = await page.evaluate(() => {
    const state = (window as any).__codexRemotePWAHarness.getState();
    return state.queuedCommands[0];
  });

  expect(command.payload.payload.runtimeRequestKind).toBe("userInput");
  expect(command.payload.payload.runtimeRequestResponse).toEqual({
    text: "Choice B keeps the rollout safer.",
    optionID: "choice-b"
  });
});

test("mobile-runtime-requests-long-unbroken-content-no-overflow", async ({ page }) => {
  await seedCustom(page, {
    projects: [{ id: "p1", name: "General" }],
    threads: [{ id: "t1", projectID: "p1", title: "Runtime request stress thread", isPinned: false }],
    selectedProjectID: "p1",
    selectedThreadID: "t1",
    messages: [
      {
        id: "m1",
        threadID: "t1",
        role: "assistant",
        text: "Runtime request queue check",
        createdAt: "2026-02-28T15:00:00.000Z"
      }
    ],
    pendingRuntimeRequests: [
      {
        requestID: `req_${"R".repeat(140)}`,
        kind: "approval",
        threadID: "t1",
        title: "Runtime request approval",
        summary: `summary_${"S".repeat(900)}`,
        responseOptions: approvalResponseOptions,
        permissions: [],
        options: []
      }
    ]
  });

  await page.getByRole("button", { name: "Open chat Runtime request stress thread" }).click();
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
