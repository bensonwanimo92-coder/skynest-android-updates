// Cloudflare Workers AI adapter for SkyNest.
// The model runs in Cloudflare; no OpenAI key or model weights are shipped in the APK.
export const DEFAULT_SKYNEST_AI_MODEL = "@cf/meta/llama-3.1-8b-instruct";

export async function generateSkyNestAnswer(env, messages) {
  if (!env?.AI || typeof env.AI.run !== "function") {
    const error = new Error("Cloudflare Workers AI binding is not configured. Add the AI binding to the Worker and redeploy.");
    error.status = 503;
    throw error;
  }
  const model = String(env.SKYNEST_AI_MODEL || DEFAULT_SKYNEST_AI_MODEL).trim();
  if (!model || model.length > 160) {
    const error = new Error("SkyNest AI model configuration is invalid.");
    error.status = 500;
    throw error;
  }
  const result = await env.AI.run(model, {
    messages,
    temperature: 0.2,
    max_tokens: 700,
  });
  const answer = result?.response ?? result?.result?.response ?? result?.output_text;
  if (typeof answer !== "string" || !answer.trim()) {
    const error = new Error("Cloudflare AI returned an empty response.");
    error.status = 502;
    throw error;
  }
  return answer.trim();
}
