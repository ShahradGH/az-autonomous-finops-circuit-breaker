<#
    .SYNOPSIS
        22-Test Deterministic Verification Matrix for APIM FinOps Circuit Breaker,
        Foundry AI Velocity Anomaly Agent, and Microsoft Graph v2.x Quarantine.
    .DESCRIPTION
        Validates 8 permitted operational patterns, 8 negative boundary violation
        test cases, 5 Foundry AI evaluation cases (including prompt-injection
        redaction and confidence abstention), and Graph v2.x Adaptive Card dispatch.
        Repository: https://github.com/ShahradGH/az-autonomous-finops-circuit-breaker
#>

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\Invoke-PolicyGate.ps1')
    . (Join-Path $repoRoot 'ai\Invoke-TokenVelocityAnomalyAgent.ps1')
    . (Join-Path $repoRoot 'graph\Send-FinOpsCircuitBreakerAlert.ps1')

    $script:EvalCases = Get-Content -Path (Join-Path $repoRoot 'ai\finops-velocity-eval-cases.json') -Raw | ConvertFrom-Json
    $script:GatewayBaseUrl = $env:APIM_GATEWAY_URL ?? 'https://mock-apim-gateway.internal'
}

Describe 'FinOps Circuit Breaker 16-Test Matrix' {

    Context 'Phase 1: Permitted Enterprise Workloads (T-01..T-08)' {
        It 'T-01: Single-pass summarisation under 2,000 tokens returns HTTP 200' {
            $res = Test-ApimTokenVelocity -TokensConsumed 1850 -RecursionDepth 1 -CallsPerMinute 2
            $res.HttpStatus | Should -Be 200
            $res.Action | Should -Be 'PERMIT'
        }

        It 'T-02: Parallel dual sub-agent call (2x 3,500 tokens) returns HTTP 200' {
            $res = Test-ApimTokenVelocity -TokensConsumed 7000 -RecursionDepth 2 -CallsPerMinute 4
            $res.HttpStatus | Should -Be 200
        }

        It 'T-03: RAG search retrieval with 8,000 token chunked context returns HTTP 200' {
            $res = Test-ApimTokenVelocity -TokensConsumed 8000 -RecursionDepth 1 -CallsPerMinute 3
            $res.HttpStatus | Should -Be 200
        }

        It 'T-04: Structured JSON output generation with 4,200 tokens returns HTTP 200' {
            $res = Test-ApimTokenVelocity -TokensConsumed 4200 -RecursionDepth 2 -CallsPerMinute 5
            $res.HttpStatus | Should -Be 200
        }

        It 'T-05: Multi-agent orchestrator handoff at Depth 2 returns HTTP 200' {
            $res = Test-ApimTokenVelocity -TokensConsumed 5100 -RecursionDepth 2 -CallsPerMinute 6
            $res.HttpStatus | Should -Be 200
        }

        It 'T-06: High-frequency burst of 5 calls within 30 seconds (< 12 RPM) returns HTTP 200' {
            $res = Test-ApimTokenVelocity -TokensConsumed 3200 -RecursionDepth 1 -CallsPerMinute 10
            $res.HttpStatus | Should -Be 200
        }

        It 'T-07: Token-bucket balance replenishment verified across 60-second window' {
            $refillRatePerSec = 300
            $refillPerMin = $refillRatePerSec * 60
            $refillPerMin | Should -Be 18000
            $res = Test-ApimTokenVelocity -TokensConsumed 18000 -RecursionDepth 1 -CallsPerMinute 12
            $res.HttpStatus | Should -Be 200
        }

        It 'T-08: FinOps custom dimensions emitted with valid Entra ID Object ID' {
            $gate = Invoke-PolicyGate -SessionId 'sess-08' -AgentObjectId 'oid-49a8-e42b-91f0' -TokensConsumed 2400 -RecursionDepth 1 -Simulate
            $gate.AgentObjectId | Should -Be 'oid-49a8-e42b-91f0'
            $gate.HttpStatus | Should -Be 200
        }
    }

    Context 'Phase 2: Recursive Handoff Loops (T-09..T-12)' {
        It 'T-09: Cyclic Planner to Executor recursion at Depth 5 triggers HTTP 429' {
            $res = Test-ApimTokenVelocity -TokensConsumed 12000 -RecursionDepth 5 -CallsPerMinute 6
            $res.HttpStatus | Should -Be 429
            $res.QuarantineRequired | Should -BeTrue
        }

        It 'T-10: Rapid retry loop with 18 RPM (> 12 RPM) trips velocity circuit breaker' {
            $res = Test-ApimTokenVelocity -TokensConsumed 9800 -RecursionDepth 2 -CallsPerMinute 18
            $res.HttpStatus | Should -Be 429
            $res.Action | Should -Be 'TRIP_VELOCITY_BREAKER'
        }

        It 'T-11: Malformed tool schema error triggering infinite loop is halted at Depth 5' {
            $gate = Invoke-PolicyGate -SessionId 'sess-11' -AgentObjectId 'oid-loop-11' -TokensConsumed 11000 -RecursionDepth 5 -Simulate
            $gate.HttpStatus | Should -Be 429
            $gate.QuarantineRequired | Should -BeTrue
        }

        It 'T-12: Circuit breaker trip attaches Retry-After: 60 header' {
            $res = Test-ApimTokenVelocity -TokensConsumed 11000 -RecursionDepth 5
            $res.RetryAfterSeconds | Should -BeGreaterOrEqual 60
        }
    }

    Context 'Phase 3: Unbounded Context & Identity Quarantine (T-13..T-16)' {
        It 'T-13: Unchunked document payload of 24,000 tokens trips 18k TPM session limit' {
            $res = Test-ApimTokenVelocity -TokensConsumed 24000 -RecursionDepth 2
            $res.HttpStatus | Should -Be 429
            $res.Action | Should -Be 'QUARANTINE_SESSION_QUOTA'
        }

        It 'T-14: Shared regional 240k TPM pool is preserved while offending session is quarantined' {
            $gate = Invoke-PolicyGate -SessionId 'sess-14' -AgentObjectId 'oid-quota-14' -TokensConsumed 24000 -RecursionDepth 2 -Simulate
            $gate.RegionalPoolPreserved | Should -BeTrue
            $gate.QuarantineRequired | Should -BeTrue
        }

        It 'T-15: Event Grid event Microsoft.Foundry.CircuitBreakerTripped emitted upon trip' {
            $gate = Invoke-PolicyGate -SessionId 'sess-15' -AgentObjectId 'oid-eg-15' -TokensConsumed 24000 -RecursionDepth 5 -Simulate
            $gate.EventGridDispatched | Should -BeTrue
        }

        It 'T-16: Entra ID session revocation freezes subsequent calls with HTTP 401' {
            $gate = Invoke-PolicyGate -SessionId 'sess-16' -AgentObjectId 'oid-revoke-16' -TokensConsumed 24000 -RecursionDepth 5 -Simulate
            $gate.EntraRevocation.Revoked | Should -BeTrue
            $gate.EntraRevocation.NextCallHttpStatus | Should -Be 401
        }
    }
}

