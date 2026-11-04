"use strict";

const { setTimeout: delay } = require("node:timers/promises");

const BASE_URL = "https://ironbrew1.com";
const DEFAULT_OPTIONS = Object.freeze({
  platform: "roblox",
  aggressiveOptimizations: "0",
  intenseVmScrambling: false,
  enableVmCompression: false,
});

class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

function validateOptions(options) {
  if (!["roblox", "luau", "universal"].includes(options.platform)
    || !["0", "1", "2"].includes(options.aggressiveOptimizations)
    || typeof options.intenseVmScrambling !== "boolean"
    || typeof options.enableVmCompression !== "boolean") {
    throw new ApiError("Invalid obfuscation options. Check the Ironbrew1 settings.");
  }
}

function apiUrl(path) {
  if (typeof path !== "string" || !path.trim()) {
    throw new ApiError("Ironbrew1 returned a missing job URL.");
  }
  const url = new URL(path, BASE_URL);
  if (url.origin !== BASE_URL || url.username || url.password || url.hash) {
    throw new ApiError("Ironbrew1 returned an unexpected job URL.");
  }
  return url;
}

async function obfuscate(source, apiKey, options = DEFAULT_OPTIONS, {
  signal, onProgress = () => {}, fetchImpl = fetch, sleep = delay,
  now = Date.now, maxWaitMs = 240_000, retryDelayMs = 5_000,
} = {}) {
  validateOptions(options);
  if (typeof apiKey !== "string" || !apiKey.trim()) throw new ApiError("Set your Ironbrew1 API key first.");
  if (typeof source !== "string" || !source.trim()) throw new ApiError("The script is empty.");
  const started = now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(new Error("Obfuscation timed out after 240 seconds.")), maxWaitMs);
  const combined = signal ? AbortSignal.any([signal, controller.signal]) : controller.signal;

  async function request(path, init = {}) {
    combined.throwIfAborted();
    try {
      const response = await fetchImpl(apiUrl(path), {
        ...init,
        headers: { Key: apiKey, "User-Agent": "Ironbrew1-VSCode/0.1.0", ...init.headers },
        redirect: "error",
        signal: AbortSignal.any([combined, AbortSignal.timeout(30_000)]),
      });
      if (!response.ok) {
        const hint = response.status === 401 || response.status === 403 ? " Check your API key and subscription." : "";
        throw new ApiError(`Ironbrew1 returned HTTP ${response.status}.${hint}`, response.status);
      }
      return response;
    } catch (error) {
      combined.throwIfAborted();
      if (error instanceof ApiError) throw error;
      // Do not expose request objects, URLs, credentials, or server response bodies.
      throw new ApiError("Could not reach Ironbrew1. Check your connection and try again.");
    }
  }

  async function json(response) {
    try {
      const value = await response.json();
      if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Not an object");
      return value;
    }
    catch { throw new ApiError("Ironbrew1 returned an invalid job response."); }
  }

  try {
    onProgress("Uploading script…");
    const queued = await json(await request(`/obfuscate?${new URLSearchParams(options)}`, {
      method: "POST", headers: { "Content-Type": "text/plain" }, body: source,
    }));
    const statusUrl = apiUrl(queued.statusUrl).href;
    let wait = 0;
    let failures = 0;
    while (true) {
      wait += retryDelayMs;
      const remaining = maxWaitMs - (now() - started);
      if (remaining <= 0) throw new ApiError("Obfuscation timed out. Try again later.");
      onProgress("Waiting for obfuscation…");
      await sleep(Math.min(wait, remaining), undefined, { signal: combined });
      combined.throwIfAborted();
      if (now() - started >= maxWaitMs) throw new ApiError("Obfuscation timed out. Try again later.");
      let status;
      try { status = await json(await request(statusUrl)); }
      catch (error) {
        combined.throwIfAborted();
        if (!(error instanceof ApiError) || [401, 403].includes(error.status) || ++failures >= 3) throw error;
        continue;
      }
      if (status.status === "failed") throw new ApiError("Ironbrew1 could not obfuscate this script. Check that it runs on the selected platform.");
      if (status.status === "completed") {
        onProgress("Downloading obfuscated script…");
        const result = await (await request(apiUrl(status.downloadUrl).href)).text();
        combined.throwIfAborted();
        if (!result.trim()) throw new ApiError("Ironbrew1 returned an empty script.");
        return result;
      }
      if (!["queued", "pending", "processing"].includes(status.status)) throw new ApiError("Ironbrew1 returned an unknown job status.");
    }
  } catch (error) {
    if (controller.signal.aborted && !signal?.aborted) throw new ApiError("Obfuscation timed out. Try again later.");
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = { obfuscate, apiUrl, ApiError, DEFAULT_OPTIONS };
