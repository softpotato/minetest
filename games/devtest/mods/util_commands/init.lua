minetest.register_chatcommand("hotbar", {
	params = "<size>",
	description = "Set hotbar size",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "No player."
		end
		local size = tonumber(param)
		if not size then
			return false, "Missing or incorrect size parameter!"
		end
		local ok = player:hud_set_hotbar_itemcount(size)
		if ok then
			return true
		else
			return false, "Invalid item count!"
		end
	end,
})

minetest.register_chatcommand("hp", {
	params = "<hp>",
	description = "Set your health",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "No player."
		end
		local hp = tonumber(param)
		if not hp or minetest.is_nan(hp) or hp < 0 or hp > 65535 then
			return false, "Missing or incorrect hp parameter!"
		end
		player:set_hp(hp)
		return true
	end,
})

local s_infplace = minetest.settings:get("devtest_infplace")
if s_infplace == "true" then
	infplace = true
elseif s_infplace == "false" then
	infplace = false
else
	infplace = minetest.is_creative_enabled("")
end

minetest.register_chatcommand("infplace", {
	params = "",
	description = "Toggle infinite node placement",
	func = function(name, param)
		infplace = not infplace
		if infplace then
			minetest.chat_send_all("Infinite node placement enabled!")
			minetest.log("action", "Infinite node placement enabled")
		else
			minetest.chat_send_all("Infinite node placement disabled!")
			minetest.log("action", "Infinite node placement disabled")
		end
		return true
	end,
})

minetest.register_chatcommand("detach", {
	params = "[<radius>]",
	description = "Detach all objects nearby",
	func = function(name, param)
		local radius = tonumber(param)
		if type(radius) ~= "number" then
			radius = 8
		end
		if radius < 1 then
			radius = 1
		end
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "No player."
		end
		local objs = minetest.get_objects_inside_radius(player:get_pos(), radius)
		local num = 0
		for o=1, #objs do
			if objs[o]:get_attach() then
				objs[o]:set_detach()
				num = num + 1
			end
		end
		return true, string.format("%d object(s) detached.", num)
	end,
})

minetest.register_chatcommand("use_tool", {
	params = "(dig <group> <leveldiff>) | (hit <damage_group> <time_from_last_punch>) [<uses>]",
	description = "Apply tool wear a number of times, as if it were used for digging",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "No player."
		end
		local mode, group, level, uses = string.match(param, "([a-z]+) ([a-z0-9]+) (-?%d+) (%d+)")
		if not mode then
			mode, group, level = string.match(param, "([a-z]+) ([a-z0-9]+) (-?%d+)")
			uses = 1
		end
		if not mode or not group or not level then
			return false
		end
		if mode ~= "dig" and mode ~= "hit" then
			return false
		end
		local tool = player:get_wielded_item()
		local caps = tool:get_tool_capabilities()
		if not caps or tool:get_count() == 0 then
			return false, "No tool in hand."
		end
		local actual_uses = 0
		for u=1, uses do
			local wear = tool:get_wear()
			local dp
			if mode == "dig" then
				dp = minetest.get_dig_params({[group]=3, level=level}, caps, wear)
			else
				dp = minetest.get_hit_params({[group]=100}, caps, level, wear)
			end
			tool:add_wear(dp.wear)
			actual_uses = actual_uses + 1
			if tool:get_count() == 0 then
				break
			end
		end
		player:set_wielded_item(tool)
		if tool:get_count() == 0 then
			return true, string.format("Tool used %d time(s). "..
					"The tool broke after %d use(s).", uses, actual_uses)
		else
			local wear = tool:get_wear()
			return true, string.format("Tool used %d time(s). "..
					"Final wear=%d", uses, wear)
		end
	end,
})


-- Unlimited node placement
minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack)
	if placer and placer:is_player() then
		return infplace
	end
end)

-- Don't pick up if the item is already in the inventory
local old_handle_node_drops = minetest.handle_node_drops
function minetest.handle_node_drops(pos, drops, digger)
	if not digger or not digger:is_player() or not infplace then
		return old_handle_node_drops(pos, drops, digger)
	end
	local inv = digger:get_inventory()
	if inv then
		for _, item in ipairs(drops) do
			if not inv:contains_item("main", item, true) then
				inv:add_item("main", item)
			end
		end
	end
end

minetest.register_chatcommand("set_displayed_itemcount", {
	params = "(-s \"<string>\" [-c <color>]) | -a <alignment_num>",
	description = "Set the displayed itemcount of the wielded item",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		local item = player:get_wielded_item()
		local meta = item:get_meta()
		local flag1 = param:sub(1, 2)
		if flag1 == "-s" then
			if param:sub(3, 4) ~= " \"" then
				return false, "Error: Space and string with \"s expected after -s."
			end
			local se = param:find("\"", 5, true)
			if not se then
				return false, "Error: String with two \"s expected after -s."
			end
			local s = param:sub(5, se - 1)
			if param:sub(se + 1, se + 4) == " -c " then
				s = minetest.colorize(param:sub(se + 5), s)
			end
			meta:set_string("count_meta", s)
		elseif flag1 == "-a" then
			local num = tonumber(param:sub(4))
			if not num then
				return false, "Error: Invalid number: "..param:sub(4)
			end
			meta:set_int("count_alignment", num)
		else
			return false
		end
		player:set_wielded_item(item)
		return true, "Displayed itemcount set."
	end,
})

minetest.register_chatcommand("dump_item", {
	params = "",
	description = "Prints a dump of the wielded item in table form",
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		local item = player:get_wielded_item()
		local str = dump(item:to_table())
		print(str)
		return true, str
	end,
})

-- shadow control
minetest.register_on_joinplayer(function (player)
	player:set_lighting({shadows={intensity = 0.33}})
end)

core.register_chatcommand("set_shadow", {
    params = "<shadow_intensity>",
    description = "Set shadow parameters of current player.",
    func = function(player_name, param)
        local shadow_intensity = tonumber(param)
        minetest.get_player_by_name(player_name):set_lighting({shadows = { intensity = shadow_intensity} })
    end
})

core.register_chatcommand("set_saturation", {
    params = "<saturation>",
    description = "Set the saturation for current player.",
    func = function(player_name, param)
        local saturation = tonumber(param)
        minetest.get_player_by_name(player_name):set_lighting({saturation = saturation })
    end
})
