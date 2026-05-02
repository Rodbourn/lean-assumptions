/-!
Shared JSON string escaping helpers for support-layer renderers.

The project emits deterministic JSON artifacts without depending on a separate
encoder. These helpers keep RFC 8259 string escaping consistent across report,
delta, and cluster renderers.
-/

namespace LeanAssumptions.JsonUtil

/-- Return a lowercase hexadecimal digit for `0 <= value < 16`. -/
private def hexDigit (value : Nat) : Char :=
  if value < 10 then
    Char.ofNat ('0'.toNat + value)
  else
    Char.ofNat ('a'.toNat + (value - 10))

/-- Render the low 16 bits of a scalar value as exactly four hexadecimal digits. -/
private def hex4 (value : Nat) : String :=
  String.ofList [
    hexDigit ((value / 4096) % 16),
    hexDigit ((value / 256) % 16),
    hexDigit ((value / 16) % 16),
    hexDigit (value % 16)
  ]

/--
Escape a string for use inside JSON quotes.

RFC 8259 requires every U+0000 through U+001F control character to be escaped.
The named short escapes are used for newline, carriage return, and tab because
they are common in existing artifacts; every other C0 control character is
emitted as a deterministic `\uXXXX` sequence.
-/
def escapeString (value : String) : String :=
  value.foldl (init := "") fun acc char =>
    match char with
    | '"' => acc ++ "\\\""
    | '\\' => acc ++ "\\\\"
    | '\n' => acc ++ "\\n"
    | '\r' => acc ++ "\\r"
    | '\t' => acc ++ "\\t"
    | _ =>
      let scalar := char.toNat
      if scalar < 0x20 then
        acc ++ "\\u" ++ hex4 scalar
      else
        acc.push char

/-- Quote and escape a JSON string. -/
def quoteString (value : String) : String :=
  "\"" ++ escapeString value ++ "\""

end LeanAssumptions.JsonUtil
