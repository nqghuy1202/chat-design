# UX Research Methods Reference

Detailed descriptions of research methods, when to use them, and best practices.

---

## Qualitative Methods

### User Interviews

**Purpose:** Understand user motivations, mental models, and context of use

**When to use:** Early discovery, exploring new domains, understanding "why"

**Duration:** 30-60 minutes per session

**Sample size:** 5-12 participants typically reveal most themes

**Output:** Interview transcripts, affinity diagrams, personas

**Best Practices:**
- Use open-ended questions (How, What, Tell me about...)
- Avoid leading questions
- Practice active listening
- Allow comfortable silences
- Follow interesting threads with probing questions

**Question Types to Avoid:**
- Leading: "Don't you think X is better?"
- Closed: "Do you like feature Y?" (yes/no)
- Hypothetical: "Would you use X if we built it?"

**Question Types to Use:**
- "Tell me about a time when..."
- "Walk me through how you..."
- "What was that experience like?"
- "What happened next?"

---

### Contextual Inquiry

**Purpose:** Observe users in their natural environment while they perform tasks

**When to use:** Understanding real-world workflows and workarounds

**Duration:** 1-3 hours on-site

**Sample size:** 6-10 participants

**Output:** Workflow diagrams, environment insights, pain point inventory

**Key Principles:**
1. **Context:** Research happens where users work
2. **Partnership:** User is expert, researcher is apprentice
3. **Interpretation:** Validate understanding in real-time
4. **Focus:** Stay on relevant topics

**Protocol:**
1. Introduction and consent
2. Ask user to perform typical tasks
3. Observe without interrupting (mostly)
4. Ask clarifying questions as they work
5. Summarize and validate understanding
6. Thank and debrief

---

### Diary Studies

**Purpose:** Capture behaviors and experiences over time in natural settings

**When to use:** Longitudinal behaviors, infrequent activities, emotional journeys

**Duration:** 1-4 weeks typically

**Sample size:** 10-15 participants (expect 20% dropout)

**Output:** Experience timelines, behavioral patterns, contextual triggers

**Implementation:**
- Provide clear prompts and structure
- Use digital tools for easy capture (photos, voice memos)
- Schedule regular check-ins (2-3 times per week)
- Plan for participant dropout (recruit 20% extra)

**Prompt Examples:**
- "Every time you [activity], capture a photo and describe..."
- "At the end of each day, rate your experience with..."
- "When you feel [emotion], note what triggered it..."

---

### Card Sorting

**Purpose:** Understand how users categorize and relate information

**When to use:** Information architecture, navigation design, taxonomy creation

**Duration:** 20-45 minutes per session

**Sample size:** 15-30 participants for reliable patterns

**Output:** Similarity matrices, dendrograms, category labels

**Variants:**

| Type | Description | Best For |
|------|-------------|----------|
| Open | Participants create their own categories | Discovery, new IA |
| Closed | Participants sort into predefined categories | Validation, existing IA |
| Hybrid | Mix of predefined + custom categories | Refinement |
| Tree Testing | Validate resulting structures | IA validation |

**Analysis:**
- Generate similarity matrix
- Create dendrogram (hierarchical clustering)
- Identify agreement percentages
- Note outliers and edge cases

---

### Focus Groups

**Purpose:** Explore attitudes, perceptions, and group dynamics around a topic

**When to use:** Concept exploration, early ideation, gathering diverse perspectives

**Duration:** 60-90 minutes

**Sample size:** 6-10 participants per group, 3-4 groups total

**Output:** Discussion themes, consensus points, divergent views

**Cautions:**
- Group dynamics can suppress minority opinions
- Louder voices may dominate
- Not suitable for usability evaluation
- Moderator skill is critical

**When NOT to Use:**
- Individual behaviors or tasks
- Usability evaluation
- Sensitive personal topics
- When conformity bias is a risk

---

## Quantitative Methods

### Surveys & Questionnaires

**Purpose:** Collect data from large samples to quantify attitudes and behaviors

**When to use:** Validation, benchmarking, prioritization, demographic insights

**Duration:** 5-15 minutes completion time

**Sample size:** 100+ for statistical significance, 1000+ for segmentation

**Output:** Statistical summaries, correlation analyses, segments

**Question Types:**
- Likert scales (5 or 7 point)
- Multiple choice (single or multi-select)
- Ranking/prioritization
- Open-ended (use sparingly)

**Standard Instruments:**

| Instrument | Purpose | Items |
|------------|---------|-------|
| SUS (System Usability Scale) | Perceived usability | 10 items |
| NPS (Net Promoter Score) | Loyalty metric | 1 question |
| CSAT (Customer Satisfaction) | Direct satisfaction | 1-3 questions |
| UEQ (User Experience Questionnaire) | Multi-dimensional UX | 26 items |

**SUS Scoring:**
- Score range: 0-100
- Average: 68
- Above 80: Excellent
- Below 50: Needs significant improvement

