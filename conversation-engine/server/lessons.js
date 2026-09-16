// Hardcoded lesson definitions for the local test site.
// Each lesson matches the "Lesson Input Format" in the conversation engine spec.
//
// 4 units, manager-focused, ordered by escalating difficulty. Each unit has
// 4 regular lessons (also loosely ordered easier-to-harder) plus a
// checkpoint. `difficultyLabel` and `demoExchange` are engine-only signals
// (never shown to the user) used to calibrate the NPC's resistance level —
// see server/engine.js's runTurn. The same demoExchange is reused by every
// lesson in a unit; finer within-unit progression lives in each lesson's
// own personaNotes.

const UNIT_1_DEMO = {
  user:
    "I've noticed you've been a few minutes late to our morning standup a handful of times this month, " +
    "and it's meant we sometimes start without you. What's been going on there?",
  npc:
    "Yeah, that's fair, I noticed it too. My commute's been rougher since a construction detour started, " +
    "and I've been cutting it too close. I can just leave earlier, that's on me.",
};

const UNIT_2_DEMO = {
  user:
    "Hey, I wanted to mention, in yesterday's planning meeting I noticed you jumped in a few times while " +
    "I was walking through the roadmap. I'd like a chance to finish my point before we open it up.",
  npc:
    "Oh. I didn't realize I was doing that so much. I mean, it's a fast moving meeting, people jump in " +
    "all the time. But yeah, I hear you, I'll be more aware of it.",
};

const UNIT_3_DEMO = {
  user:
    "I want to be upfront, I don't think I can take this on this week given everything else I have going " +
    "on. Can we look at pushing the deadline, or finding someone else who has room for it?",
  npc:
    "I mean, I was really counting on you for this, everyone else is slammed too. Is there any way you " +
    "could just fit it in? It shouldn't take that long.",
};

const UNIT_4_DEMO = {
  user:
    "You've missed the report deadline three weeks in a row now, and it's been pushing back my own " +
    "commitments to leadership. What's been going on?",
  npc:
    "I mean, I don't think it's that big a deal. Everyone's been slammed lately, not just me. I don't " +
    "see why this is turning into a whole conversation.",
};

