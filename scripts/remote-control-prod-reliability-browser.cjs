const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("@playwright/test");

const joinURL = process.env.JOIN_URL;
const artifactDir = process.env.REMOTE_BROWSER_ARTIFACT_DIR;

if (!joinURL) {
  console.error(JSON.stringify({ kind: "fatal", error: "JOIN_URL is required" }));
  process.exit(1);
}

if (!artifactDir) {
  console.error(JSON.stringify({ kind: "fatal", error: "REMOTE_BROWSER_ARTIFACT_DIR is required" }));
  process.exit(1);
}

fs.mkdirSync(artifactDir, { recursive: true });

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 430, height: 932 },
    userAgent: "CodexChatReliabilityBrowser/1.0"
  });
  const page = await context.newPage();

  page.on("console", (msg) => {
    console.log(JSON.stringify({ kind: "page_console", type: msg.type(), text: msg.text().slice(0, 1000) }));
  });
  page.on("pageerror", (error) => {
    console.log(JSON.stringify({ kind: "page_error", text: String(error).slice(0, 1000) }));
  });
  page.on("websocket", (socket) => {
    console.log(JSON.stringify({ kind: "ws_open", url: socket.url() }));
    socket.on("framesent", (event) => {
      console.log(JSON.stringify({ kind: "ws_tx", payload: String(event.payload).slice(0, 800) }));
    });
    socket.on("framereceived", (event) => {
      console.log(JSON.stringify({ kind: "ws_rx", payload: String(event.payload).slice(0, 800) }));
    });
    socket.on("close", () => {
      console.log(JSON.stringify({ kind: "ws_close", url: socket.url() }));
    });
  });

  async function shot(name) {
    const file = path.join(artifactDir, `${name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    console.log(JSON.stringify({ kind: "screenshot", file }));
  }

  async function waitForBodyText(text, timeout = 30000) {
    await page.waitForFunction(
      (expected) => document.body && document.body.innerText.includes(expected),
      text,
      { timeout }
    );
  }

  async function openReliabilityThreadIfNeeded() {
    const composerVisible = await page.locator("#composerInput").isVisible().catch(() => false);
    if (composerVisible) return;
    const threadCard = page.getByText("Reliability Thread", { exact: false }).first();
    await threadCard.waitFor({ state: "visible", timeout: 30000 });
    await threadCard.click();
    await page.waitForSelector("#composerInput", { timeout: 30000 });
  }

  try {
    await page.goto(joinURL, { waitUntil: "networkidle", timeout: 60000 });
    await shot("remote-browser-01-loaded");

    await page.waitForSelector("#preconnectPairButton", { timeout: 30000 });
    const statusBeforePair = await page.locator("body").innerText();
    console.log(JSON.stringify({ kind: "status_before_pair", text: statusBeforePair.slice(0, 1000) }));

    await page.click("#preconnectPairButton");
    await page.waitForSelector("#composerInput, #chatList, #chatView", { timeout: 90000 });
    await page.waitForTimeout(2000);
    await openReliabilityThreadIfNeeded();
    await shot("remote-browser-02-paired");

    const firstText = "browser reliability msg 1";
    await page.fill("#composerInput", firstText);
    await page.click('button[aria-label="Send message"]');
    await waitForBodyText(`Harness received: ${firstText}`);
    await shot("remote-browser-03-first-roundtrip");

    await page.reload({ waitUntil: "networkidle", timeout: 60000 });
    await page.waitForSelector("#composerInput, #chatList, #chatView", { timeout: 90000 });
    await openReliabilityThreadIfNeeded();
    await waitForBodyText(`Harness received: ${firstText}`);
    await shot("remote-browser-04-reloaded");

    const secondText = "browser reliability msg 2 after reload";
    await page.fill("#composerInput", secondText);
    await page.click('button[aria-label="Send message"]');
    await waitForBodyText(`Harness received: ${secondText}`);
    await shot("remote-browser-05-second-roundtrip");

    const finalBodyText = await page.locator("body").innerText();
    console.log(JSON.stringify({ kind: "browser_success", finalTextSample: finalBodyText.slice(0, 2000) }));
    await browser.close();
  } catch (error) {
    try {
      await shot("remote-browser-failure");
    } catch {}
    console.error(JSON.stringify({ kind: "browser_failure", error: error?.stack || String(error) }));
    await browser.close();
    process.exit(1);
  }
})();
