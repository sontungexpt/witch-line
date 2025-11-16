-- local Event = require("witch-line.core.manager.event")
-- local Session = require("witch-line.core.Session")

-- local eq = assert.are.same
-- local ok = assert.truthy

-- describe("EventStore", function()
-- 	before_each(function()
-- 		-- reset EventStore mỗi test
-- 		package.loaded["witch-line.core.Event"] = nil
-- 		Event = require("witch-line.core.Event")
-- 	end)

-- 	-- ================================
-- 	-- register_string_event
-- 	-- ================================
-- 	it("registers a normal event from string", function()
-- 		Event.register_events({
-- 			id = 1,
-- 			events = "BufEnter",
-- 		})

-- 		eq({ ["BufEnter"] = { 1 } }, Event.inspect().events)
-- 	end)

-- 	it("registers special-event from string with pattern", function()
-- 		Event.register_events({
-- 			id = 2,
-- 			events = "BufEnter *.lua",
-- 		})

-- 		local st = Event.inspect()
-- 		ok(st.special_events)
-- 		eq("BufEnter", st.special_events[1].name)
-- 		eq("*.lua", st.special_events[1].pattern)
-- 		eq({ 2 }, st.special_events[1].ids)
-- 	end)

-- 	it("registers user-event from string", function()
-- 		Event.register_events({
-- 			id = 3,
-- 			events = "User MyEvent",
-- 		})

-- 		local st = Event.inspect()
-- 		ok(st.user_events)
-- 		eq({ 3 }, st.user_events["MyEvent"])
-- 	end)

-- 	-- ================================
-- 	-- register_tbl_event
-- 	-- ================================
-- 	it("registers multiple normal events via table", function()
-- 		Event.register_events({
-- 			id = 10,
-- 			events = {
-- 				{ "BufEnter", "BufLeave" },
-- 			},
-- 		})

-- 		local st = Event.inspect().events
-- 		eq({ 10 }, st["BufEnter"])
-- 		eq({ 10 }, st["BufLeave"])
-- 	end)

-- 	it("registers table special-event with pattern", function()
-- 		Event.register_events({
-- 			id = 11,
-- 			events = {
-- 				{
-- 					[1] = "BufRead",
-- 					pattern = "*.md",
-- 					once = true,
-- 				},
-- 			},
-- 		})

-- 		local se = Event.inspect().special_events[1]
-- 		eq({ "BufRead" }, se.name)
-- 		eq("*.md", se.pattern)
-- 		eq(true, se.once)
-- 		eq({ 11 }, se.ids)
-- 	end)

-- 	-- ================================
-- 	-- Merging special-event entries
-- 	-- ================================
-- 	it("merges special-events with same opts", function()
-- 		Event.register_events({
-- 			id = 100,
-- 			events = "BufEnter *.lua",
-- 		})

-- 		Event.register_events({
-- 			id = 200,
-- 			events = "BufEnter *.lua",
-- 		})

-- 		local se = Event.inspect().special_events
-- 		eq(1, #se)
-- 		eq({ 100, 200 }, se[1].ids)
-- 	end)

-- 	it("creates separate special-events when pattern differs", function()
-- 		Event.register_events({
-- 			id = 10,
-- 			events = "BufEnter *.lua",
-- 		})

-- 		Event.register_events({
-- 			id = 20,
-- 			events = "BufEnter *.py",
-- 		})

-- 		eq(2, #Event.inspect().special_events)
-- 	end)

-- 	-- ================================
-- 	-- get_event_info
-- 	-- ================================
-- 	it("stores and retrieves event info in session", function()
-- 		local fake_sid = 1
-- 		Session.new_session(fake_sid)

-- 		-- fake store usage
-- 		Session.new_store(fake_sid, "EventInfo", {
-- 			["X"] = { event = "BufEnter" },
-- 		})

-- 		local result = Event.get_event_info({ id = "X" }, fake_sid)
-- 		eq({ event = "BufEnter" }, result)
-- 	end)

-- 	-- ================================
-- 	-- on_event (structure only)
-- 	-- ================================
-- 	it("creates autocmds for stored events", function()
-- 		-- inject a fake autocmd tracker
-- 		local created = {}
-- 		vim.api.nvim_create_autocmd = function(event, opts)
-- 			created[#created + 1] = { event = event, pattern = opts.pattern }
-- 		end

-- 		Event.register_events({ id = 1, events = "BufEnter" })
-- 		Event.register_events({ id = 2, events = "User Ready" })
-- 		Event.register_events({ id = 3, events = "BufRead *.md" })

-- 		Event.on_event(function() end)

-- 		eq("BufEnter", created[1].event) -- normal
-- 		eq("User", created[2].event) -- user
-- 		eq("BufRead", created[3].event) -- special
-- 		eq("*.md", created[3].pattern) -- special pattern
-- 	end)
-- end)
