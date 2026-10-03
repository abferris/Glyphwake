using System;

namespace Glyphwake.Glyphs;

/// Who the target or area is allowed to affect. Independent of
/// <see cref="GlyphTargetType"/>, and a flag so a glyph can hit enemies and allies at once.
[Flags]
public enum GlyphAffects
{
    None = 0,
    Enemies = 1 << 0,
    Allies = 1 << 1,
    Self = 1 << 2,
    Terrain = 1 << 3
}