import fs from "node:fs";
import http from "node:http";

const token = "secret-token";
const server = http.createServer((req, res) => {
	if (req.method === "GET" && req.url === "/v1/health") {
		res.writeHead(200, { "content-type": "application/json" });
		res.end(JSON.stringify({ ok: true, name: "brian", version: "9" }));
		return;
	}
	if (req.method === "POST" && req.url === "/v1/prompt") {
		const auth = req.headers.authorization || "";
		if (auth !== `Bearer ${token}`) {
			res.writeHead(401, { "content-type": "application/json" });
			res.end(JSON.stringify({ error: "unauthorized" }));
			return;
		}
		const chunks = [];
		req.on("data", (chunk) => chunks.push(chunk));
		req.on("end", () => {
			const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
			res.writeHead(200, { "content-type": "application/json" });
			res.end(JSON.stringify({ text: `echo:${body.prompt}` }));
		});
		return;
	}
	res.writeHead(404, { "content-type": "application/json" });
	res.end(JSON.stringify({ error: "not found" }));
});

server.listen(0, "127.0.0.1", () => {
	const address = server.address();
	fs.writeSync(1, `${address.port}\n`);
});
