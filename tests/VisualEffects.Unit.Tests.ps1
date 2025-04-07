#Requires -Modules @{ModuleName='Pester'; MaximumVersion='5.99.99'}

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('AvoidDeprecatedCommands', '',
    Justification = 'Test-Json is skipped in PowerShell 5')]
[CmdletBinding()]
param ()

BeforeDiscovery {
    # Get the module path and name, even if we are in nested sub-directories
    $manifestPath = $PSScriptRoot -replace '(\w+)\\Tests\b.*', '$1\$1.psd1'
    $moduleName = $manifestPath -replace '.*\\|\.psd1'
    $modulePath = $PSScriptRoot -replace '\\Tests\b.*'

    Get-Module $moduleName | Remove-Module
    # Importing module to build test cases in Discovery
    Import-Module $manifestPath -Force

    $legacyPowerShell = $PSEdition -ne 'Core'
    $definitionFiles = Get-ChildItem "$modulePath\Definitions\*.json"
    $presetFiles = Get-ChildItem "$modulePath\Presets\*.json"
}

BeforeAll {
    # Get the module path and name, even if we are in nested sub-directories
    $manifestPath = $PSScriptRoot -replace '(\w+)\\Tests\b.*', '$1\$1.psd1'
    $moduleName = $manifestPath -replace '.*\\|\.psd1'
    $modulePath = $PSScriptRoot -replace '\\Tests\b.*'

    # Mock function to track when Set() made a change
    function MockFunction {[CmdletBinding()]param()}
    Mock MockFunction {}

    Mock Get-VisualEffectInstance {
        $result = [pscustomobject]@{
            Name        = $Name
            Enabled     = $effectEnabled
            Description = "Some description about $Name"
        }
        $result | Add-Member -MemberType ScriptMethod -Name Set -Value {
            if ($this.Enabled -ne $args[0]) {MockFunction}
        }
        $result
    } -ModuleName $moduleName

    # Splat variable for repeated use of Should -Invoke (in module scope)
    $onceInModule = @{
        ModuleName = $moduleName
        Exactly    = $true
    }
}

Describe 'JSON files' {
    It 'Definition file <_.Name> should conform to its schema' -Skip:$legacyPowerShell -ForEach $definitionFiles {
        $schema = "$($_.DirectoryName)\Schema\$($_.BaseName)-Schema.json"
        Test-Json -Path $_.FullName -SchemaFile $schema -ErrorAction SilentlyContinue | Should -BeTrue
    }
    It 'Preset file <_.Name> should conform to its schema' -Skip:$legacyPowerShell -ForEach $presetFiles {
        $schema = "$($_.DirectoryName)\Schema\Presets-Schema.json"
        Test-Json -Path $_.FullName -SchemaFile $schema -ErrorAction SilentlyContinue | Should -BeTrue
    }
}

Describe 'Classes and enums' {
    It 'EffectName enum should match effect definitions' -ForEach @(, $definitionFiles) {
        $effects = $_ | Get-Content -Raw | ConvertFrom-Json
        $enum = InModuleScope $moduleName {[Enum]::GetNames([EffectName])}
        compare $effects.List.Name $enum -PassThru | Should -BeNullOrEmpty
    }
    It 'EffectNamePreset enum should match preset definitions' -Foreach @(, $presetFiles) {
        $enum = InModuleScope $moduleName {[Enum]::GetNames([EffectPreset])}
        compare $_.BaseName $enum -PassThru | Should -BeNullOrEmpty
    }
}

Describe 'Get-VisualEffect' {
    Context 'When a Visual Effect Does Not Exist' {
        It 'The parameter filter for enums picks this up and throws' {
            {Get-VisualEffect -Name 'NotExist'} |
                Should -Throw '*Cannot convert value "NotExist" to type "EffectName"*'
        }
    }

    Context 'When a single Visual Effect is requested by param' {
        It 'Get-VisualEffectInstance mock should be called once by name' {
            Get-VisualEffect -Name 'Animation' | Out-Null
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq 'Animation'}
        }
    }

    Context 'When a single Visual Effect is requested by pipeline' {
        It 'Get-VisualEffectInstance mock should be called once by name' {
            'Animation' | Get-VisualEffect | Out-Null
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq 'Animation'}
        }
    }

    Context 'When multiple Visual Effects are requested by param' {
        BeforeEach {
            Get-VisualEffect -Name 'Animation', 'CursorShadow' | Out-Null
        }

        It 'Get-VisualEffectInstance should be called once for <_>' -ForEach @('Animation', 'CursorShadow') {
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq $_}
        }
    }

    Context 'When multiple Visual Effects are requested by pipeline' {
        BeforeEach {
            'Animation', 'CursorShadow' | Get-VisualEffect | Out-Null
        }

        It 'Get-VisualEffectInstance should be called once for <_>' -ForEach @('Animation', 'CursorShadow') {
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq $_}
        }
    }
}

