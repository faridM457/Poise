import Foundation

// Static content for the full curriculum -- 5 units, 21 lessons and 5 unit
// checkpoints -- mirroring conversation-engine/server/lessons.js (ids, units,
// titles, characters, criteria). Structure follows conversation-lessons.md:
// every lesson has a fixed managerial stake the LLM is not allowed to vary,
// so two plays of the same lesson test the same skill at the same difficulty;
// only persona, phrasing and curveballs move.
//
// The opening line / turn replies / feedback line here are hand-written mocks
// used when LiveLessonViewModel.useMockDataForUITesting is true. They are NOT
// live generation -- the real scenario is generated per lesson by the engine.
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
    // screens either side. It moves on its own if lessons get longer, which a
    // hand-written per-lesson number would not.
    var estimatedMinutes: Int { turnReplies.count + 2 }
}

struct MockUnitInfo {
    let label: String
    let title: String
    // See LessonUnit.shortTitle -- a shorter phrasing for the Learn grid
    // card only, where the full title wraps to a second line the card then
    // has to reserve blank space for even on units that fit on one line.
    // The real title (used everywhere else, and matching the server's
    // curriculum copy) is unchanged.
    var shortTitle: String? = nil
    let subtitle: String
}

enum PoiseLessonLibrary {
    static let unitInfo: [Int: MockUnitInfo] = [
        1: MockUnitInfo(label: "Unit 1 · Foundations & Expectations", title: "Foundations & Expectations", shortTitle: "Foundations", subtitle: "Start every relationship on solid ground"),
        2: MockUnitInfo(label: "Unit 2 · Giving Feedback", title: "Giving Feedback", subtitle: "Name what's true, and make it land"),
        3: MockUnitInfo(label: "Unit 3 · Boundaries & Difficult Asks", title: "Boundaries & Difficult Asks", shortTitle: "Setting Boundaries", subtitle: "Say no and mean it"),
        4: MockUnitInfo(label: "Unit 4 · Managing Up & Across", title: "Managing Up & Across", shortTitle: "Managing Up", subtitle: "Hold your own with people who aren't your reports"),
        5: MockUnitInfo(label: "Unit 5 · Hard Conversations", title: "Hard Conversations", subtitle: "The ones you hope you never have to give"),
    ]

