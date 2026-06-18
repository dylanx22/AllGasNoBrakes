local B = __AGNB_NS.Book

-- Pure resolver: appointer authority is required to change the designation.
T.eq(B.ResolveAdminMsg(nil, "set|Bob", true), "Bob", "appointer sets admin")
T.eq(B.ResolveAdminMsg(nil, "set|Bob", false), nil, "non-appointer cannot set")
T.eq(B.ResolveAdminMsg("Bob", "clear", true), nil, "appointer clears admin")
T.eq(B.ResolveAdminMsg("Bob", "set|Carol", true), "Carol", "reassign replaces")
T.eq(B.ResolveAdminMsg("Bob", "set|Eve", false), "Bob", "delegate-forwarded appoint rejected")
T.eq(B.ResolveAdminMsg("Bob", "garbage", true), "Bob", "unknown op leaves designation")

-- Delegate inclusion: a designated name is admin (and a valid action sender)
-- without holding WoW rank; appointer-status stays false for them.
do
  local savedDb, savedName, savedDemo = __AGNB_NS.db, __AGNB_NS.MyName, (__AGNB_NS.Demo and __AGNB_NS.Demo.active)
  if __AGNB_NS.Demo then __AGNB_NS.Demo.active = false end
  __AGNB_NS.db = { designatedAdmin = "Bob" }
  __AGNB_NS.MyName = "Bob"
  T.ok(B.CanAdmin(), "delegate has CanAdmin")
  T.ok(B.senderIsAdmin("Bob"), "delegate accepted as action sender")
  T.ok(not B.senderIsAppointer("Bob"), "delegate is NOT an appointer")
  __AGNB_NS.MyName = "Carol"
  T.ok(not B.CanAdmin(), "non-delegate non-leader lacks CanAdmin")
  __AGNB_NS.db, __AGNB_NS.MyName = savedDb, savedName
  if __AGNB_NS.Demo then __AGNB_NS.Demo.active = savedDemo end
end
