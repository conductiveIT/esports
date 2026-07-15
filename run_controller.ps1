# Xbox Controller Mapper for Luanti/Minetest (No Installation / No Executables required)
# Run this inside a standard PowerShell window!

$source = @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct LuantiXInputGamepad {
    public ushort wButtons;
    public byte bLeftTrigger;
    public byte bRightTrigger;
    public short sThumbLX;
    public short sThumbLY;
    public short sThumbRX;
    public short sThumbRY;
}

[StructLayout(LayoutKind.Sequential)]
public struct LuantiXInputState {
    public uint dwPacketNumber;
    public LuantiXInputGamepad Gamepad;
}

public class LuantiGamepadMapper {
    [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")]
    public static extern uint XInputGetState(uint dwUserIndex, out LuantiXInputState pState);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, IntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, IntPtr dwExtraInfo);

    // Constants for buttons
    public const ushort XINPUT_GAMEPAD_DPAD_UP = 0x0001;
    public const ushort XINPUT_GAMEPAD_DPAD_DOWN = 0x0002;
    public const ushort XINPUT_GAMEPAD_DPAD_LEFT = 0x0004;
    public const ushort XINPUT_GAMEPAD_DPAD_RIGHT = 0x0008;
    public const ushort XINPUT_GAMEPAD_START = 0x0010;
    public const ushort XINPUT_GAMEPAD_BACK = 0x0020;
    public const ushort XINPUT_GAMEPAD_LEFT_THUMB = 0x0040;
    public const ushort XINPUT_GAMEPAD_RIGHT_THUMB = 0x0080;
    public const ushort XINPUT_GAMEPAD_LEFT_SHOULDER = 0x0100;
    public const ushort XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200;
    public const ushort XINPUT_GAMEPAD_A = 0x1000;
    public const ushort XINPUT_GAMEPAD_B = 0x2000;
    public const ushort XINPUT_GAMEPAD_X = 0x4000;
    public const ushort XINPUT_GAMEPAD_Y = 0x8000;

    // Mouse events
    public const uint MOUSEEVENTF_MOVE = 0x0001;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    public const uint MOUSEEVENTF_WHEEL = 0x0800;

    // Keyboard events
    public const uint KEYEVENTF_KEYUP = 0x0002;

    // Virtual keys
    public const byte VK_SPACE = 0x20;     // Space
    public const byte VK_SHIFT = 0x10;     // Shift
    public const byte VK_W = 0x57;
    public const byte VK_A = 0x41;
    public const byte VK_S = 0x53;
    public const byte VK_D = 0x44;
    public const byte VK_R = 0x52;         // Reload
    public const byte VK_I = 0x49;         // Inventory
    public const byte VK_ESCAPE = 0x1B;    // Menu
}
"@

# Compile C# definitions in-memory only if they are not already loaded
if (-not ([System.Management.Automation.PSTypeName]"LuantiGamepadMapper").Type) {
    Add-Type -TypeDefinition $source
}

Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Xbox Controller Mapper for Luanti Started  " -ForegroundColor Green
Write-Host "  Press Ctrl+C in this window to stop.       " -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Green

# States tracking to only trigger press/release transitions
$prev_a = $false
$prev_b = $false
$prev_x = $false
$prev_y = $false
$prev_back = $false
$prev_w = $false
$prev_s = $false
$prev_a_key = $false
$prev_d = $false
$prev_lt = $false
$prev_rt = $false
$prev_lb = $false
$prev_rb = $false

# Instantiate structures
if ($PSVersionTable.PSVersion.Major -ge 5) {
    $state = [LuantiXInputState]::new()
} else {
    $state = New-Object LuantiXInputState
}

$sensitivity = 1.2

