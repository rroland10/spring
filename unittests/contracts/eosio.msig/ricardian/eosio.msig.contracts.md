<h1 class="contract">propose</h1>

---
spec_version: "0.2.0"
title: Propose multi-sig transaction
summary: '{{proposer}} proposes {{proposal_name}} for group approval'
---

**{{proposer}}** submits proposal **{{proposal_name}}** for the listed approvers to sign before execution.

<h1 class="contract">approve</h1>

---
spec_version: "0.2.0"
title: Approve multi-sig proposal
summary: '{{level.actor}} approves proposal {{proposal_name}} from {{proposer}}'
---

**{{level.actor}}** records approval for proposal **{{proposal_name}}** submitted by **{{proposer}}**.

<h1 class="contract">unapprove</h1>

---
spec_version: "0.2.0"
title: Withdraw multi-sig approval
summary: '{{level.actor}} withdraws approval for {{proposal_name}}'
---

**{{level.actor}}** removes their prior approval for proposal **{{proposal_name}}**.

<h1 class="contract">cancel</h1>

---
spec_version: "0.2.0"
title: Cancel multi-sig proposal
summary: '{{canceler}} cancels proposal {{proposal_name}} from {{proposer}}'
---

**{{canceler}}** cancels proposal **{{proposal_name}}** before it executes.

<h1 class="contract">exec</h1>

---
spec_version: "0.2.0"
title: Execute multi-sig proposal
summary: '{{executer}} executes proposal {{proposal_name}} from {{proposer}}'
---

**{{executer}}** executes proposal **{{proposal_name}}** once required approvals are collected.

<h1 class="contract">invalidate</h1>

---
spec_version: "0.2.0"
title: Invalidate prior approvals
summary: '{{account}} invalidates all prior multi-sig approvals'
---

**{{account}}** marks their prior multi-sig approvals as stale; new approvals are required after this action.
