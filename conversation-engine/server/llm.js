import Anthropic from "@anthropic-ai/sdk";

const MODEL = "claude-sonnet-5";

let client;
function getClient() {
  if (!client) {
    if (!process.env.ANTHROPIC_API_KEY) {
      throw new Error("ANTHROPIC_API_KEY is not set. Copy .env.example to .env and add your key.");
    }
    client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  }
  return client;
}

// Forces the model to respond via a single tool call matching `schema`,
// so callers get back parsed, structured JSON instead of free text.
export async function structuredCall({ system, messages, schema, toolName, maxTokens = 1024 }) {
  const anthropic = getClient();

  const response = await anthropic.messages.create({
    model: MODEL,
    max_tokens: maxTokens,
    system,
    messages,
    tools: [
      {
        name: toolName,
        description: `Return the result of this step as structured data matching the ${toolName} schema.`,
        input_schema: schema,
      },
    ],
    tool_choice: { type: "tool", name: toolName },
  });

  const toolUse = response.content.find((block) => block.type === "tool_use");
  if (!toolUse) {
    throw new Error("LLM response did not include the expected structured tool call.");
  }
  return toolUse.input;
}
