import ctypes
from ctypes import wintypes
import time
import sys

# Load XInput library with dynamic fallback for robustness
xinput = None
for dll_name in ["xinput1_4", "xinput1_3", "xinput9_1_0"]:
    try:
        xinput = ctypes.windll.LoadLibrary(dll_name)
        break
    except Exception:
        continue

if not xinput:
    print("CRITICAL ERROR: Could not load XInput DLL. Ensure your controller is connected.")
    sys.exit(1)

user32 = ctypes.windll.user32

# XInput Structure Definitions
class XINPUT_GAMEPAD(ctypes.Structure):
    _fields_ = [
        ("wButtons", wintypes.WORD),
        ("bLeftTrigger", ctypes.c_ubyte),  # Fixed: Use unsigned byte (0 to 255)
        ("bRightTrigger", ctypes.c_ubyte), # Fixed: Use unsigned byte (0 to 255)
        ("sThumbLX", ctypes.c_short),
        ("sThumbLY", ctypes.c_short),
        ("sThumbRX", ctypes.c_short),
        ("sThumbRY", ctypes.c_short),
    ]

class XINPUT_STATE(ctypes.Structure):
    _fields_ = [
        ("dwPacketNumber", wintypes.DWORD),
        ("Gamepad", XINPUT_GAMEPAD),
    ]

# Win32 Constants
VK_SPACE = 0x20
VK_SHIFT = 0x10
VK_ESCAPE = 0x1B
VK_W = 0x57
VK_A = 0x41
VK_S = 0x53
VK_D = 0x44
VK_R = 0x52
VK_I = 0x49

KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_SCANCODE = 0x0008

MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_WHEEL = 0x0800

# Button bitmasks
XINPUT_GAMEPAD_START = 0x0010
XINPUT_GAMEPAD_BACK = 0x0020
XINPUT_GAMEPAD_LEFT_SHOULDER = 0x0100
XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200
XINPUT_GAMEPAD_A = 0x1000
XINPUT_GAMEPAD_B = 0x2000
XINPUT_GAMEPAD_X = 0x4000
XINPUT_GAMEPAD_Y = 0x8000

# State tracking for transition triggers
prev_keys = {
    VK_W: False, VK_S: False, VK_A: False, VK_D: False,
    VK_SPACE: False, VK_SHIFT: False, VK_R: False, VK_I: False,
    VK_ESCAPE: False
}
prev_lmb = False
prev_rmb = False
prev_lb = False
prev_rb = False

sensitivity = 1.3
deadzone_stick = 12000
deadzone_mouse = 8000

# Translate virtual key to hardware scan code
def get_scan_code(vk_code):
    return user32.MapVirtualKeyW(vk_code, 0)

def set_key(vk_code, press):
    scan_code = get_scan_code(vk_code)
    if press and not prev_keys[vk_code]:
        user32.keybd_event(vk_code, scan_code, 0, 0)
        prev_keys[vk_code] = True
    elif not press and prev_keys[vk_code]:
        user32.keybd_event(vk_code, scan_code, KEYEVENTF_KEYUP, 0)
        prev_keys[vk_code] = False

print("====================================================")
print("  Python Xbox Controller Mapper for Luanti Started   ")
print("  Press Ctrl+C in this terminal to stop.            ")
print("====================================================")

state = XINPUT_STATE()

while True:
    res = xinput.XInputGetState(0, ctypes.byref(state))
    if res != 0:
        print("Controller disconnected! Waiting to reconnect...")
        time.sleep(2)
        continue

    gamepad = state.Gamepad
    buttons = gamepad.wButtons

    # 1. Left Stick -> WASD
    lx = gamepad.sThumbLX
    ly = gamepad.sThumbLY

    set_key(VK_W, ly > deadzone_stick)
    set_key(VK_S, ly < -deadzone_stick)
    set_key(VK_D, lx > deadzone_stick)
    set_key(VK_A, lx < -deadzone_stick)

    # 2. Right Stick -> Mouse Move (Aiming)
    rx = gamepad.sThumbRX
    ry = gamepad.sThumbRY

    if abs(rx) > deadzone_mouse or abs(ry) > deadzone_mouse:
        # Scale input
        val_x = (rx - deadzone_mouse) if rx > 0 else (rx + deadzone_mouse)
        val_y = (ry - deadzone_mouse) if ry > 0 else (ry + deadzone_mouse)

        # Exponential curve for finer aiming control
        dx = int((val_x * val_x * (1 if val_x > 0 else -1)) / 10000000 * sensitivity)
        dy = int((-val_y * val_y * (1 if val_y > 0 else -1)) / 10000000 * sensitivity)

        user32.mouse_event(MOUSEEVENTF_MOVE, dx, dy, 0, 0)

    # 3. Triggers -> Mouse Clicks
    # Right Trigger -> Shoot (Left Click) - Threshold set to 30 for responsive taps
    r_trig = gamepad.bRightTrigger
    lmb_pressed = r_trig > 30
    if lmb_pressed and not prev_lmb:
        user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
        prev_lmb = True
    elif not lmb_pressed and prev_lmb:
        user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
        prev_lmb = False

    # Left Trigger -> Scope / Build (Right Click) - Threshold set to 30
    l_trig = gamepad.bLeftTrigger
    rmb_pressed = l_trig > 30
    if rmb_pressed and not prev_rmb:
        user32.mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0)
        prev_rmb = True
    elif not rmb_pressed and prev_rmb:
        user32.mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0)
        prev_rmb = False

    # 4. Bumpers -> Scroll Wheel (Hotbar switching)
    lb_pressed = bool(buttons & XINPUT_GAMEPAD_LEFT_SHOULDER)
    if lb_pressed and not prev_lb:
        user32.mouse_event(MOUSEEVENTF_WHEEL, 0, 0, 120, 0) # Scroll up
        prev_lb = True
    elif not lb_pressed:
        prev_lb = False

    rb_pressed = bool(buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER)
    if rb_pressed and not prev_rb:
        user32.mouse_event(MOUSEEVENTF_WHEEL, 0, 0, -120, 0) # Scroll down
        prev_rb = True
    elif not rb_pressed:
        prev_rb = False

    # 5. Buttons -> Key Press Events
    set_key(VK_SPACE, bool(buttons & XINPUT_GAMEPAD_A))
    set_key(VK_SHIFT, bool(buttons & XINPUT_GAMEPAD_B))
    set_key(VK_R, bool(buttons & XINPUT_GAMEPAD_X))
    set_key(VK_I, bool(buttons & XINPUT_GAMEPAD_Y))
    set_key(VK_ESCAPE, bool(buttons & XINPUT_GAMEPAD_BACK))

    time.sleep(0.015)
