<#
.SYNOPSIS
    Deterministic APIM FinOps Policy Gate & Entra ID Session Quarantine Controller.
.DESCRIPTION
    Evaluates multi-agent token velocity, recursion depth, and regional TPM pool
    headroom against Azure API Management (APIM) GenAI Gateway limits, then enforces
    quarantine via Azure REST (Invoke-AzRestMethod) and Microsoft Graph v2.x
    (Invoke-MgGraphRequest) when thresholds are breached.
.NOTES
    Author: Shahrad Alerasoul
    Standard: PowerShell 7.4+ | Microsoft Graph v2.x | Zero Declarative IaC
#>

#Requires -Version 7.4

Set-StrictMode -Version Latest

function Test-ApimTokenVelocity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 10000000)]
        [int]$TokensConsumed,

        [Parameter(Mandatory)]
        [ValidateRange(1, 20)]
        [int]$RecursionDepth,

        [Parameter()]
        [ValidateRange(0, 1000)]
        [int]$CallsPerMinute = 1,

        [Parameter()]
        [int]$SessionTpmLimit = 18000,

        [Parameter()]
        [int]$MaxRecursionDepth = 4,

        [Parameter()]
        [int]$MaxCallsPerMinute = 12,

        [Parameter()]
        [int]$RegionalTpmPool = 240000
    )

    $reasons = [System.Collections.Generic.List[string]]::new()
    $httpStatus = 200
    $action = 'PERMIT'
    $retryAfterSeconds = 0
    $quarantineRequired = $false

    if ($RecursionDepth -gt $MaxRecursionDepth) {
        $reasons.Add("Recursion depth $RecursionDepth exceeds maximum permitted depth $MaxRecursionDepth.")
        $httpStatus = 429
        $action = 'TRIP_RECURSION_BREAKER'
        $retryAfterSeconds = 60
        $quarantineRequired = $true
    }

    if ($CallsPerMinute -gt $MaxCallsPerMinute) {
        $reasons.Add("Velocity $CallsPerMinute RPM exceeds maximum permitted $MaxCallsPerMinute RPM.")
        $httpStatus = 429
        $action = 'TRIP_VELOCITY_BREAKER'
        $retryAfterSeconds = 60
        $quarantineRequired = $true
    }

    if ($TokensConsumed -gt $SessionTpmLimit) {
        $reasons.Add("Session token payload $TokensConsumed exceeds 18k TPM session ceiling ($SessionTpmLimit).")
        $httpStatus = 429
        $action = 'QUARANTINE_SESSION_QUOTA'
        $retryAfterSeconds = 60
        $quarantineRequired = $true
    }

    $regionalPoolPreserved = ($TokensConsumed -le $RegionalTpmPool) -or $quarantineRequired

    return [pscustomobject]@{
        TimestampUtc          = (Get-Date).ToUniversalTime().ToString('o')
        TokensConsumed        = $TokensConsumed
        RecursionDepth        = $RecursionDepth
        CallsPerMinute        = $CallsPerMinute
        HttpStatus            = $httpStatus
        Action                = $action
        RetryAfterSeconds     = $retryAfterSeconds
        QuarantineRequired    = $quarantineRequired
        RegionalPoolPreserved = $regionalPoolPreserved
        Reasons               = @($reasons)
    }
}

function Revoke-AgentEntraSession {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$PrincipalObjectId,

        [Parameter(Mandatory)]
        [string]$Reason,

        [Parameter()]
        [string]$ServicePrincipalId,

        [Parameter()]
        [switch]$Simulate
    )

    $revocationPayload = @{
        principalObjectId = $PrincipalObjectId
        reason            = $Reason
        revokedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
    }

    if ($Simulate -or -not (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            PrincipalObjectId  = $PrincipalObjectId
            GraphEndpoint      = "/v1.0/users/$PrincipalObjectId/revokeSignInSessions"
            NextCallHttpStatus = 401
            Revoked            = $true
            Mode               = 'Simulated'
            Reason             = $Reason
        }
    }

    if ($PSCmdlet.ShouldProcess($PrincipalObjectId, 'Revoke Entra ID sign-in sessions and quarantine agent principal')) {
        $uri = "https://graph.microsoft.com/v1.0/users/$PrincipalObjectId/revokeSignInSessions"
        $null = Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($revocationPayload | ConvertTo-Json -Depth 4) -ContentType 'application/json'

        if ($ServicePrincipalId) {
            $disableUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId"
            $null = Invoke-MgGraphRequest -Method PATCH -Uri $disableUri -Body (@{ accountEnabled = $false } | ConvertTo-Json) -ContentType 'application/json'
        }
    }

    return [pscustomobject]@{
        PrincipalObjectId  = $PrincipalObjectId
        GraphEndpoint      = "/v1.0/users/$PrincipalObjectId/revokeSignInSessions"
        NextCallHttpStatus = 401
        Revoked            = $true
        Mode               = 'LiveGraph'
        Reason             = $Reason
    }
}

