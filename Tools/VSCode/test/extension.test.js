"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const { DEFAULT_OPTIONS } = require("../src/client");

function harness({ cancelled = false, sameTarget = false, trusted = true } = {}) {
  const commands = new Map(); const secrets = new Map();
  const writes = []; const uploads = []; const errors = []; const opened = [];
  const uri = (value) => ({ path: new URL(value).pathname, toString: () => value });
  const input = uri("file:///workspace/source.lua");
  const target = sameTarget ? input : uri("file:///workspace/source.obfuscated.lua");
  const vscode = {
    commands: { registerCommand: (name, action) => { commands.set(name, action); return { dispose() {} }; } },
    Uri: { joinPath: (base, ...parts) => uri("file://" + path.posix.join(base.path, ...parts)) },
    ProgressLocation: { Notification: 15 },
    workspace: {
      isTrusted: trusted,
      getConfiguration: () => ({ get: (key, fallback) => fallback }),
      fs: { writeFile: async (target, body) => writes.push({ target, body }) },
      openTextDocument: async (target) => target,
    },
    window: {
      activeTextEditor: { document: { uri: input, languageId: "lua", getText: () => "print('unsaved buffer')", isUntitled: false } },
      showInputBox: async () => " test-secret ",
      showSaveDialog: async () => target,
      showInformationMessage: async () => {},
      showWarningMessage: async () => {},
      showErrorMessage: async (message) => errors.push(message),
      showTextDocument: async (document) => opened.push(document),
      withProgress: async (_, run) => run({ report() {} }, {
        isCancellationRequested: cancelled,
        onCancellationRequested: () => ({ dispose() {} }),
      }),
    },
  };
  const context = { subscriptions: [], secrets: {
    get: async (key) => secrets.get(key),
    store: async (key, value) => secrets.set(key, value),
    delete: async (key) => secrets.delete(key),
  } };
  const client = { DEFAULT_OPTIONS, obfuscate: async (...args) => {
    uploads.push(args);
    args[3].signal.throwIfAborted();
    return "print('obfuscated')";
  } };
  const sandbox = { module: { exports: {} }, require: (name) => name === "vscode" ? vscode : name === "./client" ? client : require(name), Buffer, AbortController, process };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../src/extension.js"), "utf8"), sandbox);
  sandbox.module.exports.activate(context);
  return { commands, secrets, writes, uploads, errors, opened, vscode, input };
}

test("stores and forgets API key through SecretStorage", async () => {
  const h = harness();
  await h.commands.get("ironbrew1.setApiKey")();
  assert.equal(h.secrets.get("ironbrew1.apiKey"), "test-secret");
  await h.commands.get("ironbrew1.clearApiKey")();
  assert.equal(h.secrets.size, 0);
});

test("uses unsaved editor contents and writes only the separate output", async () => {
  const h = harness();
  await h.commands.get("ironbrew1.obfuscate")();
  assert.equal(h.errors.length, 0);
  assert.equal(h.uploads[0][0], "print('unsaved buffer')");
  assert.equal(h.writes.length, 1);
  assert.notEqual(h.writes[0].target.toString(), h.input.toString());
  assert.equal(h.writes[0].body.toString(), "print('obfuscated')");
  assert.equal(h.opened.length, 1);
});

test("never uploads or overwrites when the output is the input file", async () => {
  const h = harness({ sameTarget: true });
  await h.commands.get("ironbrew1.obfuscate")();
  assert.equal(h.uploads.length, 0);
  assert.equal(h.writes.length, 0);
  assert.match(h.errors[0], /different output file/);
});

test("cancellation leaves files untouched", async () => {
  const h = harness({ cancelled: true });
  await h.commands.get("ironbrew1.obfuscate")();
  assert.equal(h.errors.length, 0);
  assert.equal(h.writes.length, 0);
});

test("cancelling output dialog does not upload", async () => {
  const h = harness(); h.vscode.window.showSaveDialog = async () => undefined;
  await h.commands.get("ironbrew1.obfuscate")();
  assert.equal(h.uploads.length, 0);
  assert.equal(h.writes.length, 0);
});

test("untrusted workspaces cannot upload", async () => {
  const h = harness({ trusted: false });
  await h.commands.get("ironbrew1.obfuscate")();
  assert.equal(h.uploads.length, 0);
});