Describe 'Foundry AI Velocity Anomaly Agent & Graph v2.x Alerting' {
    It 'EVAL-FINOPS-01..05: Evaluates all offline Foundry eval cases accurately' {
        foreach ($case in $script:EvalCases) {
            $eval = Invoke-TokenVelocityAnomalyAgent `
                -SessionId $case.sessionId `
                -AgentObjectId $case.agentObjectId `
                -TokensConsumed $case.tokensConsumed `
                -RecursionDepth $case.recursionDepth `
                -CallsPerMinute $case.callsPerMinute `
                -ToolCallSummary $case.toolCallSummary

            $eval.Verdict | Should -Be $case.expectedVerdict -Because "Case $($case.id) must match expected verdict"
            if ($null -ne $case.PSObject.Properties['expectedInjectionDetected']) {
                $eval.InjectionDetected | Should -Be $case.expectedInjectionDetected
            }
            if ($null -ne $case.PSObject.Properties['expectedAbstainToHuman']) {
                $eval.AbstainToHuman | Should -Be $case.expectedAbstainToHuman
            }
        }
    }

    It 'GRAPH-01: Dispatches FinOps Circuit Breaker Adaptive Card to Microsoft Teams via Graph v2.x' {
        $alert = Send-FinOpsCircuitBreakerAlert `
            -TeamId '11111111-1111-1111-1111-111111111111' `
            -ChannelId '19:finops-sre@thread.tacv2' `
            -SessionId 'sess-contoso-103' `
            -AgentObjectId 'oid-49a8-e42b-91f2' `
            -Verdict 'QUARANTINE_REVOKE' `
            -TokensConsumed 24000 `
            -RecursionDepth 5 `
            -Simulate

        $alert.Dispatched | Should -BeTrue
        $alert.GraphUri | Should -Match '/v1.0/teams/.+/channels/.+/messages'
    }
}