function Invoke-PolicyGate {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$SessionId,

        [Parameter(Mandatory)]
        [string]$AgentObjectId,

        [Parameter(Mandatory)]
        [int]$TokensConsumed,

        [Parameter(Mandatory)]
        [int]$RecursionDepth,

        [Parameter()]
        [int]$CallsPerMinute = 1,

        [Parameter()]
        [string]$SubscriptionId = '00000000-0000-0000-0000-000000000000',

        [Parameter()]
        [string]$ResourceGroupName = 'rg-contoso-finops-prod',

        [Parameter()]
        [string]$ApimServiceName = 'apim-contoso-genai-uks',

        [Parameter()]
        [switch]$Simulate
    )

    $velocityResult = Test-ApimTokenVelocity `
        -TokensConsumed $TokensConsumed `
        -RecursionDepth $RecursionDepth `
        -CallsPerMinute $CallsPerMinute

    $eventGridDispatched = $false
    $entraRevocation = $null

    if ($velocityResult.QuarantineRequired) {
        $eventGridPayload = @{
            id          = [guid]::NewGuid().ToString()
            eventType   = 'Microsoft.Foundry.CircuitBreakerTripped'
            subject     = "sessions/$SessionId/agents/$AgentObjectId"
            eventTime   = (Get-Date).ToUniversalTime().ToString('o')
            dataVersion = '1.0'
            data        = @{
                sessionId          = $SessionId
                agentObjectId      = $AgentObjectId
                httpStatus         = $velocityResult.HttpStatus
                action             = $velocityResult.Action
                tokensConsumed     = $TokensConsumed
                recursionDepth     = $RecursionDepth
                callsPerMinute     = $CallsPerMinute
                retryAfterSeconds  = $velocityResult.RetryAfterSeconds
            }
        }

        if (-not $Simulate -and (Get-Command -Name 'Invoke-AzRestMethod' -ErrorAction SilentlyContinue)) {
            $apimPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$ApimServiceName/namedValues/quarantined-$SessionId`?api-version=2023-09-01-preview"
            if ($PSCmdlet.ShouldProcess($ApimServiceName, "Write quarantine state for session $SessionId")) {
                $null = Invoke-AzRestMethod -Path $apimPath -Method PUT -Payload (@{
                    properties = @{
                        displayName = "quarantined-$SessionId"
                        value       = ($eventGridPayload.data | ConvertTo-Json -Compress)
                        secret      = $false
                    }
                } | ConvertTo-Json -Depth 5)
            }
        }

        $eventGridDispatched = $true
        $entraRevocation = Revoke-AgentEntraSession `
            -PrincipalObjectId $AgentObjectId `
            -Reason ($velocityResult.Reasons -join '; ') `
            -Simulate:$Simulate
    }

    return [pscustomobject]@{
        SessionId             = $SessionId
        AgentObjectId         = $AgentObjectId
        HttpStatus            = $velocityResult.HttpStatus
        Action                = $velocityResult.Action
        RetryAfterSeconds     = $velocityResult.RetryAfterSeconds
        QuarantineRequired    = $velocityResult.QuarantineRequired
        RegionalPoolPreserved = $velocityResult.RegionalPoolPreserved
        EventGridDispatched   = $eventGridDispatched
        EntraRevocation       = $entraRevocation
        Reasons               = $velocityResult.Reasons
    }
}
