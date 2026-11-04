"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { obfuscate, apiUrl, DEFAULT_OPTIONS } = require("../src/client");

function fixture(responses, overrides = {}) {
  const calls = [];
  const waits = [];
  let clock = 0;
  return {
    calls, waits,
    runtime: {
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), ...init });
        const next = responses.shift();
        if (next instanceof Error) throw next;
        assert.ok(next, "Unexpected extra request");
        return typeof next === "string" ? new Response(next) : Response.json(next);
      },
      sleep: async (ms) => { waits.push(ms); clock += ms; },
      now: () => clock,
      ...overrides,
    },
  };
}
const queued = { uploadGuid: "test-guid", statusUrl: "/status/test-guid" };
const complete = { status: "completed", downloadUrl: "/download/test-guid" };

test("queues plain text, polls with backoff, downloads, and sends all options", async () => {
  const f = fixture([queued, { status: "processing" }, complete, "print('obfuscated')"]);
  const selected = { platform: "luau", aggressiveOptimizations: "2", intenseVmScrambling: true, enableVmCompression: true };
  const result = await obfuscate("print('original')", "test-key", selected, f.runtime);
  assert.equal(result, "print('obfuscated')");
  assert.deepEqual(f.waits, [5000, 10000]);
  assert.equal(f.calls[0].method, "POST");
  assert.equal(f.calls[0].body, "print('original')");
  assert.equal(f.calls[0].headers["Content-Type"], "text/plain");
  for (const [key, value] of Object.entries(selected)) assert.equal(new URL(f.calls[0].url).searchParams.get(key), String(value));
  for (const call of f.calls) {
    assert.equal(call.headers.Key, "test-key");
    assert.equal(call.redirect, "error");
    assert.ok(call.signal);
  }
});

test("202 Accepted is a successful queue response", async () => {
  const f = fixture([complete, "result"]);
  const later = f.runtime.fetchImpl;
  f.runtime.fetchImpl = (url, init) => String(url).includes("/obfuscate?")
    ? Promise.resolve(Response.json(queued, { status: 202 })) : later(url, init);
  assert.equal(await obfuscate("return 1", "key", DEFAULT_OPTIONS, f.runtime), "result");
});

test("rejects foreign, insecure, and credential-bearing job URLs", () => {
  for (const value of ["https://evil.invalid/job", "//evil.invalid/job", "http://ironbrew1.com/job", "https://name:password@ironbrew1.com/job", "", undefined]) {
    assert.throws(() => apiUrl(value));
  }
  assert.equal(apiUrl("/status/1").origin, "https://ironbrew1.com");
});

test("never sends key to a server-provided external download URL", async () => {
  const f = fixture([queued, { ...complete, downloadUrl: "https://evil.invalid/output" }]);
  await assert.rejects(obfuscate("return 1", "key", DEFAULT_OPTIONS, f.runtime), /unexpected job URL/);
  assert.equal(f.calls.length, 2);
});

test("authentication errors are not retried or echoed with secrets", async () => {
  const f = fixture([queued]);
  f.runtime.fetchImpl = async () => new Response("secret-key script-content", { status: 401 });
  await assert.rejects(obfuscate("script-content", "secret-key", DEFAULT_OPTIONS, f.runtime), (e) => {
    assert.equal(e.status, 401);
    assert.doesNotMatch(e.message, /secret-key|script-content/);
    return true;
  });
  assert.deepEqual(f.waits, []);
});

test("retries transient status errors but stops after three", async () => {
  const f = fixture([queued, new Error("private network details"), new Error("network"), new Error("network")]);
  await assert.rejects(obfuscate("return 1", "key", DEFAULT_OPTIONS, f.runtime), /Could not reach/);
  assert.equal(f.calls.length, 4);
});

test("can recover from a failed status request", async () => {
  const f = fixture([queued, new Error("network"), complete, "result"]);
  assert.equal(await obfuscate("return 1", "key", DEFAULT_OPTIONS, f.runtime), "result");
});

test("handles failed jobs and unknown states", async () => {
  for (const status of ["failed", "unexpected"]) {
    const f = fixture([queued, { status }]);
    await assert.rejects(obfuscate("return 1", "key", DEFAULT_OPTIONS, f.runtime), /could not obfuscate|unknown job status/);
    assert.equal(f.calls.length, 2);
  }
});

test("malformed responses and empty output fail without returning source", async () => {
  for (const responses of [["not-json"], ["null"], ["[]"], [queued, complete, "  "]]) {
    const f = fixture(responses);
    await assert.rejects(obfuscate("return 1", "key", DEFAULT_OPTIONS, f.runtime), /invalid job response|empty script/);
  }
});

test("cancellation prevents all network requests when already cancelled", async () => {
  const c = new AbortController(); c.abort();
  const f = fixture([], { signal: c.signal });
  await assert.rejects(obfuscate("return 1", "key", DEFAULT_OPTIONS, f.runtime));
  assert.equal(f.calls.length, 0);
});

test("cancellation during backoff stops before the next request", async () => {
  const c = new AbortController();
  const f = fixture([queued], { signal: c.signal, sleep: async () => c.abort() });
  await assert.rejects(obfuscate("return 1", "key", DEFAULT_OPTIONS, f.runtime));
  assert.equal(f.calls.length, 1);
});

test("wall clock deadline stops polling before another request", async () => {
  const f = fixture([queued], { maxWaitMs: 1000 });
  await assert.rejects(obfuscate("return 1", "key", DEFAULT_OPTIONS, f.runtime), /timed out/);
  assert.equal(f.calls.length, 1);
});

test("validates configuration, source, and key before upload", async () => {
  const f = fixture([]);
  await assert.rejects(obfuscate("source", "key", { ...DEFAULT_OPTIONS, platform: "invalid" }, f.runtime), /Invalid/);
  await assert.rejects(obfuscate("source", "", DEFAULT_OPTIONS, f.runtime), /API key/);
  await assert.rejects(obfuscate(" ", "key", DEFAULT_OPTIONS, f.runtime), /empty/);
  assert.equal(f.calls.length, 0);
});
