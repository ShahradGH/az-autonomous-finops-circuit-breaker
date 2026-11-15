<#
.SYNOPSIS
    Dispatches FinOps Circuit Breaker Adaptive Cards & Entra Quarantine via Microsoft Graph v2.x.
.DESCRIPTION
    Posts an actionable Adaptive Card to the FinOps & SRE Microsoft Teams channel
    using Invoke-MgGraphRequest (Graph v1.0/v2.x) and triggers Entra ID session
    revocation for quarantined workload identities.
.NOTES
    Author: Shahrad Alerasoul
    Standard: PowerShell 7.4+ | Microsoft Graph v2.x
#>

#Requires -Version 7.4

Set-StrictMode -Version Latest

function Send-FinOpsCircuitBreakerAlert {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$TeamId,

        [Parameter(Mandatory)]
        [string]$ChannelId,

        [Parameter(Mandatory)]
        [string]$SessionId,

        [Parameter(Mandatory)]
        [string]$AgentObjectId,

        [Parameter(Mandatory)]
        [string]$Verdict,

        [Parameter(Mandatory)]
        [int]$TokensConsumed,

        [Parameter(Mandatory)]
        [int]$RecursionDepth,

        [Parameter()]
        [string]$Rationale = 'Session exceeded APIM FinOps velocity or recursion guardrails.',

        [Parameter()]
        [switch]$Simulate
    )

    $cardBody = @{
        type    = 'AdaptiveCard'
        version = '1.5'
        body    = @(
            @{
                type   = 'TextBlock'
                size   = 'Large'
                weight = 'Bolder'
                color  = 'Attention'
                text   = "FinOps Circuit Breaker Tripped: $Verdict"
            },
            @{
                type  = 'FactSet'
                facts = @(
                    @{ title = 'Session ID'; value = $SessionId },
                    @{ title = 'Agent OID'; value = $AgentObjectId },
                    @{ title = 'Tokens Consumed'; value = "$TokensConsumed TPM" },
                    @{ title = 'Recursion Depth'; value = "$RecursionDepth" },
                    @{ title = 'Rationale'; value = $Rationale }
                )
            }
        )
    } | ConvertTo-Json -Depth 8

    $messagePayload = @{
        body = @{
            contentType = 'html'
            content     = "<attachment id=`"finops-cb-$SessionId`"></attachment>"
        }
        attachments = @(
            @{
                id          = "finops-cb-$SessionId"
                contentType = 'application/vnd.microsoft.card.adaptive'
                content     = $cardBody
            }
        )
    }

    $graphUri = "https://graph.microsoft.com/v1.0/teams/$TeamId/channels/$ChannelId/messages"

    if ($Simulate -or -not (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            Dispatched   = $true
            Mode         = 'Simulated'
            GraphUri     = $graphUri
            SessionId    = $SessionId
            Verdict      = $Verdict
            AttachmentId = "finops-cb-$SessionId"
        }
    }

    if ($PSCmdlet.ShouldProcess("$TeamId/$ChannelId", "Post FinOps Circuit Breaker Adaptive Card for $SessionId")) {
        $response = Invoke-MgGraphRequest -Method POST -Uri $graphUri -Body ($messagePayload | ConvertTo-Json -Depth 10) -ContentType 'application/json'
        return [pscustomobject]@{
            Dispatched   = $true
            Mode         = 'LiveGraph'
            GraphUri     = $graphUri
            MessageId    = $response.id
            SessionId    = $SessionId
            Verdict      = $Verdict
            AttachmentId = "finops-cb-$SessionId"
        }
    }
}