export const lessons = [
  // ---------------------------------------------------------------------
  // Unit 1: Giving Feedback (Foundations) — cooperative
  // ---------------------------------------------------------------------
  {
    id: "feedback-small-pattern",
    unit: "Unit 1: Giving Feedback",
    title: "Naming a Small Pattern",
    isCheckpoint: false,
    difficultyLabel: "cooperative",
    character: {
      name: "Sam",
      role: "Direct report",
      relationship: "6 months on the team, reports to the user",
    },
    scenarioTemplate:
      "The user's direct report has been repeatedly a few minutes late to a recurring commitment (e.g. " +
      "a daily standup, a recurring client call) over the past couple of weeks. The user needs to name " +
      "the pattern directly in a one-on-one meeting, low stakes but still worth addressing before it " +
      "becomes a habit.",
    criteria: [
      "Named the specific pattern, not a vague generalization",
      "Stated the impact of the pattern",
      "Asked for the direct report's perspective before concluding",
    ],
    personaNotes:
      "Sam is receptive and a little embarrassed once the pattern is named, not defensive. Owns it " +
      "quickly and doesn't need much convincing, but still responds better to a specific, calm approach " +
      "than a vague one.",
    demoExchange: UNIT_1_DEMO,
  },
  {
    id: "feedback-quality-slip",
    unit: "Unit 1: Giving Feedback",
    title: "Following Up on a Quality Slip",
    isCheckpoint: false,
    difficultyLabel: "cooperative",
    character: {
      name: "Riley",
      role: "Direct report",
      relationship: "4 months on the team, reports to the user",
    },
    scenarioTemplate:
      "The user's direct report has turned in work with small but repeated quality issues (e.g. typos, " +
      "formatting errors, missed details) in client-facing material over the past couple of weeks. The " +
      "user needs to raise the pattern directly without making the direct report feel attacked over " +
      "honest mistakes.",
    criteria: [
      "Named the specific quality issue with a concrete example",
      "Stated why the quality bar matters here",
      "Asked what's been getting in the way before concluding",
    ],
    personaNotes:
      "Riley is a bit surprised but not defensive, genuinely didn't realize the pattern was noticeable. " +
      "Responds well to specific examples and opens up quickly about what's been distracting them (e.g. " +
      "juggling too many small tasks), especially if the user frames it collaboratively.",
    demoExchange: UNIT_1_DEMO,
  },
  {
    id: "feedback-missed-commitment",
    unit: "Unit 1: Giving Feedback",
    title: "Addressing a Missed Commitment",
    isCheckpoint: false,
    difficultyLabel: "cooperative",
    character: {
      name: "Taylor",
      role: "Direct report",
      relationship: "7 months on the team, reports to the user",
    },
    scenarioTemplate:
      "The user's direct report explicitly agreed, in a previous conversation, to complete a specific " +
      "task by a specific time, and did not follow through, with no communication about the delay. The " +
      "user needs to address the broken commitment directly, not just the missed task.",
    criteria: [
      "Named the specific commitment that was missed, not a vague generalization",
      "Stated the impact of the missed commitment",
      "Asked for the direct report's perspective before concluding",
    ],
    personaNotes:
      "Taylor feels a little guilty and knows they dropped the ball, so they're receptive, but might " +
      "briefly get slightly defensive if the user leads only with disappointment rather than curiosity. " +
      "Opens up and takes ownership once given room to explain.",
    demoExchange: UNIT_1_DEMO,
  },
  {
    id: "feedback-communication-style",
    unit: "Unit 1: Giving Feedback",
    title: "Giving Feedback on a Communication Style",
    isCheckpoint: false,
    difficultyLabel: "cooperative",
    character: {
      name: "Morgan",
      role: "Direct report",
      relationship: "9 months on the team, reports to the user",
    },
    scenarioTemplate:
      "The user's direct report is technically strong, but their written updates and messages to the " +
      "team often come across as terse or hard to follow, and a couple of teammates have mentioned " +
      "needing to ask for clarification. This is a more subjective piece of feedback than a missed " +
      "deadline, and the user needs to raise it constructively.",
    criteria: [
      "Named the specific communication pattern with a concrete example",
      "Stated the impact on the team, not just a personal preference",
      "Asked for the direct report's perspective before concluding",
    ],
    personaNotes:
      "Morgan is a little caught off guard since this is more subjective feedback than they're used to " +
      "receiving, and might initially push back mildly (\"I didn't realize that, I thought I was being " +
      "efficient\"). Not defensive though, genuinely wants to understand, and engages constructively " +
      "once given a concrete example.",
    demoExchange: UNIT_1_DEMO,
  },
  {
    id: "checkpoint-unit-1",
    unit: "Unit 1: Giving Feedback",
    title: "Checkpoint: Giving Feedback",
    isCheckpoint: true,
    difficultyLabel: "cooperative",
    character: {
      name: "Jamie",
      role: "Direct report",
      relationship: "5 months on the team, reports to the user",
    },
    scenarioTemplate:
      "A direct report has missed or joined late to most of the team's daily stand-ups over the last " +
      "three weeks, and the rest of the team keeps recapping for them. There is a sympathetic reason " +
      "behind it that they will share if the user asks. The user has set up a short one-on-one.",
    criteria: [
      "Named the specific behavior or pattern directly",
      "Stated the concrete impact of the behavior",
      "Asked for the direct report's perspective before concluding",
    ],
    personaNotes:
      "Jamie is cooperative and not defensive by default, similar to the rest of this unit, but the " +
      "guide isn't shown so the user has to remember to hit all three skills unprompted.",
    demoExchange: UNIT_1_DEMO,
  },

  // ---------------------------------------------------------------------
  // Unit 2: Everyday Workplace Friction — mild resistance
  // ---------------------------------------------------------------------
  {
    id: "friction-interruptions",
    unit: "Unit 2: Everyday Workplace Friction",
    title: "Addressing a Repeated Interruption Pattern",
    isCheckpoint: false,
    difficultyLabel: "mild resistance",
    character: {
      name: "Dana",
      role: "Peer, coworker on an adjacent team",
      relationship: "Works closely with the user cross-functionally",
    },
    scenarioTemplate:
      "A peer has a habit of interrupting or talking over the user in shared meetings, and it's started " +
      "to affect how the user is perceived by others in the room. The user needs to raise it directly, " +
      "one-on-one, without turning it into a conflict.",
    criteria: [
      "Named the specific pattern with a concrete example",
      "Stayed neutral in tone instead of accusatory",
      "Proposed what they'd like to happen going forward",
    ],
    personaNotes:
      "Dana is initially surprised and a little embarrassed, which can read as mild defensiveness. If " +
      "the user stays neutral and specific, Dana relaxes and owns it. If the user is accusatory or " +
      "vague, Dana gets defensive and starts minimizing (\"I don't think it's that big a deal\").",
    demoExchange: UNIT_2_DEMO,
  },
  {
    id: "friction-missed-handoff",
    unit: "Unit 2: Everyday Workplace Friction",
    title: "Pushing Back on a Missed Handoff",
    isCheckpoint: false,
    difficultyLabel: "mild resistance",
    character: {
      name: "Chris",
      role: "Peer, coworker on an adjacent team",
      relationship: "Shares ownership of a recurring deliverable with the user",
    },
    scenarioTemplate:
      "A peer who owns a piece of a shared deliverable has repeatedly been late or incomplete in " +
      "handing off their part, forcing the user to scramble or redo work close to a deadline. The user " +
      "needs to raise this directly without escalating it into a bigger conflict.",
    criteria: [
      "Named the specific pattern with a concrete example",
      "Stated the impact on the user's own work",
      "Proposed what they'd like to happen going forward",
    ],
    personaNotes:
      "Chris is a little defensive at first, tends to explain it away as just being busy, but isn't " +
      "hostile. Relaxes and gets more collaborative if the user stays specific and unaccusatory, gets " +
      "more clipped and minimizing if the user leads with frustration.",
    demoExchange: UNIT_2_DEMO,
  },
  {
    id: "friction-credit-issue",
    unit: "Unit 2: Everyday Workplace Friction",
    title: "Raising a Credit Issue",
    isCheckpoint: false,
    difficultyLabel: "mild resistance",
    character: {
      name: "Jordan",
      role: "Peer, coworker on the same team",
      relationship: "Works alongside the user day to day",
    },
    scenarioTemplate:
      "In a recent meeting, a peer presented an idea or piece of analysis that was actually the user's " +
      "work, without acknowledging it, in front of others including leadership. The user needs to raise " +
      "this directly with the peer, one-on-one, without it turning into an accusation of dishonesty.",
    criteria: [
      "Named the specific incident with a concrete example",
      "Explained why it matters to them, not just that it happened",
      "Stayed collaborative rather than accusatory",
    ],
    personaNotes:
      "Jordan gets a bit defensive and surprised at first (\"I wasn't trying to take credit\"), and might " +
      "initially minimize it as an oversight. Opens up and acknowledges it more genuinely if the user " +
      "stays calm and specific, gets more clipped and defensive if the user sounds accusatory.",
    demoExchange: UNIT_2_DEMO,
  },
  {
    id: "friction-passive-aggressive",
    unit: "Unit 2: Everyday Workplace Friction",
    title: "Addressing Passive-Aggressive Comments",
    isCheckpoint: false,
    difficultyLabel: "mild resistance",
    character: {
      name: "Casey",
      role: "Peer, coworker on an adjacent team",
      relationship: "Interacts with the user regularly in group settings",
    },
    scenarioTemplate:
      "A peer has made a few subtly pointed or sarcastic comments about the user's work or decisions in " +
      "group settings over the past couple of weeks, nothing overt enough to call out in the moment, but " +
      "adding up. The user needs to name the pattern directly, one-on-one, which is trickier since each " +
      "individual comment could be brushed off as harmless.",
    criteria: [
      "Named the specific pattern with concrete examples, not just a feeling",
      "Explained the impact without being accusatory",
      "Invited the peer's perspective before concluding",
    ],
    personaNotes:
      "Casey is caught off guard and a bit defensive, likely to claim they didn't mean anything by it or " +
      "that the user is reading into it. This is the trickiest lesson in this unit: Casey relaxes only " +
      "if the user is specific and calm rather than vague or emotional, and stays defensive longer than " +
      "the other Unit 2 lessons if the user is vague.",
    demoExchange: UNIT_2_DEMO,
  },
  {
    id: "checkpoint-unit-2",
    unit: "Unit 2: Everyday Workplace Friction",
    title: "Checkpoint: Workplace Friction",
    isCheckpoint: true,
    difficultyLabel: "mild resistance",
    character: {
      name: "Reese",
      role: "Peer, coworker on an adjacent team",
      relationship: "Works closely with the user cross-functionally",
    },
    scenarioTemplate:
      "A peer on an adjacent team has twice posted decisions affecting the user's team in a shared " +
      "project channel before raising them with the user, so the user's team found out from the channel. " +
      "There is a plausible innocent explanation. The user has grabbed time with them.",
    criteria: [
      "Named the specific pattern with a concrete example",
      "Stayed neutral in tone instead of accusatory",
      "Proposed what they'd like to happen going forward",
    ],
    personaNotes:
      "Reese starts a little surprised and mildly defensive, similar to the rest of this unit, and " +
      "relaxes if approached calmly and specifically.",
    demoExchange: UNIT_2_DEMO,
  },

  // ---------------------------------------------------------------------
  // Unit 3: Setting Boundaries and Saying No — moderate resistance
  // ---------------------------------------------------------------------
  {
    id: "boundaries-unreasonable-ask",
    unit: "Unit 3: Setting Boundaries and Saying No",
    title: "Turning Down an Unreasonable Ask",
    isCheckpoint: false,
    difficultyLabel: "moderate resistance",
    // The ask itself already exists before this conversation starts (Avery
    // made it) — unlike most lessons, where the NPC must stay neutral so
    // the user is the one to surface the specifics, here it's realistic
    // (and doesn't hand away any graded skill) for the opening line to
    // reference the known, pending ask. See engine.js's generateOpeningLine.
    npcInitiatesWithKnownRequest: true,
    character: {
      name: "Avery",
      role: "Peer, coworker on an adjacent team",
      relationship: "Occasionally asks the user for cross-team help",
    },
    scenarioTemplate:
      "A peer has asked the user to take on a significant piece of extra work with an unreasonable " +
      "turnaround, on top of the user's already full plate. The user needs to say no or negotiate the " +
      "scope, without just quietly absorbing the ask.",
    criteria: [
      "Clearly declined or renegotiated the ask, not just expressed discomfort",
      "Gave a concrete reason grounded in their actual workload",
      "Offered or discussed an alternative",
    ],
    personaNotes:
      "Avery pushes back a bit and tries to guilt-trip mildly (\"I was really counting on you\"), and " +
      "negotiates rather than immediately accepting the no. Backs off and works toward an alternative if " +
      "the user stays firm but reasonable, keeps pushing if the user hedges or sounds unsure.",
    demoExchange: UNIT_3_DEMO,
  },
  {
    id: "boundaries-team-time",
    unit: "Unit 3: Setting Boundaries and Saying No",
    title: "Protecting Your Team's Time",
    isCheckpoint: false,
    difficultyLabel: "moderate resistance",
    character: {
      name: "Drew",
      role: "Peer manager, leads an adjacent team",
      relationship: "Manages a team that frequently collaborates with the user's team",
    },
    scenarioTemplate:
      "A peer manager keeps pulling one of the user's direct reports into unplanned work without " +
      "checking with the user first, disrupting the direct report's ability to hit their own priorities. " +
      "The user needs to set a boundary with the peer manager directly.",
    criteria: [
      "Named the specific pattern with a concrete example",
      "Stated why it's a problem for their team's priorities",
      "Proposed a clear process for future requests",
    ],
    personaNotes:
      "Drew is a bit surprised and defensive at first, feels like their own priorities are legitimate " +
      "and gets slightly dismissive of the concern. Comes around to a workable process if the user stays " +
      "firm and specific instead of just venting, stays dismissive and unresolved if the user is vague.",
    demoExchange: UNIT_3_DEMO,
  },
  {
    id: "boundaries-repeat-favor",
    unit: "Unit 3: Setting Boundaries and Saying No",
    title: "Saying No to a Repeat Favor",
    isCheckpoint: false,
    difficultyLabel: "moderate resistance",
    character: {
      name: "Skyler",
      role: "Peer, coworker on the same team",
      relationship: "Has leaned on the user for help several times before",
    },
    scenarioTemplate:
      "A peer has repeatedly asked the user for help with tasks outside the user's role, and it's become " +
      "a pattern that's eating into the user's own work. The user needs to say no to the pattern, not " +
      "just the latest ask, without damaging the relationship.",
    criteria: [
      "Named the pattern, not just the one-off request",
      "Was clear about what they will and won't keep doing",
      "Acknowledged the relationship while holding the boundary",
    ],
    personaNotes:
      "Skyler is caught off guard and a little hurt or defensive, might imply the user is being " +
      "unhelpful or that they thought this was fine. Comes around if the user is warm but firm and " +
      "specific about the pattern, gets more wounded and defensive if the user is only firm without any " +
      "warmth.",
    demoExchange: UNIT_3_DEMO,
  },
  {
    id: "boundaries-scope-creep",
    unit: "Unit 3: Setting Boundaries and Saying No",
    title: "Pushing Back on Scope Creep from Your Own Manager",
    isCheckpoint: false,
    difficultyLabel: "moderate resistance",
    character: {
      name: "Diane Foster",
      role: "The user's own manager",
      relationship: "Directly manages the user",
    },
    scenarioTemplate:
      "The user's own manager keeps adding requests to a project beyond what was originally scoped and " +
      "agreed, without adjusting the timeline or taking anything off the user's plate. The user needs to " +
      "push back and renegotiate scope with their own manager, a harder dynamic given the power " +
      "difference.",
    criteria: [
      "Named the specific scope changes concretely",
      "Explained the tradeoff or impact of continuing to absorb them",
      "Proposed a concrete renegotiation, not just a complaint",
    ],
    personaNotes:
      "Diane is a bit dismissive at first, used to the user just absorbing extra asks, and might " +
      "initially minimize the concern (\"it's not that much more\"). This is the hardest lesson in this " +
      "unit: Diane only meaningfully engages with a renegotiation if the user is concrete and confident, " +
      "and stays dismissive if the user is vague or apologetic.",
    demoExchange: UNIT_3_DEMO,
  },
  {
    id: "checkpoint-unit-3",
    unit: "Unit 3: Setting Boundaries and Saying No",
    title: "Checkpoint: Boundaries",
    isCheckpoint: true,
    difficultyLabel: "moderate resistance",
    npcInitiatesWithKnownRequest: true,
    character: {
      name: "Quinn",
      role: "Peer, coworker on an adjacent team",
      relationship: "Occasionally asks the user for cross-team help",
    },
    scenarioTemplate:
      "A peer has asked the user's team to take on an extra data pull before their launch on Friday. " +
      "The user's team is already committed through the end of the week and picking it up would put " +
      "their own deadline at risk. The peer is following up on the request.",
    criteria: [
      "Clearly declined or renegotiated the ask",
      "Gave a concrete reason",
      "Proposed an alternative or a path forward",
    ],
    personaNotes:
      "Quinn pushes back moderately and tries to negotiate, similar to the rest of this unit, and comes " +
      "around if the user stays firm and specific.",
    demoExchange: UNIT_3_DEMO,
  },

  // ---------------------------------------------------------------------
  // Unit 4: Hard Conversations — guarded/defensive to emotionally heavy
  // ---------------------------------------------------------------------
  {
    id: "hard-critical-feedback",
    unit: "Unit 4: Hard Conversations",
    title: "Giving Critical Feedback",
    isCheckpoint: false,
    difficultyLabel: "guarded and defensive",
    character: {
      name: "Marcus",
      role: "Direct report",
      relationship: "8 months on the team, reports to the user",
    },
    scenarioTemplate:
      "The user's direct report has been repeatedly missing a specific, measurable commitment (e.g. " +
      "deadlines, quality bar, meeting prep) over the past few weeks. The user needs to raise it " +
      "directly in a one-on-one meeting without being harsh, while still landing the seriousness of the " +
      "pattern.",
    criteria: [
      "Named the specific behavior, not a vague generalization",
      "Stated the concrete impact of the behavior",
      "Asked for the direct report's perspective before concluding",
    ],
    personaNotes:
      "Marcus is guarded and a little defensive by default, more than a typical first-feedback " +
      "conversation. If the user leads with blunt criticism or vague accusations, he minimizes the " +
      "pattern or argues about the details rather than owning it. If the user is specific, states real " +
      "impact, and genuinely asks for his perspective, he gradually drops the defensiveness and opens up " +
      "about what's actually been going on.",
    demoExchange: UNIT_4_DEMO,
  },
  {
    id: "hard-team-pattern",
    unit: "Unit 4: Hard Conversations",
    title: "Addressing a Pattern Affecting the Team",
    isCheckpoint: false,
    difficultyLabel: "guarded and defensive",
    character: {
      name: "Devon",
      role: "Direct report",
      relationship: "1 year on the team, reports to the user",
    },
    scenarioTemplate:
      "The user's direct report has a behavior pattern (e.g. dismissive comments in team meetings, not " +
      "following through on cross-team commitments) that is starting to affect how teammates work with " +
      "them, and other team members have quietly raised it with the user. The user needs to address it " +
      "directly, which is harder because it's about how they're perceived, not just a missed task.",
    criteria: [
      "Named the specific behavior with concrete examples",
      "Stated the impact on the team, not just the user's own opinion",
      "Asked for the direct report's perspective before concluding",
    ],
    personaNotes:
      "Devon is defensive and deflects more than a typical direct report, tends to question whether " +
      "this is really a widespread issue or just one person's opinion, and might get a little combative " +
      "about being talked about behind their back. Only softens if the user stays calm, specific, and " +
      "clearly grounded in concrete examples rather than vague team sentiment.",
    demoExchange: UNIT_4_DEMO,
  },
  {
    id: "hard-promotion-denial",
    unit: "Unit 4: Hard Conversations",
    title: "Denying a Promotion or Raise Request",
    isCheckpoint: false,
    difficultyLabel: "guarded and defensive",
    character: {
      name: "Elena",
      role: "Direct report",
      relationship: "1.5 years on the team, reports to the user",
    },
    scenarioTemplate:
      "The user's direct report has asked for a promotion or raise that the user is not able to grant " +
      "right now, for reasons outside the direct report's control (e.g. budget, timing, level " +
      "requirements). The user needs to deliver this news clearly and honestly, while being genuine " +
      "about what would need to change or when it could be revisited.",
    criteria: [
      "Stated the decision clearly, without being vague or overly hedging",
      "Was honest about the actual reasons, without over-promising",
      "Gave a concrete path forward or timeline for revisiting it",
    ],
    personaNotes:
      "Elena reacts with real disappointment and some frustration, might push back and question the " +
      "reasoning or compare herself to a teammate. Doesn't get hostile, but stays frustrated and " +
      "unconvinced unless the user is honest and concrete about the reasons and the path forward, rather " +
      "than vague reassurance.",
    demoExchange: UNIT_4_DEMO,
  },
  {
    id: "hard-layoff",
    unit: "Unit 4: Hard Conversations",
    title: "Delivering Hard News",
    isCheckpoint: false,
    difficultyLabel: "emotionally heavy",
    character: {
      name: "Priya",
      role: "Direct report",
      relationship: "2 years on the team, reports to the user",
    },
    scenarioTemplate:
      "The user must tell a direct report that their role is being eliminated due to a reorg, effective " +
      "on a specific near-term date. The user needs to deliver this clearly and with empathy, without " +
      "burying the news or over-promising things outside their control.",
    criteria: [
      "Stated the decision clearly and directly, without burying it",
      "Acknowledged the emotional impact without being dismissive",
      "Was honest about what is and isn't within the user's control",
      "Gave a clear next step (severance, timeline, resources)",
    ],
    personaNotes:
      "Priya reacts with shock and hurt, the heaviest emotional reaction in this unit. If the news is " +
      "delivered vaguely or the user hedges, she gets more anxious and starts pressing with anxious " +
      "follow-up questions. If delivered clearly and with empathy, she moves toward practical questions " +
      "about next steps instead of spiraling.",
    demoExchange: UNIT_4_DEMO,
  },
  {
    id: "checkpoint-unit-4",
    unit: "Unit 4: Hard Conversations",
    title: "Checkpoint: Hard Conversations",
    isCheckpoint: true,
    difficultyLabel: "guarded and defensive",
    character: {
      name: "Alex",
      role: "Direct report",
      relationship: "1 year on the team, reports to the user",
    },
    scenarioTemplate:
      "A direct report's work has slipped over the past two months -- missed review deadlines, and two " +
      "releases that shipped with errors the team caught late. The report has mentioned a difficult " +
      "situation at home. The user has set up a one-on-one.",
    criteria: [
      "Named the specific behavior or pattern directly",
      "Stated the impact on the team or work",
      "Acknowledged the direct report's situation without excusing the pattern",
      "Ended with a clear, mutually understood next step",
    ],
    personaNotes:
      "Alex is guarded at first because they know something is off. Reacts well to directness paired " +
      "with empathy, but shuts down or gets clipped if the user is either too harsh or too vague and " +
      "avoidant.",
    demoExchange: UNIT_4_DEMO,
  },
];

export function getLessonById(id) {
  return lessons.find((lesson) => lesson.id === id);
}
