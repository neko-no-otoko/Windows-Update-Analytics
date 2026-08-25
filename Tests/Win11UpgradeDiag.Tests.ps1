BeforeAll {
    $toolRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $toolRoot 'Modules/Common.psm1') -Force
    Import-Module (Join-Path $toolRoot 'Modules/Analysis.psm1') -Force
}

Describe 'Upgrade extend-code decoding' {
    It 'decodes SafeOS boot' {
        $value = Get-WudPhaseOperation '0x20017'
        $value.Phase | Should -Be 'SafeOS'
        $value.Operation | Should -Be 'Boot'
    }

    It 'decodes OOBE data migration' {
        $value = Get-WudPhaseOperation '0x4000D'
        $value.Phase | Should -Be 'OOBE Boot'
        $value.Operation | Should -Be 'Migrate data'
    }

    It 'does not invent a phase for malformed input' {
        $value = Get-WudPhaseOperation 'not-a-code'
        $value.Phase | Should -BeNullOrEmpty
        $value.Operation | Should -BeNullOrEmpty
    }
}

Describe 'Result and extend-code extraction' {
    It 'normalizes the result and extend code' {
        $value = Get-WudCodesFromText 'Setup failed: 0xc1900101 - 0x20017'
        $value.ResultCode | Should -Be '0xC1900101'
        $value.ExtendCode | Should -Be '0x20017'
    }

    It 'classifies HRESULT and setup extend codes' {
        $value = Get-WudCodesFromText 'Failure 0x80072EE2 followed by 0x20017'
        $value.Codes | Should -Contain '0x80072EE2'
        $value.Codes | Should -Contain '0x20017'
        @($value.CodeDetails | Where-Object Code -eq '0x20017')[0].Type | Should -Be 'SetupExtend'
    }
}

Describe 'Time-zone normalization' {
    It 'orders the repeated DST hour using explicit offsets' {
        $earlier = ConvertTo-WudLogTimestamp '2025-11-02T01:30:00-05:00'
        $later = ConvertTo-WudLogTimestamp '2025-11-02T01:30:00-06:00'
        $earlier.ExplicitOffset | Should -BeTrue
        $later.ExplicitOffset | Should -BeTrue
        ([DateTimeOffset]::Parse($earlier.TimestampUtc)) | Should -BeLessThan ([DateTimeOffset]::Parse($later.TimestampUtc))
    }
}

Describe 'Static data contracts' {
    It 'contains a 25H2 target mapping' {
        $target = Get-WudTargetDefinition -ToolRoot $toolRoot -TargetVersion '25H2'
        $target.buildFamily | Should -Be 26200
    }

    It 'has unique diagnostic rule identifiers' {
        $catalog = Get-Content -LiteralPath (Join-Path $toolRoot 'Data/rules.json') -Raw | ConvertFrom-Json
        @($catalog.rules.id | Select-Object -Unique).Count | Should -Be @($catalog.rules).Count
    }

    It 'versions the rule catalog independently' {
        $catalog = Get-Content -LiteralPath (Join-Path $toolRoot 'Data/rules.json') -Raw | ConvertFrom-Json
        $catalog.catalogVersion | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'ships a machine-readable fleet summary schema' {
        $schema = Get-Content -LiteralPath (Join-Path $toolRoot 'Data/Summary.schema.json') -Raw | ConvertFrom-Json
        $schema.'$id' | Should -Be 'urn:win11upgradediag:summary:1.0.0'
        @($schema.required) | Should -Contain 'Findings'
        @($schema.required) | Should -Contain 'ArtifactHashes'
    }
}

Describe 'Read-only safety contract' {
    BeforeAll {
        $collectorSource = Get-Content -LiteralPath (Join-Path $toolRoot 'Modules/Collectors.psm1') -Raw
    }

    It 'does not invoke repair-mode servicing commands' {
        $collectorSource | Should -Not -Match '(?i)/RestoreHealth|/ScanNow|chkdsk(?:\.exe)?\s+[^\r\n]*(?:/f|/r)'
    }

    It 'does not use Win32_Product inventory' {
        $collectorSource | Should -Not -Match '(?i)Win32_Product'
    }

    It 'gates media execution with scan-only' {
        $collectorSource | Should -Match "'/compat', 'scanonly'"
        $collectorSource | Should -Match '\$dynamicUpdate\s*=\s*''Disable'''
    }
}

Describe 'End-to-end fixture contract' {
    It 'passes parser, correlation, archive, report, schema, persistence, and safety fixtures' {
        { & (Join-Path $PSScriptRoot 'Invoke-FixtureTests.ps1') } | Should -Not -Throw
    }
}
