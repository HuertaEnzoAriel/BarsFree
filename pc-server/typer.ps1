# Proceso persistente: lee lineas de stdin y simula teclado con SendInput.
#   T <texto en base64 UTF-8>  -> escribe el texto (unicode)
#   K <vk decimal>             -> presiona una tecla virtual (13 = Enter, 9 = Tab)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class KB {
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public INPUTUNION u; }
  [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);

  static INPUT Key(ushort vk, ushort scan, uint flags) {
    INPUT i = new INPUT(); i.type = 1;
    i.u.ki.wVk = vk; i.u.ki.wScan = scan; i.u.ki.dwFlags = flags;
    return i;
  }
  public static void Text(string s) {
    foreach (char c in s) {
      INPUT[] a = new INPUT[] { Key(0, c, 0x0004), Key(0, c, 0x0004 | 0x0002) };
      SendInput(2, a, Marshal.SizeOf(typeof(INPUT)));
    }
  }
  public static void VK(ushort vk) {
    INPUT[] a = new INPUT[] { Key(vk, 0, 0), Key(vk, 0, 0x0002) };
    SendInput(2, a, Marshal.SizeOf(typeof(INPUT)));
  }
}
"@

while (($line = [Console]::In.ReadLine()) -ne $null) {
  if ($line.Length -lt 3) { continue }
  $cmd = $line.Substring(0, 1)
  $arg = $line.Substring(2)
  if ($cmd -eq 'T') {
    [KB]::Text([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($arg)))
  } elseif ($cmd -eq 'K') {
    [KB]::VK([uint16]$arg)
  }
}
