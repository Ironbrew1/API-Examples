"use strict";

const vscode = require("vscode");
const { posix } = require("node:path");
const { obfuscate, DEFAULT_OPTIONS } = require("./client");
const SECRET = "ironbrew1.apiKey";
let running = false;

async function setApiKey(context) {
  const value = await vscode.window.showInputBox({
    title: "Ironbrew1 API Key", prompt: "Enter your Ironbrew1 API key.",
    password: true, ignoreFocusOut: true,
    validateInput: (text) => text.trim() ? undefined : "Enter an API key.",
  });
  if (!value?.trim()) return undefined;
  await context.secrets.store(SECRET, value.trim());
  return value.trim();
}

async function options() {
  const config = vscode.workspace.getConfiguration("ironbrew1", vscode.window.activeTextEditor?.document.uri);
  const entries = [
    { label: "Platform", key: "platform", values: ["roblox", "luau", "universal"] },
    { label: "Aggressive optimizations", key: "aggressiveOptimizations", values: ["0", "1", "2"] },
    { label: "Intense VM scrambling", key: "intenseVmScrambling", values: [false, true] },
    { label: "VM compression", key: "enableVmCompression", values: [false, true] },
  ];
  const selected = await vscode.window.showQuickPick(entries.map((item) => ({
    ...item, description: String(config.get(item.key, DEFAULT_OPTIONS[item.key])),
  })), { title: "Ironbrew1 Options", placeHolder: "Choose an option to change" });
  if (!selected) return;
  const value = await vscode.window.showQuickPick(selected.values.map((value) => ({
    label: String(value), value,
    description: value === config.get(selected.key, DEFAULT_OPTIONS[selected.key]) ? "Current" : "",
  })), { title: selected.label });
  if (!value) return;
  await config.update(selected.key, value.value, vscode.ConfigurationTarget.Global);
  if (config.get(selected.key) !== value.value) {
    await vscode.window.showInformationMessage("A workspace setting overrides this option. Change it in Settings.", "Open Settings")
      .then((choice) => choice && vscode.commands.executeCommand("workbench.action.openSettings", `ironbrew1.${selected.key}`));
  }
}

function sameFile(a, b) {
  const normalize = (uri) => {
    const value = uri.toString();
    return process.platform === "win32" ? value.toLowerCase() : value;
  };
  return normalize(a) === normalize(b);
}

async function obfuscateEditor(context) {
  if (!vscode.workspace.isTrusted) {
    await vscode.window.showWarningMessage("Trust this workspace before using Ironbrew1.");
    return;
  }
  if (running) {
    await vscode.window.showInformationMessage("An Ironbrew1 obfuscation is already running.");
    return;
  }
  const editor = vscode.window.activeTextEditor;
  if (!editor || !(/\.(lua|luau)$/i.test(editor.document.uri.path) || ["lua", "luau"].includes(editor.document.languageId))) {
    await vscode.window.showInformationMessage("Open a Lua or Luau script first.");
    return;
  }
  const source = editor.document.getText();
  if (!source.trim()) {
    await vscode.window.showInformationMessage("The script is empty.");
    return;
  }
  running = true;
  try {
    const apiKey = await context.secrets.get(SECRET) || await setApiKey(context);
    if (!apiKey) return;
    const input = editor.document.uri;
    const name = posix.basename(input.path).replace(/\.(lua|luau)$/i, "") + ".obfuscated" + (/\.luau$/i.test(input.path) ? ".luau" : ".lua");
    const folder = editor.document.isUntitled ? vscode.workspace.workspaceFolders?.[0]?.uri : vscode.Uri.joinPath(input, "..");
    const target = await vscode.window.showSaveDialog({
      title: "Save Obfuscated Script", saveLabel: "Obfuscate and Save",
      defaultUri: folder ? vscode.Uri.joinPath(folder, name) : undefined,
      filters: { "Lua / Luau": ["lua", "luau"] },
    });
    if (!target) return;
    if (sameFile(input, target)) {
      await vscode.window.showErrorMessage("Choose a different output file to keep your original script.");
      return;
    }
    const config = vscode.workspace.getConfiguration("ironbrew1", input);
    const selected = Object.fromEntries(Object.entries(DEFAULT_OPTIONS).map(([key, value]) => [key, config.get(key, value)]));
    const result = await vscode.window.withProgress({
      location: vscode.ProgressLocation.Notification, title: "Ironbrew1", cancellable: true,
    }, async (progress, token) => {
      const controller = new AbortController();
      const subscription = token.onCancellationRequested(() => controller.abort());
      if (token.isCancellationRequested) controller.abort();
      try {
        const output = await obfuscate(source, apiKey, selected, {
          signal: controller.signal, onProgress: (message) => progress.report({ message }),
        });
        controller.signal.throwIfAborted();
        return output;
      } catch (error) {
        if (token.isCancellationRequested) return undefined;
        throw error;
      } finally { subscription.dispose(); }
    });
    if (result === undefined) return;
    await vscode.workspace.fs.writeFile(target, Buffer.from(result, "utf8"));
    await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(target), { preview: false });
    await vscode.window.showInformationMessage("Ironbrew1: obfuscated script saved.");
  } finally { running = false; }
}

function activate(context) {
  const commands = {
    "ironbrew1.obfuscate": () => obfuscateEditor(context),
    "ironbrew1.setApiKey": async () => {
      if (await setApiKey(context)) await vscode.window.showInformationMessage("Ironbrew1 API key saved.");
    },
    "ironbrew1.clearApiKey": async () => {
      await context.secrets.delete(SECRET);
      await vscode.window.showInformationMessage("Ironbrew1 API key forgotten.");
    },
    "ironbrew1.options": options,
  };
  for (const [name, action] of Object.entries(commands)) {
    context.subscriptions.push(vscode.commands.registerCommand(name, async () => {
      try { await action(); }
      catch (error) { await vscode.window.showErrorMessage(`Ironbrew1: ${error.message || "Operation failed."}`); }
    }));
  }
}

module.exports = { activate };
