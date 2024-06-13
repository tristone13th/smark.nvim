local M = {}

function M.file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
	end
	return f ~= nil
end

function M.directory_exists(path)
	local ok, _, code = os.rename(path, path)
	if not ok then
		if code == 13 then
			-- Permission denied, but it exists
			return true
		end
	end
	return ok
end

function M.sanitize_path(path)
	return path:gsub("[/\\]", "%%")
end

function M.prefix_blank_nums(text)
	local count = 0
	for i = 1, #text do
		local char = text:sub(i, i)
		if char == " " or char == "\t" then
			count = count + 1
		else
			break
		end
	end
	return count
end

function M.is_position_in_range(line, character, start_line, end_line, start_character, end_character)
	if line > start_line and line < end_line then
		return true
	elseif line == start_line and line == end_line and character >= start_character and character < end_character then
		return true
	elseif line == start_line and character >= start_character then
		return true
	elseif line == end_line and character < end_character then
		return true
	end
	return false
end

return M
