#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sovereign Compliance, Core Hours Lockdown & Network Telemetry Git Pre-Push Hook
    Managed centrally by ShahradGH/sovereign-repo-conductor (Weekly Fleet Sync).
.DESCRIPTION
    Enforces the Core Business Hours Commit & Push Blackout Directive:
      1. ASSERT_PUSH_TIMESTAMP_VALID: Hard-blocks git push operations during
         Monday-Friday 08:30-17:30 UK local time (GMT/BST) commencing 30 November 2026.
         Guarantees zero working-hours git push telemetry on public GitHub streams.
      2. ASSERT_GIT_IDENTITY: Prohibits corporate employer emails.
      3. ASSERT_OUTGOING_COMMITS_CLEAN: Scans commits scheduled for push to ensure no
         working-hours author dates were recorded after the effective date.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RemoteName,

    [Parameter(Position = 1)]
    [string]$RemoteUrl
)

$ErrorActionPreference = 'Stop'

Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " SOVEREIGN COMPLIANCE & TELEMETRY PRE-PUSH GATE" -ForegroundColor White
Write-Host " Central Policy Conductor: ShahradGH/sovereign-repo-conductor" -ForegroundColor Gray
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. ASSERT_PUSH_TIMESTAMP_VALID: Core Business Hours Push Blackout Gate
# -----------------------------------------------------------------------------
$effectiveStartDate = [datetime]::Parse("2026-11-30T00:00:00Z")
$ukTz = [System.TimeZoneInfo]::FindSystemTimeZoneById("GMT Standard Time")
$nowUk = [System.TimeZoneInfo]::ConvertTimeFromUtc([System.DateTime]::UtcNow, $ukTz)
$dayOfWeek = $nowUk.DayOfWeek
$timeOfDay = $nowUk.TimeOfDay
$blackoutStart = [System.TimeSpan]::Parse("08:30:00")
$blackoutEnd = [System.TimeSpan]::Parse("17:30:00")

$isBusinessDay = ($dayOfWeek -ge [System.DayOfWeek]::Monday -and $dayOfWeek -le [System.DayOfWeek]::Friday)
$isCoreHours = ($isBusinessDay -and $timeOfDay -ge $blackoutStart -and $timeOfDay -le $blackoutEnd)
$isCovenantInEffect = ($nowUk.Date -ge $effectiveStartDate.Date)

