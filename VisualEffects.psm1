# Load the api and class definitions
using module .\PInvoke\Win32.psm1
using module .\Classes\Classes.psm1

#region Internal Helper Functions
function Get-VisualEffectInstance {
    <#
    .SYNOPSIS
        Take a Visual Effect name and instantiate the class instance for that particular effect
    .NOTES
        Simple constructor call wrapped in a function to allow mocking in Pester
    #>
    [CmdletBinding()]
    param (
        # Effect Name
        [Parameter(Mandatory)]
        [string]
        $Name
    )

    [VisualEffectFactory]::NewInstance($Name)
}
#endregion

#region Public Functions
function Get-VisualEffect {
    <#
    .SYNOPSIS
        Gets Windows visual effect setting and its current state
    .DESCRIPTION
        Gets the values of System Parameters such as Visual Effects and Animations
    .EXAMPLE
        Get-VisualEffect
        Gets all Visual Effects settings
    .EXAMPLE
        Get-VisualEffect -Name DropShadow
        Gets the Drop Shadow Visual Effect setting
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [EffectName[]]
        $Name = [Enum]::GetNames([EffectName])
    )

    process {
        foreach ($feature in $Name) {
            Get-VisualEffectInstance -Name $feature
        }
    }
}

function Set-VisualEffect {
    <#
    .SYNOPSIS
        Enable / disable Windows visual effect
    .DESCRIPTION
        Enables / disables System Parameters such as Visual Effects and Animations
    .EXAMPLE
        Set-VisualEffect -Name DropShadow -Enabled $true
        Enables Drop Shadow Visual Effect
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # Effect name
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [EffectName]
        $Name,

        # Turn feature on/off
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Value')]
        [bool]
        $Enabled
    )

    begin {
        # This class instance will collect and send the broadcast messages
        $broadcast = [BroadcastMessage]::new()
        $effectsChanged = $false
    }

    process {
        $effect = Get-VisualEffectInstance -Name $Name
        if ($effect.Enabled -ne $Enabled) {
            if ($PSCmdlet.ShouldProcess($Name, "Set effect to $Enabled")) {
                $effect.Set($Enabled, $broadcast)
                $effectsChanged = $true
            }
        }
    }

    end {
        if ($effectsChanged) {
            $broadcast.SendAll()

            # Register customized settings (ensures that SystemPropertiesPerformance.exe shows them correctly)
            $setItemPropertyArgs = @{
                Path    = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
                Name    = 'VisualFXSetting'
                Value   = 3
                Confirm = $false
            }
            Set-ItemProperty @setItemPropertyArgs
        }
    }
}

function Get-VisualEffectPreset {
    <#
    .SYNOPSIS
        Gets predefined sets of visual effects
    .DESCRIPTION
        Gets predefined sets of visual effects
    .EXAMPLE
        Get-VisualEffectPreset
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [EffectPreset[]]
        $Name = [Enum]::GetNames([EffectPreset])
    )

    process {
        foreach ($preset in $Name) {
            Get-Content "$PSScriptRoot\Presets\$preset.json" -Raw |
                ConvertFrom-Json |
                select * -ExcludeProperty '$schema'
        }
    }
}

function Set-VisualEffectPreset {
    <#
    .SYNOPSIS
        Apply a preset of visual effects
    .DESCRIPTION
        Apply a preset of visual effects
    .EXAMPLE
        Set-VisualEffectPreset -Name Performance
        Disabled all visual effects except font smoothing (recommended for traders)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [EffectPreset]
        $Name
    )

    process {
        (Get-VisualEffectPreset $Name).Settings | Set-VisualEffect
    }
}
#endregion
