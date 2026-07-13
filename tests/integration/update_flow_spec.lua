--- Integration tests for the full update flow.
--- Tests style inheritance + separator resolution end-to-end through
--- update.lua → behavior → highlight → statusline.
---
--- Replaces the original inherit_sep_spec.lua with cleaner structure.

local a = require("tests.helpers.assert")
local F = require("tests.helpers.component_factory")
local Env = require("tests.helpers.mock_env")

Env.install()

local function fresh()
    Env.uninstall()
    Env.install()
    Env.reset_calls()
    return Env.get_update()
end

-- ============================================================
print("=== Style: child inherits parent style ===")

do
    local update = fresh()
    local parent = F.make_comp({ style = { fg = "#ffffff", bg = "#333333" }, update = function() return "p" end })
    local child = F.make_comp({ ___parent_id = parent.id, update = function() return "c" end })
    Env.register(parent)
    Env.register(child)
    Env.run_update(update, child)
    local sv = Env.find_set_value(child.id)
    a.not_nil(sv, "child value set")
    a.not_nil(sv.hl_name, "child got highlight")
end

-- ============================================================
print("=== Style: child overrides fg, inherits bg ===")

do
    local update = fresh()
    local parent = F.make_comp({ style = { fg = "#aaa", bg = "#111" }, update = function() return "p" end })
    local child = F.make_comp({ ___parent_id = parent.id, style = { fg = "#bbb" }, update = function() return "c" end })
    Env.register(parent)
    Env.register(child)
    Env.run_update(update, child)
    local sv = Env.find_set_value(child.id)
    a.not_nil(sv.hl_name, "merged highlight created")
    local hl = vim.api.nvim_get_hl(0, { name = sv.hl_name, create = false })
    a.not_nil(hl, "highlight group exists in nvim")
end

-- ============================================================
print("=== Style: grandchild chain ===")

do
    local update = fresh()
    local gp, mid, leaf = F.make_chain(
        { style = { fg = "#aaa", bg = "#111" }, update = function() return "gp" end },
        { update = function() return "mid" end },
        { update = function() return "leaf" end }
    )
    Env.register(gp)
    Env.register(mid)
    Env.register(leaf)
    Env.run_update(update, leaf)
    a.not_nil(Env.find_set_value(leaf.id).hl_name, "leaf got highlight from grandparent")
end

-- ============================================================
print("=== Sep: parent left sep inherited by child ===")

do
    local update = fresh()
    local parent = F.make_comp({ left = ">>", style = { fg = "#fff", bg = "#000" }, update = function() return "p" end })
    local child = F.make_comp({ ___parent_id = parent.id, update = function() return "c" end })
    Env.register(parent)
    Env.register(child)
    Env.run_update(update, child)
    local left = Env.find_side_values(child.id)
    a.not_nil(left, "child left sep set")
    a.eq(left.value, ">>", "value inherited")
end

-- ============================================================
print("=== Sep: parent value wins over child ===")

do
    local update = fresh()
    local parent = F.make_comp({ left = "PARENT", style = { fg = "#fff", bg = "#000" }, update = function() return "p" end })
    local child = F.make_comp({ ___parent_id = parent.id, left = "CHILD", update = function() return "c" end })
    Env.register(parent)
    Env.register(child)
    Env.run_update(update, child)
    local left = Env.find_side_values(child.id)
    a.eq(left.value, "PARENT", "parent wins")
end

-- ============================================================
print("=== Sep: right sep inherited ===")

do
    local update = fresh()
    local parent = F.make_comp({ right = "<<", style = { fg = "#fff", bg = "#000" }, update = function() return "p" end })
    local child = F.make_comp({ ___parent_id = parent.id, update = function() return "c" end })
    Env.register(parent)
    Env.register(child)
    Env.run_update(update, child)
    local _, right = Env.find_side_values(child.id)
    a.not_nil(right, "right sep set")
    a.eq(right.value, "<<")
end

-- ============================================================
print("=== Sep: both left and right ===")

do
    local update = fresh()
    local comp = F.make_comp({ left = "[", right = "]", style = { fg = "#fff", bg = "#000" }, update = function() return "h" end })
    Env.register(comp)
    Env.run_update(update, comp)
    local left, right = Env.find_side_values(comp.id)
    a.not_nil(left)
    a.not_nil(right)
    a.eq(left.value, "[")
    a.eq(right.value, "]")
end

-- ============================================================
print("=== Sep: dynamic parent sep changes between renders ===")

do
    local update = fresh()
    local counter = 0
    local parent = F.make_comp({
        left = function() counter = counter + 1; return counter == 1 and "A" or "B" end,
        style = { fg = "#fff", bg = "#000" },
        update = function() return "p" end,
    })
    local child = F.make_comp({ ___parent_id = parent.id, update = function() return "c" end })
    Env.register(parent)
    Env.register(child)

    Env.run_update(update, child)
    a.eq(Env.find_side_values(child.id).value, "A", "first render: A")

    Env.reset_calls()
    Env.run_update(update, child)
    a.eq(Env.find_side_values(child.id).value, "B", "second render: B")
end

-- ============================================================
print("=== Sep style: default SepBg ===")

do
    local update = fresh()
    local comp = F.make_comp({ left = "<<", style = { fg = "#ffffff", bg = "#333333" }, update = function() return "v" end })
    Env.register(comp)
    Env.run_update(update, comp)
    local left = Env.find_side_values(comp.id)
    a.not_nil(left.hl_name, "SepBg highlight allocated")
end

-- ============================================================
print("=== Sep style: Inherited reuses main hl ===")