while ($true) {
    $result = [LuantiGamepadMapper]::XInputGetState(0, [ref]$state)
    if ($result -ne 0) {
        Write-Host "Controller not detected! Reconnecting..." -ForegroundColor Red
        Start-Sleep -Seconds 2
        continue
    }

    # 1. Left Stick -> WASD
    $lx = $state.Gamepad.sThumbLX
    $ly = $state.Gamepad.sThumbLY
    $stick_deadzone = 12000

    $w_pressed = $ly -gt $stick_deadzone
    $s_pressed = $ly -lt -$stick_deadzone
    $d_pressed = $lx -gt $stick_deadzone
    $a_pressed = $lx -lt -$stick_deadzone

    # W key
    if ($w_pressed -and -not $prev_w) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_W, 0, 0, [IntPtr]::Zero)
    } elseif (-not $w_pressed -and $prev_w) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_W, 0, [LuantiGamepadMapper]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
    $prev_w = $w_pressed

    # S key
    if ($s_pressed -and -not $prev_s) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_S, 0, 0, [IntPtr]::Zero)
    } elseif (-not $s_pressed -and $prev_s) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_S, 0, [LuantiGamepadMapper]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
    $prev_s = $s_pressed

    # A key
    if ($a_pressed -and -not $prev_a_key) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_A, 0, 0, [IntPtr]::Zero)
    } elseif (-not $a_pressed -and $prev_a_key) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_A, 0, [LuantiGamepadMapper]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
    $prev_a_key = $a_pressed

    # D key
    if ($d_pressed -and -not $prev_d) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_D, 0, 0, [IntPtr]::Zero)
    } elseif (-not $d_pressed -and $prev_d) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_D, 0, [LuantiGamepadMapper]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
    $prev_d = $d_pressed


    # 2. Right Stick -> Mouse Move (Aiming)
    $rx = $state.Gamepad.sThumbRX
    $ry = $state.Gamepad.sThumbRY
    $mouse_deadzone = 8000

    if ([Math]::Abs($rx) -gt $mouse_deadzone -or [Math]::Abs($ry) -gt $mouse_deadzone) {
        # Exponential curve for finer aiming control
        $val_x = if ($rx -gt 0) { $rx - $mouse_deadzone } else { $rx + $mouse_deadzone }
        $val_y = if ($ry -gt 0) { $ry - $mouse_deadzone } else { $ry + $mouse_deadzone }

        $dx = [int]($val_x * $val_x * [Math]::Sign($val_x) / 10000000 * $sensitivity)
        $dy = [int](-$val_y * $val_y * [Math]::Sign($val_y) / 10000000 * $sensitivity)

        [LuantiGamepadMapper]::mouse_event([LuantiGamepadMapper]::MOUSEEVENTF_MOVE, $dx, $dy, 0, [IntPtr]::Zero)
    }


    # 3. Triggers -> Mouse Clicks
    $trigger_threshold = 100
    
    # Right Trigger -> Shoot / Left Click
    $rt_pressed = $state.Gamepad.bRightTrigger -gt $trigger_threshold
    if ($rt_pressed -and -not $prev_rt) {
        [LuantiGamepadMapper]::mouse_event([LuantiGamepadMapper]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [IntPtr]::Zero)
    } elseif (-not $rt_pressed -and $prev_rt) {
        [LuantiGamepadMapper]::mouse_event([LuantiGamepadMapper]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [IntPtr]::Zero)
    }
    $prev_rt = $rt_pressed

    # Left Trigger -> Build / Aim / Right Click
    $lt_pressed = $state.Gamepad.bLeftTrigger -gt $trigger_threshold
    if ($lt_pressed -and -not $prev_lt) {
        [LuantiGamepadMapper]::mouse_event([LuantiGamepadMapper]::MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, [IntPtr]::Zero)
    } elseif (-not $lt_pressed -and $prev_lt) {
        [LuantiGamepadMapper]::mouse_event([LuantiGamepadMapper]::MOUSEEVENTF_RIGHTUP, 0, 0, 0, [IntPtr]::Zero)
    }
    $prev_lt = $lt_pressed


    # 4. Bumpers -> Scroll Wheel (Hotbar selection)
    $lb_pressed = ($state.Gamepad.wButtons -band [LuantiGamepadMapper]::XINPUT_GAMEPAD_LEFT_SHOULDER) -ne 0
    if ($lb_pressed -and -not $prev_lb) {
        [LuantiGamepadMapper]::mouse_event([LuantiGamepadMapper]::MOUSEEVENTF_WHEEL, 0, 0, 120, [IntPtr]::Zero) # Scroll Up
    }
    $prev_lb = $lb_pressed

    $rb_pressed = ($state.Gamepad.wButtons -band [LuantiGamepadMapper]::XINPUT_GAMEPAD_RIGHT_SHOULDER) -ne 0
    if ($rb_pressed -and -not $prev_rb) {
        [LuantiGamepadMapper]::mouse_event([LuantiGamepadMapper]::MOUSEEVENTF_WHEEL, 0, 0, -120, [IntPtr]::Zero) # Scroll Down
    }
    $prev_rb = $rb_pressed


    # 5. Buttons -> Key Bindings
    $buttons = $state.Gamepad.wButtons

    # A Button -> Jump (Space)
    $a_pressed = ($buttons -band [LuantiGamepadMapper]::XINPUT_GAMEPAD_A) -ne 0
    if ($a_pressed -and -not $prev_a) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_SPACE, 0, 0, [IntPtr]::Zero)
    } elseif (-not $a_pressed -and $prev_a) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_SPACE, 0, [LuantiGamepadMapper]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
    $prev_a = $a_pressed

    # B Button -> Sneak (Shift)
    $b_pressed = ($buttons -band [LuantiGamepadMapper]::XINPUT_GAMEPAD_B) -ne 0
    if ($b_pressed -and -not $prev_b) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_SHIFT, 0, 0, [IntPtr]::Zero)
    } elseif (-not $b_pressed -and $prev_b) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_SHIFT, 0, [LuantiGamepadMapper]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
    $prev_b = $b_pressed

    # X Button -> Reload (R)
    $x_pressed = ($buttons -band [LuantiGamepadMapper]::XINPUT_GAMEPAD_X) -ne 0
    if ($x_pressed -and -not $prev_x) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_R, 0, 0, [IntPtr]::Zero)
    } elseif (-not $x_pressed -and $prev_x) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_R, 0, [LuantiGamepadMapper]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
    $prev_x = $x_pressed

    # Y Button -> Inventory (I)
    $y_pressed = ($buttons -band [LuantiGamepadMapper]::XINPUT_GAMEPAD_Y) -ne 0
    if ($y_pressed -and -not $prev_y) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_I, 0, 0, [IntPtr]::Zero)
    } elseif (-not $y_pressed -and $prev_y) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_I, 0, [LuantiGamepadMapper]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
    $prev_y = $y_pressed

    # Back Button -> Menu (Escape)
    $back_pressed = ($buttons -band [LuantiGamepadMapper]::XINPUT_GAMEPAD_BACK) -ne 0
    if ($back_pressed -and -not $prev_back) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_ESCAPE, 0, 0, [IntPtr]::Zero)
    } elseif (-not $back_pressed -and $prev_back) {
        [LuantiGamepadMapper]::keybd_event([LuantiGamepadMapper]::VK_ESCAPE, 0, [LuantiGamepadMapper]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
    $prev_back = $back_pressed

    Start-Sleep -Milliseconds 15
}