if ($isCovenantInEffect -and $isCoreHours) {
    if ($env:SOVEREIGN_ALLOW_CORE_HOURS_PUSH -eq "1") {
        Write-Host "`n[OVERRIDE AUDIT NOTE] SOVEREIGN_ALLOW_CORE_HOURS_PUSH=1 detected." -ForegroundColor Yellow
        Write-Host "Push permitted under explicit operational override. Exercise extreme caution.`n" -ForegroundColor DarkYellow
    } else {
        Write-Host "`n=================================================================" -ForegroundColor Red
        Write-Host " [CRITICAL COMPLIANCE GATE] CORE BUSINESS HOURS PUSH BLACKOUT" -ForegroundColor Red
        Write-Host " Git push blocked by Sovereign Corporate Compliance & Legal Insulation Directive." -ForegroundColor Red
        Write-Host "=================================================================" -ForegroundColor Red
        Write-Host " Current UK Local Time: $($nowUk.ToString('dddd, dd MMMM yyyy HH:mm:ss')) (GMT/BST)" -ForegroundColor Yellow
        Write-Host " Contractual Blackout: Monday–Friday 08:30 to 17:30 UK Time (Active since 30 Nov 2026)" -ForegroundColor Yellow
        Write-Host "`n Public Telemetry Directive:" -ForegroundColor White
        Write-Host "  - Pushing to GitHub during core hours leaks public 'pushed_at' network timestamps." -ForegroundColor Gray
        Write-Host "  - All network pushes must be deferred to Slot B (17:45-18:30 UK) or Slot A (07:45-08:15 UK)." -ForegroundColor Gray
        Write-Host "  - Local commits are safely stored on your workstation. No work is lost." -ForegroundColor Gray
        Write-Host "`n Push Window Targets:" -ForegroundColor Cyan
        Write-Host "  - Slot B (This Evening): Today at 17:45 UK Local Time" -ForegroundColor Green
        Write-Host "  - Slot A (Tomorrow Morning): Tomorrow at 07:45 UK Local Time" -ForegroundColor Green
        Write-Host "`n If this is an emergency non-workstation action, bypass with:" -ForegroundColor DarkGray
        Write-Host '   $env:SOVEREIGN_ALLOW_CORE_HOURS_PUSH="1"; git push' -ForegroundColor DarkGray
        Write-Host "=================================================================`n" -ForegroundColor Red
        exit 1
    }
} else {
    if (-not $isCovenantInEffect) {
        Write-Host "[Gate 1: Telemetry Blackout] Phase 1 Pre-Effective Window (Prior to 30 Nov 2026). Network push permitted. PASSED." -ForegroundColor Green
    } else {
        Write-Host "[Gate 1: Telemetry Blackout] Outside Core Business Hours ($($nowUk.ToString('HH:mm')) UK). PASSED." -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# 2. ASSERT_GIT_IDENTITY: Personal Identity Verification Gate
# -----------------------------------------------------------------------------
$gitUserEmail = (& git config user.email 2>$null)
$gitUserName = (& git config user.name 2>$null)

if ([string]::IsNullOrWhiteSpace($gitUserEmail)) {
    $gitUserEmail = (& git config --global user.email 2>$null)
}
if ([string]::IsNullOrWhiteSpace($gitUserName)) {
    $gitUserName = (& git config --global user.name 2>$null)
}

$bannedEmailPattern = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('KD9pKUAoYXZhbmFkZXxhY2NlbnR1cmUpXC5jb20='))
if ($gitUserEmail -match $bannedEmailPattern) {
    Write-Host "`n=================================================================" -ForegroundColor Red
    Write-Host " [CRITICAL COMPLIANCE GATE] CORPORATE IDENTITY CONTAMINATION DETECTED" -ForegroundColor Red
    Write-Host "=================================================================" -ForegroundColor Red
    Write-Host " Git Email configured as: $gitUserEmail" -ForegroundColor Yellow
    Write-Host " Corporate employer credentials are strictly forbidden on personal repositories." -ForegroundColor White
    Write-Host " Configure personal identity before pushing: git config user.email 'shahrad@users.noreply.github.com'" -ForegroundColor White
    exit 1
}

Write-Host "[Gate 2: Personal Identity] Git identity verified ($gitUserEmail). PASSED." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 3. ASSERT_OUTGOING_COMMITS: Check Outgoing Commits for Core-Hours Telemetry
# -----------------------------------------------------------------------------
if ($isCovenantInEffect) {
    try {
        $upstreamRef = "@{u}"
        $outgoingCommitDates = (& git log "$upstreamRef..HEAD" --format="%aI" 2>$null)
        if ($outgoingCommitDates) {
            foreach ($dateStr in $outgoingCommitDates) {
                if ([string]::IsNullOrWhiteSpace($dateStr)) { continue }
                $commitUtc = [datetime]::Parse($dateStr).ToUniversalTime()
                $commitUk = [System.TimeZoneInfo]::ConvertTimeFromUtc($commitUtc, $ukTz)
                $cDay = $commitUk.DayOfWeek
                $cTime = $commitUk.TimeOfDay
                if ($commitUk.Date -ge $effectiveStartDate.Date -and ($cDay -ge [System.DayOfWeek]::Monday -and $cDay -le [System.DayOfWeek]::Friday) -and ($cTime -ge $blackoutStart -and $cTime -le $blackoutEnd)) {
                    Write-Host "`n[CRITICAL WARNING] Outgoing commit recorded author timestamp inside core hours: $($commitUk.ToString('yyyy-MM-dd HH:mm:ss')) UK" -ForegroundColor Red
                    Write-Host "Amend the commit timestamp outside core hours before pushing to protect telemetry." -ForegroundColor Yellow
                    if ($env:SOVEREIGN_ALLOW_CORE_HOURS_PUSH -ne "1") {
                        exit 1
                    }
                }
            }
        }
    } catch {
        # Untracked or new branch
    }
}

Write-Host "[Gate 3: Telemetry Verification] Ready for remote distribution. PASSED." -ForegroundColor Green
exit 0

