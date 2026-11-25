// Run with Deno: deno run --allow-net=ironbrew1.com --allow-read=input.lua --allow-write=output.lua main.ts
const BASE_URL = "https://ironbrew1.com";
const API_KEY = "IB1-APIKEYHERE";

const INPUT_PATH = "input.lua";
const OUTPUT_PATH = "output.lua";

const OPTIONS: Record<string, string> = {
  platform: "roblox",
  aggressiveOptimizations: "0",
  intenseVmScrambling: "false",
  enableVmCompression: "false",
};

const RETRY_DELAY = 5;
const MAX_WAIT = 240;
const MAX_FAILS = 3;

interface Queued {
  uploadGuid: string;
  statusUrl: string;
}

interface Status {
  status: string;
  downloadUrl?: string;
}

const sleep = (seconds: number) => new Promise((resolve) => setTimeout(resolve, seconds * 1000));
const headers = { Key: API_KEY };

const queueResponse = await fetch(`${BASE_URL}/obfuscate?${new URLSearchParams(OPTIONS)}`, {
  method: "POST",
  headers: { ...headers, "Content-Type": "text/plain" },
  body: await Deno.readFile(INPUT_PATH),
});
if (!queueResponse.ok) {
  console.error(`Unable to queue obfuscation: ${queueResponse.status}`);
  Deno.exit(1);
}

const queued: Queued = await queueResponse.json();
console.log(`Obfuscation started with GUID: ${queued.uploadGuid}`);

let elapsed = 0;
let fails = 0;
let wait = 0;

while (true) {
  wait += RETRY_DELAY;
  await sleep(wait);
  elapsed += wait;

  const statusResponse = await fetch(BASE_URL + queued.statusUrl, { headers });
  if (!statusResponse.ok) {
    fails++;
    console.log(`Status check failed with status: ${statusResponse.status} (${fails}/${MAX_FAILS})`);
    if (fails >= MAX_FAILS || elapsed >= MAX_WAIT) {
      console.error(`Obfuscation failed (fails: ${fails} | elapsed time: ${elapsed})`);
      Deno.exit(1);
    }
    continue;
  }

  const status: Status = await statusResponse.json();

  if (status.status === "completed") {
    console.log(`Obfuscation completed in ${elapsed} seconds`);
    const download = await fetch(BASE_URL + status.downloadUrl, { headers });
    if (!download.ok) {
      console.error(`Download failed with status: ${download.status}`);
      Deno.exit(1);
    }
    await Deno.writeFile(OUTPUT_PATH, new Uint8Array(await download.arrayBuffer()));
    console.log(`Saved obfuscated script to ${OUTPUT_PATH}`);
    break;
  }

  if (status.status === "failed" || elapsed >= MAX_WAIT) {
    console.error(`Obfuscation failed (status: ${status.status} | elapsed time: ${elapsed})`);
    Deno.exit(1);
  }

  console.log(`Obfuscation is still in progress. Elapsed time: ${elapsed} seconds. Checking again in ${RETRY_DELAY + wait} seconds.`);
}
