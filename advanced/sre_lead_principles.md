# SRE Lead Principles — FAANG Interview Level

This is what separates a Senior SRE from an SRE Lead. The board asks about judgment, not just commands.

---

## Q1. Define SLI, SLO, SLA, and Error Budget. Design them for a checkout API.

**Answer:**

**Definitions:**
| Term | What it is | Who owns it |
|------|-----------|-------------|
| **SLI** (Service Level Indicator) | A metric that measures service behavior (e.g. request success rate) | Engineering |
| **SLO** (Service Level Objective) | A target for an SLI over a time window (e.g. 99.9% success rate over 30 days) | Engineering |
| **SLA** (Service Level Agreement) | A contractual commitment to customers, with penalties for breach | Business/Legal |
| **Error Budget** | The allowed amount of unreliability: `1 - SLO`. For 99.9% SLO → 0.1% = 43.2 min/month | Engineering |

**SLOs for a checkout API:**

**Availability SLO:**
```
SLI:  rate of successful HTTP responses (2xx + 4xx client errors)
      / total requests, measured at load balancer

SLO:  99.95% over 28 days
      (i.e. allow 20.2 minutes of downtime per month)

Error Budget:
  0.05% × 28 days × 24h × 60m = 20.16 minutes / month
```

**Latency SLO:**
```
SLI:  proportion of requests completing in < 500ms
      (p95, not average — averages hide tail latency)

SLO:  95% of checkout requests < 500ms
      99% of checkout requests < 2000ms
```

**Freshness SLO (for catalog / price data):**
```
SLI:  percentage of time the product catalog was updated within 5 minutes

SLO:  99.9% over 30 days
```

**Prometheus/SLO tooling:**
```yaml
# Sloth (SLO as code for Prometheus)
version: "prometheus/v1"
service: "checkout-api"
slos:
  - name: "requests-availability"
    objective: 99.95
    sli:
      events:
        error_query: sum(rate(http_requests_total{job="checkout",code=~"5.."}[{{.window}}]))
        total_query: sum(rate(http_requests_total{job="checkout"}[{{.window}}]))
    alerting:
      burn_rate_alerts:
        - name: CheckoutHighErrorBudgetBurn
          short_window: 5m
          long_window: 1h
          burn_rate_factor: 14.4    # burn rate that exhausts budget in 2h
          severity: critical
        - name: CheckoutLowErrorBudgetBurn
          short_window: 30m
          long_window: 6h
          burn_rate_factor: 6
          severity: warning
```

**Error Budget Policy:**
| Budget remaining | Action |
|-----------------|--------|
| > 50% | Normal feature velocity |
| 25–50% | Reliability review before new deploys |
| 10–25% | Freeze new features, focus on reliability |
| < 10% | Incident-level response, no deploys |
| Exhausted | Post-mortem required, no deploys until budget resets |

---

## Q2. Walk me through your worst incident and what the team changed afterward.

**Answer framework — FAANG interviewers score this heavily. They want a REAL story, not a textbook.**

**Structure: STAR + SRE context**

**Situation:** Describe the system and what failed. Be specific — duration, customer impact, error rate.

**Timeline:** Include the detection gap (often the most damning part for SRE):
```
14:32 — First alert fires (PagerDuty)
14:38 — On-call engineer acknowledges (6 min detection → ack)
14:55 — Root cause identified (17 min to diagnosis)
15:42 — Fix deployed (47 min total downtime)
15:50 — Incident declared resolved after monitoring period
```

**Root cause (be specific, not vague):**
- "A Terraform apply changed a security group rule that blocked the health check port"
- "A memory leak in the new version caused OOMKills under traffic spikes"
- "A dependency update changed an API contract silently"

**Action items (the part that demonstrates lead thinking):**
```
Immediate (done same day):
  ✅ Added Terraform plan review requirement for security group changes
  ✅ Added health check to staging smoke test

Short-term (within 1 sprint):
  ✅ Improved alert: fire at 5% error rate, not 20%
  ✅ Added runbook link to alert message
  ✅ Added automated rollback if error rate > 10% for 3 minutes

Long-term (1 quarter):
  ✅ Implemented error budget tracking with SLO dashboards
  ✅ Defined change freeze process for high-traffic periods
  ✅ Improved load test to catch memory leak class of bugs
```

