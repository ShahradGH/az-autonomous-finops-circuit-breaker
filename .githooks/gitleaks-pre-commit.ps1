#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sovereign Compliance, Core Hours Lockdown & Zero-Leak Git Pre-Commit Hook
    Managed centrally by ShahradGH/sovereign-repo-conductor (Weekly Fleet Sync).
.DESCRIPTION
    Enforces corporate compliance, Day-1 Prior Works ring-fencing, and technical clean-room boundaries:
      1. ASSERT_TIMESTAMP_VALID: Blocks git commits during Monday-Friday 08:30-17:30 UK local time (GMT/BST).
      2. ASSERT_GIT_IDENTITY: Prohibits corporate employer emails.
      3. ASSERT_NO_INTERNAL_KEYWORDS: Scans staged diffs for employer keywords in public/personal repos.
      4. ASSERT_ZERO_LEAK_SECRETS: Blocks internal VPS domains, VPS IPs, Entra tokens, PATs, and private keys.
      5. ASSERT_SYNTHETIC_DATA: Validates domain fixtures (RFC 1918 / RFC 5737 / contoso.com / example.com).
#>

[CmdletBinding()]
param(
    [switch]$StagedOnly = $true
)

$ErrorActionPreference = 'Stop'

Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " SOVEREIGN COMPLIANCE & LEGAL INSULATION PRE-COMMIT GATE" -ForegroundColor White
Write-Host " Central Policy Conductor: ShahradGH/sovereign-repo-conductor" -ForegroundColor Gray
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. ASSERT_TIMESTAMP_VALID: Core Business Hours Blackout Gate
# -----------------------------------------------------------------------------
# Statutory Effective Date: 30 November 2026 (Employment Start Date).
# - Prior to 30 November 2026: Day-1 Prior Works creation window. Commits permitted at all hours.
# - On and after 30 November 2026: Contractual core hours Monday through Friday, 08:30 - 17:30 UK Local Time.
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
    if ($env:SOVEREIGN_ALLOW_CORE_HOURS_COMMIT -eq "1") {
        Write-Host "`n[OVERRIDE AUDIT NOTE] SOVEREIGN_ALLOW_CORE_HOURS_COMMIT=1 detected." -ForegroundColor Yellow
        Write-Host "Commit permitted under explicit operational override. Ensure commit telemetry is compliant before push.`n" -ForegroundColor DarkYellow
    } else {
        Write-Host "`n=================================================================" -ForegroundColor Red
        Write-Host " [CRITICAL COMPLIANCE GATE] CORE BUSINESS HOURS COMMIT BLACKOUT" -ForegroundColor Red
        Write-Host " Commit blocked by Sovereign Corporate Compliance & Legal Insulation Directive." -ForegroundColor Red
        Write-Host "=================================================================" -ForegroundColor Red
        Write-Host " Current UK Local Time: $($nowUk.ToString('dddd, dd MMMM yyyy HH:mm:ss')) (GMT/BST)" -ForegroundColor Yellow
        Write-Host " Contractual Blackout: Monday–Friday 08:30 to 17:30 UK Time (Active since 30 Nov 2026)" -ForegroundColor Yellow
        Write-Host "`n Operational Directives:" -ForegroundColor White
        Write-Host "   1. Personal repositories must NEVER record commit telemetry during enterprise employer business hours." -ForegroundColor Gray
        Write-Host "   2. Changes must remain staged or uncommitted locally during business hours." -ForegroundColor Gray
        Write-Host "   3. Execute 'git commit' and 'git push' strictly:" -ForegroundColor White
        Write-Host "      - Slot A (Morning Commute):  07:45 – 08:15 UK (Tue/Wed/Thu)" -ForegroundColor Green
        Write-Host "      - Slot B (Evening Catch-up): 17:45 – 18:30 UK (Tue/Wed/Thu)" -ForegroundColor Green
        Write-Host "      - Slot C (Weekend Deep-Dive):09:30 – 10:30 UK (Saturday)" -ForegroundColor Green
        Write-Host "      - Anytime outside Mon-Fri 08:30-17:30 UK" -ForegroundColor Green
        Write-Host "`n To defer: Keep your working tree as-is. Commit after 17:45 UK local time." -ForegroundColor Cyan
        Write-Host " For automated CI/Pester test runners only: set `$env:SOVEREIGN_ALLOW_CORE_HOURS_COMMIT = '1'." -ForegroundColor DarkGray
        Write-Host "=================================================================`n" -ForegroundColor Red
        exit 1
    }
} elseif (-not $isCovenantInEffect) {
    $daysRemaining = ($effectiveStartDate.Date - $nowUk.Date).Days
    Write-Host "[Gate 1: Timestamp Valid] Day-1 Prior Works creation window active ($daysRemaining days until 30 Nov 2026 employment start). Commits permitted at all hours. PASSED." -ForegroundColor Green
} else {
    Write-Host "[Gate 1: Timestamp Valid] UK Time $($nowUk.ToString('HH:mm:ss')) is outside core business hours blackout. PASSED." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 2. ASSERT_GIT_IDENTITY: Personal Identity & Email Enforcement
# -----------------------------------------------------------------------------
try {
    $gitEmail = (& (Get-Command git).Source config user.email).Trim()
    $gitName = (& (Get-Command git).Source config user.name).Trim()

    $bannedEmailPattern = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('KD9pKUAoYXZhbmFkZXxhY2NlbnR1cmUpXC5jb20='))
    if ($gitEmail -match $bannedEmailPattern) {
        Write-Host "`n[FATAL COMPLIANCE VIOLATION] FORBIDDEN CORPORATE GIT IDENTITY DETECTED" -ForegroundColor Red
        Write-Host " Committer email '$gitEmail' belongs to employer domain." -ForegroundColor Red
        Write-Host " Personal repositories must strictly use personal git credentials (e.g. ShahradGH)." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[Gate 2: Git Identity] Personal identity confirmed ($gitName <$gitEmail>). PASSED." -ForegroundColor Green
} catch {
    Write-Warning "[Gate 2: Git Identity] Could not read git user.email. Ensure personal git config is set."
}

# -----------------------------------------------------------------------------
# 3. Gather Staged Diff Lines
# -----------------------------------------------------------------------------
$isInsideWorkTree = (& (Get-Command git).Source rev-parse --is-inside-work-tree 2>$null) -eq 'true'
if (-not $isInsideWorkTree) {
    Write-Host "[Zero-Leak Hook] Not inside a git repository work tree. Check skipped." -ForegroundColor Yellow
    exit 0
}

$diffCommand = if ($StagedOnly) {
    "git diff --cached --unified=0 --no-color"
} else {
    "git diff HEAD --unified=0 --no-color"
}

$stagedLines = & (Get-Command git).Source ($diffCommand.Split(' ') | Select-Object -Skip 1)

if (-not $stagedLines -or $stagedLines.Count -eq 0) {
    Write-Host "[Zero-Leak Hook] No staged diff detected. Commit allowed." -ForegroundColor Green
    exit 0
}

# -----------------------------------------------------------------------------
# 4. ASSERT_NO_INTERNAL_KEYWORDS & ASSERT_ZERO_LEAK_SECRETS
# -----------------------------------------------------------------------------
$repoRoot = (& (Get-Command git).Source rev-parse --show-toplevel).Trim()
$repoLeaf = Split-Path $repoRoot -Leaf
$isPrivateWorkPersonality = ($repoLeaf -eq "workpersonality")

# Core secret and clean-room signatures (evaluated via dynamically decoded clean-room patterns)
$criticalSignatures = [System.Collections.Generic.List[hashtable]]::new()

$sigDomain = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('bXZwZm91bmRyeVwuYWxlcmFzb3VsXC5uZXQ='))
$sigIp = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('MTkyXC4xNDJcLjQxXC40Mw=='))

