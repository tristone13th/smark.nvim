local M = {}
local persistence = require("smark.persistence")
local utils = require("smark.utils")

M.bookmarks = {}

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

	local icon = "🚩"

	for line, _ in pairs(M.bookmarks[file_name]) do
		local sign_name = tostring(line)
		if vim.fn.sign_getdefined(sign_name) == nil or #vim.fn.sign_getdefined(sign_name) == 0 then
			vim.fn.sign_define(sign_name, { text = icon, texthl = "Error", numhl = "Error" })
		end
		vim.fn.sign_place(0, icon_group, sign_name, bufnr, { lnum = line, priority = 10 })
	end
end

function M.create_bookmark()
	local file_name = vim.api.nvim_buf_get_name(0)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = vim.api.nvim_get_current_line()
	local prefix_blanks = utils.prefix_blank_nums(current_line)

	if not M.bookmarks[file_name] then
		M.bookmarks[file_name] = {}
	end

	M.bookmarks[file_name][tostring(cursor[1])] = math.max(cursor[2] - prefix_blanks, 0)
	M.save_bookmarks()
	M.display_bookmarks(0)
end

function M.delete_bookmark()
	local file_name = vim.api.nvim_buf_get_name(0)
	local cursor = vim.api.nvim_win_get_cursor(0)

	if not M.bookmarks[file_name] then
		return
	end

	M.bookmarks[file_name][tostring(cursor[1])] = nil

	M.save_bookmarks()
	M.display_bookmarks(0)
end

-- Do we have a bookmark in current cursor?
function M.has_bookmark()
	local file_path = vim.api.nvim_buf_get_name(0)
	local bookmarks_file = M.bookmarks[file_path]
	local cursor = vim.api.nvim_win_get_cursor(0)

	if not bookmarks_file then
		return false
	end

	if bookmarks_file[tostring(cursor[1])] then
		return true
	end

	return false
end

function M.toggle_bookmark()
	if M.has_bookmark() then
		M.delete_bookmark()
	else
		M.create_bookmark()
	end
end

function M.on_buf_write_post(event)
	M.calibrate_bookmarks(event.buf)
end

function M.on_buf_enter(event)
	M.display_bookmarks(event.buf)
end

-- use signs to calibrate M.bookmarks[]
function M.calibrate_bookmarks(bufnr)
	local file_name = vim.api.nvim_buf_get_name(bufnr)

	local file_marks = M.bookmarks[file_name]
	if not file_marks then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()

	local extmarks = vim.fn.sign_getplaced(current_buf, { group = "smark" })

	local new_marks = {}
	for _, marks in ipairs(extmarks) do
		for _, sign in ipairs(marks.signs) do
			for name, col in pairs(file_marks) do
				if name == sign.name then
					new_marks[tostring(sign.lnum)] = col
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

return M
