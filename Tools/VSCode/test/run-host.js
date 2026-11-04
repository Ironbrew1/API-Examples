"use strict";
const path = require("node:path");
const { runTests } = require("@vscode/test-electron");

runTests({
  extensionDevelopmentPath: path.resolve(__dirname, ".."),
  extensionTestsPath: path.resolve(__dirname, "host.js"),
  launchArgs: ["--no-sandbox", "--disable-gpu", "--skip-welcome", "--skip-release-notes", "--disable-workspace-trust"],
}).catch((error) => { console.error(error); process.exitCode = 1; });
