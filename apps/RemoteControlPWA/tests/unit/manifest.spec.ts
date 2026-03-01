import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

function readManifest() {
  const manifestPath = join(import.meta.dirname, "..", "..", "public", "manifest.webmanifest");
  const raw = readFileSync(manifestPath, "utf8");
  return JSON.parse(raw) as {
    display?: string;
    orientation?: string;
    icons?: Array<{ purpose?: string }>;
  };
}

describe("manifest", () => {
  it("uses standalone display mode with orientation unlocked", () => {
    const manifest = readManifest();
    expect(manifest.display).toBe("standalone");
    expect(manifest.orientation).toBe("any");
  });

  it("includes a maskable icon for Android install surfaces", () => {
    const manifest = readManifest();
    const hasMaskable = (manifest.icons || []).some((icon) => (icon.purpose || "").split(/\s+/).includes("maskable"));
    expect(hasMaskable).toBe(true);
  });
});
