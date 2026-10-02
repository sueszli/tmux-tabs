import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const source = readFileSync(process.argv[2], "utf8");
const { default: extension } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);
const handlers = new Map();
const calls = [];
const exec = promisify(execFile);
const pi = {
    on(event, handler) { handlers.set(event, handler); },
    async exec(command, args, options) {
        calls.push({ command, args, options });
        return exec(command, args, { timeout: options.timeout });
    },
};

extension(pi);
assert.deepEqual([...handlers.keys()], ["session_start", "agent_start", "agent_settled", "session_shutdown"]);
assert.equal(handlers.has("agent_end"), false);
for (const [event, expected] of [
    ["session_start", "SessionStart"],
    ["agent_start", "UserPromptSubmit"],
    ["agent_settled", "Stop"],
    ["session_shutdown", "SessionEnd"],
]) {
    await handlers.get(event)({}, { mode: "tui" });
    assert.equal(calls.at(-1).args.at(-1), expected);
    assert.equal(calls.at(-1).options.timeout, 3000);
}
assert.equal(calls.length, 4);
for (const mode of ["print", "json", "rpc"]) {
    for (const handler of handlers.values()) await handler({}, { mode });
}
assert.equal(calls.length, 4);

// Hook failures must not escape into Pi's event handling.
pi.exec = async () => { throw new Error("tmux unavailable"); };
await handlers.get("agent_start")({}, { mode: "tui" });

for (const tmux of [undefined, "/tmp/tmux-1000/default,123,0", "/tmp/tmux-1000/tabs-other,123,0"]) {
    if (tmux === undefined) delete process.env.TMUX;
    else process.env.TMUX = tmux;
    handlers.clear();
    extension(pi);
    assert.equal(handlers.size, 0);
}
process.env.TMUX = "/tmp/tmux-1000/tabs,123,0";
delete process.env.TMUX_PANE;
extension(pi);
assert.equal(handlers.size, 0);
console.log("Pi extension lifecycle tests passed");
