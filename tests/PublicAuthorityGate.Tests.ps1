BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/..").Path
    if (-not (Test-Path "$repoRoot/.git")) {
        $repoRoot = (Get-Location).Path
    }
}

Describe "Public Authority Repository - 16-Test Governance & Security Gate" {

    Context "Zero-Leak Static Analysis" {
        It "1. Must not contain references to private internal domain" {
            $domPattern = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('bXZwZm91bmRyeS5hbGVyYXNvdWwubmV0'))
            $matches = Get-ChildItem -Path $repoRoot -Recurse -File |
                Where-Object { $_.FullName -notmatch '[\\/]\.git|[\\/]\.githooks' -and $_.Name -notmatch '\.(png|jpg|ico|svg)$|PublicAuthorityGate\.Tests\.ps1' } |
                Select-String -Pattern $domPattern -SimpleMatch
            $matches | Should -BeNullOrEmpty
        }

        It "2. Must not contain references to internal VPS dedicated IP" {
            $ipPattern = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('MTkyLjE0Mi40MS40Mw=='))
            $matches = Get-ChildItem -Path $repoRoot -Recurse -File |
                Where-Object { $_.FullName -notmatch '[\\/]\.git|[\\/]\.githooks' -and $_.Name -notmatch '\.(png|jpg|ico|svg)$|PublicAuthorityGate\.Tests\.ps1' } |
                Select-String -Pattern $ipPattern -SimpleMatch
            $matches | Should -BeNullOrEmpty
        }

        It "3. Must not expose Entra ID JWT tokens or bearer tokens" {
            $matches = Get-ChildItem -Path $repoRoot -Recurse -File |
                Where-Object { $_.FullName -notmatch '[\\/]\.git|[\\/]\.githooks' -and $_.Name -notmatch '\.(png|jpg|ico|svg)$|PublicAuthorityGate\.Tests\.ps1' } |
                Select-String -Pattern 'ey[A-Za-z0-9_-]{30,}\.ey[A-Za-z0-9_-]{30,}'
            $matches | Should -BeNullOrEmpty
        }

        It "4. Must not contain raw private keys or certificates" {
            $matches = Get-ChildItem -Path $repoRoot -Recurse -File |
                Where-Object { $_.FullName -notmatch '[\\/]\.git|[\\/]\.githooks' -and $_.Name -notmatch '\.(png|jpg|ico|svg)$|PublicAuthorityGate\.Tests\.ps1' } |
                Select-String -Pattern '-----BEGIN (?:RSA|EC|DSA|OPENSSH|PRIVATE) KEY-----'
            $matches | Should -BeNullOrEmpty
        }
    }

    Context "Centralized Governance & De-Autonomisation" {
        It "5. Must not contain standalone .github/dependabot.yml or dependabot.yaml" {
            Test-Path "$repoRoot/.github/dependabot.yml" | Should -Be $false
            Test-Path "$repoRoot/.github/dependabot.yaml" | Should -Be $false
        }

        It "6. Must not contain renovate.json or .renovaterc" {
            Test-Path "$repoRoot/renovate.json" | Should -Be $false
            Test-Path "$repoRoot/.github/renovate.json" | Should -Be $false
            Test-Path "$repoRoot/.renovaterc" | Should -Be $false
        }

        It "7. Must not contain unauthorized autonomous scheduled cron workflows" {
            $workflowFiles = Get-ChildItem -Path "$repoRoot/.github/workflows" -Filter "*.yml" -ErrorAction SilentlyContinue
            foreach ($wf in $workflowFiles) {
                $content = Get-Content $wf.FullName -Raw
                if ($wf.Name -ne "weekly-fleet-conductor.yml") {
                    $hasCron = $content -match "schedule\s*:"
                    $hasCron | Should -Be $false -Because "Target repository workflows must not run unsanctioned independent crons; central control-plane owns schedules."
                }
            }
        }
    }

    Context "Baseline Compliance" {
        It "8. Must have canonical .editorconfig in root" {
            Test-Path "$repoRoot/.editorconfig" | Should -Be $true
        }

        It "9. Must have Zero-Leak pre-commit hook installed" {
            $hookExists = (Test-Path "$repoRoot/.githooks/gitleaks-pre-commit.ps1") -or (Test-Path "$repoRoot/.git/hooks/pre-commit")
            $hookExists | Should -Be $true
        }

        It "10. Workflows must not reference legacy action versions (checkout@v1-v3)" {
            $workflowFiles = Get-ChildItem -Path "$repoRoot/.github/workflows" -Filter "*.yml" -ErrorAction SilentlyContinue
            foreach ($wf in $workflowFiles) {
                $content = Get-Content $wf.FullName -Raw
                $content | Should -Not -Match "actions/checkout@(v1|v2|v3)\b"
                $content | Should -Not -Match "actions/setup-node@(v1|v2|v3)\b"
            }
        }

        It "11. Workflows must specify explicit permissions block" {
            $workflowFiles = Get-ChildItem -Path "$repoRoot/.github/workflows" -Filter "*.yml" -ErrorAction SilentlyContinue
            foreach ($wf in $workflowFiles) {
                $content = Get-Content $wf.FullName -Raw
                $content | Should -Match "permissions\s*:"
            }
        }
    }

    Context "Repository Hygiene & Identity" {
        It "12. Must have a populated README.md" {
            Test-Path "$repoRoot/README.md" | Should -Be $true
            (Get-Item "$repoRoot/README.md").Length | Should -BeGreaterThan 50
        }

        It "13. Public authority repo must have a LICENSE file" {
            $hasLicense = (Test-Path "$repoRoot/LICENSE") -or (Test-Path "$repoRoot/LICENSE.md") -or (Test-Path "$repoRoot/LICENSE.txt")
            $hasLicense | Should -Be $true
        }

        It "14. Must not commit environment files (.env, .env.local)" {
            $envFiles = Get-ChildItem -Path $repoRoot -Filter ".env*" -File -Recurse -Exclude *.example*,*.template*
            $envFiles | Should -BeNullOrEmpty
        }

        It "15. Must not track editor backup files (*.bak, *.swp, *~)" {
            $bakFiles = Get-ChildItem -Path $repoRoot -Include "*.bak","*.swp","*~" -File -Recurse
            $bakFiles | Should -BeNullOrEmpty
        }

        It "16. Must contain centralized sovereign-repo-conductor header in managed workflows" {
            $workflowFiles = Get-ChildItem -Path "$repoRoot/.github/workflows" -Filter "*.yml" -ErrorAction SilentlyContinue
            foreach ($wf in $workflowFiles) {
                $header = Get-Content $wf.FullName -TotalCount 5
                ($header -join "`n") | Should -Match "Managed centrally by ShahradGH/sovereign-repo-conductor"
            }
        }
    }
}

