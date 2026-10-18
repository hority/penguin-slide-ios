// Renders the sound lab's effects and music to WAV files for the app.
//   NODE_PATH=$(npm root -g) node ci/render-sounds.cjs HelloFlight/Sounds
// The lab page (tools/sound-lab/index.html, sounds.js) is the source: each sound is rendered
// by the same OfflineAudioContext code the lab plays, in headless Chromium (Playwright).
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

(async () => {
  const outDir = process.argv[2];
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto("file://" + path.resolve(__dirname, "../tools/sound-lab/index.html"));
  const files = await page.evaluate(async () => {
    const result = {};
    for (const name of window.SoundLab.names) {
      const bytes = new Uint8Array(window.SoundLab.wav(await window.SoundLab.render(name)));
      let binary = "";
      for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      result[name] = btoa(binary);
    }
    return result;
  });
  for (const [name, data] of Object.entries(files)) {
    const buffer = Buffer.from(data, "base64");
    fs.writeFileSync(path.join(outDir, name + ".wav"), buffer);
    console.log(`${name.padEnd(9)} ${(buffer.length / 1024).toFixed(0).padStart(5)} KB`);
  }
  await browser.close();
})();
