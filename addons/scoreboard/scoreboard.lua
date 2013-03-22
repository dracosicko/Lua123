-- Scoreboard addon for Windower4 --

require 'tablehelper'
require 'stringhelper'
require 'mathhelper'

------- USER SETTINGS -------

local x_pos_default = 1500
local y_pos_default = 500
local player_display_count = 5

-----------------------------

local dps_db = T{}
local active_party = T{}
local dps_start_time = 0
local dps_stop_time  = 0
local dps_active = false
local dps_autostart = true

local mob_filter = T{} -- subset of mobs that we're currently displaying damage for

 -- this is lame but it keeps the bg table size consistent
local wait_msg = 'Waiting for results...                 '

function event_addon_command(...)
  local params = {...};
	
	if #params < 1 then
		return
	end

	if params[1] ~= nil then
		if params[1]:lower() == "help" then
			write('sb help : Shows help message')
			write('sb pos <x> <y> : Positions the scoreboard')
			write('sb reset : Reset damage')
			write('sb report : Reports damage to current chatmode')
			write('sb filters  : Shows current filter settings')
			write('sb add <mob1> <mob2> ... : Add mob patterns to the filter (substrings ok)')
			write('sb clear : Clears mob filter')
			write('sb start : Starts dps clock. Automaticly starts if autostart is on')
			write('sb stop: Stops dps clock')
		elseif params[1]:lower() == "pos" then
			if params[3] ~= nil then
				tb_set_location('scoreboard', params[2], params[3])
			end
		elseif params[1]:lower() == "reset" then
			initialize()
		elseif params[1]:lower() == "report" then
			report_summary()
		elseif params[1]:lower() == "mobs" then
			local mob_str
			if mob_filter:isempty() then
				mob_str = "Scoreboard mobs: All"
			else
				mob_str = "Scoreboard mobs: " .. mob_filter:concat(', ')
			end
			add_to_chat(55, mob_str)
		elseif params[1]:lower() == "add" then
			for i=2, #params do
				mob_filter:append(params[i])
			end
			update_scoreboard()
		elseif params[1]:lower() == "clear" then
			mob_filter = T{}
			update_scoreboard()
		elseif params[1]:lower() == "start" then
			dps_start_time = os.time()
			dps_active = true
			update_scoreboard()
			add_to_chat(55, "Scoreboard: Started DPS clock.")
		elseif params[1]:lower() == "stop" then
			dps_stop_time = os.time()
			dps_active = false
			add_to_chat(55, "Scoreboard: Stopped DPS clock.")
			update_scoreboard()
		end
	end
end

-- Resets all data tracking variables
function initialize()

	dps_db = T{}
	start_time = os.time()

	dps_db = T{}
	active_party = T{}
	dps_start_time = 0
	dps_stop_time  = 0
	dps_active = false
	dps_autostart = true

	tb_set_text('scoreboard',  build_scoreboard_header() .. wait_msg)
end

function event_load()
	send_command('alias sb lua c scoreboard')
	
	tb_create('scoreboard')
	tb_set_bg_color('scoreboard', 200, 30, 30, 30)
	tb_set_font('scoreboard', 'courier', 10)
	tb_set_bold('scoreboard', false)
	tb_set_color('scoreboard', 255, 225, 225, 225)
	tb_set_location('scoreboard', x_pos_default, y_pos_default)
	tb_set_visibility('scoreboard', 1)
	tb_set_bg_visibility('scoreboard', 1)

	initialize()
end


function event_unload()
	send_command('unalias sb')
	tb_delete('scoreboard')
end


function parse_line(line)
    local start, stop, player, mob, damage
	local result = {}

	-- Get medicines out of the way first
    if string.find(line, '^(%w+) uses a .*%.$') then
		return nil
	end
	
	-- Regular melee hits
    start, stop, player,
    mob, damage = string.find(line, "^(%w+) hits (.*) for (%d+) points? of damage%.")
    if player and mob and damage then
		accumulate(mob, player, damage)
        return true
    end

	-- Retaliates
    start, stop, player,
	mob, damage = string.find(line, "^(%w+) Retaliates%. (.-) takes (%d+) points? of damage%.")
    if player and mob and damage then
		accumulate(mob, player, damage)
		return true
    end	
	
	-- Counters
    start, stop, mob,
	player, damage = string.find(line, "^(.-)'s attack is countered by (%w+)%. %1 takes (%d+) point? of damage%.")
    if player and mob and damage then
		accumulate(mob, player, damage)
		return true
    end
	

	-- critical hit
    start, stop, player,
	mob, damage = string.find(line, "^(%w+) scores a critical hit!\7([^.]-) takes (%d+) points? of damage%.")
	if player and mob and damage then
		accumulate(mob, player, damage)
		return true
	end
	
	-- weaponskill
    start, stop, player,
	wsName, mob, damage = string.find(line, "^(%w+) uses (.*)%.\7([^.]-) takes (%d+) points? of damage%.")
	if player and wsName and mob and damage then
		accumulate(mob, player, damage)
		return true
	end

	-- spellcasting
	line = string.gsub(line, "^Magic Burst! ", "") -- strip off magic burst tag if there is one
    start, stop, player,
	spellName, mob, damage = string.find(line, "^(%w+) casts (.*)%.\7([^.]-) takes (%d+) points? of damage%.")
	if player and spellName and mob and damage then
		accumulate(mob, player, damage)
		return true
	end

    return nil
