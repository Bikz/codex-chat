import { expect, test } from "@playwright/test";

const longMessage = Array.from({ length: 12 }, (_, index) => `line ${index + 1} with verbose mobile text`).join("\n");

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

async function seedDemo(page: Parameters<typeof test>[0]["page"]) {
  await page.goto("/?e2e=1#view=home&pid=all");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);
  await page.evaluate((payload) => {
    (window as any).__codexRemotePWAHarness.resetStorage();
    (window as any).__codexRemotePWAHarness.seed(payload, { authenticated: true });
  }, snapshotPayload);
}

async function seedCustom(page: Parameters<typeof test>[0]["page"], payload: unknown) {
  await page.goto("/?e2e=1#view=home&pid=all");
  await expect.poll(async () => page.evaluate(() => Boolean((window as any).__codexRemotePWAHarness))).toBe(true);
  await page.evaluate((nextPayload) => {
    (window as any).__codexRemotePWAHarness.resetStorage();
    (window as any).__codexRemotePWAHarness.seed(nextPayload, { authenticated: true });
  }, payload);
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

test("mobile-thread-navigation-back", async ({ page }) => {
  await seedDemo(page);

  await page.getByRole("button", { name: "Open chat Daily sync" }).click();
  await expect(page).toHaveURL(/view=thread/);
  await expect(page.locator("#chatView")).toBeVisible();

  await page.goBack();
  await expect(page).toHaveURL(/view=home/);
  await expect(page.locator("#homeView")).toBeVisible();
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