Describe 'Set-VisualEffect' {
    BeforeAll {
        Mock Set-ItemProperty {} -ModuleName $moduleName -ParameterFilter {$Name -eq 'VisualFXSetting'}
    }

    Context 'When a Visual Effect Does Not Exist' {
        It 'The parameter filter for enums picks this up and throws' {
            {Set-VisualEffect -Name 'NotExist' -Enabled $true} |
                Should -Throw '*Cannot convert value "NotExist" to type "EffectName"*'
        }
    }

    Context 'When a single Visual Effect is enabled by param and it is currently disabled' {
        BeforeEach {
            # Ensure the Get Method on mocked Get-VisualEffectInstance returns false
            $effectEnabled = $false
            Set-VisualEffect -Name 'Animation' -Enabled $true | Out-Null
        }

        It 'Get-VisualEffectInstance mock should be called once by name' {
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq 'Animation'}
        }
        It 'MockFunction should be called once' {
            Should -Invoke MockFunction -Exactly
        }
        It 'VisualFXSetting should be set' {
            Should -Invoke @onceInModule Set-ItemProperty
        }
    }

    Context 'When a single Visual Effect is enabled by pipeline and it is currently disabled' {
        BeforeEach {
            $effectEnabled = $false
            'Animation' | Set-VisualEffect -Enabled $true | Out-Null
        }

        It 'Get-VisualEffectInstance mock should be called once by name' {
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq 'Animation'}
        }
        It 'MockFunction should be called once' {
            Should -Invoke MockFunction -Exactly
        }
        It 'VisualFXSetting should be set' {
            Should -Invoke @onceInModule Set-ItemProperty
        }
    }

    Context 'When multiple Visual Effects are enabled by pipeline and they are currently disabled' {
        BeforeEach {
            $effectEnabled = $false
            'Animation', 'CursorShadow' | Set-VisualEffect -Enabled $true | Out-Null
        }

        It 'Get-VisualEffectInstance should be called once for <_>' -ForEach @('Animation', 'CursorShadow') {
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq $_}
        }
        It 'MockFunction should be called twice' {
            Should -Invoke MockFunction -Exactly -Times 2
        }
        It 'VisualFXSetting should be set' {
            Should -Invoke @onceInModule Set-ItemProperty
        }
    }

    Context 'Running in -WhatIf mode' {
        BeforeAll {
            # Using BeforeAll and -Scope Context so we only see the WhatIf message once
            Set-VisualEffect -Name 'Animation' -Enabled $true -WhatIf
        }

        It 'Get-VisualEffectInstance mock should be called once by name' {
            Should -Invoke @onceInModule Get-VisualEffectInstance -Scope Context -ParameterFilter {
                $Name -eq 'Animation'
            }
        }
        It 'MockFunction should not be called' {
            Should -Invoke MockFunction -Times 0 -Scope Context
        }
        It 'VisualFXSetting should not be set' {
            Should -Invoke Set-ItemProperty -ModuleName $moduleName -Times 0 -Scope Context
        }
    }

    Context 'When a single Visual Effect is enabled by param and it is currently enabled' {
        BeforeEach {
            # Ensure the Get Method on mocked Get-VisualEffectInstance returns true
            $effectEnabled = $true
            Set-VisualEffect -Name 'Animation' -Enabled $true | Out-Null
        }

        It 'Get-VisualEffectInstance mock should be called once by name' {
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq 'Animation'}
        }
        It 'MockFunction should not be called' {
            Should -Invoke MockFunction -Times 0
        }
        It 'VisualFXSetting should not be set' {
            Should -Invoke Set-ItemProperty -ModuleName $moduleName -Times 0
        }
    }

    Context 'When a single Visual Effect is enabled by pipeline and it is currently enabled' {
        BeforeEach {
            $effectEnabled = $true
            'Animation' | Set-VisualEffect -Enabled $true | Out-Null
        }

        It 'Get-VisualEffectInstance mock should be called once by name' {
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq 'Animation'}
        }
        It 'MockFunction should not be called' {
            Should -Invoke MockFunction -Times 0
        }
        It 'VisualFXSetting should not be set' {
            Should -Invoke Set-ItemProperty -ModuleName $moduleName -Times 0
        }
    }

    Context 'When multiple Visual Effects are enabled by pipeline and they are currently enabled' {
        BeforeEach {
            $effectEnabled = $true
            'Animation', 'CursorShadow' | Set-VisualEffect -Enabled $true | Out-Null
        }

        It 'Get-VisualEffectInstance should be called once for <_>' -ForEach @('Animation', 'CursorShadow') {
            Should -Invoke @onceInModule Get-VisualEffectInstance -ParameterFilter {$Name -eq $_}
        }
        It 'MockFunction should not be called' {
            Should -Invoke MockFunction -Times 0
        }
        It 'VisualFXSetting should not be set' {
            Should -Invoke Set-ItemProperty -ModuleName $moduleName -Times 0
        }
    }
}

Describe 'Get-VisualEffectPreset' {
    BeforeDiscovery {
        $presets = Get-VisualEffectPreset
    }

    It 'There are at least 2 presets' -Foreach @(, $presets) {
        $_.Count | Should -BeGreaterOrEqual 2
    }

    Context 'Preset <_.Name>' -ForEach $presets {
        It 'Has a <Attribute> property' -ForEach @(
                @{Attribute = 'Name'; Value = $_.Name}
                @{Attribute = 'Description'; Value = $_.Description}
                @{Attribute = 'Settings'; Value = $_.Settings}
        ) {
            $Value | Should -Not -BeNullOrEmpty
        }
        It 'Setting <_.Name> has an Enabled property' -ForEach $_.Settings {
            $_.Enabled | Should -BeOfType [bool]
        }
    }
}

Describe 'Set-VisualEffectPreset' {
    BeforeAll {
        # Local Mocks
        Mock Set-VisualEffect {} -ModuleName $moduleName

        $testPreset = Get-VisualEffectPreset | select -First 1
    }

    Context 'When a Preset is applied' {
        It 'There should be settings found' {
            $testPreset.Settings.Count | Should -BeGreaterThan 5
        }
        It 'Set-VisualEffect mock should be called for each setting' {
            Set-VisualEffectPreset -Name $testPreset.Name
            Should -Invoke Set-VisualEffect -ModuleName $moduleName -Exactly $testPreset.Settings.Count
        }
    }
}
