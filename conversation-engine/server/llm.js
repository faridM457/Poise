import {
  BedrockRuntimeClient,
  ConverseCommand,
} from "@aws-sdk/client-bedrock-runtime";
import { fromNodeProviderChain } from "@aws-sdk/credential-providers";
import { STSClient, GetCallerIdentityCommand } from "@aws-sdk/client-sts";

// Claude on Amazon Bedrock.
//
// Replaces the Claude Agent SDK, which shelled out to the local Claude Code
// CLI and borrowed its login. That was convenient — no key to manage — but it
// was a per-developer credential on one laptop, so the engine could never be
// deployed. Bedrock authenticates with ordinary AWS credentials, which a
// deployed server can hold (or better, assume via an IAM role).
//
// Required environment:
//   AWS_REGION              e.g. us-east-1 (or us-west-2)
//   AWS_ACCESS_KEY_ID       omit both when running with an IAM role
//   AWS_SECRET_ACCESS_KEY
//   BEDROCK_MODEL_ID        optional, see below
//
// Model access is NOT on by default: Anthropic models have to be enabled for
// your account, per region, in the Bedrock console under Model access.
// Requests before that return AccessDeniedException, which is mapped to a
// readable message below. Newer Claude models are also served through
// cross-region inference profiles whose ids carry a region prefix
// ("us.anthropic.…"); if a plain model id is rejected as invalid, that prefix
// is usually what is missing.
const MODEL_ID =
  process.env.BEDROCK_MODEL_ID || "us.anthropic.claude-haiku-4-5-20251001-v1:0";

const REGION = process.env.AWS_REGION;

// Credentials are never taken implicitly.
//
// The AWS SDK's default provider chain falls back to ~/.aws/credentials, so a
// client built with no credentials silently runs as whatever IAM user happens
// to be configured on the machine -- and bills that account. That is not
// hypothetical: it already happened here once, against an unrelated personal
// profile left over from another project.
//
// So the source has to be stated. Exactly one of:
//
//   AWS_PROFILE                     a named profile (SSO or otherwise). The
//                                   normal local-development answer, and the
//                                   one that cannot pick up [default].
//   AWS_ACCESS_KEY_ID / _SECRET_    explicit keys.
//   AWS_USE_AMBIENT_CREDENTIALS     the provider chain, deliberately. Correct
//                                   in deployment, where an ECS task role or
//                                   EC2 instance role supplies credentials and
//                                   there are no env vars to read.
//
// Nothing is used by default.
const PROFILE = process.env.AWS_PROFILE;

// Optional but strongly worth setting: the account this service is allowed to
// bill. Checked once, lazily, against STS. A profile can be re-pointed, an SSO
// session can resolve somewhere unexpected, and a role can be assumed in the
// wrong account -- this turns any of those into a refusal instead of a
// surprise on someone's bill.
const EXPECTED_ACCOUNT_ID = process.env.AWS_EXPECTED_ACCOUNT_ID;

function credentialSource() {
  if (PROFILE) {
    return { credentials: fromNodeProviderChain({ profile: PROFILE }), label: `profile "${PROFILE}"` };
  }
  if (process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY) {
    return {
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
        ...(process.env.AWS_SESSION_TOKEN ? { sessionToken: process.env.AWS_SESSION_TOKEN } : {}),
      },
      label: "explicit AWS_ACCESS_KEY_ID",
    };
  }
  if (process.env.AWS_USE_AMBIENT_CREDENTIALS === "true") {
    return { credentials: undefined, label: "the AWS provider chain (ambient, opted in)" };
  }
  return null;
}

const source = credentialSource();

const client = source
  ? new BedrockRuntimeClient({
      ...(REGION ? { region: REGION } : {}),
      ...(source.credentials ? { credentials: source.credentials } : {}),
    })
  : null;

// Resolved once and reused; null means the check is disabled.
let accountCheck = null;

async function assertExpectedAccount() {
  if (!EXPECTED_ACCOUNT_ID) return;
  if (!accountCheck) {
    accountCheck = (async () => {
      const sts = new STSClient({
        ...(REGION ? { region: REGION } : {}),
        ...(source.credentials ? { credentials: source.credentials } : {}),
      });
      const identity = await sts.send(new GetCallerIdentityCommand({}));
      if (identity.Account !== EXPECTED_ACCOUNT_ID) {
        throw new Error(
          `Refusing to run: credentials from ${source.label} resolve to AWS account ` +
            `${identity.Account} (${identity.Arn}), but AWS_EXPECTED_ACCOUNT_ID is ` +
            `${EXPECTED_ACCOUNT_ID}. Fix the profile or the expectation before any billable call.`
        );
      }
    })();
  }
  await accountCheck;
}

function regionLabel() {
  return REGION ?? "the region from your AWS config";
}

