local _, ns = ...
ns = ns or __AGNB_NS
ns.Hash = ns.Hash or {}
local H = ns.Hash

-- Bundled SHA-256 -- the binding behind commit/reveal, so a single cheater can't
-- open a binary bet either way. Uses WoW's fast `bit` library in-game and a
-- pure-arithmetic fallback under the standalone test harness (no `bit`/operators,
-- so the file still parses under Lua 5.1).
local band, bxor, bor, bnot, lshift, rshift
local MOD = 4294967296   -- 2^32
if bit and bit.band then
  band, bxor, bor, bnot, lshift, rshift =
    bit.band, bit.bxor, bit.bor, bit.bnot, bit.lshift, bit.rshift
else
  local function combine(a, b, f)
    local res, p = 0, 1
    for _ = 1, 32 do
      local x, y = a % 2, b % 2
      if f(x, y) == 1 then res = res + p end
      a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    return res
  end
  band = function(a, b) return combine(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end
  bor  = function(a, b) return combine(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end) end
  bxor = function(a, b) return combine(a, b, function(x, y) return (x ~= y) and 1 or 0 end) end
  bnot = function(a) return (MOD - 1) - a end
  lshift = function(a, n) return (a * (2 ^ n)) % MOD end
  rshift = function(a, n) return math.floor(a / (2 ^ n)) end
end

local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function rrot(x, n)
  return bor(rshift(x, n), lshift(x, 32 - n)) % MOD
end

local function be32(n)
  return string.char(band(rshift(n, 24), 255), band(rshift(n, 16), 255),
                     band(rshift(n, 8), 255), band(n, 255))
end

function H.SHA256(msg)
  msg = tostring(msg)
  local bitlen = #msg * 8
  msg = msg .. "\128"
  while (#msg % 64) ~= 56 do msg = msg .. "\0" end
  msg = msg .. be32(math.floor(bitlen / MOD)) .. be32(bitlen % MOD)

  local h0,h1,h2,h3 = 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a
  local h4,h5,h6,h7 = 0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19

  for i = 1, #msg, 64 do
    local w = {}
    for j = 0, 15 do
      local a, b, c, d = msg:byte(i + j * 4, i + j * 4 + 3)
      w[j + 1] = ((a * 256 + b) * 256 + c) * 256 + d
    end
    for j = 17, 64 do
      local x15, x2 = w[j - 15], w[j - 2]
      local s0 = bxor(bxor(rrot(x15, 7), rrot(x15, 18)), rshift(x15, 3))
      local s1 = bxor(bxor(rrot(x2, 17), rrot(x2, 19)), rshift(x2, 10))
      w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % MOD
    end
    local a,b,c,d,e,f,g,h = h0,h1,h2,h3,h4,h5,h6,h7
    for j = 1, 64 do
      local S1 = bxor(bxor(rrot(e, 6), rrot(e, 11)), rrot(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = (h + S1 + ch + K[j] + w[j]) % MOD
      local S0 = bxor(bxor(rrot(a, 2), rrot(a, 13)), rrot(a, 22))
      local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
      local t2 = (S0 + maj) % MOD
      h=g; g=f; f=e; e=(d + t1) % MOD; d=c; c=b; b=a; a=(t1 + t2) % MOD
    end
    h0=(h0+a)%MOD; h1=(h1+b)%MOD; h2=(h2+c)%MOD; h3=(h3+d)%MOD
    h4=(h4+e)%MOD; h5=(h5+f)%MOD; h6=(h6+g)%MOD; h7=(h7+h)%MOD
  end
  return ("%08x%08x%08x%08x%08x%08x%08x%08x"):format(h0,h1,h2,h3,h4,h5,h6,h7)
end

-- Commit to a hidden pick: H(pick \0 nonce \0 player). Reveal later; others verify.
function H.Commit(pick, nonce, player)
  return H.SHA256(tostring(pick) .. "\0" .. tostring(nonce) .. "\0" .. tostring(player))
end

-- Fair shared seed from every participant's secret, canonical (sorted by player)
-- so it's independent of message-receipt order and no one can steer it.
function H.Seed(secretsByPlayer)
  local names = {}
  for p in pairs(secretsByPlayer) do names[#names + 1] = p end
  table.sort(names)
  local parts = {}
  for _, p in ipairs(names) do parts[#parts + 1] = p .. "=" .. tostring(secretsByPlayer[p]) end
  return H.SHA256(table.concat(parts, "\n"))
end
