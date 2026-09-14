import Foundation

// Static content for all 20 lessons across the 4 units, mirroring the real
// curriculum in conversation-engine/server/lessons.js (titles, units,
// characters, criteria). The opening line / turn replies / feedback line
// for each are hand-written mocks in the same tone as the original
// "Naming a Small Pattern" mock -- NOT live LLM generation. LiveLessonViewModel
// looks these up by id when Self.useMockDataForUITesting is true.
struct MockLessonContent {
    let id: String
    let unitNumber: Int
    let title: String
    // Shown on the Learn path node instead of `title` when the full title
    // runs too long to fit at a fixed font size in two lines -- all node
    // labels render at the same size, so long titles get a shorter phrasing
    // here rather than being shrunk to fit.
    var shortTitle: String? = nil
    let icon: String
    let isCheckpoint: Bool
    let character: EngineCharacter
    let briefing: String
    let criteria: [String]
    let openingLine: String
    let turnReplies: [String]
    let feedbackLine: String

    // Derived, not hand-set: a lesson ends when the user has taken
    // `turnReplies.count` turns (see LiveLessonViewModel), and a turn is one
    // NPC line to read plus one reply to compose -- budget about a minute
    // each, plus roughly two more for the briefing, guide and feedback
    // screens either side. All 20 lessons are currently 3 turns, so this is
    // 5 minutes across the board; it moves on its own if lessons get longer,
    // which a hand-written per-lesson number would not.
    var estimatedMinutes: Int { turnReplies.count + 2 }
}

struct MockUnitInfo {
    let label: String
    let title: String
    let subtitle: String
}

enum PoiseLessonLibrary {
    static let unitInfo: [Int: MockUnitInfo] = [
        1: MockUnitInfo(label: "Unit 1 · Giving Feedback", title: "Speak It Plainly", subtitle: "Name patterns clearly and with care"),
        2: MockUnitInfo(label: "Unit 2 · Workplace Friction", title: "Steady Under Friction", subtitle: "Address friction without escalating it"),
        3: MockUnitInfo(label: "Unit 3 · Boundaries", title: "Hold Your Line", subtitle: "Say no and renegotiate with confidence"),
        4: MockUnitInfo(label: "Unit 4 · Hard Conversations", title: "Lead With Steadiness", subtitle: "Balance directness with empathy"),
    ]

