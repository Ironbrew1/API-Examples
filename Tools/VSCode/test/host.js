"use strict";
const assert = require("node:assert/strict");
const vscode = require("vscode");

exports.run = async () => {
  const extension = vscode.extensions.getExtension("CEOofKohler.ironbrew1");
  assert.ok(extension, "Extension must be recognized by VS Code");
  await extension.activate();
  assert.ok(extension.isActive);
  const commands = await vscode.commands.getCommands(true);
  for (const name of ["obfuscate", "setApiKey", "clearApiKey", "options"]) {
    assert.ok(commands.includes(`ironbrew1.${name}`), `Missing command: ${name}`);
  }
  const config = vscode.workspace.getConfiguration("ironbrew1");
  assert.equal(config.get("platform"), "roblox");
  assert.equal(config.get("enableVmCompression"), false);
  console.log("PASS: real VS Code extension host activation, four commands, default settings.");
};
