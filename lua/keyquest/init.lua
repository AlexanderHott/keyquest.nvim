local M = {}

---Replace things like <leader> from a keymap
---@param keymap string
---@return string
local function expand_keymap(keymap)
	return vim.api.nvim_replace_termcodes(keymap, true, true, true)
end

---Executes a keymap like <CMD>Oil<CR>
---@param keymap_str string
local function exec_keymap_str(keymap_str)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keymap_str, true, false, true), "n", false)
end

---@type Quest[]
local quests = {}

---@type integer?
local buf = nil
---@type integer?
local win = nil

---@class Quest
---@field mode string
---@field keymap string
---@field amount_goal number
---@field amount_curr number

---@class KeyQuestOpts
---@field quests Quest[]

---@param opts KeyQuestOpts
function M.setup(opts)
	opts.quests = vim.F.if_nil(opts.quests, {})
	quests = opts.quests
	M.register_quests()
end

function M.register_quests()
	local keymaps = M.get_keymaps({})
	for _, quest in ipairs(quests) do
		local quest_keymap = expand_keymap(quest.keymap)

		if keymaps[quest.mode][quest_keymap] ~= nil then
			-- keymap is one set by lua
			local existing_keymap = keymaps[quest.mode][quest_keymap]
			vim.keymap.set(quest.mode, quest.keymap, function()
				if quest.amount_curr < quest.amount_goal then
					quest.amount_curr = quest.amount_curr + 1
				end
				M._update_quests()

				if type(existing_keymap.rhs) == "function" then
					existing_keymap.rhs()
				elseif type(existing_keymap.rhs) == "string" then
					exec_keymap_str(existing_keymap.rhs)
				end
			end)
		else
			-- keymap is builtin to nvim
			vim.keymap.set(quest.mode, quest.keymap, function()
				if quest.amount_curr < quest.amount_goal then
					quest.amount_curr = quest.amount_curr + 1
				end
				M._update_quests()

				exec_keymap_str(quest.keymap)
			end)
		end
	end
end

function M.get_keymaps(opts)
	-- https://github.com/nvim-telescope/telescope.nvim/blob/eae0d8fbde590b0eaa2f9481948cd6fd7dd21656/lua/telescope/builtin/__internal.lua#L1236-L1296
	opts.modes = vim.F.if_nil(opts.modes, { "n", "i", "c", "x" })

	local keymap_encountered = {} -- used to make sure no duplicates are inserted into keymaps_table
	local keymaps_table = {}
	---@type table<string, vim.api.keyset.keymap>
	local keymaps_by_lhs = {}

	-- helper function to populate keymaps_table and determine max_len_lhs
	local function extract_keymaps(keymaps, output)
		for _, keymap in pairs(keymaps) do
			local keymap_key = keymap.buffer .. keymap.mode .. keymap.lhs -- should be distinct for every keymap
			if not keymap_encountered[keymap_key] then
				keymap_encountered[keymap_key] = true
				if
					(opts.show_plug or not string.find(keymap.lhs, "<Plug>"))
					and (not opts.lhs_filter or opts.lhs_filter(keymap.lhs))
					and (not opts.filter or opts.filter(keymap))
				then
					table.insert(keymaps_table, keymap)
					output[keymap.lhs] = keymap
				end
			end
		end
	end

	for _, mode in pairs(opts.modes) do
		keymaps_by_lhs[mode] = {}
		local global = vim.api.nvim_get_keymap(mode)
		local buf_local = vim.api.nvim_buf_get_keymap(0, mode)
		if not opts.only_buf then
			extract_keymaps(global, keymaps_by_lhs[mode])
		end
		extract_keymaps(buf_local, keymaps_by_lhs[mode])
	end

	return keymaps_by_lhs
end

function M.toggle()
	if buf == nil and win == nil then
		buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].modifiable = true
		local text, window_w = M._get_quest_text()
		win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			width = window_w,
			height = #text,
			row = 0,
			col = vim.api.nvim_win_get_width(vim.api.nvim_get_current_win()),
			style = "minimal",
			border = "rounded",
		})
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
	else
		if win ~= nil then
			vim.api.nvim_win_close(win, false)
			win = nil
		end
		if buf ~= nil then
			vim.api.nvim_buf_delete(buf, {})
			buf = nil
		end
	end
end

function M._get_quest_text()
	local quest_text = { "Quests", "" }
	local max_w = string.len(quest_text[1])
	for _, quest in ipairs(quests) do
		local icon = ""
		if quest.amount_curr == quest.amount_goal then
			icon = "󰄲"
		else
			icon = "󰄱"
		end
		local line_text = icon .. " " .. quest.keymap .. " " .. quest.amount_curr .. "/" .. quest.amount_goal
		local line_len = string.len(line_text)
		max_w = math.max(max_w, line_len)
		table.insert(quest_text, line_text)
	end

	return quest_text, max_w
end

function M._update_quests()
	if buf ~= nil and win ~= nil then
		local text, window_w = M._get_quest_text()
		vim.api.nvim_win_set_width(win, window_w)
		vim.api.nvim_win_set_height(win, #text)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
	end
end

return M