    static let all: [MockLessonContent] = [
        // MARK: - Unit 1: Giving Feedback (cooperative)
        MockLessonContent(
            id: "feedback-small-pattern",
            unitNumber: 1,
            title: "Naming a Small Pattern",
            icon: "text.bubble.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Sam", role: "Direct report", relationship: "6 months on the team, reports to the user"),
            briefing: "Sam has quietly missed two handoff details on the Meridian project this month -- nothing dramatic, but you're the one catching it each time. You've asked Sam to grab a few minutes.",
            criteria: [
                "Name a specific, observable pattern rather than a vague complaint",
                "Invite Sam's perspective before proposing a fix",
                "Agree on one concrete next step together",
            ],
            openingLine: "Hey, thanks for grabbing time -- everything okay? You mentioned wanting to talk about Meridian?",
            turnReplies: [
                "Oh -- I didn't realize that landed on you both times. I think I assumed someone else was tracking the client follow-ups.",
                "That's fair. I can set myself a reminder the day before each handoff so it stops slipping through.",
                "Okay, let's do that -- I'll send you a quick confirmation each time going forward.",
            ],
            feedbackLine: "You named the pattern clearly and gave Sam room to respond before proposing next steps -- a steady, well-paced conversation."
        ),
        MockLessonContent(
            id: "feedback-quality-slip",
            unitNumber: 1,
            title: "Following Up on a Quality Slip",
            shortTitle: "Quality Slip Follow-Up",
            icon: "text.bubble.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Riley", role: "Direct report", relationship: "4 months on the team, reports to the user"),
            briefing: "Riley's last few pieces of client-facing work have had small but repeated quality slips -- a typo here, a formatting miss there. Nothing huge on its own, but it's adding up. You've asked to talk it through.",
            criteria: [
                "Name the specific quality issue with a concrete example",
                "State why the quality bar matters here",
                "Ask what's been getting in the way before concluding",
            ],
            openingLine: "Hey, thanks for making time -- what's up?",
            turnReplies: [
                "Oh, I didn't realize it was showing up that much. I've had a lot of small things going at once, so I think I've been rushing the final pass.",
                "That makes sense. I can build in a few extra minutes to proofread before sending things out.",
                "Yeah, I'll start doing a last check against the brief before anything goes to a client.",
            ],
            feedbackLine: "You gave Riley a concrete example instead of a vague impression, and asked what was behind it before jumping to a fix -- that's what kept this collaborative instead of accusatory."
        ),
        MockLessonContent(
            id: "feedback-missed-commitment",
            unitNumber: 1,
            title: "Addressing a Missed Commitment",
            shortTitle: "A Missed Commitment",
            icon: "text.bubble.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Taylor", role: "Direct report", relationship: "7 months on the team, reports to the user"),
            briefing: "Taylor agreed to finish a specific task by Friday and didn't follow through, with no heads-up about the delay. You want to name the broken commitment, not just the missed task.",
            criteria: [
                "Name the specific commitment that was missed, not a vague generalization",
                "State the impact of the missed commitment",
                "Ask for Taylor's perspective before concluding",
            ],
            openingLine: "Hey -- got a minute? I wanted to check in about Friday's deliverable.",
            turnReplies: [
                "Yeah... I know I said I'd have it done. I got pulled into something else and just didn't say anything, which I know isn't great.",
                "You're right, I should have flagged it as soon as I knew I'd miss it, instead of letting it just go quiet.",
                "I hear you. Next time something's at risk, I'll give you a heads-up as soon as I know, not after the deadline passes.",
            ],
            feedbackLine: "You separated the missed commitment from the silence around it, and gave Taylor room to own both -- that landed the seriousness without piling on."
        ),
        MockLessonContent(
            id: "feedback-communication-style",
            unitNumber: 1,
            title: "Giving Feedback on a Communication Style",
            shortTitle: "Feedback on Communication",
            icon: "text.bubble.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Morgan", role: "Direct report", relationship: "9 months on the team, reports to the user"),
            briefing: "Morgan's written updates are technically solid but often read as terse, and a couple of teammates have had to ask for clarification. This is more subjective than a missed deadline, and you want to raise it constructively.",
            criteria: [
                "Name the specific communication pattern with a concrete example",
                "State the impact on the team, not just a personal preference",
                "Ask for Morgan's perspective before concluding",
            ],
            openingLine: "Hey, thanks for hopping on -- I wanted to talk through something about your updates, nothing alarming.",
            turnReplies: [
                "Huh, I didn't realize that -- I thought I was just being efficient by keeping things short.",
                "Okay, that's useful to know. I can add a bit more context so people aren't left guessing.",
                "Got it -- I'll try adding one or two extra lines of context on the next few updates and see how that lands.",
            ],
            feedbackLine: "You framed this as a team-impact issue rather than a personal preference, and gave Morgan a concrete example to work from -- that's exactly what kept it from feeling like nitpicking."
        ),
        MockLessonContent(
            id: "checkpoint-unit-1",
            unitNumber: 1,
            title: "Checkpoint: Giving Feedback",
            icon: "flag.checkered",
            isCheckpoint: true,
            character: EngineCharacter(name: "Jamie", role: "Direct report", relationship: "5 months on the team, reports to the user"),
            briefing: "A combined scenario for Unit 1: Jamie has a specific pattern with a plausible, sympathetic reason behind it. Name it, explain the impact, and hear Jamie out -- without a guide this time.",
            criteria: [
                "Name the specific behavior or pattern directly",
                "State the concrete impact of the behavior",
                "Ask for Jamie's perspective before concluding",
            ],
            openingLine: "Hey, thanks for meeting -- what did you want to chat about?",
            turnReplies: [
                "Oh -- I hadn't thought about it landing like that. There's been a reason behind it, but I get why it's still worth raising.",
                "That's a fair point. I can see how that's been affecting things.",
                "Okay, I'm on board -- let's figure out what I'll do differently going forward.",
            ],
            feedbackLine: "Even without a visible guide, you hit all three moves -- naming the pattern, stating its impact, and checking in with Jamie before wrapping up."
        ),

        // MARK: - Unit 2: Everyday Workplace Friction (mild resistance)
        MockLessonContent(
            id: "friction-interruptions",
            unitNumber: 2,
            title: "Addressing a Repeated Interruption Pattern",
            shortTitle: "Repeated Interruptions",
            icon: "person.2.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Dana", role: "Peer, coworker on an adjacent team", relationship: "Works closely with the user cross-functionally"),
            briefing: "Dana has a habit of talking over you in shared meetings, and it's starting to affect how you're perceived in the room. You want to raise it directly, one-on-one, without turning it into a conflict.",
            criteria: [
                "Name the specific pattern with a concrete example",
                "Stay neutral in tone instead of accusatory",
                "Propose what you'd like to happen going forward",
            ],
            openingLine: "Hey, got a sec? Wanted to mention something from this week's planning meeting.",
            turnReplies: [
                "Oh -- I didn't realize I was doing that. I guess it's just a fast-moving meeting and I jump in without thinking.",
                "Fair enough, I don't mean to talk over you, I just get excited about the topic.",
                "Okay, that's reasonable -- I'll make more of an effort to let you finish before I jump in.",
            ],
            feedbackLine: "You stayed specific and neutral instead of accusatory, which is exactly what kept Dana from getting defensive -- and you were clear about what you'd like to see change."
        ),
        MockLessonContent(
            id: "friction-missed-handoff",
            unitNumber: 2,
            title: "Pushing Back on a Missed Handoff",
            shortTitle: "A Missed Handoff",
            icon: "person.2.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Chris", role: "Peer, coworker on an adjacent team", relationship: "Shares ownership of a recurring deliverable with the user"),
            briefing: "Chris owns part of a deliverable you share, and their handoffs keep coming late or incomplete, forcing you to scramble near the deadline. You want to raise it without escalating into a bigger conflict.",
            criteria: [
                "Name the specific pattern with a concrete example",
                "State the impact on your own work",
                "Propose what you'd like to happen going forward",
            ],
            openingLine: "Hey, do you have a minute? Wanted to talk through how the last couple handoffs have gone.",
            turnReplies: [
                "Yeah, I mean, things have just been busy on my end, I didn't think it was that big a deal.",
                "I hear you, I guess I didn't realize how much it was affecting your side of things.",
                "Okay -- how about I send my part a day earlier from now on, so you've got buffer?",
            ],
            feedbackLine: "You named the pattern instead of just venting about the latest instance, and stayed specific about the impact on your own work -- that's what moved Chris from minimizing to actually proposing a fix."
        ),
        MockLessonContent(
            id: "friction-credit-issue",
            unitNumber: 2,
            title: "Raising a Credit Issue",
            icon: "person.2.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Jordan", role: "Peer, coworker on the same team", relationship: "Works alongside the user day to day"),
            briefing: "In a recent meeting, Jordan presented your analysis as their own in front of leadership, without acknowledging it. You want to raise this directly, one-on-one, without it turning into an accusation of dishonesty.",
            criteria: [
                "Name the specific incident with a concrete example",
                "Explain why it matters to you, not just that it happened",
                "Stay collaborative rather than accusatory",
            ],
            openingLine: "Hey, can I grab a few minutes? I wanted to bring something up about Tuesday's meeting.",
            turnReplies: [
                "Oh -- I wasn't trying to take credit, I just didn't think to call out who did what.",
                "I get why that would bother you, that wasn't my intention but I see how it looked.",
                "Next time I'll make sure to mention your name when I'm presenting something you put together.",
            ],
            feedbackLine: "You stayed collaborative instead of accusatory while still being clear about why it mattered to you -- that's what let Jordan actually acknowledge it instead of just getting defensive."
        ),
        MockLessonContent(
            id: "friction-passive-aggressive",
            unitNumber: 2,
            title: "Addressing Passive-Aggressive Comments",
            shortTitle: "Passive-Aggressive Comments",
            icon: "person.2.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Casey", role: "Peer, coworker on an adjacent team", relationship: "Interacts with the user regularly in group settings"),
            briefing: "Casey has made a few subtly pointed comments about your work in group settings over the last couple weeks -- nothing overt enough to call out in the moment, but it's adding up. You want to name the pattern directly, one-on-one.",
            criteria: [
                "Name the specific pattern with concrete examples, not just a feeling",
                "Explain the impact without being accusatory",
                "Invite Casey's perspective before concluding",
            ],
            openingLine: "Hey, thanks for hopping on -- I wanted to check in about something.",
            turnReplies: [
                "Hm, I don't think I meant anything by those comments, honestly. Maybe you're reading into it a bit.",
                "Okay... I guess I have been a little frustrated about some of the recent decisions, and it's probably coming out sideways.",
                "That's fair, I'll bring it to you directly instead of making comments in front of everyone else.",
            ],
            feedbackLine: "This one's tricky since each comment alone seems small, but you stayed specific and calm instead of vague or emotional -- that's what got Casey to actually own it instead of staying defensive."
        ),
        MockLessonContent(
            id: "checkpoint-unit-2",
            unitNumber: 2,
            title: "Checkpoint: Workplace Friction",
            shortTitle: "Checkpoint: Friction",
            icon: "flag.checkered",
            isCheckpoint: true,
            character: EngineCharacter(name: "Reese", role: "Peer, coworker on an adjacent team", relationship: "Works closely with the user cross-functionally"),
            briefing: "A combined scenario for Unit 2: Reese has a specific behavioral pattern with a plausible innocent explanation. Address it without a visible guide.",
            criteria: [
                "Name the specific pattern with a concrete example",
                "Stay neutral in tone instead of accusatory",
                "Propose what you'd like to happen going forward",
            ],
            openingLine: "Hey, thanks for making time -- what's on your mind?",
            turnReplies: [
                "Oh, I didn't realize that was landing that way, that wasn't the intention.",
                "That's fair, I can see why it would come across like that.",
                "Okay, let's agree on how we'll handle it differently going forward.",
            ],
            feedbackLine: "No guide this time, but you still named the pattern, stayed neutral, and proposed a clear path forward -- a solid close to this unit."
        ),

        // MARK: - Unit 3: Setting Boundaries and Saying No (moderate resistance)
        MockLessonContent(
            id: "boundaries-unreasonable-ask",
            unitNumber: 3,
            title: "Turning Down an Unreasonable Ask",
            shortTitle: "An Unreasonable Ask",
            icon: "hand.raised.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Avery", role: "Peer, coworker on an adjacent team", relationship: "Occasionally asks the user for cross-team help"),
            briefing: "Avery has asked you to take on a significant piece of extra work with an unreasonable turnaround, on top of your already full plate. You need to say no or renegotiate the scope.",
            criteria: [
                "Clearly decline or renegotiate the ask, not just express discomfort",
                "Give a concrete reason grounded in your actual workload",
                "Offer or discuss an alternative",
            ],
            openingLine: "Hey, so about that thing I asked you to help with by Friday -- were you able to look at it?",
            turnReplies: [
                "I mean, I was really counting on you for this one -- is there any way you could just fit it in?",
                "Okay... I get it, everyone's slammed. Could you at least look at part of it?",
                "Alright, let's figure out who else might have room, or push the date.",
            ],
            feedbackLine: "You gave a concrete, workload-based reason instead of just hedging, and stayed firm without being harsh -- that's what moved Avery from pushing to actually negotiating."
        ),
        MockLessonContent(
            id: "boundaries-team-time",
            unitNumber: 3,
            title: "Protecting Your Team's Time",
            icon: "hand.raised.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Drew", role: "Peer manager, leads an adjacent team", relationship: "Manages a team that frequently collaborates with the user's team"),
            briefing: "Drew keeps pulling one of your direct reports into unplanned work without checking with you first, disrupting their priorities. You need to set a boundary with Drew directly.",
            criteria: [
                "Name the specific pattern with a concrete example",
                "State why it's a problem for your team's priorities",
                "Propose a clear process for future requests",
            ],
            openingLine: "Hey, got a minute? Wanted to talk about how we coordinate on cross-team asks.",
            turnReplies: [
                "I mean, my team's priorities are pretty urgent too -- I didn't think it was a big deal to pull them in directly.",
                "Okay, I hear that it's been disruptive on your side.",
                "Sure, let's set up a quick check-in with me before pulling anyone directly -- that works.",
            ],
            feedbackLine: "You stayed firm and specific instead of just venting about the disruption, which is what got Drew to agree to an actual process instead of staying dismissive."
        ),
        MockLessonContent(
            id: "boundaries-repeat-favor",
            unitNumber: 3,
            title: "Saying No to a Repeat Favor",
            icon: "hand.raised.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Skyler", role: "Peer, coworker on the same team", relationship: "Has leaned on the user for help several times before"),
            briefing: "Skyler has repeatedly asked for help with tasks outside your role, and it's become a pattern eating into your own work. You need to say no to the pattern, not just the latest ask.",
            criteria: [
                "Name the pattern, not just the one-off request",
                "Be clear about what you will and won't keep doing",
                "Acknowledge the relationship while holding the boundary",
            ],
            openingLine: "Hey, thanks for hopping on -- I wanted to talk about something before it comes up again.",
            turnReplies: [
                "Oh... I didn't realize it had become a pattern, I thought it had just been a one-off each time.",
                "That stings a little, I thought you didn't mind helping out.",
                "Okay, I get it. I'll try to find another way to handle these instead of leaning on you.",
            ],
            feedbackLine: "You acknowledged the relationship while still holding the line on the pattern -- that warmth-plus-firmness combo is what kept Skyler from feeling dismissed."
        ),
        MockLessonContent(
            id: "boundaries-scope-creep",
            unitNumber: 3,
            title: "Pushing Back on Scope Creep from Your Own Manager",
            shortTitle: "Scope Creep from Manager",
            icon: "hand.raised.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Diane Foster", role: "The user's own manager", relationship: "Directly manages the user"),
            briefing: "Your manager, Diane, keeps adding requests to a project beyond what was originally scoped, without adjusting the timeline. You need to push back and renegotiate scope with your own manager -- a harder dynamic given the power difference.",
            criteria: [
                "Name the specific scope changes concretely",
                "Explain the tradeoff or impact of continuing to absorb them",
                "Propose a concrete renegotiation, not just a complaint",
            ],
            openingLine: "Hey, do you have a few minutes? I wanted to talk through the scope of the project.",
            turnReplies: [
                "It's not that much more, is it? I didn't think a couple extra asks would be a big deal.",
                "Hm, okay, I hadn't thought about it that way in terms of tradeoffs.",
                "Alright, let's talk about what we can push out or reprioritize to make room for the new asks.",
            ],
            feedbackLine: "This is the hardest lesson in the unit -- you stayed concrete and confident instead of apologetic, which is exactly what it took to get Diane to actually engage with renegotiating instead of brushing it off."
        ),
        MockLessonContent(
            id: "checkpoint-unit-3",
            unitNumber: 3,
            title: "Checkpoint: Boundaries",
            icon: "flag.checkered",
            isCheckpoint: true,
            character: EngineCharacter(name: "Quinn", role: "Peer, coworker on an adjacent team", relationship: "Occasionally asks the user for cross-team help"),
            briefing: "A combined scenario for Unit 3: Quinn has an unreasonable ask pending. Say no to or renegotiate it, without a visible guide.",
            criteria: [
                "Clearly decline or renegotiate the ask",
                "Give a concrete reason",
                "Propose an alternative or a path forward",
            ],
            openingLine: "Hey, so were you able to take a look at that ask I sent over?",
            turnReplies: [
                "I was really hoping you could help since everyone else is tied up too.",
                "Okay, that's fair -- what if we scaled it down instead?",
                "Alright, let's go with that plan.",
            ],
            feedbackLine: "No guide this time, but you still declined clearly, gave a real reason, and landed on an alternative -- a strong close to this unit."
        ),

        // MARK: - Unit 4: Hard Conversations (guarded/defensive to emotionally heavy)
        MockLessonContent(
            id: "hard-critical-feedback",
            unitNumber: 4,
            title: "Giving Critical Feedback",
            icon: "exclamationmark.triangle.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Marcus", role: "Direct report", relationship: "8 months on the team, reports to the user"),
            briefing: "Marcus has been repeatedly missing a specific, measurable commitment over the past few weeks. You need to raise it directly without being harsh, while still landing the seriousness of the pattern.",
            criteria: [
                "Name the specific behavior, not a vague generalization",
                "State the concrete impact of the behavior",
                "Ask for Marcus's perspective before concluding",
            ],
            openingLine: "Hey, thanks for coming in -- I wanted to talk about the last few deadlines.",
            turnReplies: [
                "I mean, I don't think it's been that bad -- other things have come up too.",
                "...Okay, fair, it has been a few times in a row now.",
                "There's actually been something going on that I haven't mentioned. I can walk you through it.",
            ],
            feedbackLine: "You stayed specific and asked for his side instead of leading with blunt criticism -- that's what got Marcus to drop the defensiveness and actually open up."
        ),
        MockLessonContent(
            id: "hard-team-pattern",
            unitNumber: 4,
            title: "Addressing a Pattern Affecting the Team",
            shortTitle: "A Team-Wide Pattern",
            icon: "exclamationmark.triangle.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Devon", role: "Direct report", relationship: "1 year on the team, reports to the user"),
            briefing: "Devon has a behavior pattern that's starting to affect how teammates work with them, and others have quietly raised it with you. You need to address it directly, which is harder since it's about perception, not a missed task.",
            criteria: [
                "Name the specific behavior with concrete examples",
                "State the impact on the team, not just your own opinion",
                "Ask for Devon's perspective before concluding",
            ],
            openingLine: "Hey, thanks for meeting -- I wanted to bring up something I've been noticing.",
            turnReplies: [
                "Is this really a widespread thing, or is this just one person's opinion? I don't love the idea of being talked about.",
                "Okay... I hear that it's more than just one instance.",
                "Alright, I'll be more mindful of how that comes across going forward.",
            ],
            feedbackLine: "You grounded this in concrete examples rather than vague team sentiment, which is what kept Devon from staying combative about being \"talked about.\""
        ),
        MockLessonContent(
            id: "hard-promotion-denial",
            unitNumber: 4,
            title: "Denying a Promotion or Raise Request",
            shortTitle: "Denying a Raise Request",
            icon: "exclamationmark.triangle.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Elena", role: "Direct report", relationship: "1.5 years on the team, reports to the user"),
            briefing: "Elena asked for a promotion or raise you're not able to grant right now, for reasons outside her control. You need to deliver this clearly and honestly, while being genuine about what would need to change.",
            criteria: [
                "State the decision clearly, without being vague or overly hedging",
                "Be honest about the actual reasons, without over-promising",
                "Give a concrete path forward or timeline for revisiting it",
            ],
            openingLine: "Hey, thanks for meeting -- I wanted to follow up on what we talked about last week.",
            turnReplies: [
                "Okay... that's disappointing to hear. Can you tell me more about why, though? I feel like I've been doing everything right.",
                "I guess I just feel like I'm being compared to someone else's timeline instead of my own.",
                "Alright, I appreciate you being straight with me about the timeline -- let's talk about what I should focus on.",
            ],
            feedbackLine: "You were honest about the real reasons instead of offering vague reassurance, and gave Elena an actual path forward -- that's what kept her engaged instead of just frustrated."
        ),
        MockLessonContent(
            id: "hard-layoff",
            unitNumber: 4,
            title: "Delivering Hard News",
            icon: "exclamationmark.triangle.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Priya", role: "Direct report", relationship: "2 years on the team, reports to the user"),
            briefing: "You need to tell Priya that her role is being eliminated due to a reorg, effective on a specific near-term date. You need to deliver this clearly and with empathy, without burying the news or over-promising.",
            criteria: [
                "State the decision clearly and directly, without burying it",
                "Acknowledge the emotional impact without being dismissive",
                "Be honest about what is and isn't within your control",
                "Give a clear next step (severance, timeline, resources)",
            ],
            openingLine: "Hey, thanks for making time -- I need to share something difficult with you.",
            turnReplies: [
                "Wait... what? Is there anything that can be done? This doesn't make any sense.",
                "Okay... I'm still processing this. What happens now, practically?",
                "Alright. I appreciate you being direct with me about it, even though it's hard to hear.",
            ],
            feedbackLine: "This is the heaviest conversation in the unit, and you delivered the news clearly while still acknowledging the impact -- that combination is what moved Priya from shock toward practical next-step questions instead of spiraling."
        ),
        MockLessonContent(
            id: "checkpoint-unit-4",
            unitNumber: 4,
            title: "Checkpoint: Hard Conversations",
            shortTitle: "Checkpoint: Hard Talks",
            icon: "flag.checkered",
            isCheckpoint: true,
            character: EngineCharacter(name: "Alex", role: "Direct report", relationship: "1 year on the team, reports to the user"),
            briefing: "A combined scenario for Unit 4: Alex has a clear behavioral pattern with a real personal factor complicating it. Balance directness with empathy, without a visible guide.",
            criteria: [
                "Name the specific behavior or pattern directly",
                "State the impact on the team or work",
                "Acknowledge Alex's situation without excusing the pattern",
                "End with a clear, mutually understood next step",
            ],
            openingLine: "Hey, thanks for meeting -- I wanted to talk through something with you.",
            turnReplies: [
                "Yeah... I kind of figured something was up. I've had a lot going on, but I know that's not really an excuse.",
                "I appreciate you not just writing me off for it. I do want to fix this.",
                "Okay, that next step makes sense -- I can commit to that.",
            ],
            feedbackLine: "You balanced directness with empathy without a guide to lean on -- naming the pattern, acknowledging what's behind it, and still landing on a clear next step."
        ),
    ]

    static func content(for id: String) -> MockLessonContent? {
        all.first { $0.id == id }
    }
}