---

### A/B Testing

**Purpose:** Compare two variants to determine which performs better

**When to use:** Optimization, validating hypotheses, incremental improvements

**Duration:** Depends on traffic (days to weeks)

**Sample size:** Statistical calculators determine minimum sample

**Output:** Conversion rates, confidence intervals, winner determination

**Requirements:**
1. Clear hypothesis before starting
2. Single variable change (isolate the effect)
3. Sufficient sample size for statistical power
4. Appropriate duration (capture full cycles)

**Metrics to Track:**
- Conversion rate
- Click-through rate
- Time on page
- Bounce rate
- Revenue per visitor

**Statistical Significance:**
- Aim for 95% confidence level
- Use sample size calculators
- Run until minimum sample reached
- Don't peek and stop early

---

### Usability Metrics

**Purpose:** Quantify the usability of a system through standardized measures

**Key Metrics:**

| Metric | Description | Benchmark |
|--------|-------------|-----------|
| Task Success Rate | % completing tasks | 78% average |
| Time on Task | Duration to complete | Task-specific |
| Error Rate | Errors per task | <10% ideal |
| Learnability | Improvement over attempts | Session-specific |
| Efficiency | Steps vs. optimal path | <150% optimal |

**Measurement Tips:**
- Define "success" before testing
- Use consistent task definitions
- Record both completion and partial completion
- Track recovery from errors

---

### Analytics & Behavioral Data

**Purpose:** Understand actual user behavior at scale through passive data collection

**Tools:** Google Analytics, Mixpanel, Amplitude, Hotjar, FullStory

**Output:** Funnels, user flows, drop-off points, feature usage

**Key Analyses:**

| Analysis | Purpose | Tool Feature |
|----------|---------|--------------|
| Funnel conversion | Identify drop-off points | Funnel reports |
| User flow | Map navigation patterns | Flow visualization |
| Cohort retention | Track user engagement over time | Cohort analysis |
| Feature adoption | Measure feature usage | Event tracking |
| Session recordings | Observe individual behavior | Session replay |

**Combining with Qualitative:**
- Use analytics to identify "what"
- Use qualitative to understand "why"
- Target interviews at drop-off points
- Validate survey responses with behavior

---

## Usability Testing

### Moderated Testing

**Characteristics:**
- Real-time facilitation
- Can probe for clarification
- Better for complex tasks
- Higher cost per session
- Typical: 5-8 participants

**Protocol:**
1. Introduction and consent (5 min)
2. Pre-task questions (5 min)
3. Task completion with think-aloud (30-45 min)
4. Post-task questionnaire (5 min)
5. Debrief interview (10 min)

**Moderator Best Practices:**
- Stay neutral (no reactions to success/failure)
- Avoid helping (redirect back to task)
- Ask "What are you thinking?" not "Why did you do that?"
- Save probing questions for after task completion

---

### Unmoderated Testing

**Characteristics:**
- Remote, asynchronous
- Larger sample sizes
- Natural environment
- Lower cost per participant
- Typical: 20+ participants

**Tools:** UserTesting, Maze, Lookback, Trymata, Lyssna

**Best Practices (2026):**
- Limit tests to 7-8 tasks (prevent cognitive overload)
- Use simple, actionable instructions
- Create realistic tasks mimicking actual activities
- Test setup beforehand
- Have backup plans for technical issues

---

### Decision Matrix: Moderated vs. Unmoderated

| Factor | Moderated | Unmoderated |
|--------|-----------|-------------|
| Complexity | Complex workflows | Simple tasks |
| Budget | Higher per-session | Lower per-participant |
| Scale | 5-8 participants | 20+ participants |
| Depth | Deep exploration | Quick validation |
| Timing | Real-time insights | Asynchronous |
| Probe ability | Can follow up | Fixed script only |
| Environment | Controlled | Natural |

---

## Think-Aloud Protocol

**Concurrent Think-Aloud:**
- Verbalize while doing tasks
- More natural, less filtered
- May slow task completion
- Good for understanding process

**Retrospective Think-Aloud:**
- Verbalize after task, using recording
- Does not interrupt flow
- May have recall bias
- Good for complex tasks

**Prompts:**
- "Keep talking about what you're thinking"
- "Tell me what's going through your mind"
- "What are you looking for?"
- "What do you expect to happen?"

---

## Method Selection Guide

| Research Question | Primary Method | Secondary Method |
|-------------------|----------------|------------------|
| Why do users behave this way? | Interviews | Contextual Inquiry |
| Can users complete tasks? | Usability Testing | Analytics |
| How do users categorize content? | Card Sorting | Tree Testing |
| What do users prefer? | Surveys | A/B Testing |
| What happens over time? | Diary Studies | Analytics Cohorts |
| What patterns exist at scale? | Surveys + Analytics | Segmentation |
| Is this concept viable? | Concept Testing | Interviews |
| How does this compare to competition? | Competitive Analysis | Benchmarking |