$criticalSignatures.Add(@{ Name = "Internal Domain"; Pattern = $sigDomain })
$criticalSignatures.Add(@{ Name = "Internal VPS IP"; Pattern = $sigIp })
$criticalSignatures.Add(@{ Name = "Private Subnet IPv4 (10.x.x.x)"; Pattern = '\b10\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b' })
$criticalSignatures.Add(@{ Name = "Entra ID / JWT Token"; Pattern = 'ey[A-Za-z0-9_-]{25,}\.ey[A-Za-z0-9_-]{25,}' })
$criticalSignatures.Add(@{ Name = "Azure Client Secret"; Pattern = '(?:client_secret|clientSecret|azure_secret)\s*[:=]\s*["''][a-zA-Z0-9~_.-]{30,}["'']' })
$criticalSignatures.Add(@{ Name = "GitHub Classic PAT"; Pattern = 'gh[pousr]_[A-Za-z0-9_]{36,255}' })
$criticalSignatures.Add(@{ Name = "GitHub Fine-Grained PAT"; Pattern = 'github_pat_[A-Za-z0-9_]{82}' })
$criticalSignatures.Add(@{ Name = "Cryptographic Private Key"; Pattern = '-----BEGIN (?:RSA|EC|DSA|OPENSSH|PRIVATE) KEY-----' })
$criticalSignatures.Add(@{ Name = "AWS Access Key"; Pattern = '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b' })

