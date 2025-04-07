#Requires -Modules @{ModuleName='Pester'; MaximumVersion='5.99.99'}

BeforeAll {
    # Get the module path and name, even if we are in nested sub-directories
    $manifestPath = $PSScriptRoot -replace '(\w+)\\Tests\b.*', '$1\$1.psd1'
    $moduleName = $manifestPath -replace '.*\\|\.psd1'

    Get-Module $moduleName | Remove-Module
    Import-Module $manifestPath -Force
}

Describe 'Get-VisualEffectInstance' {
    Context 'When a <Type> effect is requested' -ForEach @(
        @{Name = 'TaskbarAnimations'; Type = 'VisualEffectRegistry'; Broadcast = 'VisualEffects'}
        @{Name = 'ClientAreaAnimation'; Type = 'VisualEffectSPI'; Broadcast = $null}
        @{Name = 'Animation'; Type = 'VisualEffectSPIAnimation'; Broadcast = $null}
    ) {
        BeforeAll {
            $result = InModuleScope $moduleName {Get-VisualEffectInstance -Name $Name} -Parameters $_
        }

        It 'Has the proper <Attribute> attribute' -ForEach @(
            @{Attribute = 'Name'; Value = $_.Name}
            @{Attribute = 'Broadcast'; Value = $_.Broadcast}
        ) {
            $result.$Attribute | Should -BeExactly $Value
        }
        It 'Has the proper type' {
            $result.GetType() | Should -Be $Type
        }
    }
}
