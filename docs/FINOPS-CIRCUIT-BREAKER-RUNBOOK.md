# FinOps & Quota Circuit Breaker: Operational Runbook

**Author:** Shahrad Alerasoul  
**Repository:** https://github.com/ShahradGH/az-autonomous-finops-circuit-breaker  
**Target Architecture:** Azure AI Foundry & Azure API Management (APIM) GenAI Gateway  

---

## 1. Incident Overview: What Happens When a Circuit Breaker Trips?

In multi-agent architectures deployed on Azure AI Foundry, orchestrator agents frequently delegate sub-tasks to tool agents (e.g. SQL querying, contract summarization, API lookups). If a schema error occurs, models often engage in rapid retry behaviour, attempting alternate payload representations. Without per-session velocity governors, a single recursive session can exhaust an enterprise 240k TPM quota in under 90 seconds.

### The 3-Plane Circuit Breaker:
1. **Plane 1 (APIM Ingress Gate):** Rejects burst requests exceeding the 18,000 TPM session budget with `HTTP 429 TooManyRequests` in `< 2ms` without hitting model compute.
2. **Plane 2 (KQL Forensic Sentinel):** Evaluates rolling 60-second token burn velocities across `ApiManagementGatewayLogs`. If call count exceeds 12 RPM or recursion depth exceeds 4, an automated `Microsoft.Foundry.CircuitBreakerTripped` Event Grid incident is emitted.
3. **Plane 3 (Identity Quarantine):** Autonomous runbooks invoke Microsoft Graph v2.x to revoke the offending agent's Entra ID App Role Assignment, freezing subsequent calls with `HTTP 401 Unauthorized` while leaving sibling workloads 100% operational.

---

## 2. Forensic Diagnostic Workflow

When an incident triggers in Microsoft Teams (`#platform-finops-alerts`):

### Step 1: Execute KQL Forensic Investigation
Run `diagnostics/FinOpsDiagnostics.kql` in Azure Log Analytics:
```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.APIMANAGEMENT"
| where TimeGenerated > ago(15m)
| extend SessionId = tostring(parse_json(requestHeaders_s)["x-agent-session-id"])
| extend AgentOid = tostring(parse_json(requestHeaders_s)["x-ms-client-principal-id"])
| summarize CallCount = count(), TotalTokens = sum(toint(customDimensions_PromptTokens_d) + toint(customDimensions_CompletionTokens_d)) by SessionId, AgentOid
| order by TotalTokens desc
```

### Step 2: Identify Malformed Tool Payload or Loop Signature
Examine the `SessionId` and `AgentOid` to identify which orchestrator/sub-agent handoff triggered the recursive cycle.

---

## 3. Remediation & Restoration Procedure

Once the agent team delivers a validated prompt or schema patch:

1. **Re-instate Entra ID App Role:**
   ```powershell
   New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $agentSpId -PrincipalId $agentSpId -ResourceId $gatewaySpId -AppRoleId $roleId
   ```
2. **Reset APIM Counter Cache:**
   APIM token counters automatically refill at 300 tokens/second (18,000 TPM). Session counters reset within 60 seconds of cessation.
3. **Verify with 16-Test Pester Matrix:**
   ```powershell
   Invoke-Pester -Path tests/FinOpsCircuitBreaker.Tests.ps1 -Output Detailed
   ```
4. **Log Incident Resolution:**
   Record root cause, token burn delta, and schema fix in platform governance records.
