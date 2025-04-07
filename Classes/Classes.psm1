#region Classes and enums

# We define these enums to provide PS5 compatible tab completion and validation for the public functions.
# The Pester tests ensure that they correspond to the actual definitions.

enum EffectName {
    Animation
    ClientAreaAnimation
    ComboBoxAnimation
    CursorShadow
    DragFullWindows
    DropShadow
    EnableAeroPeek
    FontSmoothing
    IconShadow
    ListBoxSmoothScrolling
    MenuAnimation
    SelectionFade
    ShowThumbnails
    TaskbarAnimations
    TaskbarThumbnailCache
    ToolTipAnimation
    TranslucentSelect
}

enum EffectPreset {
    NoAnimation
    Performance
}

<# There are two types of effects: API-based and registry-based. We use a class for each type so we can handle
   get/set operations using a common interface.
#>

# Base class
class VisualEffect {
    # The common properties and methods that the child classes should have
    [string] $Name
    [bool]   $Enabled
    [string] $Description
    hidden [string] $Type

    [void] Refresh () {
        throw 'You must override this method'
    }

    [void] Set ([bool] $Enabled, [BroadcastMessage] $Broadcast) {
        throw 'You must override this method'
    }

    VisualEffect () {
        if ($this.GetType() -eq [VisualEffect]) {
            throw 'You cannot instantiate this base class'
        }
    }
}

# Child class that describes registry-based effects
class VisualEffectRegistry : VisualEffect {
    hidden [string]   $Key
    hidden [string]   $Value
    hidden [psobject] $DataOff   = 0
    hidden [psobject] $DataOn    = 1
    hidden [string]   $Broadcast = 'VisualEffects'

    [void] Refresh () {
        $data = (Get-ItemProperty $this.Key).($this.Value)
        $this.Enabled = ($data -eq $this.DataOn)
    }

    [void] Set ([bool] $Enabled, [BroadcastMessage] $Broadcast) {
        $data = if ($Enabled) {$this.DataOn} else {$this.DataOff}
        Set-ItemProperty -Path $this.Key -Name $this.Value -Value $data
        $Broadcast.AddBroadcast($this.Broadcast)
    }
}

# Child class that describes API-based effects
class VisualEffectSPI : VisualEffect {
    hidden [int] $SpiGet
    hidden [int] $SpiSet
    hidden [int] $WinIni = [Win32.User]::SPIF_UPDATEINIFILE -bor [Win32.User]::SPIF_SENDCHANGE

    [void] Refresh () {
        $featureEnabled = $false
        $ret = [Win32.User]::GetSystemParametersInfoBool($this.SPIGet, 0, [ref]$featureEnabled, 0)
        if (-not $ret) {
            throw "Failed to get System Parameter for $($this.Name)"
        }
        $this.Enabled = $featureEnabled
    }

    [void] Set ([bool] $Enabled, [BroadcastMessage] $Broadcast) {
        $ret = [Win32.User]::SetSystemParametersInfoBool($this.SpiSet, 0, $Enabled, $this.WinIni)
        if (-not $ret) {
            throw "Failed to set System Parameter $($this.Name) to $Enabled"
        }
    }
}

# Special case for the Animation effect
class VisualEffectSPIAnimation : VisualEffectSPI {
    [void] Refresh () {
        $animationInfo = [Win32.User+ANIMATIONINFO]::new(0)
        $ret = [Win32.User]::SystemParametersInfoAnimation(
            $this.SPIGet, $animationInfo.cbSize, [ref]$animationInfo, 0)
        if (-not $ret) {
            throw "Failed to get System Parameter for $($this.Name)"
        }
        $this.Enabled = $animationInfo.iMinAnimate
    }

    [void] Set ([bool] $Enabled, [BroadcastMessage] $Broadcast) {
        $animationInfo = [Win32.User+ANIMATIONINFO]::new($Enabled)
        $ret = [Win32.User]::SystemParametersInfoAnimation(
            $this.SpiSet, $animationInfo.cbSize, [ref]$animationInfo, $this.WinIni)
        if (-not $ret) {
            throw "Failed to set System Parameter $($this.Name) to $Enabled"
        }
    }
}

# Effects that make changes through the uiParam parameter
class VisualEffectSPIAltParam : VisualEffectSPI {
    [void] Set ([bool] $Enabled, [BroadcastMessage] $Broadcast) {
        # Oddly, setting these effects requires a different parameter order
        $ret = [Win32.User]::SetSystemParametersInfoBool($this.SpiSet, [int]$Enabled, $null, $this.WinIni)
        if (-not $ret) {
            throw "Failed to set System Parameter $($this.Name) to $Enabled"
        }
    }
}

# Class that tracks and sends broadcast messages
class BroadcastMessage {
    # The broadcasts that need to be sent after all settings have been updated
    [hashtable] $Broadcast = @{}

    # Add a broadcast message to the list
    [void] AddBroadcast ([string] $Message) {
        $this.Broadcast[$Message] = $true
    }

    # Send a broadcast
    [void] SendBroadcast ([string] $Message) {
        $hwndBroadcast   = [IntPtr] 0xffff
        $wmSettingChange = 0x1a
        $smToAbortIfHung = 0x0002
        $timeout         = 5000
        $result          = [UIntPtr]::Zero

        [Win32.User]::SendMessageTimeout($hwndBroadcast, $wmSettingChange, [UIntPtr]::Zero, $Message,
            $smToAbortIfHung, $timeout, [ref]$result) >$null
    }

    # Send the collected broadcasts so changes take effect immediately
    [void] SendAll () {
        # The "VisualEffects" message should always be sent
        $this.AddBroadcast('VisualEffects')
        $this.Broadcast.Keys | foreach {$this.SendBroadcast($_)}
    }
}

# Factory class that generates VisualEffect instances
class VisualEffectFactory {
    # The definitions of the visual effects, preloaded in the static constructor
    static [hashtable] $Definitions

    # Create a new class instance for the named effect
    static [VisualEffect] NewInstance ([string] $Name) {
        $definition = $([VisualEffectFactory]::Definitions[$Name])
        $instance = $definition -as $definition.Type
        $instance.Refresh()
        return $instance
    }

    # Static constructor to import the definitions (runs automatically before the creation of the first instance)
    static VisualEffectFactory () {
        $jsonData = Get-Content "$PSScriptRoot\..\Definitions\*.json" -Raw | ConvertFrom-Json
        [VisualEffectFactory]::Definitions = $jsonData.List | Group-Object Name -AsHashTable -AsString
    }
}
#endregion
