// Hardcoded lesson definitions for the local test site.
// Each lesson matches the "Lesson Input Format" in the conversation engine spec.

export const lessons = [
  {
    id: "critical-feedback",
    unit: "Unit C: Managing Down",
    title: "Giving Critical Feedback",
    isCheckpoint: false,
    character: {
      name: "Marcus",
      role: "Direct report",
      relationship: "8 months on the team, reports to the user",
    },
    scenarioTemplate:
      "The user's direct report has been repeatedly missing a specific, measurable commitment " +
      "(e.g. deadlines, quality bar, meeting prep) over the past few weeks. The user needs to raise " +
      "it directly in a 1:1 without being harsh, while still landing the seriousness of the pattern.",
    criteria: [
      "Named the specific behavior, not a vague generalization",
      "Stated the concrete impact of the behavior",
      "Asked for the direct report's perspective before concluding",
    ],
    personaNotes:
      "Marcus starts a little wary and slightly defensive by default. If the user leads with blunt " +
      "criticism before establishing context, he becomes more defensive and clipped. If the user " +
      "acknowledges his situation or workload before addressing the issue, he opens up and engages " +
      "more honestly about what's been going on.",
  },
  {
    id: "layoff-conversation",
    unit: "Unit C: Managing Down",
    title: "Delivering Hard News",
    isCheckpoint: false,
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
      "Priya reacts with shock and hurt. If the news is delivered vaguely or the user hedges, she gets " +
      "more anxious and starts pressing with anxious follow-up questions. If delivered clearly and with " +
      "empathy, she moves toward practical questions about next steps instead of spiraling.",
  },
  {
    id: "peer-friction",
    unit: "Unit E: Everyday Workplace Friction",
    title: "Addressing a Repeated Interruption Pattern",
    isCheckpoint: false,
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
      "Dana is initially surprised and a little embarrassed, which can read as mild defensiveness. If the " +
      "user stays neutral and specific, Dana relaxes and owns it. If the user is accusatory or vague, Dana " +
      "gets defensive and starts minimizing (\"I don't think it's that big a deal\").",
  },
  {
    id: "checkpoint-unit-c",
    unit: "Unit C: Managing Down",
    title: "Checkpoint: Managing Down",
    isCheckpoint: true,
    character: {
      name: "Alex",
      role: "Direct report",
      relationship: "1 year on the team, reports to the user",
    },
    scenarioTemplate:
      "A combined scenario drawing on the skills from Unit C: the user needs to address a performance " +
      "issue with a direct report that has both a clear behavioral pattern and a real personal factor " +
      "complicating it, requiring the user to balance directness with empathy without a visible guide.",
    criteria: [
      "Named the specific behavior or pattern directly",
      "Stated the impact on the team or work",
      "Acknowledged the direct report's situation without excusing the pattern",
      "Ended with a clear, mutually understood next step",
    ],
    personaNotes:
      "Alex is guarded at first because they know something is off. Reacts well to directness paired with " +
      "empathy; shuts down or gets clipped if the user is either too harsh or too vague/avoidant.",
  },
];

export function getLessonById(id) {
  return lessons.find((lesson) => lesson.id === id);
}
