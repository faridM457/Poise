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
        return sanitizeStructuredOutput(message.structured_output);
      }

      const reason = message.subtype === "success" ? message.result : message.subtype;
      throw new Error(describeAgentFailure(reason, assistantError));
    }
  }

  throw new Error("Agent SDK query ended without producing a result.");
}

// Prompting alone doesn't reliably keep the model off em dashes, stage
// directions, and the like (especially on a lighter model), so enforce it
// deterministically on every string the model returns rather than trusting
// compliance. Dialogue fields must render as plain spoken text on screen —
// no asterisk/bracket stage directions, no ellipses, no dash-as-punctuation.
function sanitizeStructuredOutput(value) {
  if (typeof value === "string") {
    return sanitizeText(value);
  }
  if (Array.isArray(value)) {
    return value.map(sanitizeStructuredOutput);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, sanitizeStructuredOutput(v)]));
  }
  return value;
}

function sanitizeText(text) {
  return text
    .replace(/\*[^*]*\*/g, "") // *action* stage directions
    .replace(/\[[^\]]*\]/g, "") // [action] stage directions
    .replace(/\s*[—–]\s*/g, ", ") // em/en dash used as punctuation
    .replace(/\s+-\s+/g, ", ") // " - " used as a dash (spaced hyphen), not compound words like "one-on-one"
    .replace(/^-\s+/g, "") // leading "- " bullet-style dash
    .replace(/\s*;\s*/g, ", ") // semicolon
    .replace(/\.{2,}|…/g, ".") // ellipsis
    .replace(/[ \t]{2,}/g, " ") // collapse whitespace left behind by removals
    .trim();
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
