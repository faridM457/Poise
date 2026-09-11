import { query } from "@anthropic-ai/claude-agent-sdk";

// Model alias resolved by the Claude Code CLI the SDK shells out to
// ('haiku' | 'sonnet' | 'opus', or a full model ID). Defaults to the
// cheapest tier since each engine stage is a short, single-shot call.
const MODEL = process.env.CLAUDE_ENGINE_MODEL || "haiku";

// Runs a single-turn query against Claude via the Agent SDK, which shells out
// to the local Claude Code CLI and reuses its login — a Claude Pro/Max
// subscription login counts against plan usage, not per-token API billing.
// `outputFormat: {type: "json_schema"}` forces the turn to end with a
// response matching `schema`, so callers get back parsed, structured JSON
// instead of free text.
export async function structuredCall({ system, messages, schema }) {
  const prompt = messages.map((m) => m.content).join("\n\n");

  let assistantError = null;

  for await (const message of query({
    prompt,
    options: {
      model: MODEL,
      systemPrompt: system,
      outputFormat: { type: "json_schema", schema },
      tools: [],
      maxTurns: 4,
      permissionMode: "default",
    },
  })) {
    if (message.type === "assistant" && message.error) {
      assistantError = message.error;
    }

    if (message.type === "result") {
      if (message.subtype === "success" && !message.is_error) {
        return message.structured_output;
      }

      const reason = message.subtype === "success" ? message.result : message.subtype;
      throw new Error(describeAgentFailure(reason, assistantError));
    }
  }

  throw new Error("Agent SDK query ended without producing a result.");
}

function describeAgentFailure(reason, assistantError) {
  if (assistantError === "rate_limit") {
    return "Hit your Claude Pro/Max plan's usage limit for this window. Wait for it to reset, or set CLAUDE_ENGINE_MODEL and try a lighter model.";
  }
  if (assistantError === "authentication_failed" || assistantError === "oauth_org_not_allowed") {
    return "Not logged in to Claude Code (or the session is invalid). Run `claude login` and try again.";
  }
  if (assistantError === "billing_error" || assistantError === "account_on_hold") {
    return `Claude account billing issue: ${assistantError}.`;
  }
  return `Agent SDK call failed: ${reason}`;
}
