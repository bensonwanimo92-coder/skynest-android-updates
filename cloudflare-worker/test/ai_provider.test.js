import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_SKYNEST_AI_MODEL, generateSkyNestAnswer } from "../src/ai_provider.js";

test("SkyNest uses Cloudflare Workers AI without an external API key", async () => {
  let called;
  const answer = await generateSkyNestAnswer({
    AI: { run: async (model, input) => { called = { model, input }; return { response: "Hello from SkyNest." }; } },
  }, [{ role: "user", content: "Hello" }]);
  assert.equal(answer, "Hello from SkyNest.");
  assert.equal(called.model, DEFAULT_SKYNEST_AI_MODEL);
  assert.equal(called.input.max_tokens, 700);
});

test("SkyNest AI supports a configured Cloudflare model", async () => {
  let model;
  await generateSkyNestAnswer({
    SKYNEST_AI_MODEL: "@cf/meta/llama-3.1-8b-instruct",
    AI: { run: async (name) => { model = name; return { response: "ok" }; } },
  }, []);
  assert.equal(model, "@cf/meta/llama-3.1-8b-instruct");
});

test("SkyNest AI fails closed when Cloudflare AI binding is missing", async () => {
  await assert.rejects(() => generateSkyNestAnswer({}, []), { status: 503 });
});

test("SkyNest AI rejects empty model output", async () => {
  await assert.rejects(() => generateSkyNestAnswer({
    AI: { run: async () => ({ response: "  " }) },
  }, []), { status: 502 });
});