**What separates a lead answer:** You made the team better, not just fixed the bug. You changed the process, the tooling, the culture. You measured whether the changes worked.

---

## Q3. How do you decide what to alert on? How do you prevent alert fatigue?

**Answer:**

**Two categories of alerts:**

**Symptom-based (pages):** Alert when users are affected right now.
```
DO page on:
- Error rate > 1% for 5 min (users failing requests)
- p99 latency > 5s for 5 min (users experiencing slowness)
- Availability SLO burn rate too high (budget about to exhaust)

DO NOT page on:
- CPU > 80% (no user impact if app is healthy)
- Disk usage > 70% (should be a ticket, not a page)
- Deployment running (engineer knows, it's not an incident)
```

**Cause-based (tickets):** Low-urgency signals that need attention, but not at 3am.
```
File as tickets, not pages:
- SSL cert expiring in 14 days
- Disk usage > 70%
- Replica lag > 30 seconds (watch, not page)
- Old AMI in use (security scan)
```

**Error budget burn rate alerts (Google's model):**
Instead of static thresholds, alert when error budget is burning too fast:
```
Alert 1 (critical): burning at 14.4x → exhausts 30-day budget in 2 hours
Alert 2 (warning): burning at 6x → exhausts 30-day budget in 5 days
```
This approach fires fewer false positives and always tells you the business impact.

**Alert fatigue prevention:**
1. **Audit your alerts quarterly.** If an alert fires and no one acts on it within 24h, it shouldn't be an alert.
2. **Track MTTR per alert.** Alert firing → too-long-to-resolve → on-call learns to ignore it.
3. **Require runbook links** in every alert. If you can't write a runbook for it, it shouldn't be an alert.
4. **Require every alert to justify the wake-up.** If the business isn't impacted, it should be a ticket.
5. **Merge related alerts.** Fifteen alerts about the same incident = fifteen times the cognitive load.

---

## Q4. What is toil and how do you handle it as an SRE lead?

**Answer:**

**Toil** (Google SRE definition): Manual, repetitive, automatable work tied to running a production service that scales linearly with service growth and has no enduring value.

**Examples:**
- Manually provisioning access tickets every time a developer needs prod read access
- Manually rotating secrets every 90 days
- Running the same SQL query every oncall to check DB state
- Manually scaling up before every planned high-traffic event
- Manually creating JIRA tickets for deploy failures

**Toil vs Overhead vs Valid Ops work:**
| Type | Example | Action |
|------|---------|--------|
| Toil | Manual secret rotation | Automate (Secrets Manager rotation) |
| Overhead | Sprint planning, design docs | Minimize, don't automate |
| Valid ops | Incident response | Improve playbooks, reduce frequency |

**How to handle it as a lead:**
```
1. Measure it first — ask the team to log toil for 2 weeks
   (a Slack message in #toil with ~30 min estimates is enough)

2. Rank by: (frequency × time per occurrence × stress level)
   Not every toil task is worth automating. Pick the top 3.

3. Budget 20-30% of sprint capacity for toil reduction
   (The Google target is < 50% of SRE time on toil)

4. Don't just automate — eliminate
   Ask "should this exist at all" before "how do I automate this"
   Example: instead of automating prod access tickets, build self-service with time-boxed JIT access

5. Measure again after — did the automation actually reduce time spent?
```

**Toil reduction example:**
```
Before: On-call manually restarts API pods every ~3 days when memory leaks accumulate
Toil cost: 15 min × 10 occurrences/month = 2.5h/month, wakes someone up at night

Option A (automate the toil): CronJob to restart pods at 3am
  → reduces wake-ups, but memory leak still exists

Option B (eliminate the toil): Fix the memory leak
  → zero toil, better reliability, frees engineering time

Option B is always better. Use Option A only if Option B is infeasible short-term.
```

---

## Q5. How do you design an on-call rotation for a team of 8 engineers?

**Answer:**

**Principles first:**
1. **On-call should be sustainable.** If people are burned out, reliability degrades because the best engineers leave.
2. **On-call should be empowering.** On-call engineers must have the access and runbooks to resolve issues, not just escalate.
3. **On-call should be fair.** Rotation must account for time zones, seniority, personal situations.

**Rotation design for 8 engineers:**
```
Primary on-call: 1 person per week (full responsibility)
Secondary/backup: 1 person (escalation if primary unreachable)
Rotation: weekly swap on Tuesdays (avoid Monday transitions)

Shadow rotation (for new team members):
  - First month: shadow an experienced primary, observe responses
  - Second month: shadow as secondary
  - Third month: take primary with mentor available
```

**On-call readiness checklist (per rotation):**
```
Before going on-call:
  ✅ All runbooks reviewed and up-to-date
  ✅ Access to production systems verified
  ✅ PagerDuty escalation paths verified
  ✅ No known risky changes scheduled during your rotation
  ✅ Brief with previous on-call: any known issues?

During:
  ✅ All pages acknowledged within 5 minutes
  ✅ Incident declared if user impact > 5 minutes
  ✅ Escalate within 15 min if you can't diagnose
  ✅ Log all manual actions taken for postmortem

After rotation:
  ✅ Incident retrospective for any pages
  ✅ File toil tickets for anything done manually > 2x
  ✅ Update runbooks if anything was wrong/missing
```

**Preventing on-call burnout:**
```
Metrics to track:
  - Pages per week per engineer (target < 5 pages/rotation)
  - Median time to resolve (MTTR)
  - Pages outside business hours (sleep disruption metric)
  - Alert noise ratio (pages that led to action vs total)

If pages/rotation > 10: this is a reliability problem, not a staffing problem
  → Stop feature work, reduce error budget spend, fix the noisy service
```

---

## Q6. How do you run a blameless postmortem?

**Answer:**

**Why blameless:** Finding who made the mistake does not prevent the next mistake. Finding what conditions made the mistake easy to make does. If engineers fear blame, they hide information, which makes future incidents worse.

**Postmortem structure:**
```markdown
# Incident: [Title] — [Date]
**Severity:** P1 (user-facing outage)
**Duration:** 47 minutes
**Impact:** 8% of checkout requests failed, ~$120K revenue impact

## Timeline
| UTC   | Event |
|-------|-------|
| 14:32 | First customer reports in #prod-alerts Slack |
| 14:38 | On-call acknowledged PagerDuty page |
| 14:55 | Root cause identified: security group change |
| 15:42 | Fix deployed |

## Root Cause
A Terraform apply changed the ECS service security group, removing port 8080 inbound
from the ALB security group. This was not caught in review because the plan output
showed the change as a replacement, not clearly indicating a broken rule.

## Contributing Factors (NOT "who did it")
- Terraform plan output for security group rules is hard to read (rule ordering changes)
- No automated test validates that the ALB can reach the ECS health check port after apply
- Staging environment does not have ALB → ECS connectivity (uses a simpler setup)

## Action Items
| Action | Owner | Due |
|--------|-------|-----|
| Add post-apply smoke test: ALB health check → ECS passes | @alex | 2026-05-01 |
| Add OPA policy: block SG changes without explicit review | @sam | 2026-05-07 |
| Mirror ALB → ECS setup in staging | @priya | 2026-05-14 |
| Add Terraform plan annotation for security group changes | @alex | 2026-05-07 |

## What Went Well
- Detection was fast (< 10 min from first alert to ack)
- Communication in the incident channel was clear
- Rollback path (revert Terraform) was well understood
```

**Lead behaviors during postmortem facilitation:**
- Start with facts, timeline — not blame
- Ask "what would have made this impossible?" not "who should have caught this?"
- Make sure action items have owners and dates — postmortems without follow-through teach learned helplessness
- Share the postmortem widely — every engineer learning from one incident multiplies the value

---

## BONUS: Questions to ask the interviewers (demonstrates lead thinking)

These show you think systemically, not just technically:

1. **"What's the current on-call burden — pages per week per engineer?"**
   → Shows you care about team sustainability

2. **"Where does reliability work fit in the roadmap — do you have error budgets?"**
   → Shows you understand SRE culture vs DevOps-washing

3. **"What's the last P1 incident that happened? What changed afterward?"**
   → Tests whether the company actually does postmortems or just fixes bugs

4. **"How does the SRE team's work get prioritized against feature teams?"**
   → Shows you know the org friction point every SRE team faces

5. **"What does success look like in 6 months for this role?"**
   → Aligns expectations, shows leadership mindset

6. **"What's the thing the team is most proud of building, and what's the thing they most want to fix?"**
   → Gets real signal on team health and technical debt
