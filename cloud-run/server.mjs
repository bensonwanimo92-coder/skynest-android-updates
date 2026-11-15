import http from "node:http";
import worker from "./src/index.js";

const port = Number(process.env.PORT || 8080);

const server = http.createServer(async (incoming, outgoing) => {
  try {
    const chunks = [];
    for await (const chunk of incoming) chunks.push(chunk);
    const body = chunks.length ? Buffer.concat(chunks) : undefined;
    const host = incoming.headers.host || "localhost";
    const request = new Request(`http://${host}${incoming.url || "/"}`, {
      method: incoming.method || "GET",
      headers: incoming.headers,
      ...(body ? { body } : {}),
    });
    const response = await worker.fetch(request, process.env);
    outgoing.statusCode = response.status;
    response.headers.forEach((value, key) => outgoing.setHeader(key, value));
    outgoing.end(Buffer.from(await response.arrayBuffer()));
  } catch (error) {
    outgoing.statusCode = 500;
    outgoing.setHeader("content-type", "application/json; charset=utf-8");
    outgoing.end(JSON.stringify({ error: "Internal server error." }));
    console.error("Request adapter error:", error);
  }
});

server.listen(port, "0.0.0.0", () => {
  console.log(`SkyNest M-Pesa API listening on port ${port}`);
});
