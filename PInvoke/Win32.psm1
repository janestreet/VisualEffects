$typeDefinition = '
public const int SPIF_UPDATEINIFILE = 0x01;
public const int SPIF_SENDCHANGE = 0x02;

[StructLayout(LayoutKind.Sequential)]
public struct ANIMATIONINFO {
    public ANIMATIONINFO(System.Int32 iMinAnimate)
    {
        this.cbSize = (System.UInt32)Marshal.SizeOf(typeof(ANIMATIONINFO));
        this.iMinAnimate = iMinAnimate;
    }

    public System.UInt32 cbSize;
    public System.Int32 iMinAnimate;
}

[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto, EntryPoint = "SystemParametersInfo")]
public static extern bool SystemParametersInfoAnimation(
    int uiAction, uint uiParam, ref ANIMATIONINFO pvParam, int fWinIni);

[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto, EntryPoint = "SystemParametersInfo")]
public static extern bool GetSystemParametersInfoBool(
    int uiAction, int uiParam, ref bool lpvParam, int fuWinIni);

[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto, EntryPoint = "SystemParametersInfo")]
public static extern bool SetSystemParametersInfoBool(
    int uiAction, int uiParam, bool lpvParam, int fuWinIni);

[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'

Add-Type -Name 'User' -Namespace 'Win32' -Language CSharp -MemberDefinition $typeDefinition