// Runs a single-turn call and returns parsed, schema-conforming JSON.
//
// Structure is enforced through tool use rather than by asking for JSON in the
// prompt: the schema is declared as a tool's input schema and `toolChoice`
// forces the model to call it, so the response is a validated object instead
// of prose that has to be parsed and might not be JSON at all.
//
// `toolName` and `maxTokens` were already being passed by every call site and
// silently dropped by the previous wrapper, which destructured only
// { system, messages, schema }. They are honoured now — which matters most for
// generateFeedback, whose response carries a feedback line plus three skill
// notes.
export async function structuredCall({
  system,
  messages,
  schema,
  toolName = "submit_response",
  maxTokens = 512,
}) {
  if (!client) {
    throw new Error(
      "No Bedrock credential source configured. Set AWS_PROFILE to a named profile, or " +
        "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or AWS_USE_AMBIENT_CREDENTIALS=true to " +
        "deliberately use the provider chain (an instance or task role in deployment). " +
        "Refusing to fall back to the machine's default profile, which bills whichever account " +
        "it happens to belong to."
    );
  }

  await assertExpectedAccount();

  const prompt = messages.map((m) => m.content).join("\n\n");

  let response;
  try {
    response = await client.send(
      new ConverseCommand({
        modelId: MODEL_ID,
        system: [{ text: system }],
        messages: [{ role: "user", content: [{ text: prompt }] }],
        inferenceConfig: {
          maxTokens,
          // Low but not zero: these are short, structured generations where
          // the scenario specifics should still vary between plays.
          temperature: 0.7,
        },
        toolConfig: {
          tools: [
            {
              toolSpec: {
                name: toolName,
                description: "Return the structured result for this request.",
                inputSchema: { json: schema },
              },
            },
          ],
          toolChoice: { tool: { name: toolName } },
        },
      })
    );
  } catch (error) {
    throw new Error(describeBedrockFailure(error));
  }

  // A forced toolChoice should always produce exactly one toolUse block, but
  // a truncated response (maxTokens too low) can come back without one —
  // which is a far more useful thing to say than "cannot read property of
  // undefined" three frames later.
  const blocks = response?.output?.message?.content ?? [];
  const toolUse = blocks.find((block) => block.toolUse)?.toolUse;

  if (!toolUse) {
    const stop = response?.stopReason ?? "unknown";
    if (stop === "max_tokens") {
      throw new Error(
        `Model hit the ${maxTokens}-token limit for ${toolName} before returning a complete result. Raise maxTokens at the call site.`
      );
    }
    const text = blocks.find((block) => block.text)?.text;
    throw new Error(
      `Model did not call ${toolName} (stopReason: ${stop})` +
        (text ? `. It replied with text instead: ${text.slice(0, 200)}` : "")
    );
  }

  return sanitizeStructuredOutput(toolUse.input);
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

// Bedrock's exceptions are precise but their messages assume you already know
// the service. These are the four that actually come up while setting it up.
function describeBedrockFailure(error) {
  const name = error?.name ?? "";

  if (name === "AccessDeniedException") {
    return (
      `Bedrock denied access to ${MODEL_ID} in ${regionLabel()}. Either the IAM principal lacks ` +
      `bedrock:InvokeModel, or Anthropic model access has not been enabled for this account ` +
      `in that region (Bedrock console, Model access).`
    );
  }
  if (name === "ValidationException") {
    return (
      `Bedrock rejected the request for ${MODEL_ID}: ${error.message}. If the model id is ` +
      `reported as invalid, it may need the cross-region inference prefix (us.${MODEL_ID}).`
    );
  }
  if (name === "ResourceNotFoundException") {
    // Two quite different situations share this exception, and the message is
    // the only way to tell them apart.
    if (/use case details/i.test(error.message ?? "")) {
      return (
        "Bedrock requires Anthropic use case details for this AWS account before it will serve " +
        "the model. Submit the form in the Bedrock console (Model access, Anthropic), then allow " +
        "about 15 minutes. Calls made before the gate engages can succeed, so a single working " +
        "request does not mean this step was done."
      );
    }
    return (
      `Bedrock has no model ${MODEL_ID} in ${regionLabel()}: ${error.message}. The id may be ` +
      `retired -- check "aws bedrock list-foundation-models --by-provider anthropic" for one ` +
      `whose lifecycle status is ACTIVE.`
    );
  }
  if (name === "ThrottlingException") {
    return "Bedrock throttled the request. Retry, or request a quota increase for this model.";
  }
  if (name === "CredentialsProviderError" || name === "UnrecognizedClientException") {
    return (
      "No usable AWS credentials. Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (or run with " +
      "an IAM role), and confirm AWS_REGION."
    );
  }
  return `Bedrock call failed (${name || "unknown error"}): ${error?.message ?? error}`;
}
