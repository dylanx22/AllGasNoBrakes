local _, ns = ...
ns = ns or __AGNB_NS
ns.Book = ns.Book or {}
local B = ns.Book

-- Pure bet-rigging heuristic. A whisper is suspicious only when DEATH-language and
-- a GOLD-offer co-occur (score 2), so single innocent words don't trip it. Each
-- client scans only its OWN incoming whispers (privacy); the glue decides what to
-- do with a hit. Best-effort deterrent, not a guarantee.
local DEATH_WORDS = {
  "die", "death", "throw", "feed", "wipe", "first blood", "on this pull",
  "let me die", "take the l", "suicide",
}
local GOLD_WORDS = {
  "gold", "i got you", "i'll pay", "ill pay", "i pay", "payout", "cut you in", "split the",
}

-- Returns score (0..2) and the matched terms.
function B.ScoreWhisper(text)
  if not text or text == "" then return 0, {} end
  local low = text:lower()
  local terms, hasDeath, hasGold = {}, false, false
  for _, w in ipairs(DEATH_WORDS) do
    if low:find(w, 1, true) then terms[#terms + 1] = w; hasDeath = true end
  end
  if low:find("%d+%s*g%f[%A]") or low:find("%d+%s*gold") then
    terms[#terms + 1] = "<amount>"; hasGold = true
  end
  for _, w in ipairs(GOLD_WORDS) do
    if low:find(w, 1, true) then terms[#terms + 1] = w; hasGold = true end
  end
  return (hasDeath and 1 or 0) + (hasGold and 1 or 0), terms
end
