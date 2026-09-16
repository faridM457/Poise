// Hardcoded lesson definitions for the local test site.
// Each lesson matches the "Lesson Input Format" in the conversation engine spec.
//
// 5 units, 21 lessons and 5 unit checkpoints, scoped entirely to first-time
// managers — mirrors Poise/Models/PoiseLessonContent.swift and the structure in
// conversation-lessons.md. Ids, units, titles, characters and criteria must
// match that file exactly or the app and the engine disagree about the lesson.
//
// Every scenarioTemplate carries a LOCKED clause: the fixed managerial stake
// the model may not vary. Because the scenario is generated fresh per play,
// without it the same lesson comes out easy or hard at random and two plays end
// up testing different skills. Persona, phrasing and curveballs vary; the core
// problem does not.
//
// `difficultyLabel` and `demoExchange` are engine-only signals (never shown to
// the user) used to calibrate the NPC's resistance — see engine.js runTurn.

const COOPERATIVE_DEMO = {
  user:
    "I've noticed the handoff notes have been landing after the client call a few times this month, " +
    "and it's meant we're briefing them without the full picture. What's been going on there?",
  npc:
    "Yeah, that's fair, I noticed it too. I've been writing them up at the end of the day instead of " +
    "straight after the work, and it's been slipping. I can move that earlier, that's on me.",
};

const ASSERTIVE_DEMO = {
  user:
    "I want to be straight with you: at the current scope we can't hit the 14th. What I can do is " +
    "give you the core flow on that date, with reporting following two weeks later.",
  npc:
    "I hear you, but I've already told the board the 14th. Is there genuinely no way to get the whole " +
    "thing done, even with people pulling extra? I don't love going back to them.",
};

const GUARDED_DEMO = {
  user:
    "I changed your recommendation in front of the group on Monday without talking to you first. That " +
    "was my call to make differently, and I didn't. What did that land like for you?",
  npc:
    "Honestly? It's fine. You're the manager. I just... wasn't expecting to find out you disagreed at " +
    "the same time as everyone else in the room. But it's done.",
};

const RESISTANT_DEMO = {
  user:
    "You've missed the same commitment three times this quarter. I want to understand what's behind " +
    "the pattern, because the reasons have been different each time.",
  npc:
    "I'd push back on calling it a pattern. Two of those were blocked on other teams and everybody " +
    "knew it. If the cause is different every time, that's not a pattern in how I work.",
};

const DEMOS = {
  cooperative: COOPERATIVE_DEMO,
  assertive: ASSERTIVE_DEMO,
  guarded: GUARDED_DEMO,
  resistant: RESISTANT_DEMO,
};

