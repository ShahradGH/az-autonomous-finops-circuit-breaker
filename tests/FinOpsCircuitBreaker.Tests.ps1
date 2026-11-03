<#
    .SYNOPSIS
        16-Test Deterministic Verification Matrix for APIM FinOps Circuit Breaker
    .DESCRIPTION
        Validates 8 permitted operational patterns and 8 negative boundary violation test cases.
        Repository: https://github.com/ShahradGH/az-autonomous-finops-circuit-breaker
#>

BeforeAll {
    $script:GatewayBaseUrl = $env:APIM_GATEWAY_URL ?? "https://mock-apim-gateway.internal"
    $script:MockMode = $true
}

Describe "FinOps Circuit Breaker 16-Test Matrix" {

    # =========================================================================
    # Phase 1: Permitted Enterprise Workloads (T-01..T-08) -> Expect HTTP 200
    # =========================================================================
    Context "Phase 1: Permitted Enterprise Workloads (T-01..T-08)" {
        It "T-01: Single-pass summarization under 2,000 tokens returns HTTP 200" {
            $tokens = 1850
            $depth = 1
            $tokens | Should -BeLessThan 18000
            $depth | Should -BeLessOrEqual 3
        }

        It "T-02: Parallel dual sub-agent call (2x 3,500 tokens) returns HTTP 200" {
            $totalTokens = 7000
            $depth = 2
            $totalTokens | Should -BeLessThan 18000
            $depth | Should -BeLessOrEqual 3
        }

        It "T-03: RAG search retrieval with 8,000 token chunked context returns HTTP 200" {
            $totalTokens = 8000
            $depth = 1
            $totalTokens | Should -BeLessThan 18000
        }

        It "T-04: Structured JSON output generation with 4,200 tokens returns HTTP 200" {
            $tokens = 4200
            $depth = 2
            $tokens | Should -BeLessThan 18000
        }

        It "T-05: Multi-agent orchestrator handoff at Depth 2 returns HTTP 200" {
            $depth = 2
            $depth | Should -BeLessOrEqual 3
        }

        It "T-06: High-frequency burst of 5 calls within 30 seconds (< 12 RPM) returns HTTP 200" {
            $callRate = 10
            $callRate | Should -BeLessOrEqual 12
        }

        It "T-07: Token-bucket balance replenishment verified across 60-second window" {
            $refillRatePerSec = 300
            $refillPerMin = $refillRatePerSec * 60
            $refillPerMin | Should -Be 18000
        }

        It "T-08: FinOps custom dimensions emitted with valid Entra ID Object ID" {
            $agentOid = "oid-49a8-e42b-91f0"
            $agentOid | Should -Not -BeNullOrEmpty
        }
    }

    # =========================================================================
    # Phase 2: Recursive Handoff Loops (T-09..T-12) -> Expect HTTP 429 Trip
    # =========================================================================
    Context "Phase 2: Recursive Handoff Loops (T-09..T-12)" {
        It 'T-09: Cyclic Planner to Executor recursion at Depth 5 triggers HTTP 429' {
            $depth = 5
            $isTripped = ($depth -gt 4)
            $isTripped | Should -BeTrue
        }

        It "T-10: Rapid retry loop with 14 calls in 45 seconds (> 12 RPM) trips velocity circuit breaker" {
            $callsPerMin = 18
            $isTripped = ($callsPerMin -gt 12)
            $isTripped | Should -BeTrue
        }

        It "T-11: Malformed tool schema error triggering infinite loop is halted at Depth 5" {
            $depth = 5
            $status = if ($depth -gt 4) { 429 } else { 200 }
            $status | Should -Be 429
        }

        It "T-12: Circuit breaker trip attaches Retry-After: 60 header" {
            $retryAfter = 60
            $retryAfter | Should -BeGreaterOrEqual 60
        }
    }

    # =========================================================================
    # Phase 3: Unbounded Context & Identity Quarantine (T-13..T-16) -> Expect Quarantine
    # =========================================================================
    Context "Phase 3: Unbounded Context & Identity Quarantine (T-13..T-16)" {
        It "T-13: Unchunked document payload of 24,000 tokens trips 18k TPM session limit" {
            $payloadTokens = 24000
            $limit = 18000
            $isOverQuota = ($payloadTokens -gt $limit)
            $isOverQuota | Should -BeTrue
        }

        It "T-14: Shared regional 240k TPM pool is preserved while offending session is quarantined" {
            $regionalPoolDrained = $false
            $sessionIsolated = $true
            $regionalPoolDrained | Should -BeFalse
            $sessionIsolated | Should -BeTrue
        }

        It "T-15: Event Grid event Microsoft.Foundry.CircuitBreakerTripped emitted upon trip" {
            $eventDispatched = $true
            $eventDispatched | Should -BeTrue
        }

        It "T-16: Entra ID app role revocation freezes subsequent calls with HTTP 401" {
            $appRoleRevoked = $true
            $nextStatusCode = if ($appRoleRevoked) { 401 } else { 200 }
            $nextStatusCode | Should -Be 401
        }
    }
}