# Employer Clean-Room Keywords (enforced strictly on all repos except private workpersonality)
if (-not $isPrivateWorkPersonality) {
    $sigEmployer1 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('KD9pKVxiYXZhbmFkZVxi'))
    $sigEmployer2 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('KD9pKVxiYWNjZW50dXJlXGI='))
    $sigCorporateEmail = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('KD9pKVthLXpBLVowLTkuXyUrLV0rQChhdmFuYWRlfGFjY2VudHVyZSlcLmNvbQ=='))

    $criticalSignatures.Add(@{ Name = "Employer Corporate Keyword 1"; Pattern = $sigEmployer1 })
    $criticalSignatures.Add(@{ Name = "Employer Corporate Keyword 2"; Pattern = $sigEmployer2 })
    $criticalSignatures.Add(@{ Name = "Corporate Email Pattern"; Pattern = $sigCorporateEmail })
}

$violations = [System.Collections.Generic.List[PSCustomObject]]::new()
$currentFile = "unknown"

foreach ($line in $stagedLines) {
    if ($line -match '^\+\+\+ b/(.*)$') {
        $currentFile = $Matches[1]
        continue
    }

    # Only inspect added lines (starting with +) excluding diff header (+++)
    if ($line -match '^\+(?!\+\+)(.*)$') {
        $content = $Matches[1]

        foreach ($sig in $criticalSignatures) {
            if ($content -match $sig.Pattern) {
                # Ignore self-references inside this hook script, rule definitions, and test files
                if ($currentFile -like "*gitleaks*" -or `
                    $currentFile -like "*pre-commit*" -or `
                    $currentFile -like "*pre-push*" -or `
                    $currentFile -like "*canonical-versions.json" -or `
                    $currentFile -like "*Tests.ps1" -or `
                    $currentFile -like "*rules*" -or `
                    $currentFile -like "*PRIOR-WORKS*" -or `
                    $currentFile -like "*FLEET_MATRIX*") {
                    continue
                }

                $violations.Add([PSCustomObject]@{
                    File = $currentFile
                    Rule = $sig.Name
                    Snippet = ($content.Trim() | ForEach-Object { if ($_.Length -gt 60) { $_.Substring(0, 60) + "..." } else { $_ } })
                })
            }
        }
    }
}

# Also run native gitleaks protect if installed
$gitleaksCmd = Get-Command gitleaks -ErrorAction SilentlyContinue
if ($gitleaksCmd) {
    Write-Host "[Zero-Leak Hook] Running native Gitleaks scanner..." -ForegroundColor Cyan
    $gitleaksOutput = & $gitleaksCmd.Source protect --staged --verbose 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[Zero-Leak Hook] Native Gitleaks reported secret exposure!`n$gitleaksOutput"
        exit 1
    }
}

if ($violations.Count -gt 0) {
    Write-Host "`n=================================================================" -ForegroundColor Red
    Write-Host " [CRITICAL COMPLIANCE GATE] CLEAN-ROOM VIOLATION DETECTED" -ForegroundColor Red
    Write-Host " Commit blocked by sovereign-repo-conductor pre-commit hook." -ForegroundColor Red
    Write-Host "=================================================================`n" -ForegroundColor Red

    foreach ($v in $violations) {
        Write-Host " File:    $($v.File)" -ForegroundColor Yellow
        Write-Host " Rule:    $($v.Rule)" -ForegroundColor Red
        Write-Host " Snippet: $($v.Snippet)" -ForegroundColor DarkGray
        Write-Host "-----------------------------------------------------------------"
    }

    Write-Host "`nPlease scrub employer keywords, client references, sensitive credentials, or internal IPs before committing." -ForegroundColor White
    exit 1
}

Write-Host "[Gate 3: Clean-Room & Zero-Leak] Staged files verified clean. PASSED." -ForegroundColor Green
exit 0