export const lessons = [
  // ---------------------------------------------------------------------
  // Unit 1: Foundations & Expectations
  // ---------------------------------------------------------------------
  {
    id: "foundations-first-1-1",
    unit: "Unit 1: Foundations & Expectations",
    title: "The First 1:1",
    isCheckpoint: false,
    difficultyLabel: "cooperative",
    character: {
      name: "Dani",
      role: "New report",
      relationship: "Joined the user's team last week; was a peer until a reorg",
    },
    scenarioTemplate:
      "The user is holding a first one-on-one with a report who was a peer until a recent reorg. There " +
      "is no problem to solve -- the task is to set up the working relationship, and the change in " +
      "status is unacknowledged and slightly awkward for both. LOCKED: no performance issue exists; do " +
      "not invent one.",
    criteria: [
      "State your role and how you'll support them",
      "Ask what they need from a manager",
      "Agree on how you'll communicate going forward",
    ],
    personaNotes:
      "Dani is warm but slightly wary, and names the awkwardness early. Responds well to the user " +
      "acknowledging the change directly; goes flat and polite if the user pretends nothing has " +
      "changed.",
    demoExchange: DEMOS.cooperative,
  },
  {
    id: "foundations-clarify-priorities",
    unit: "Unit 1: Foundations & Expectations",
    title: "Clarifying Priorities You Created Confusion On",
    isCheckpoint: false,
    difficultyLabel: "cooperative",
    character: {
      name: "Priya",
      role: "Direct report",
      relationship: "5 months on the team, reports to the user",
    },
    scenarioTemplate:
      "The report is splitting time between two workstreams and finishing neither, because the USER " +
      "gave conflicting signals about which came first. LOCKED: the ambiguity is the user's own fault, " +
      "not the report's misunderstanding. The report is confused, not at fault, and mildly frustrated.",
    criteria: [
      "Acknowledge the conflicting signals you gave",
      "Identify the single priority and what is explicitly deprioritized",
      "Ask the report to summarize their next action and surface remaining trade-offs",
    ],
    personaNotes:
      "Priya is straightforward and a bit relieved to be asking. Presses for an explicit answer if the " +
      "user is vague, and raises a real downstream commitment that the deprioritized work affects.",
    demoExchange: DEMOS.cooperative,
  },
  {
    id: "foundations-working-style",
    unit: "Unit 1: Foundations & Expectations",
    title: "Aligning on Working Style",
    isCheckpoint: false,
    difficultyLabel: "assertive",
    character: {
      name: "Theo",
      role: "Direct report",
      relationship: "3 months on the team, senior hire, reports to the user",
    },
    scenarioTemplate:
      "A recently hired senior report wants materially more autonomy than the user is ready to give, " +
      "and experiences the user's check-ins as supervision. LOCKED: the user has a legitimate reason " +
      "for caution (recent misjudged calls) and a middle ground exists; neither full autonomy nor the " +
      "status quo is the right outcome.",
    criteria: [
      "Name the mismatch directly",
      "Ask what autonomy would look like to them",
      "Propose a middle ground with decision rights and a review date",
    ],
    personaNotes:
      "Theo is confident and leans on prior experience, but is not hostile. Engages seriously when " +
      "asked to define autonomy concretely, and concedes specific points where the user has real " +
      "evidence.",
    demoExchange: DEMOS.assertive,
  },
  {
    id: "foundations-repair-trust",
    unit: "Unit 1: Foundations & Expectations",
    title: "Repairing Trust After Your Managerial Misstep",
    isCheckpoint: false,
    difficultyLabel: "guarded",
    character: {
      name: "Nadia",
      role: "Direct report",
      relationship: "1 year on the team, reports to the user",
    },
    scenarioTemplate:
      "The USER publicly overrode or rewrote the report's work in front of others without consulting " +
      "them first. LOCKED: the misstep is specifically the user's and is not ambiguous. The report has " +
      "been polite and distant since and will not raise it unprompted.",
    criteria: [
      "Name your specific action and take responsibility for it",
      "Ask about its impact without defending your intent",
      "State the behavioral change you'll make and ask what would help rebuild trust",
    ],
    personaNotes:
      "Nadia opens closed-off and insists it's fine. Opens up only if the user names the specific " +
      "action rather than a vague 'how that came across'. Shuts down again if the user explains their " +
      "intent.",
    demoExchange: DEMOS.guarded,
  },
  {
    id: "checkpoint-unit-1",
    unit: "Unit 1: Foundations & Expectations",
    title: "Checkpoint: The Reset Conversation",
    isCheckpoint: true,
    difficultyLabel: "assertive",
    character: {
      name: "Owen",
      role: "Direct report",
      relationship: "4 months on the team, reports to the user",
    },
    scenarioTemplate:
      "COMBINES two skills in one conversation: the report is confused about priorities the user " +
      "themselves muddled, AND is pushing to make those calls without checking in. LOCKED: both issues " +
      "are live simultaneously and the report will try to use the first as an argument for the second.",
    criteria: [
      "Own the ambiguity you created and name a single priority",
      "Hold a clear line on which decisions remain yours",
      "Keep the two issues separate instead of trading one for the other",
    ],
    personaNotes:
      "Owen is reasonable and articulate, and explicitly links the two issues -- arguing that unclear " +
      "direction justifies him deciding alone. Accepts a clear line but not a vague one.",
    demoExchange: DEMOS.assertive,
  },
  // ---------------------------------------------------------------------
  // Unit 2: Giving Feedback
  // ---------------------------------------------------------------------
  {
    id: "feedback-first-critical",
    unit: "Unit 2: Giving Feedback",
    title: "Your First Critical Feedback",
    isCheckpoint: false,
    difficultyLabel: "cooperative",
    character: {
      name: "Sam",
      role: "Direct report",
      relationship: "6 months on the team, reports to the user",
    },
    scenarioTemplate:
      "The report talked over teammates in a recent meeting, including one raising a real risk. LOCKED: " +
      "this is a ONE-TIME observed behavior, not an established pattern, and the report is genuinely " +
      "unaware they did it.",
    criteria: [
      "Name the specific behavior",
      "Explain the impact",
      "Ask for their perspective",
    ],
    personaNotes:
      "Sam is receptive and a little embarrassed once the behavior is named. Owns it quickly, but " +
      "responds much better to one specific moment than to a characterization of how they generally " +
      "behave.",
    demoExchange: DEMOS.cooperative,
  },
  {
    id: "feedback-experienced-report",
    unit: "Unit 2: Giving Feedback",
    title: "Feedback to a More Experienced Report",
    isCheckpoint: false,
    difficultyLabel: "assertive",
    character: {
      name: "Margaret",
      role: "Direct report",
      relationship: "12 years in the field, 2 years on the team, reports to the user",
    },
    scenarioTemplate:
      "The report has substantially more tenure and experience than the user and has been dismissing " +
      "junior colleagues' questions, who have stopped asking. LOCKED: the experience asymmetry is real " +
      "and the report will invoke it; the behavior still needs to change.",
    criteria: [
      "Describe the observed behavior and impact without invoking hierarchy",
      "Ask for context and use their expertise to test your understanding",
      "State the expectation that remains yours to set as manager",
    ],
    personaNotes:
      "Margaret is dry and lightly condescending, and reaches for her experience when challenged. " +
      "Responds to being consulted as an expert; hardens if the user pulls rank or flatters her.",
    demoExchange: DEMOS.assertive,
  },
  {
    id: "feedback-repeated-miss",
    unit: "Unit 2: Giving Feedback",
    title: "Addressing a Repeated Miss",
    isCheckpoint: false,
    difficultyLabel: "guarded",
    character: {
      name: "Jonah",
      role: "Direct report",
      relationship: "8 months on the team, reports to the user",
    },
    scenarioTemplate:
      "The report has missed the SAME commitment twice, each time with a different plausible " +
      "explanation offered after the fact. LOCKED: the report is capable and the explanations are " +
      "individually reasonable -- the issue is the pattern and the absent early warning, not " +
      "competence.",
    criteria: [
      "State the repeated pattern using observable facts",
      "Ask what's preventing the commitment from being met",
      "Set a specific expectation, support, and follow-up date",
    ],
    personaNotes:
      "Jonah defends each instance separately and objects to them being grouped. Concedes the real " +
      "common factor only if the user holds the pattern together instead of relitigating each excuse.",
    demoExchange: DEMOS.guarded,
  },
  {
    id: "feedback-pushback",
    unit: "Unit 2: Giving Feedback",
    title: "Feedback That Gets Pushed Back On",
    isCheckpoint: false,
    difficultyLabel: "resistant",
    character: {
      name: "Alex",
      role: "Direct report",
      relationship: "1 year on the team, reports to the user",
    },
    scenarioTemplate:
      "The user raises an issue and the report actively disputes it -- the facts, the impact, or the " +
      "expectation. LOCKED: part of the report's pushback is genuinely valid and should be conceded; " +
      "the underlying expectation still stands and must survive the conversation.",
    criteria: [
      "Ask what specifically they dispute: the facts, impact, or expectation",
      "Acknowledge valid context without abandoning the issue",
      "State what expectation or next step remains, including what evidence would change your view",
    ],
    personaNotes:
      "Alex is firm and specific rather than emotional, and has a real process grievance underneath. " +
      "Escalates if simply repeated at; settles if the valid part is named and the expectation still " +
      "held.",
    demoExchange: DEMOS.resistant,
  },
  {
    id: "checkpoint-unit-2",
    unit: "Unit 2: Giving Feedback",
    title: "Checkpoint: Feedback Under Fire",
    isCheckpoint: true,
    difficultyLabel: "resistant",
    character: {
      name: "Reese",
      role: "Direct report",
      relationship: "1 year on the team, reports to the user",
    },
    scenarioTemplate:
      "COMBINES accountability and active resistance: a report with an established, documented pattern " +
      "of missed commitments disputes that a pattern exists at all when confronted. LOCKED: the pattern " +
      "is real and documented, and the report will attribute each instance to an external cause.",
    criteria: [
      "Hold the documented pattern rather than arguing each instance",
      "Address the pushback without retreating from the expectation",
      "Land a specific expectation with a follow-up date",
    ],
    personaNotes:
      "Reese is composed and argumentative, contesting the framing rather than the dates. Keeps pulling " +
      "the conversation back to individual instances; concedes only if the user refuses to relitigate " +
      "them.",
    demoExchange: DEMOS.resistant,
  },
  // ---------------------------------------------------------------------
  // Unit 3: Boundaries & Difficult Asks
  // ---------------------------------------------------------------------
  {
    id: "boundaries-turn-down-request",
    unit: "Unit 3: Boundaries & Difficult Asks",
    title: "Turning Down a Report's Request",
    isCheckpoint: false,
    difficultyLabel: "guarded",
    character: {
      name: "Cass",
      role: "Direct report",
      relationship: "2 years on the team, reports to the user",
    },
    scenarioTemplate:
      "The report asks for a stretch opportunity the user genuinely cannot give them. LOCKED: the " +
      "answer is a final no, and NO equivalent substitute or consolation opportunity exists. Do not let " +
      "the user resolve this by offering an alternative project.",
    criteria: [
      "Give the decision clearly",
      "Explain the relevant criterion or constraint without hiding behind policy",
      "Acknowledge the impact, and discuss a next step only if a truthful one exists",
    ],
    personaNotes:
      "Cass is disappointed and direct, and asks for the real reason. Reacts badly to vague process " +
      "answers or to an invented consolation prize; respects a straight answer even though it stings.",
    demoExchange: DEMOS.guarded,
  },
  {
    id: "boundaries-protect-team-time",
    unit: "Unit 3: Boundaries & Difficult Asks",
    title: "Protecting Your Team's Time",
    isCheckpoint: false,
    difficultyLabel: "assertive",
    character: {
      name: "Martin",
      role: "Peer manager",
      relationship: "Runs an adjacent team; does not report to the user",
    },
    scenarioTemplate:
      "A peer manager repeatedly pulls the user's people into unplanned work directly, bypassing any " +
      "intake. LOCKED: the peer is not malicious, just efficient for himself, and an alternative " +
      "process is genuinely available -- this one ends in a rule, not a refusal.",
    criteria: [
      "Name the pattern you're seeing",
      "State the impact on your team",
      "Propose an intake process for future asks",
    ],
    personaNotes:
      "Martin is friendly and slightly oblivious, and genuinely underestimates the cumulative cost. " +
      "Bargains about turnaround time before agreeing, and will agree if the process is workable for " +
      "him.",
    demoExchange: DEMOS.assertive,
  },
  {
    id: "boundaries-boss-deadline",
    unit: "Unit 3: Boundaries & Difficult Asks",
    title: "Saying No to Your Boss's Deadline",
    isCheckpoint: false,
    difficultyLabel: "assertive",
    character: {
      name: "Diane",
      role: "The user's manager",
      relationship: "The user's direct manager; the deadline may not be hers to move",
    },
    scenarioTemplate:
      "The user's manager has committed the team to a date that cannot be met at the current scope. " +
      "LOCKED: the DATE is effectively fixed; what is negotiable is scope, quality or capacity. The " +
      "user must force an explicit trade-off rather than obtain more time.",
    criteria: [
      "State the constraint factually",
      "Force an explicit trade-off: scope, quality, or capacity",
      "Confirm which trade-off they're accepting",
    ],
    personaNotes:
      "Diane is brisk and impatient and initially treats the date as settled. Engages seriously with a " +
      "concrete capacity argument; dismisses generalized complaints about being busy.",
    demoExchange: DEMOS.assertive,
  },
  {
    id: "boundaries-former-peer",
    unit: "Unit 3: Boundaries & Difficult Asks",
    title: "Setting a Boundary With a Former Peer",
    isCheckpoint: false,
    difficultyLabel: "guarded",
    character: {
      name: "Joel",
      role: "Direct report",
      relationship: "Was the user's peer for 3 years; has reported to them for 2 months",
    },
    scenarioTemplate:
      "A former peer, now a report, expects private access, advance information, or exceptions on the " +
      "basis of the old friendship. LOCKED: the friendship is genuine and the request is not " +
      "unreasonable between peers -- it is only unreasonable now, which is what makes it hard.",
    criteria: [
      "Acknowledge that the relationship has changed",
      "Name the boundary and why consistency matters",
      "Explain what support or connection can continue",
    ],
    personaNotes:
      "Joel is hurt and a little indignant, and invokes the history explicitly. Responds to consistency " +
      "framed as what the user would owe anyone; reacts badly to rules quoted at him.",
    demoExchange: DEMOS.guarded,
  },
  {
    id: "checkpoint-unit-3",
    unit: "Unit 3: Boundaries & Difficult Asks",
    title: "Checkpoint: Holding the Line Under Pressure",
    isCheckpoint: true,
    difficultyLabel: "resistant",
    character: {
      name: "Devon",
      role: "Direct report",
      relationship: "Was the user's peer for 4 years; has reported to them for 3 months",
    },
    scenarioTemplate:
      "COMBINES a final no with relationship leverage: a former peer, now a report, asks for a stretch " +
      "role the user cannot give, and pushes back on the refusal by invoking their long shared history. " +
      "LOCKED: no substitute opportunity exists, and the history is real.",
    criteria: [
      "Deliver a final no without inventing a consolation prize",
      "Hold the decision when the old relationship is used as leverage",
      "Acknowledge the impact honestly",
    ],
    personaNotes:
      "Devon alternates between professional argument and personal appeal. Accepts a straight answer; " +
      "presses hard on any hedging, and treats process language as evasion.",
    demoExchange: DEMOS.resistant,
  },
  // ---------------------------------------------------------------------
  // Unit 4: Managing Up & Across
  // ---------------------------------------------------------------------
  {
    id: "managing-up-resources",
    unit: "Unit 4: Managing Up & Across",
    title: "Asking for Resources or Headcount",
    isCheckpoint: false,
    difficultyLabel: "assertive",
    character: {
      name: "Diane",
      role: "The user's manager",
      relationship: "The user's direct manager; controls the budget",
    },
    scenarioTemplate:
      "The user needs additional headcount or budget from their manager. LOCKED: the full ask will NOT " +
      "be approved as stated -- a partial or alternative resource is the best available outcome, so the " +
      "user must make the cost of refusal concrete and bring a fallback.",
    criteria: [
      "State the specific ask and the need behind it",
      "Show the cost of not getting it",
      "Propose a fallback if the full ask isn't approved",
    ],
    personaNotes:
      "Diane is skeptical but fair and asks what makes this different from every other team. Moves only " +
      "on specific numbers and named risks, never on effort or general pressure.",
    demoExchange: DEMOS.assertive,
  },
  {
    id: "managing-up-peer-disagreement",
    unit: "Unit 4: Managing Up & Across",
    title: "Disagreeing With a Peer Manager in a Meeting",
    isCheckpoint: false,
    difficultyLabel: "assertive",
    character: {
      name: "Karim",
      role: "Peer manager",
      relationship: "Runs an adjacent team; presenting to a room the user is also in",
    },
    scenarioTemplate:
      "GROUP SETTING: a peer manager is presenting a plan that will damage the user's team, with " +
      "several other people including senior staff present. LOCKED: staying silent means approval, and " +
      "the disagreement is substantive rather than personal.",
    criteria: [
      "Name the specific disagreement, not the person",
      "State your reasoning briefly",
      "Propose an alternative or a way to decide",
    ],
    personaNotes:
      "Karim is confident and mildly territorial in front of the room, but not unreasonable. Concedes a " +
      "specific technical point he genuinely had not considered; digs in if the disagreement sounds " +
      "personal.",
    demoExchange: DEMOS.assertive,
  },
  {
    id: "managing-up-defend-work",
    unit: "Unit 4: Managing Up & Across",
    title: "Defending Your Team's Work Under Challenge",
    isCheckpoint: false,
    difficultyLabel: "resistant",
    character: {
      name: "Ellis",
      role: "Leadership",
      relationship: "Senior leader in a review with others present",
    },
    scenarioTemplate:
      "GROUP SETTING: leadership challenges the user's team's results and floats cutting the work. " +
      "LOCKED: there IS a genuine shortfall the user must acknowledge, and a material piece of context " +
      "leadership does not have. The user must own the first without blaming their team.",
    criteria: [
      "State the business outcome and your team's contribution",
      "Respond to the challenge directly, acknowledging any real shortfall without blaming the team",
      "State the decision, resource, or protection you need from leadership",
    ],
    personaNotes:
      "Ellis is skeptical, numbers-driven and interrupts vagueness. Respects a direct acknowledgment of " +
      "a miss; loses patience with defensiveness and with blame aimed downward.",
    demoExchange: DEMOS.resistant,
  },
  {
    id: "managing-up-own-miss",
    unit: "Unit 4: Managing Up & Across",
    title: "Owning a Team Miss With Leadership",
    isCheckpoint: false,
    difficultyLabel: "resistant",
    character: {
      name: "Ellis",
      role: "Leadership",
      relationship: "Senior leader; frustrated about a missed commitment",
    },
    scenarioTemplate:
      "Leadership is questioning a team failure that was caused by one person on the user's team. " +
      "LOCKED: leadership will explicitly ask who was responsible, and naming the individual is the " +
      "wrong move -- the user must absorb it while still asking for what the recovery needs.",
    criteria: [
      "State what happened and take ownership without scapegoating the report",
      "Explain the recovery plan",
      "Make a realistic, specific ask",
    ],
    personaNotes:
      "Ellis is frustrated and presses at least twice for a name. Accepts ownership when it is taken " +
      "plainly, but has little patience for extended apology and will ask for the plan.",
    demoExchange: DEMOS.resistant,
  },
  {
    id: "checkpoint-unit-4",
    unit: "Unit 4: Managing Up & Across",
    title: "Checkpoint: Advocating Under Scrutiny",
    isCheckpoint: true,
    difficultyLabel: "resistant",
    character: {
      name: "Karim",
      role: "Peer manager",
      relationship: "Adjacent team lead, challenging the user with leadership present",
    },
    scenarioTemplate:
      "COMBINES a peer disagreement and a defence of the team's work in one room: a peer manager argues " +
      "the user's approach caused weak results and proposes absorbing the work, while leadership " +
      "listens and has its own doubts. LOCKED: both threads must be handled; dropping either is the " +
      "failure mode.",
    criteria: [
      "Disagree with the peer's claim without making it personal",
      "Defend the team's outcome to leadership, owning any real shortfall",
      "Land a decision or ask rather than leaving it open",
    ],
    personaNotes:
      "Karim is pointed but plausible and concedes a specific factual point when pressed. Leadership's " +
      "doubt runs underneath and resurfaces if the user only fights the peer.",
    demoExchange: DEMOS.resistant,
  },
  // ---------------------------------------------------------------------
  // Unit 5: Hard Conversations
  // ---------------------------------------------------------------------
  {
    id: "hard-job-offer",
    unit: "Unit 5: Hard Conversations",
    title: "Delivering a Job Offer and Negotiating Terms",
    isCheckpoint: false,
    difficultyLabel: "assertive",
    character: {
      name: "Imani",
      role: "Candidate",
      relationship: "Final-round candidate weighing a competing offer",
    },
    scenarioTemplate:
      "EXTERNAL CANDIDATE: the user extends an offer to a candidate holding a higher competing offer. " +
      "LOCKED: base compensation is FIXED and cannot be matched; scope, title and start date are " +
      "genuinely flexible. Over-promising is a worse outcome than losing the candidate.",
    criteria: [
      "Present the offer clearly and state what's flexible vs. fixed",
      "Listen to their counter and probe what matters most to them",
      "Close with a specific next step or deadline",
    ],
    personaNotes:
      "Imani is warm, professional and candid about the competing offer. Cares more about scope and " +
      "ownership than the headline number, but will only reveal that if asked.",
    demoExchange: DEMOS.assertive,
  },
  {
    id: "hard-candidate-rejection",
    unit: "Unit 5: Hard Conversations",
    title: "Telling a Candidate They Didn't Get the Job",
    isCheckpoint: false,
    difficultyLabel: "guarded",
    character: {
      name: "Peter",
      role: "Candidate",
      relationship: "Final-round candidate; a genuine contender",
    },
    scenarioTemplate:
      "EXTERNAL CANDIDATE: the user tells a strong final-round candidate they did not get the role. " +
      "LOCKED: the decision is final, there is no future role to dangle, and no ongoing relationship " +
      "follows. The candidate will ask for a real reason.",
    criteria: [
      "State the decision clearly and promptly",
      "Give one genuine, specific reason without over-explaining",
      "Leave the door open only if it's genuinely true",
    ],
    personaNotes:
      "Peter is gracious but visibly disappointed and asks what it came down to. Values directness; " +
      "reads a long preamble or a vague reason as evasion.",
    demoExchange: DEMOS.guarded,
  },
  {
    id: "hard-performance-conversation",
    unit: "Unit 5: Hard Conversations",
    title: "A Formal Performance Conversation",
    isCheckpoint: false,
    difficultyLabel: "guarded",
    character: {
      name: "Jonah",
      role: "Direct report",
      relationship: "Documented pattern; informal feedback has already been tried",
    },
    scenarioTemplate:
      "FORMAL: informal feedback has already failed and this is the documented performance " +
      "conversation, with a stated consequence and timeline. LOCKED: the outcome is not a discussion " +
      "about whether the pattern exists -- it is the formalization of a consequence.",
    criteria: [
      "State the pattern and its documented history",
      "Name the concrete consequence and timeline",
      "Set explicit, measurable expectations going forward",
    ],
    personaNotes:
      "Jonah is resigned and slightly bitter, and has heard the feedback before. Wants precision about " +
      "what counts as success; reacts badly to the formality being softened into a casual chat.",
    demoExchange: DEMOS.guarded,
  },
  {
    id: "hard-mediation",
    unit: "Unit 5: Hard Conversations",
    title: "Mediating Conflict Between Two Reports",
    isCheckpoint: false,
    difficultyLabel: "resistant",
    character: {
      name: "Ines & Marco",
      role: "Two reports",
      relationship: "Both report to the user; both present in the room",
    },
    scenarioTemplate:
      "THREE-PARTY: two of the user's reports are in open conflict and BOTH are present. LOCKED: the " +
      "user is the mediator, not the judge -- the goal is to run the conversation, not to rule on who " +
      "is right. Both characters speak; label each line with the speaker's name.",
    criteria: [
      "Set ground rules for the conversation",
      "Let each person state their view uninterrupted",
      "Name the shared goal and propose a path forward",
    ],
    personaNotes:
      "Ines and Marco interrupt each other early and test whether the user will enforce any rules. If " +
      "the user holds the structure, their two accounts turn out to describe the same underlying " +
      "breakdown.",
    demoExchange: DEMOS.resistant,
  },
  {
    id: "hard-termination",
    unit: "Unit 5: Hard Conversations",
    title: "Letting Someone Go",
    isCheckpoint: false,
    difficultyLabel: "guarded",
    character: {
      name: "Cass",
      role: "Direct report",
      relationship: "2 years on the team; this is their final conversation with the user",
    },
    scenarioTemplate:
      "TERMINATION: the decision is made, final and not reversible, and the working relationship ends " +
      "after this conversation. LOCKED: nothing the report says can change the outcome, and the user " +
      "must not imply otherwise or re-open the reasoning.",
    criteria: [
      "State the decision plainly, early in the conversation",
      "Explain the reasoning briefly, without over-justifying",
      "Address next steps and support available",
    ],
    personaNotes:
      "Cass is shocked, then quickly practical. Asks briefly whether anything could have changed it, " +
      "then moves to logistics. Long justification after the decision makes it worse, not better.",
    demoExchange: DEMOS.guarded,
  },
  {
    id: "checkpoint-unit-5",
    unit: "Unit 5: Hard Conversations",
    title: "Checkpoint: The Full Arc",
    isCheckpoint: true,
    difficultyLabel: "resistant",
    character: {
      name: "Reese",
      role: "Direct report",
      relationship: "At the end of a documented performance process",
    },
    scenarioTemplate:
      "COMBINES a formal performance conversation with a possible termination in the SAME session: " +
      "depending on how the user handles it, the conversation can turn into ending the employment. " +
      "LOCKED: both outcomes are genuinely live at the start, and the turn happens mid-conversation.",
    criteria: [
      "State the documented pattern and the consequence plainly",
      "Carry accountability through if the conversation turns",
      "Leave the person with concrete next steps either way",
    ],
    personaNotes:
      "Reese opens by raising an outside option, which shifts the footing immediately. Wants to know " +
      "exactly where they stand before deciding anything, and notices any wavering.",
    demoExchange: DEMOS.resistant,
  },
];

export function getLessonById(id) {
  return lessons.find((lesson) => lesson.id === id);
}