do
    local update = fresh()
    local comp = F.make_comp({ left = "|", left_style = 0, style = { fg = "#fff", bg = "#000" }, update = function() return "v" end })
    Env.register(comp)
    Env.run_update(update, comp)
    local sv = Env.find_set_value(comp.id)
    local left = Env.find_side_values(comp.id)
    a.eq(left.hl_name, sv.hl_name, "Inherited side uses main hl name")
end

-- ============================================================
print("=== Sep style: custom table ===")

do
    local update = fresh()
    local comp = F.make_comp({ left = "<", left_style = { fg = "#deadbeef", bold = true }, style = { fg = "#fff", bg = "#000" }, update = function() return "v" end })
    Env.register(comp)
    Env.run_update(update, comp)
    local left = Env.find_side_values(comp.id)
    local hl = vim.api.nvim_get_hl(0, { name = left.hl_name, create = false })
    a.is_true(hl.bold, "custom bold applied")
end

-- ============================================================
print("=== Sep style: string link ===")

do
    local update = fresh()
    vim.api.nvim_set_hl(0, "TestSepHL", { fg = "#aabbcc" })
    local comp = F.make_comp({ left = "<", left_style = "TestSepHL", style = { fg = "#fff", bg = "#000" }, update = function() return "v" end })
    Env.register(comp)
    Env.run_update(update, comp)
    local left = Env.find_side_values(comp.id)
    local hl = vim.api.nvim_get_hl(0, { name = left.hl_name, create = false })
    a.eq(hl.link, "TestSepHL", "links to target hl")
end

-- ============================================================
print("=== Dynamic style from update() ===")

do
    local update = fresh()
    local comp = F.make_comp({
        style = { fg = "#000", bg = "#fff" },
        update = function() return "dyn", { fg = "#ff0000", bg = "#00ff00" } end,
    })
    Env.register(comp)
    Env.run_update(update, comp)
    local sv = Env.find_set_value(comp.id)
    a.not_nil(sv.hl_name, "dynamic style highlight created")
end

-- ============================================================
print("=== Hidden component: no value or side ===")

do
    local update = fresh()
    local comp = F.make_comp({ style = { fg = "#fff", bg = "#000" }, left = "<<", right = ">>", hidden = true, update = function() return "h" end })
    Env.register(comp)
    Env.run_update(update, comp)
    a.is_nil(Env.find_set_value(comp.id), "hidden: no set_value")
    local l, r = Env.find_side_values(comp.id)
    a.is_nil(l, "hidden: no left")
    a.is_nil(r, "hidden: no right")
end

-- ============================================================
print("=== Empty update: component hidden ===")

do
    local update = fresh()
    local comp = F.make_comp({ style = { fg = "#fff", bg = "#000" }, left = "<<", update = function() return "" end })
    Env.register(comp)
    Env.run_update(update, comp)
    a.is_nil(Env.find_set_value(comp.id), "empty value hidden")
end

-- ============================================================
print("=== Dynamic right sep has dirty flag ===")

do
    local update = fresh()
    local comp = F.make_comp({ right = function() return ">" end, style = { fg = "#fff", bg = "#000" }, update = function() return "v" end })
    Env.register(comp)
    Env.run_update(update, comp)
    local _, right = Env.find_side_values(comp.id)
    a.not_nil(right, "dynamic right sep set")
    a.not_nil(right.value, "has value")
end

-- ============================================================
print("=== No-style parent+child => no custom highlight ===")

do
    local update = fresh()
    local parent = F.make_comp({ update = function() return "p" end })
    local child = F.make_comp({ ___parent_id = parent.id, update = function() return "c" end })
    Env.register(parent)
    Env.register(child)
    Env.run_update(update, child)
    local sv = Env.find_set_value(child.id)
    a.not_nil(sv, "child value was set")
    a.is_nil(sv.hl_name, "no custom highlight without explicit style")
end

-- ============================================================
print("=== Grandchild inherits grandparent sep (middle has none) ===")

do
    local update = fresh()
    local gp, mid, leaf = F.make_chain(
        { left = "<<", right = ">>", style = { fg = "#fff", bg = "#000" }, update = function() return "gp" end },
        { update = function() return "mid" end },
        { update = function() return "leaf" end }
    )
    Env.register(gp)
    Env.register(mid)
    Env.register(leaf)
    Env.run_update(update, leaf)
    local l, r = Env.find_side_values(leaf.id)
    a.eq(l.value, "<<", "left from grandparent")
    a.eq(r.value, ">>", "right from grandparent")
end

-- ============================================================
print("=== Parent sep style + child sep style override ===")

do
    local update = fresh()
    local parent = F.make_comp({ left = "<<", left_style = 2, style = { fg = "#fff", bg = "#333" }, update = function() return "p" end })
    local child = F.make_comp({ ___parent_id = parent.id, left_style = 1, update = function() return "c" end })
    Env.register(parent)
    Env.register(child)
    Env.run_update(update, child)
    local left = Env.find_side_values(child.id)
    a.not_nil(left.hl_name, "child got its own sep highlight")
end

-- ============================================================
print("=== Mixed: style inheritance + separator together ===")

do
    local update = fresh()
    local parent = F.make_comp({ style = { fg = "#aaa", bg = "#111" }, left = "(", right = ")", update = function() return "p" end })
    local child = F.make_comp({ ___parent_id = parent.id, style = { fg = "#bbb" }, update = function() return "c" end })
    Env.register(parent)
    Env.register(child)
    Env.run_update(update, child)
    local sv = Env.find_set_value(child.id)
    local l, r = Env.find_side_values(child.id)
    a.not_nil(sv, "child main value set")
    a.eq(l.value, "(")
    a.eq(r.value, ")")
end

-- ============================================================
-- Summary
-- ============================================================
Env.uninstall()
local ok = a.summary()
os.exit(ok and 0 or 1)
