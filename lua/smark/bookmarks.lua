local M = {}
local persistence = require("smark.persistence")
local utils = require("smark.utils")

M.bookmarks = {}
M.text = nil
M.yanked = false
M.marks_in_selection = {}

function M.setup()
	vim.api.nvim_create_autocmd({ "DirChangedPre" }, {
		callback = M.save_bookmarks,
		pattern = { "*" },
	})
	-- Include the case when session is loaded since that will also change the cwd.
	-- Will trigger when vim is launched and load the session
	vim.api.nvim_create_autocmd({ "DirChanged" }, {
		callback = M.load_bookmarks,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "BufEnter" }, {
		callback = M.on_buf_enter,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		callback = M.on_buf_write_post,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "TextYankPost" }, {
		callback = function()
			M.yanked = true
		end,
		pattern = { "*" },
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		callback = function(event)
			M.display_bookmarks(event.buf)
		end,
	})
end

function M.display_bookmarks(bufnr)
	if bufnr == 0 or bufnr == nil then
		bufnr = vim.api.nvim_get_current_buf()
	end

	local icon_group = "smark"

	vim.fn.sign_unplace(icon_group, { buffer = bufnr })

	local file_name = vim.api.nvim_buf_get_name(bufnr)

	if not M.bookmarks[file_name] then
		return
	end

	local sign_name = "smark_symbol"
	local icon = "🚩"
	if vim.fn.sign_getdefined(sign_name) == nil or #vim.fn.sign_getdefined(sign_name) == 0 then
		vim.fn.sign_define(sign_name, { text = icon, texthl = "Error", numhl = "Error" })
	end

	for id, _ in pairs(M.bookmarks[file_name]) do
		local sign_id = tonumber(id)
		local line = math.floor(sign_id / 1000)
		vim.fn.sign_place(sign_id, icon_group, sign_name, bufnr, { lnum = line, priority = 10 })
	end
end

function M.create_bookmark(symbol)
	local file_name = vim.api.nvim_buf_get_name(0)

	if not M.bookmarks[file_name] then
		M.bookmarks[file_name] = {}
	end

	if symbol then
		M.bookmarks[file_name][tostring(symbol.lnum * 1000 + symbol.col)] = math.max(symbol.col, 0)
	else
		local cursor = vim.api.nvim_win_get_cursor(0)
		local current_line = vim.api.nvim_get_current_line()
		local prefix_blanks = utils.prefix_blank_nums(current_line)
		M.bookmarks[file_name][tostring(cursor[1] * 1000 + cursor[2])] = math.max(cursor[2] - prefix_blanks, 0)
	end
end

function M.delete_bookmark()
	local file_name = vim.api.nvim_buf_get_name(0)
	local cursor = vim.api.nvim_win_get_cursor(0)

	if not M.bookmarks[file_name] then
		return
	end

	for id, _ in pairs(M.bookmarks[file_name]) do
		if math.floor(tonumber(id) / 1000) == cursor[1] then
			M.bookmarks[file_name][id] = nil
		end
	end
end

-- Do we have a bookmark in current cursor?
function M.has_bookmark()
	local file_path = vim.api.nvim_buf_get_name(0)
	local bookmarks_file = M.bookmarks[file_path]
	local cursor = vim.api.nvim_win_get_cursor(0)

	if not bookmarks_file then
		return false
	end

	for id, _ in pairs(bookmarks_file) do
		if math.floor(tonumber(id) / 1000) == cursor[1] then
			return true
		end
	end

	return false
end

function M.toggle_bookmark()
	if M.has_bookmark() then
		M.delete_bookmark()
	else
		M.create_bookmark()
	end
	M.save_bookmarks()
	M.display_bookmarks(0)
end

function M.on_buf_write_post(event)
	M.calibrate_bookmarks(event.buf)
end

function M.on_buf_enter(event)
	M.display_bookmarks(event.buf)
end

-- use signs to calibrate M.bookmarks[]
function M.calibrate_bookmarks(bufnr)
	if bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	local file_name = vim.api.nvim_buf_get_name(bufnr)

	local file_marks = M.bookmarks[file_name]
	if not file_marks then
		return
	end

	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "smark" })

	local new_marks = {}
	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			for id, col in pairs(file_marks) do
				if tonumber(id) == sign.id then
					new_marks[tostring(sign.lnum * 1000 + col)] = col
					break
				end
			end
		end
	end

	M.bookmarks[file_name] = new_marks
	M.save_bookmarks()
	M.display_bookmarks(bufnr)
end

function M.load_bookmarks(event)
	M.bookmarks = persistence.load()
	M.display_bookmarks(event.buf)
end

function M.save_bookmarks()
	persistence.save(M.bookmarks)
end

local function get_visual_selection()
	local s_start = vim.fn.getpos("'<")
	local s_end = vim.fn.getpos("'>")
	local start_line = s_start[2]
	local end_line = s_end[2]
	local start_c = s_start[3]
	local end_c = s_end[3]

	-- get all bookmarks in the selection
	local bufnr = vim.api.nvim_get_current_buf()
	local extmarks = vim.fn.sign_getplaced(bufnr, { group = "smark" })
	local file_name = vim.api.nvim_buf_get_name(bufnr)
	if not M.bookmarks[file_name] then
		return
	end

	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			local col = sign.id % 1000
			if utils.is_position_in_range(sign.lnum, col, start_line, end_line, start_c, end_c) then
				table.insert(M.marks_in_selection, { lnum = sign.lnum - start_line, col = col })
				M.bookmarks[file_name][tostring(sign.id)] = nil
			end
		end
	end
	local n_lines = math.abs(end_line - start_line) + 1

	-- get all lines of text
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	lines[1] = string.sub(lines[1], start_c, -1)
	if n_lines == 1 then
		lines[n_lines] = string.sub(lines[n_lines], 1, end_c - start_c + 1)
	else
		lines[n_lines] = string.sub(lines[n_lines], 1, end_c)
	end

	return table.concat(lines, "\n")
end

local function split_text(text)
	local lines = {}
	for line in text:gmatch("([^\n]*)\n?") do
		table.insert(lines, line)
	end
	return lines
end

function M.paste_text()
	if not M.yanked then
		if not vim.tbl_isempty(M.marks_in_selection) then
			local cursor = vim.api.nvim_win_get_cursor(0)

			-- vim.api.nvim_paste(M.text, true, -1)
			vim.api.nvim_put(split_text(M.text), "c", true, false)
			for _, symbol in ipairs(M.marks_in_selection) do
				symbol.lnum = symbol.lnum + cursor[1]
				M.create_bookmark(symbol)
			end
			M.marks_in_selection = {}
		else
			vim.api.nvim_put(split_text(M.text), "c", true, false)
		end
		M.save_bookmarks()
		M.display_bookmarks(0)
	else
		vim.cmd("normal! p")
	end
end

function M.delete_visual_selection()
	M.calibrate_bookmarks(0)
	M.text = get_visual_selection()
	vim.cmd('normal! gv"') -- Re-select the last selected text
	vim.cmd('normal! "_d') -- Delete the selected text without affecting registers
	M.yanked = false
end

return M
