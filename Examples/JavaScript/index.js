// Requires Node.js 18+ (built-in fetch). Also runs on Bun.
const fs = require("fs");

const BASE_URL = "https://ironbrew1.com";
const API_KEY = "IB1-APIKEYHERE";

const INPUT_PATH = "input.lua";
const OUTPUT_PATH = "output.lua";

const OPTIONS = {
  platform: "roblox",
  aggressiveOptimizations: "0",
  intenseVmScrambling: "false",
  enableVmCompression: "false",
};

const RETRY_DELAY = 5;
const MAX_WAIT = 240;
const MAX_FAILS = 3;

const sleep = (seconds) => new Promise((resolve) => setTimeout(resolve, seconds * 1000));

async function main() {
  const queueResponse = await fetch(`${BASE_URL}/obfuscate?${new URLSearchParams(OPTIONS)}`, {
    method: "POST",
    headers: { Key: API_KEY, "Content-Type": "text/plain" },
    body: fs.readFileSync(INPUT_PATH),
  });
  if (!queueResponse.ok) throw new Error(`Unable to queue obfuscation: ${queueResponse.status}`);

  const queued = await queueResponse.json();
  console.log(`Obfuscation started with GUID: ${queued.uploadGuid}`);

  let elapsed = 0;
  let fails = 0;
  let wait = 0;

  while (true) {
    wait += RETRY_DELAY;
    await sleep(wait);
    elapsed += wait;

    const statusResponse = await fetch(BASE_URL + queued.statusUrl, { headers: { Key: API_KEY } });
    if (!statusResponse.ok) {
      fails++;
      console.log(`Status check failed with status: ${statusResponse.status} (${fails}/${MAX_FAILS})`);
      if (fails >= MAX_FAILS || elapsed >= MAX_WAIT) {
        throw new Error(`Obfuscation failed (fails: ${fails} | elapsed time: ${elapsed})`);
      }
      continue;
    }

    const status = await statusResponse.json();

    if (status.status === "completed") {
      console.log(`Obfuscation completed in ${elapsed} seconds`);
      const download = await fetch(BASE_URL + status.downloadUrl, { headers: { Key: API_KEY } });
      if (!download.ok) throw new Error(`Download failed with status: ${download.status}`);
      fs.writeFileSync(OUTPUT_PATH, Buffer.from(await download.arrayBuffer()));
      console.log(`Saved obfuscated script to ${OUTPUT_PATH}`);
      return;
    }

    if (status.status === "failed" || elapsed >= MAX_WAIT) {
      throw new Error(`Obfuscation failed (status: ${status.status} | elapsed time: ${elapsed})`);
    }

    console.log(`Obfuscation is still in progress. Elapsed time: ${elapsed} seconds. Checking again in ${RETRY_DELAY + wait} seconds.`);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
