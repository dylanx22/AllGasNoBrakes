local H = __AGNB_NS.Hash

-- SHA-256 against published vectors.
T.eq(H.SHA256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "empty")
T.eq(H.SHA256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "abc")
T.eq(H.SHA256("The quick brown fox jumps over the lazy dog"),
     "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592", "fox")
-- a >64-byte input exercises multi-block processing
T.eq(H.SHA256(string.rep("a", 100)),
     "2816597888e4a0d3a36b82b83316ab32680eb8f00f8cd3b904d681246d285a0e", "100 a's")

-- Commit binds (pick, nonce, player); any change flips the hash.
local c = H.Commit("over", "n0nce", "Dylock")
T.eq(c, H.Commit("over", "n0nce", "Dylock"), "deterministic")
T.ok(c ~= H.Commit("under", "n0nce", "Dylock"), "pick changes hash")
T.ok(c ~= H.Commit("over", "n0nce2", "Dylock"), "nonce changes hash")
T.ok(c ~= H.Commit("over", "n0nce", "Grug"), "player changes hash")

-- Seed is canonical: independent of the order secrets arrive in.
T.eq(H.Seed({ Dylock = "a", Grug = "b" }), H.Seed({ Grug = "b", Dylock = "a" }), "seed canonical by player")
T.ok(H.Seed({ Dylock = "a" }) ~= H.Seed({ Dylock = "b" }), "different secrets -> different seed")
