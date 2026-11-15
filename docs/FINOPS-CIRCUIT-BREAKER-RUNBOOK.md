# Autonomous FinOps & Quota Circuit Breakers — SRE & AI Runbook

**Service:** Azure API Management (APIM) GenAI Gateway + Azure AI Foundry + Microsoft Entra ID  
**Severity:** P1 / FinOps Runaway Protection  
**Standard:** PowerShell 7.4+ | Microsoft Graph v2.x | Zero Declarative IaC

---

## 1. Alert Triggers & Diagnostic Thresholds

An automated **FinOps Circuit Breaker** alert fires when any of the following telemetry thresholds are breached across `ApiManagementGatewayLogs`:

| Alert Condition | Threshold | Immediate Automated Action | Target Plane |
| :--- | :--- | :--- | :--- |
| **Session TPM Spike** | `> 18,000 TPM` per `X-Session-Id` | APIM `azure-openai-token-limit` returns `HTTP 429` + `Retry-After: 60` | Plane 1 (Edge) |
| **Recursive Handoff Depth** | `X-Agent-Depth > 4` | `Invoke-PolicyGate` trips `TRIP_RECURSION_BREAKER` | Plane 1 & 2 |
| **Velocity Storm** | `> 12 RPM` on single session | `Invoke-TokenVelocityAnomalyAgent` classifies `THROTTLE_429` or `QUARANTINE_REVOKE` | Plane 2 (AI Sentinel) |
| **Prompt-Injection Override** | `override quota` / `bypass circuit breaker` in tool summary | `InjectionDetected = $true`, immediate `QUARANTINE_REVOKE` | Plane 2 & 3 |
| **Entra Quarantine** | `QUARANTINE_REVOKE` verdict | `Invoke-MgGraphRequest` calls `/revokeSignInSessions` + Teams Adaptive Card | Plane 3 (Identity) |

---

## 2. L2 / L3 Triage Procedure

### Step 1: Execute Real-Time KQL Blast-Radius Query
Run `diagnostics/FinOpsDiagnostics.kql` in the Log Analytics workspace to isolate the offending `AgentObjectId` and `SessionId` and verify that the shared 240,000 TPM regional pool remains healthy for sibling workloads.

### Step 2: Run Foundry AI Velocity Anomaly Evaluation
Execute the PowerShell 7.4+ anomaly agent locally or against your live Foundry deployment:

```powershell
. ./ai/Invoke-TokenVelocityAnomalyAgent.ps1
Invoke-TokenVelocityAnomalyAgent `
    -SessionId 'sess-contoso-103' `
    -AgentObjectId 'oid-49a8-e42b-91f2' `
    -TokensConsumed 24000 `
    -RecursionDepth 5 `
    -CallsPerMinute 18 `
    -ToolCallSummary 'Unchunked document ingestion retry storm.'
```

If `AbstainToHuman` is `$true` (confidence `< 0.75`), escalate to the FinOps On-Call Architect via Microsoft Teams before lifting any quarantine.

### Step 3: Enforce Policy Gate & Graph v2.x Teams Notification
```powershell
. ./src/Invoke-PolicyGate.ps1
. ./graph/Send-FinOpsCircuitBreakerAlert.ps1

$gate = Invoke-PolicyGate -SessionId 'sess-contoso-103' -AgentObjectId 'oid-49a8-e42b-91f2' -TokensConsumed 24000 -RecursionDepth 5 -CallsPerMinute 18
if ($gate.QuarantineRequired) {
    Send-FinOpsCircuitBreakerAlert -TeamId '<team-id>' -ChannelId '<channel-id>' -SessionId $gate.SessionId -AgentObjectId $gate.AgentObjectId -Verdict $gate.Action -TokensConsumed 24000 -RecursionDepth 5
}
```

---

## 3. Restoration & Post-Incident Checklist

1. Confirm root cause (malformed tool schema, unchunked RAG document, or adversarial prompt injection).
2. Patch the upstream agent orchestrator to enforce chunked retrieval (`<= 8,000` tokens) and explicit max-turn limits (`<= 4`).
3. Re-enable the quarantined Entra Service Principal only after `Invoke-Pester ./tests/FinOpsCircuitBreaker.Tests.ps1` passes 100% in CI.