end


function accumulate (mob, player, damage)
	local mobdb, playerdb
	
	if active_party[player] == nil then
		return
	end

	mob = string.lower(mob:gsub('^[tT]he ', ''))
	if dps_db[mob] == nil then
		dps_db[mob] = T{}
	end
	
	damage = tonumber(damage)
	if dps_db[mob][player] == nil then
		dps_db[mob][player] = damage
	else
		dps_db[mob][player] = damage + dps_db[mob][player] 
	end
	
end

function update_active_party()
	local party_data = get_party()
	local new_party = {}
	
	for _, member in pairs(party_data) do
		new_party[member["name"]] = 1
	end
	
	active_party = new_party
end


-- Returns following two element pair:
-- - table of sorted 2-tuples containing {player, damage}
-- - integer containing the total damage done
function get_sorted_player_damage()
	-- In order to sort by damage, we have to first add it all up into a table
	-- and then build a table of sortable 2-tuples and then finally we can sort...
	local mob, players
	local player_total_dmg = T{}

	if dps_db == nil then
		return
	end
	
	local function filter_contains_mob(mob_name)
		for _, mob_pattern in ipairs(mob_filter) do
			if mob_name:find(mob_pattern) then
				return true
			end
		end
		return false
	end
	
	for mob, players in pairs(dps_db) do
		-- If the filter isn't active, include all mobs

		if mob_filter:isempty() or filter_contains_mob(mob) then
			for player, damage in pairs(players) do
				if player_total_dmg[player] ~= nil then
					player_total_dmg[player] = player_total_dmg[player] + damage
				else
					player_total_dmg[player] = damage
				end
			end
		end
	end
	
	local sortable = T{}
	local total_damage = 0
	for player, damage in pairs(player_total_dmg) do
		total_damage = total_damage + damage
		sortable:append({player, damage})
	end

	local function cmp(a, b) 
		return a[2] > b[2]
	end
	table.sort(sortable, cmp)
	
	return sortable, total_damage
end

-- Returns the string for the scoreboard header with updated info
-- about current mob filtering and whether or not time is currently
-- contributing to the DPS value.
function build_scoreboard_header()
	local mob_filter_str
	
	if mob_filter:isempty() then
		mob_filter_str = "All"
	else
		mob_filter_str = "Custom ('//sb mobs' to view)"
	end
	
	local labels
	if dps_db:isempty() then
		labels = "\n"
	else
		labels = string.format("%23s%7s%8s\n", "Tot", "Pct", "DPS")
	end
	
	local dps_status
	if dps_active then
		dps_status = "Active"
	else
		dps_status = "Paused"
	end
	return string.format("Mobs: %-9s\nDPS: %s\n%s", mob_filter_str, dps_status, labels)
end

function update_scoreboard()
	local damage_table, total_damage
	damage_table, total_damage = get_sorted_player_damage()
	
	local display_table = T{}
	local player_lines = 0
	for k, v in pairs(damage_table) do
		if player_lines < player_display_count then
			local stop_time
			if dps_active then
				stop_time = os.time()
			else
				stop_time = dps_stop_time
			end

			local dps = math.round(v[2]/(stop_time - start_time), 2)
			local percent = string.format('(%.1f%%)', 100 * v[2]/total_damage)
			display_table:append(string.format("%-16s%7d%8s %7.2f", v[1], v[2], percent, dps))
		end
		player_lines = player_lines + 1
	end
	
	local dps_lines
	if dps_db:isempty() then
		dps_lines = wait_msg
	else
		dps_lines = table.concat(display_table, '\n')
	end
	tb_set_text('scoreboar7d', build_scoreboard_header() .. dps_lines)
end


function report_summary ()
	local damage_table, total_damage
	damage_table, total_damage = get_sorted_player_damage()

	local display_table = T{}
	for k, v in pairs(damage_table) do
		display_table:append(string.format("%s %d(%.1f%%)", v[1], v[2], 100 * v[2]/total_damage))
	end

	send_command('input ' .. table.concat(display_table, ', '))
end


function event_incoming_text(original, modified, color)
	update_active_party()
	
	local success = parse_line(original)
	if success then
		if dps_autostart and not dps_active then
			dps_start_time = os.time()
			dps_active = true
			dps_stop_time = 0
		end
		update_scoreboard()
	end
	
	return modified, color
end


--[[

== Chat Log Syntax ==

Crit syntax:
<Player> scores a critical hit!0x07<mob> takes <integers> point(s)? of damage.

Melee syntax:
<Player> hits <mob> for <integer> point(s)? of damage.

Melee miss syntax:
<Player> misses <mob>.

Weaponskill syntax:
<Player> uses <WS Name>.0x07<mob> takes <integers> point(s)? of damage.

Weaponskill miss syntax:
<Player> uses <WS Name>, but misses the <mob>.

Offensive spell syntax:
<Player> casts <Spell name>.\0x07<mob> takes <integers> point(s) of damage.

Retaliation syntax:
<Player> retaliates. <mob> takes <integers> points? of damage.

Counter syntax:
<mob>'s attack is countered by <Player>. <mob> takes <integers> points? of damage.

Magic Burst syntax:
Magic Burst! <mob> takes <integers> points? of damage.

Medicine syntax:
<Player> uses a <medicine name>.

]]--


--[[
Copyright (c) 2013, Jerry Hebert
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Scoreboard nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL JERRY HEBERT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]--
