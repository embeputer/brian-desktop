#!/usr/bin/env node
// Speaks the subset of Brian's RPC JSONL protocol used by the desktop client.
// Records are split on LF only. One text delta is written in two chunks and
// contains U+2028 so a line reader that splits on Unicode separators would fail.

import { Buffer } from "node:buffer";

let buffer = Buffer.alloc(0);

process.stdin.on("data", (chunk) => {
	buffer = Buffer.concat([buffer, chunk]);
	while (true) {
		const newline = buffer.indexOf(0x0a);
		if (newline === -1) return;
		let line = buffer.subarray(0, newline);
		buffer = buffer.subarray(newline + 1);
		if (line.length > 0 && line[line.length - 1] === 0x0d) line = line.subarray(0, -1);
		if (line.length === 0) continue;
		handle(JSON.parse(line.toString("utf8")));
	}
});

process.stdin.on("end", () => {
	process.exit(0);
});

function out(value) {
	process.stdout.write(`${JSON.stringify(value)}\n`);
}

function handle(command) {
	if (command.type === "get_state") {
		out({
			id: command.id,
			type: "response",
			command: "get_state",
			success: true,
			data: {
				sessionId: "sess-test",
				thinkingLevel: "off",
				isStreaming: false,
				model: { provider: "fake", id: "fake-1" },
			},
		});
		process.stderr.write("ready\n");
		return;
	}
	if (command.type === "prompt") {
		const delta = "Hello \u2028world";
		out({ type: "agent_start" });
		out({
			type: "message_start",
			message: { role: "assistant", content: [], stopReason: "pending" },
		});
		const record = JSON.stringify({
			type: "message_update",
			assistantMessageEvent: { type: "text_delta", contentIndex: 0, delta },
		});
		process.stdout.write(record.slice(0, 12), () => {
			process.stdout.write(`${record.slice(12)}\n`, () => {
				setTimeout(() => {
					out({
						type: "message_end",
						message: {
							role: "assistant",
							content: [{ type: "text", text: "FINAL" }],
							stopReason: "stop",
						},
					});
					out({
						type: "delivery",
						delivery: {
							text: delta,
							embeds: [{ title: "later" }],
							questions: [],
							attachments: [],
							errors: [],
						},
					});
					out({
						id: command.id,
						type: "response",
						command: "prompt",
						success: true,
						data: { disposition: "started" },
					});
					out({ type: "agent_end", messages: [], willRetry: false });
					out({ type: "agent_settled", aborted: false });
				}, 150);
			});
		});
	}
}
