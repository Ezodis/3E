// SPDX-License-Identifier: MIT
namespace ThreeE.PhoneControl;

// A bounded palette, not arbitrary native key codes. Modifiers travel with a
// complete keystroke; nothing remains pressed while waiting for the network.
public static class PhoneKeyboard {
    public const int Shift = 1, Control = 2, Alt = 4, Meta = 8, Fn = 16, ModifierMask = 31;
    public const int KeyCount = 63;
    public static int Navigation(int id, int modifiers) => (modifiers & Fn) == 0 ? id : id switch {
        0 => 8, 4 => 9, 6 => 10, 5 => 61, 7 => 62, _ => id
    };
    public static (ushort Key, bool Extended, int Modifiers) Windows(int id, int modifiers) {
        id = Navigation(id, modifiers);
        ushort key = id switch {
            0 or 11 => 0x08, 1 => 0x0D, 2 => 0x09, 3 => 0x1B,
            4 => 0x25, 5 => 0x26, 6 => 0x27, 7 => 0x28,
            8 => 0x2E, 9 => 0x24, 10 => 0x23, 48 => 0x20, 61 => 0x21, 62 => 0x22,
            >= 12 and < 38 => (ushort)(0x41 + id - 12),
            >= 38 and < 48 => (ushort)(0x30 + id - 38),
            >= 49 and <= 60 => (ushort)(0x70 + id - 49),
            _ => throw new ArgumentOutOfRangeException(nameof(id))
        };
        return (key, id is >= 4 and <= 10 or 61 or 62, (modifiers & 15) | (id == 11 ? Control : 0));
    }
    private static readonly ushort[] macLetters = {0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6};
    private static readonly ushort[] macDigits = {29,18,19,20,21,23,22,26,28,25};
    private static readonly ushort[] macFunctions = {122,120,99,118,96,97,98,100,101,109,103,111};
    public static (ushort Key, ulong Flags) Mac(int id, int modifiers) {
        int original = id;
        id = Navigation(id, modifiers);
        ushort key = id switch {
            0 or 11 => 51, 1 => 36, 2 => 48, 3 => 53,
            4 or 9 => 123, 5 => 126, 6 or 10 => 124, 7 => 125, 8 => 117,
            48 => 49, 61 => 116, 62 => 121,
            >= 12 and < 38 => macLetters[id - 12],
            >= 38 and < 48 => macDigits[id - 38],
            >= 49 and <= 60 => macFunctions[id - 49],
            _ => throw new ArgumentOutOfRangeException(nameof(id))
        };
        bool fnHomeEnd = (modifiers & Fn) != 0 && original is 4 or 6;
        if (fnHomeEnd) key = original == 4 ? (ushort)115 : (ushort)119;
        ulong flags = 0;
        if ((modifiers & Shift) != 0) flags |= 1UL << 17;
        if ((modifiers & Control) != 0) flags |= 1UL << 18;
        if ((modifiers & Alt) != 0 || id == 11) flags |= 1UL << 19;
        if ((modifiers & Meta) != 0 || !fnHomeEnd && id is 9 or 10) flags |= 1UL << 20;
        if (key is >= 123 and <= 126) flags |= 1UL << 21;
        if ((modifiers & Fn) != 0 || id is >= 4 and <= 10 or >= 49 and <= 62) flags |= 1UL << 23;
        return (key, flags);
    }
}