    static let all: [MockLessonContent] = [
        // MARK: - Unit 1: Foundations & Expectations
        MockLessonContent(
            id: "foundations-first-1-1",
            unitNumber: 1,
            title: "Your First One-on-One",
            icon: "person.2.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Dani", role: "New report", relationship: "Joined your team last week; was a peer until the reorg"),
            briefing: "Dani starts reporting to you today. Until the reorg two weeks ago you sat at the same level, and neither of you has acknowledged that out loud yet. This is your first one-on-one and there is no problem to solve -- only the working relationship to set up.",
            criteria: [
                "State your role and how you'll support them",
                "Ask what they need from a manager",
                "Agree on how you'll communicate going forward",
            ],
            openingLine: "So... this is weird, right? Last month we were complaining about the same roadmap together. How do you want to do this?",
            turnReplies: [
                "Okay, that helps. Honestly I mostly want someone who'll tell me straight when something isn't working, instead of finding out in a review.",
                "I'd rather have a standing time than ad-hoc pings. Ad-hoc always ends up being urgent things only.",
                "Thirty minutes on Tuesdays works. And I'll bring a list rather than making you dig for it.",
            ],
            feedbackLine: "You named the change in the relationship instead of pretending it hadn't happened, then let Dani define what they needed before you set the cadence -- that's what made this feel like an agreement rather than an announcement."
        ),
        MockLessonContent(
            id: "foundations-clarify-priorities",
            unitNumber: 1,
            title: "Clarifying Priorities You Created Confusion On",
            shortTitle: "Clarifying Your Own Mixed Signals",
            icon: "person.2.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Priya", role: "Direct report", relationship: "5 months on the team, reports to you"),
            briefing: "Two weeks ago you told Priya the migration was the priority. Last Thursday, in a hurry, you asked her to take the partner integration as well and implied it was urgent. She has been splitting her time and finishing neither. The confusion is yours, not hers.",
            criteria: [
                "Acknowledge the conflicting signals you gave",
                "Identify the single priority and what is explicitly deprioritized",
                "Ask the report to summarize their next action and surface remaining trade-offs",
            ],
            openingLine: "I've been meaning to ask -- which of these actually comes first? I've been trying to move both and I don't think I'm doing either of them well.",
            turnReplies: [
                "Okay. I'll be honest, I assumed the integration had jumped the queue because of how you asked for it.",
                "So migration first, and I just stop touching the integration? I want to be sure, because I told Marco I'd have something for him Friday.",
                "Got it -- migration through end of month, integration paused, and I'll tell Marco today that Friday isn't happening.",
            ],
            feedbackLine: "You owned the mixed signal as yours before asking Priya to re-plan around it, and you named what gets dropped rather than leaving 'prioritize the migration' to mean everything-plus-one-thing."
        ),
        MockLessonContent(
            id: "foundations-working-style",
            unitNumber: 1,
            title: "Aligning on Working Style",
            icon: "person.2.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Theo", role: "Direct report", relationship: "3 months on the team, senior hire, reports to you"),
            briefing: "Theo wants to ship without review and has said your check-ins feel like supervision. You are not comfortable handing over that much yet -- he is three months in and two recent calls went badly. You need a workable middle, not a winner.",
            criteria: [
                "Name the mismatch directly",
                "Ask what autonomy would look like to them",
                "Propose a middle ground with decision rights and a review date",
            ],
            openingLine: "Can I be direct? I've shipped bigger things than this at my last place. The check-ins are starting to feel like I'm being watched.",
            turnReplies: [
                "Autonomy to me means I don't need a sign-off for anything reversible. If I can undo it in a day, let me just do it.",
                "That's fair on the client-facing stuff. I didn't have the context on the Halvorsen account, I'll give you that.",
                "So anything reversible is mine, client-facing comes to you, and we look at it again in six weeks. I can work with that.",
            ],
            feedbackLine: "You didn't cave to the framing or dig in against it -- you got Theo to define autonomy concretely, which turned an argument about trust into a workable split of decision rights."
        ),
        MockLessonContent(
            id: "foundations-repair-trust",
            unitNumber: 1,
            title: "Repairing Trust After Your Managerial Misstep",
            shortTitle: "Repairing Trust After Your Misstep",
            icon: "person.2.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Nadia", role: "Direct report", relationship: "1 year on the team, reports to you"),
            briefing: "In Monday's review you rewrote Nadia's recommendation on the spot, in front of the wider group, without speaking to her first. She has been polite and distant since. The mistake here is specifically yours.",
            criteria: [
                "Name your specific action and take responsibility for it",
                "Ask about its impact without defending your intent",
                "State the behavioral change you'll make and ask what would help rebuild trust",
            ],
            openingLine: "It's fine, honestly. You're the manager, you get to make the call. Was there something else you needed?",
            turnReplies: [
                "I mean -- since you're asking. It wasn't the decision. It was finding out you disagreed at the same moment as everyone else in that room.",
                "People came up to me afterwards. That's the part I'm still sitting with. It looked like I hadn't done the work.",
                "If you disagree next time, tell me first. Even five minutes before. I'd rather change my own slide than be corrected on it.",
            ],
            feedbackLine: "You named the specific action rather than apologizing for a vague 'how that came across', and you let Nadia describe the impact without explaining what you'd meant -- that restraint is what made the apology land."
        ),
        MockLessonContent(
            id: "checkpoint-unit-1",
            unitNumber: 1,
            title: "Checkpoint: The Reset Conversation",
            shortTitle: "The Reset Conversation",
            icon: "flag.checkered",
            isCheckpoint: true,
            character: EngineCharacter(name: "Owen", role: "Direct report", relationship: "4 months on the team, reports to you"),
            briefing: "Owen has asked for time. He is unclear on what you want prioritized -- reasonably, because you have changed the answer twice -- and he is also pushing to make those calls himself without checking in. Both are live in the same conversation.",
            criteria: [
                "Own the ambiguity you created and name a single priority",
                "Hold a clear line on which decisions remain yours",
                "Keep the two issues separate instead of trading one for the other",
            ],
            openingLine: "I want to talk about the roadmap, but honestly I also want to talk about how much of this I should be bringing to you at all.",
            turnReplies: [
                "Right, but part of why I'd rather just decide is that the direction keeps moving. If I'm choosing anyway, I'd rather choose deliberately.",
                "Okay. So you're saying the priority confusion is on you, but the sign-off boundary isn't up for negotiation because of it.",
                "That's reasonable. I'd rather have a clear line than a vague one I keep guessing at.",
            ],
            feedbackLine: "The hard part here was not letting your own mistake become leverage against you. You owned the confusion fully and still held the decision-rights line, instead of conceding autonomy as compensation."
        ),

        // MARK: - Unit 2: Giving Feedback
        MockLessonContent(
            id: "feedback-first-critical",
            unitNumber: 2,
            title: "Your First Critical Feedback",
            icon: "text.bubble.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Sam", role: "Direct report", relationship: "6 months on the team, reports to you"),
            briefing: "In Tuesday's planning session Sam talked over two teammates, including one who had been trying to raise a risk. Sam almost certainly doesn't know they did it. This is a one-time observation, not a pattern -- yet.",
            criteria: [
                "Name the specific behavior",
                "Explain the impact",
                "Ask for their perspective",
            ],
            openingLine: "Hey -- you said you wanted five minutes? Everything alright?",
            turnReplies: [
                "Oh. I didn't realize I did that. That meeting moves fast and I was trying to keep us on time.",
                "Yeah, Ravi did start to say something about the vendor timeline. I think I rolled straight over it.",
                "I'll go back to him today. And I'll try to actually pause before jumping in next time.",
            ],
            feedbackLine: "You gave Sam one specific moment rather than a characterization of how they behave in meetings, and asked for their read before agreeing a fix -- which is why this landed as information instead of an accusation."
        ),
        MockLessonContent(
            id: "feedback-experienced-report",
            unitNumber: 2,
            title: "Feedback to a More Experienced Report",
            shortTitle: "Feedback to a Senior Report",
            icon: "text.bubble.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Margaret", role: "Direct report", relationship: "12 years in the field, 2 years on the team, reports to you"),
            briefing: "Margaret has been doing this twice as long as you have. She has been dismissing junior engineers' questions in review -- briskly, not cruelly -- and two of them have stopped asking. When challenged she tends to reach for her experience.",
            criteria: [
                "Describe the observed behavior and impact without invoking hierarchy",
                "Ask for context and use their expertise to test your understanding",
                "State the expectation that remains yours to set as manager",
            ],
            openingLine: "I've been doing code review since before that team was hired, so you'll forgive me if I'm curious where this is going.",
            turnReplies: [
                "Because nine times out of ten the question is answered in the doc. I'm not going to reread the doc aloud for people.",
                "Hm. I hadn't considered that they'd stop asking entirely. That's not what I want either -- I'd rather they ask than guess.",
                "Fine. I'll point to where the answer is instead of implying they should already know it. That I can do.",
            ],
            feedbackLine: "You didn't flatter the experience or pull rank against it -- you used Margaret's expertise to pressure-test your own read, then still named the expectation as yours to set. That's the balance this one is about."
        ),
        MockLessonContent(
            id: "feedback-repeated-miss",
            unitNumber: 2,
            title: "Addressing a Repeated Miss",
            icon: "text.bubble.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Jonah", role: "Direct report", relationship: "8 months on the team, reports to you"),
            briefing: "Jonah has missed the same weekly handoff twice now. Both times there was a plausible reason and both times you heard it after the fact. He is capable, which is exactly why this has become a pattern rather than an accident.",
            criteria: [
                "State the repeated pattern using observable facts",
                "Ask what's preventing the commitment from being met",
                "Set a specific expectation, support, and follow-up date",
            ],
            openingLine: "I know what this is about. Look, last week was genuinely out of my hands -- the data didn't land until Thursday night.",
            turnReplies: [
                "Okay, but you're stacking them together like it's one thing. They were two completely different causes.",
                "...I suppose the common part is that both times I knew by Wednesday it was going to be tight and didn't say anything.",
                "A heads-up by Wednesday I can do. And if it slips again after that, I understand it's a different conversation.",
            ],
            feedbackLine: "The move here was refusing to relitigate each excuse separately. By holding the pattern together you got Jonah to the real issue -- the missing early warning -- and then set a date rather than a hope."
        ),
        MockLessonContent(
            id: "feedback-pushback",
            unitNumber: 2,
            title: "Feedback That Gets Pushed Back On",
            icon: "text.bubble.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Alex", role: "Direct report", relationship: "1 year on the team, reports to you"),
            briefing: "You are raising that Alex's status updates have been leaving out known risks. Alex disputes this -- not defensively at first, but firmly, and with specifics. Some of what he says is fair. The underlying expectation still stands.",
            criteria: [
                "Ask what specifically they dispute: the facts, impact, or expectation",
                "Acknowledge valid context without abandoning the issue",
                "State what expectation or next step remains, including what evidence would change your view",
            ],
            openingLine: "I don't think that's accurate, honestly. I flagged the vendor risk in the channel on the 3rd. It's there, you can look.",
            turnReplies: [
                "Because the update goes to leadership and every time I put a risk in it, it turns into a meeting I have to run. So I raise it where it actually gets solved.",
                "I'm not saying I won't. I'm saying the format punishes flagging things and then I get told I'm not flagging things.",
                "If the risk line doesn't automatically spawn a review, I'll put them in the update. That's a fair trade.",
            ],
            feedbackLine: "You separated what Alex was disputing -- the facts, not the expectation -- and conceded the real point about the process without letting the expectation go with it. Naming what would change your mind is what kept this a conversation."
        ),
        MockLessonContent(
            id: "checkpoint-unit-2",
            unitNumber: 2,
            title: "Checkpoint: Feedback Under Fire",
            shortTitle: "Feedback Under Fire",
            icon: "flag.checkered",
            isCheckpoint: true,
            character: EngineCharacter(name: "Reese", role: "Direct report", relationship: "1 year on the team, reports to you"),
            briefing: "Reese has missed the same client deadline three times this quarter. You have the dates. When you raise it, Reese disputes that it is a pattern at all and has an account of each one that puts the cause elsewhere.",
            criteria: [
                "Hold the documented pattern rather than arguing each instance",
                "Address the pushback without retreating from the expectation",
                "Land a specific expectation with a follow-up date",
            ],
            openingLine: "Three times? I'd push back on that framing. Two of those were blocked on legal and everyone knew it.",
            turnReplies: [
                "Right, but if the cause is different every time, then it isn't a pattern in my behavior, it's a pattern in this company.",
                "I'm not trying to be difficult. I just don't want 'Reese misses deadlines' written down somewhere when the details matter.",
                "Okay. The details go in the note, and the deadline still holds. I can live with that if it's both.",
            ],
            feedbackLine: "The trap here is retreating into re-examining each date once the pushback starts. You kept accountability and resistance in the same conversation without letting one cancel the other."
        ),

        // MARK: - Unit 3: Boundaries & Difficult Asks
        MockLessonContent(
            id: "boundaries-turn-down-request",
            unitNumber: 3,
            title: "Turning Down a Report's Request",
            icon: "hand.raised.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Cass", role: "Direct report", relationship: "2 years on the team, reports to you"),
            briefing: "Cass wants to lead the platform rebuild. You are giving it to someone else, and there is genuinely no equivalent project to offer instead -- not this quarter, possibly not this year. There is no consolation prize to reach for.",
            criteria: [
                "Give the decision clearly",
                "Explain the relevant criterion or constraint without hiding behind policy",
                "Acknowledge the impact, and discuss a next step only if a truthful one exists",
            ],
            openingLine: "So -- did you get a chance to think about the rebuild? I've been mapping out how I'd sequence it.",
            turnReplies: [
                "Oh. Okay. Can I ask what tipped it? I'd rather know than guess.",
                "That's hard to hear but it's at least a real answer. I was half expecting 'timing'.",
                "I don't need you to find me something to make up for it. I'd rather you just tell me when something real comes up.",
            ],
            feedbackLine: "You gave the decision first and the reasoning second, and -- hardest part -- you let the disappointment sit instead of filling it with a substitute project you'd have had to invent."
        ),
        MockLessonContent(
            id: "boundaries-protect-team-time",
            unitNumber: 3,
            title: "Protecting Your Team's Time",
            icon: "hand.raised.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Martin", role: "Peer manager", relationship: "Runs an adjacent team; does not report to you"),
            briefing: "Martin's team has been going directly to two of your engineers for 'quick favours' -- four times in three weeks, none of it tracked, all of it landing mid-sprint. Martin is not being malicious; he has simply found a shortcut that works for him.",
            criteria: [
                "Name the pattern you're seeing",
                "State the impact on your team",
                "Propose an intake process for future asks",
            ],
            openingLine: "Hey! Good timing, I was going to grab Ines later about a quick schema thing --",
            turnReplies: [
                "Ah. I didn't realize it had been that many. It genuinely does feel like fifteen minutes each time from my side.",
                "I mean, going through a queue slows us down. That's why I stopped doing it in the first place, if I'm honest.",
                "Fine -- if you commit to a two-day turnaround on the queue, I'll stop tapping people directly. That's workable.",
            ],
            feedbackLine: "You made this about a system rather than about Martin, and you left with a rule instead of a refusal -- which is the difference between solving this once and solving it every three weeks."
        ),
        MockLessonContent(
            id: "boundaries-boss-deadline",
            unitNumber: 3,
            title: "Saying No to Your Boss's Deadline",
            icon: "hand.raised.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Diane", role: "Your manager", relationship: "Your direct manager; the deadline may not be hers to move"),
            briefing: "Diane has committed your team to a date you cannot hit at the current scope. The date may be genuinely fixed. What is negotiable is what ships by it -- and that trade has to be made explicitly, by her, not quietly absorbed by your team.",
            criteria: [
                "State the constraint factually",
                "Force an explicit trade-off: scope, quality, or capacity",
                "Confirm which trade-off they're accepting",
            ],
            openingLine: "I've already told the board the 14th, so I'm hoping this is a conversation about how, not whether.",
            turnReplies: [
                "Everyone's capacity looks like that right now. What makes yours different?",
                "Hm. So if I hold the 14th, I'm choosing to ship without the reporting module. You're saying that's the actual choice.",
                "Then we ship the core on the 14th and reporting lands in March. I'll tell them that myself.",
            ],
            feedbackLine: "You didn't ask for more time and you didn't quietly absorb the gap -- you converted a fixed date into an explicit choice and made Diane own which thing she was giving up."
        ),
        MockLessonContent(
            id: "boundaries-former-peer",
            unitNumber: 3,
            title: "Setting a Boundary With a Former Peer",
            shortTitle: "A Boundary With a Former Peer",
            icon: "hand.raised.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Joel", role: "Direct report", relationship: "Was your peer for 3 years; has reported to you for 2 months"),
            briefing: "Joel keeps treating you as his back channel -- asking what was said in leadership, expecting a heads-up on decisions before the team hears them, and floating exceptions to process 'since it's us'. You were genuinely close. That is exactly what makes this hard.",
            criteria: [
                "Acknowledge that the relationship has changed",
                "Name the boundary and why consistency matters",
                "Explain what support or connection can continue",
            ],
            openingLine: "Off the record -- is the restructure actually happening? You'd tell me, right? It's me.",
            turnReplies: [
                "Wow. Okay. Two months ago you'd have just told me.",
                "I'm not asking you to play favourites. I'm asking you to treat me like someone you've known for three years.",
                "...Yeah. I'd probably be annoyed if you were doing it for someone else and not me. I hadn't flipped it around like that.",
            ],
            feedbackLine: "You acknowledged the friendship as real rather than pretending the history away, and grounded the boundary in consistency -- what you'd owe anyone on the team -- which is far harder to argue with than a rule."
        ),
        MockLessonContent(
            id: "checkpoint-unit-3",
            unitNumber: 3,
            title: "Checkpoint: Holding the Line Under Pressure",
            shortTitle: "Holding the Line",
            icon: "flag.checkered",
            isCheckpoint: true,
            character: EngineCharacter(name: "Devon", role: "Direct report", relationship: "Was your peer for 4 years; has reported to you for 3 months"),
            briefing: "Devon -- a former peer, now your report -- wants the lead role on the new initiative. You cannot give it to him and there is no equivalent substitute. When you say no, he reaches for the history between you.",
            criteria: [
                "Deliver a final no without inventing a consolation prize",
                "Hold the decision when the old relationship is used as leverage",
                "Acknowledge the impact honestly",
            ],
            openingLine: "Come on. You know what I can do -- you've seen me do it. You of all people shouldn't need convincing.",
            turnReplies: [
                "That's a very managerial answer for someone I've known four years.",
                "I'm not asking for a favour. I'm asking you to weigh what you actually know about my work over whatever the process says.",
                "Alright. I don't like it. But I'd rather you say it straight than dress it up.",
            ],
            feedbackLine: "Two pressures at once: no alternative to offer, and a relationship being used as leverage. You held the decision without either hiding behind process or trading on the friendship to soften it."
        ),

        // MARK: - Unit 4: Managing Up & Across
        MockLessonContent(
            id: "managing-up-resources",
            unitNumber: 4,
            title: "Asking for Resources or Headcount",
            icon: "megaphone.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Diane", role: "Your manager", relationship: "Your direct manager; controls the budget"),
            briefing: "You need one more engineer. Your team has absorbed two extra services this year with no additions, and the on-call rotation is down to three people. Diane is not hostile, but the budget round closed last month.",
            criteria: [
                "State the specific ask and the need behind it",
                "Show the cost of not getting it",
                "Propose a fallback if the full ask isn't approved",
            ],
            openingLine: "Before you start -- you should know headcount closed in October. So tell me what you need and I'll tell you what's possible.",
            turnReplies: [
                "Everyone is running hot. What I need from you is why yours is a risk and not just a complaint.",
                "Three people on a rotation covering two new services. Alright, that's a number I can take upstairs.",
                "I can't promise a hire. I can probably get you a contractor for two quarters. Would that hold it?",
            ],
            feedbackLine: "You asked for something specific and then made the cost of refusing it concrete, rather than apologizing for needing anything. Bringing your own fallback is what turned a no into a partial yes."
        ),
        MockLessonContent(
            id: "managing-up-peer-disagreement",
            unitNumber: 4,
            title: "Disagreeing With a Peer Manager in a Meeting",
            shortTitle: "Disagreeing With a Peer, Publicly",
            icon: "megaphone.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Karim", role: "Peer manager", relationship: "Runs an adjacent team; presenting to a room you're both in"),
            briefing: "Karim is walking the room through a migration plan that will break your team's release process. Six other people are present, including his skip-level. Saying nothing means it gets approved; saying it badly turns a technical disagreement into a standoff.",
            criteria: [
                "Name the specific disagreement, not the person",
                "State your reasoning briefly",
                "Propose an alternative or a way to decide",
            ],
            openingLine: "...and assuming no objections, we'd start cutting over the week of the 12th. Everyone good?",
            turnReplies: [
                "I mean, we modelled this. The cutover window is fine for our services.",
                "Your release train. Right. I genuinely didn't have that in front of me.",
                "Okay -- if we run one service through first and it doesn't break your train, we go. If it does, we talk again.",
            ],
            feedbackLine: "You disagreed with the plan rather than with Karim, kept the reasoning short enough that the room could follow it, and gave everyone a way to decide -- so it resolved instead of becoming a contest."
        ),
        MockLessonContent(
            id: "managing-up-defend-work",
            unitNumber: 4,
            title: "Defending Your Team's Work Under Challenge",
            shortTitle: "Defending Your Team's Work",
            icon: "megaphone.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Ellis", role: "Leadership", relationship: "Senior leader in a review with others present"),
            briefing: "Leadership is questioning whether your team's project is worth continuing. Adoption is below the original target -- that part is true. The rest of the picture is not in the room, and there is a real shortfall you will have to own without handing your team to the wolves.",
            criteria: [
                "State the business outcome and your team's contribution",
                "Respond to the challenge directly, acknowledging any real shortfall without blaming the team",
                "State the decision, resource, or protection you need from leadership",
            ],
            openingLine: "The numbers we're looking at are roughly half of what was projected. Help me understand why this continues.",
            turnReplies: [
                "That's context, but it's still half. I need to know whether the target was wrong or the execution was.",
                "Alright -- so the target assumed an integration that didn't ship. That's a material difference, and it wasn't your call.",
                "What do you need to get to a real number by the next review?",
            ],
            feedbackLine: "You owned the genuine shortfall without offering up a name for it, and you left the room with an ask rather than just a defence -- that's what separates representing a team from reporting on one."
        ),
        MockLessonContent(
            id: "managing-up-own-miss",
            unitNumber: 4,
            title: "Owning a Team Miss With Leadership",
            shortTitle: "Owning a Team Miss",
            icon: "megaphone.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Ellis", role: "Leadership", relationship: "Senior leader; frustrated about a missed commitment"),
            briefing: "Your team missed a commitment that leadership had already promised externally. One person on your team made the call that caused it. Leadership wants to know what happened, and there is a real temptation to be specific about who.",
            criteria: [
                "State what happened and take ownership without scapegoating the report",
                "Explain the recovery plan",
                "Make a realistic, specific ask",
            ],
            openingLine: "I had to walk this back with the client personally this morning. So: what happened?",
            turnReplies: [
                "Someone made a judgement call that turned out to be wrong. Who?",
                "You're not going to give me a name. Fine -- then it's yours. What's the plan?",
                "Two weeks, and you'll want the freeze lifted for it. I can do one of those. Which matters more?",
            ],
            feedbackLine: "Leadership asked twice for a name and you took it both times without turning it into a performance of martyrdom. Then you still asked for what the recovery actually needs, which is the part most people drop once they're apologizing."
        ),
        MockLessonContent(
            id: "checkpoint-unit-4",
            unitNumber: 4,
            title: "Checkpoint: Advocating Under Scrutiny",
            shortTitle: "Advocating Under Scrutiny",
            icon: "flag.checkered",
            isCheckpoint: true,
            character: EngineCharacter(name: "Karim", role: "Peer manager", relationship: "Adjacent team lead, challenging you with leadership in the room"),
            briefing: "In a review with leadership present, Karim argues your team's approach is the reason the numbers are soft and proposes folding the work into his team. Leadership is listening and has its own questions about the results.",
            criteria: [
                "Disagree with the peer's claim without making it personal",
                "Defend the team's outcome to leadership, owning any real shortfall",
                "Land a decision or ask rather than leaving it open",
            ],
            openingLine: "I'll be blunt -- I think the approach is the problem, and I think we'd have shipped this two quarters ago.",
            turnReplies: [
                "That's a generous reading of your own timeline, but go on.",
                "Okay, the integration dependency is real. I'll grant you that one.",
                "So your ask is a decision today on who owns the dependency, not on who owns the project. That's a different conversation.",
            ],
            feedbackLine: "Two fights at once, and the failure mode is picking one. You pushed back on Karim's claim and answered leadership's real doubt in the same conversation, without dropping either thread."
        ),

        // MARK: - Unit 5: Hard Conversations
        MockLessonContent(
            id: "hard-job-offer",
            unitNumber: 5,
            title: "Delivering a Job Offer and Negotiating Terms",
            shortTitle: "Delivering a Job Offer",
            icon: "exclamationmark.triangle.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Imani", role: "Candidate", relationship: "Final-round candidate weighing another offer"),
            briefing: "You are extending an offer to Imani, who has a competing one. Base salary is fixed -- you have no room there. Start date and title are genuinely flexible. Over-promising to close her would be worse than losing her.",
            criteria: [
                "Present the offer clearly and state what's flexible vs. fixed",
                "Listen to their counter and probe what matters most to them",
                "Close with a specific next step or deadline",
            ],
            openingLine: "Thank you -- genuinely. I should be upfront that I do have another offer in hand, and it's a bit higher.",
            turnReplies: [
                "The number matters, but it's not the only thing. The other role is a much bigger team and I'd be one of twelve.",
                "Honestly? Scope. I want to own something end to end rather than a slice of it.",
                "Give me until Friday. If the scope is what you've described, that's the stronger offer for me.",
            ],
            feedbackLine: "You said what was fixed before she asked, which bought you credibility for everything after -- then found what she actually valued instead of trying to win on the number you couldn't move."
        ),
        MockLessonContent(
            id: "hard-candidate-rejection",
            unitNumber: 5,
            title: "Telling a Candidate They Didn't Get the Job",
            shortTitle: "Rejecting a Final Candidate",
            icon: "exclamationmark.triangle.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Peter", role: "Candidate", relationship: "Final-round candidate; genuinely close"),
            briefing: "Peter made it to the final two and was a real contender. You are calling to tell him he didn't get it. There is no ongoing relationship to manage afterwards -- which makes honesty easier and vagueness more tempting.",
            criteria: [
                "State the decision clearly and promptly",
                "Give one genuine, specific reason without over-explaining",
                "Leave the door open only if it's genuinely true",
            ],
            openingLine: "Hi -- thanks for calling. I've been hoping to hear from you.",
            turnReplies: [
                "Ah. Okay. Thank you for telling me directly, that's more than most do.",
                "Can I ask what it came down to? I'd rather have something I can use.",
                "That's fair, and it's useful. I appreciate you not dressing it up.",
            ],
            feedbackLine: "You led with the decision instead of burying it after a preamble, gave one real reason rather than a list of softeners, and didn't promise a future round that isn't coming."
        ),
        MockLessonContent(
            id: "hard-performance-conversation",
            unitNumber: 5,
            title: "A Formal Performance Conversation",
            icon: "exclamationmark.triangle.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Jonah", role: "Direct report", relationship: "Documented pattern; informal feedback has already been tried"),
            briefing: "Informal feedback hasn't worked. This is the formal conversation: a documented pattern, a stated consequence, and a timeline. Jonah knows roughly what is coming and is somewhere between defensive and resigned.",
            criteria: [
                "State the pattern and its documented history",
                "Name the concrete consequence and timeline",
                "Set explicit, measurable expectations going forward",
            ],
            openingLine: "There's an HR person on the invite for next week, so I assume I know what this is. Let's just do it.",
            turnReplies: [
                "I've heard the pattern before. What's different this time is the paperwork, right?",
                "So thirty days. And if the numbers are there at the end of thirty days, this goes away?",
                "I want it written down. Not because I don't trust you -- because I want to know exactly what counts.",
            ],
            feedbackLine: "You didn't soften the formality into a chat. Naming the consequence and the date plainly is what makes a performance conversation fair -- Jonah leaves knowing exactly what counts, which is the only version he can act on."
        ),
        MockLessonContent(
            id: "hard-mediation",
            unitNumber: 5,
            title: "Mediating Conflict Between Two Reports",
            shortTitle: "Mediating Between Two Reports",
            icon: "exclamationmark.triangle.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Ines & Marco", role: "Two reports", relationship: "Both report to you; both in the room and barely speaking"),
            briefing: "Ines and Marco have stopped working together in any real sense and it is now affecting the team. Both are in the room. Your job is not to rule on who was right -- it is to run a conversation neither of them can run alone.",
            criteria: [
                "Set ground rules for the conversation",
                "Let each person state their view uninterrupted",
                "Name the shared goal and propose a path forward",
            ],
            openingLine: "MARCO: I'm happy to talk, but I'd like it noted that I've tried this twice already. INES: That's not -- sorry. Go ahead.",
            turnReplies: [
                "INES: Fine. My version is that decisions get made in conversations I'm not in, and then I'm told. MARCO: That's not --",
                "MARCO: Alright. Mine is that I ask, I get no answer for three days, and then I'm the one who went around her.",
                "INES: ...That's actually the same complaint, isn't it. MARCO: Sort of, yes.",
            ],
            feedbackLine: "You held the rules instead of taking a side -- cutting off the first interruption is what made the second turn possible. They found the shared cause themselves, which is the only version that survives the meeting."
        ),
        MockLessonContent(
            id: "hard-termination",
            unitNumber: 5,
            title: "Letting Someone Go",
            icon: "exclamationmark.triangle.fill",
            isCheckpoint: false,
            character: EngineCharacter(name: "Cass", role: "Direct report", relationship: "2 years on the team; this is their last conversation with you"),
            briefing: "The decision is made and is not reversible. Cass is being let go today. Nothing you say will change the outcome, and everything you say should reflect that -- this is the last conversation you will have as their manager.",
            criteria: [
                "State the decision plainly, early in the conversation",
                "Explain the reasoning briefly, without over-justifying",
                "Address next steps and support available",
            ],
            openingLine: "You've got your serious face on. Is this about the Q3 review?",
            turnReplies: [
                "Right. Okay. I think I knew that was coming, I just didn't think it was today.",
                "Is there anything I could have -- no. Don't answer that. It's done, isn't it.",
                "Just tell me what happens now. Laptop, accounts, what I say to people.",
            ],
            feedbackLine: "You said it early rather than letting Cass work it out mid-sentence, and you didn't keep justifying after the decision landed. Moving to the practical questions when asked is what respect looks like in this conversation."
        ),
        MockLessonContent(
            id: "checkpoint-unit-5",
            unitNumber: 5,
            title: "Checkpoint: The Full Arc",
            shortTitle: "The Full Arc",
            icon: "flag.checkered",
            isCheckpoint: true,
            character: EngineCharacter(name: "Reese", role: "Direct report", relationship: "At the end of a documented performance process"),
            briefing: "This is the performance conversation at the end of the process. Depending on how it goes, it may become the termination conversation in the same sitting. Both outcomes are genuinely on the table when you walk in.",
            criteria: [
                "State the documented pattern and the consequence plainly",
                "Carry accountability through if the conversation turns",
                "Leave the person with concrete next steps either way",
            ],
            openingLine: "Before you start -- I've been offered something else. So depending on what you're about to say, this might be a different conversation.",
            turnReplies: [
                "I'd rather know where I stand first. Is the plan still on the table or is it past that?",
                "Okay. That's clearer than the last three months have been, I'll give you that.",
                "Then let's do it properly. Tell me what the timeline looks like from here.",
            ],
            feedbackLine: "This one can turn mid-conversation, and the failure is handling the first half well and then losing the thread when it does. You carried the same clarity across the shift instead of starting over."
        ),
    ]

    static func content(for id: String) -> MockLessonContent? {
        all.first { $0.id == id }
    }
}
