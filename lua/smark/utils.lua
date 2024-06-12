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

return M
