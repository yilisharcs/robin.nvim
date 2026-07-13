package.path = "./vendor/mini.doc/lua/?.lua;" .. package.path

local minidoc = require("mini.doc")
minidoc.setup()

local spec = {
        id = "robin",
        title = "Robin",
        author = "yilisharcs",
        cmd_prefix = "",
}

local repo = spec.author .. "/" .. spec.id .. ".nvim"
local url = "https://github.com/" .. repo

-- documentation manifest. `entrypoint` is explicitly placed at the first index
-- of the input array passed to `minidoc.generate()` so it can be accessible as
-- doc[1] in its many hooks.
local manifest = {
        entrypoint = "lua/" .. spec.id .. "/init.lua",
        metadata = {},
}
setmetatable(manifest, {
        __call = function(self)
                return { self.entrypoint, unpack(self.metadata) }
        end,
})

local H = {}

-- indentation levels
H.s4 = string.rep(" ", 4)
H.s8 = string.rep(" ", 8)

--- Check if any line in a section matches a literal pattern.
---
--- This function iterates through the numeric indices of a section object. It
--- returns true on the first match or nil if no match is found.
---@param section table Documentation section object.
---@param pattern string Literal string to find.
---
---@return boolean? # True if found, nil otherwise.
H.has_pattern = function(section, pattern)
        for _, line in ipairs(section) do
                if type(line) == "string" and line:find(pattern, 1, true) then
                        return true
                end
        end
end

--- shared logic for merging config (no-op: robin accepts no config)
H.prepare_doc_tree = function(doc, is_readme) end

-- logic for Vim help file
local doc_hooks = vim.deepcopy(minidoc.config.hooks)
doc_hooks.doc = function(doc)
        H.prepare_doc_tree(doc, false)
        minidoc.default_hooks.doc(doc)
end

-- logic for README.md
local readme_hooks = vim.deepcopy(minidoc.config.hooks)

-- NOTE: the original hook generates a tags file.
--       the README.md does not need a tags file.
readme_hooks.write_post = function(d)
        local output = d.info.output
        local msg = ("%s is successfully generated."):format(vim.inspect(output))
        vim.notify(msg, vim.log.levels.INFO)
end

readme_hooks.sections["@toc_entry"] = function(s)
        local content = vim.trim(table.concat(s, " "))
        s:clear_lines()
        s:insert("## " .. content)
        s:insert("")
end
readme_hooks.doc = function(doc)
        local file = doc[1]
        H.prepare_doc_tree(doc, true)

        local to_remove = {}
        local skip = false
        for i, block in ipairs(file) do
                local should_remove = false

                -- find the start of the API section
                if
                        block:has_descendant(function(s)
                                return s.info and s.info.id == "@toc_entry" and H.has_pattern(s, "PLUGIN API")
                        end)
                then
                        skip = true
                end

                if skip then
                        should_remove = true
                end

                -- find the next major section to stop skipping
                if
                        block:has_descendant(function(s)
                                return s.info and s.info.id == "@toc_entry" and H.has_pattern(s, "TROUBLESHOOTING")
                        end)
                then
                        skip = false
                        should_remove = false
                end

                if should_remove then
                        table.insert(to_remove, i)
                end
        end

        -- remove the blocks from the tree in reverse
        for i = #to_remove, 1, -1 do
                file:remove(to_remove[i])
        end

        -- remove `[id].Setup` class block
        for i = #file, 1, -1 do
                if
                        file[i]:has_descendant(function(s)
                                return s.info and s.info.id == "@signature" and H.has_pattern(s, spec.title .. ".setup")
                        end)
                then
                        file:remove(i)
                end
        end

        -- NOTE: skip default doc hook which adds Vim modeline!!
        -- minidoc.default_hooks.doc(doc)
end

readme_hooks.write_pre = function(lines)
        -- header
        local res = {
                "# " .. spec.id .. ".nvim",
                "",
                "Cross-instance cached manpages for Neovim.",
                "",
                "## INSTALLATION",
                "",
                "Using Neovim's built-in package manager:",
                "",
                "```lua",
                "vim.pack.add({",
                H.s8 .. 'src = "' .. url .. '",',
                "})",
                "```",
                "",
                "Using [lazy.nvim](https://github.com/folke/lazy.nvim):",
                "",
                "```lua",
                "{",
                H.s8 .. '"' .. repo .. '",',
                "}",
                "```",
                "",
        }

        local in_code_block = false
        for i, line in ipairs(lines) do
                if
                        -- separators
                        line:match("^=+$")
                        or line:match("^%-+$")
                        -- title
                        or line:find(spec.id .. ".nvim.txt", 1, true)
                        -- help tags
                        or line:match("^%s*%*" .. spec.title .. "%S*%*%s*$")
                        -- license line
                        or line:match("^%s*Apache License 2.0 Copyright")
                        -- TOC
                        or line:match("^%s*Table of Contents%s*$")
                        -- modeline
                        or line:match("vim:tw=78:ts=8:noet:ft=help:norl:")
                then
                        goto next_line
                end

                if line:match("^%s+" .. url .. "/issues$") then
                        table.insert(res, "")
                        table.insert(res, vim.trim(line))
                        goto next_line
                end

                -- convert vim code blocks into markdown code blocks
                if line:match("^%s*>lua%s*$") then
                        in_code_block = true
                        table.insert(res, "")
                        table.insert(res, "```lua")
                        goto next_line
                elseif line:match("^%s*>bash%s*$") then
                        in_code_block = true
                        table.insert(res, "")
                        table.insert(res, "```bash")
                        goto next_line
                elseif line:match("^%s*>%s*$") then
                        in_code_block = true
                        table.insert(res, "")
                        table.insert(res, "```")
                        goto next_line
                elseif line:match("^%s*<%s*$") then
                        in_code_block = false
                        table.insert(res, "```")
                        table.insert(res, "")
                        goto next_line
                end

                -- level 3 headers
                local h_title = line:match("^%s*#%s*([^~]-)%s*~%s*$")
                if h_title then
                        table.insert(res, "")
                        table.insert(res, "### " .. vim.trim(h_title))
                        table.insert(res, "")
                        goto next_line
                end

                -- level 5 headers
                local cmd_tag = line:match("^%s+%*(:" .. spec.cmd_prefix .. "%w+)%*%s*$")
                if cmd_tag then
                        local sig = cmd_tag
                        local next_line = lines[i + 1]
                        if next_line then
                                sig = next_line:match("^(:" .. spec.cmd_prefix .. "%w+.-)%s%s") or sig
                        end
                        table.insert(res, "")
                        table.insert(res, "##### " .. sig)
                        table.insert(res, "")
                        goto next_line
                end

                if in_code_block then
                        -- de-indent
                        line = line:gsub("^" .. H.s4, "")
                else
                        line = line:gsub("%*" .. spec.id .. ".nvim%*", "_" .. spec.id .. ".nvim_")
                        -- replace command signature at start of
                        -- line with spaces to maintain alignment
                        line = line:gsub("^:" .. spec.cmd_prefix .. "%w+.-%s%s+", function(m)
                                return string.rep(" ", #m)
                        end)

                        -- inline formatting
                        line = line:gsub("|:checkhealth| `" .. spec.id .. "` ", "`:checkhealth " .. spec.id .. "` ")
                        line = line:gsub("|([^|]+)|", "`%1`")
                end
                table.insert(res, line)

                ::next_line::
        end

        -- append license
        vim.list_extend(res, {
                "",
                "## LICENSE",
                "",
                "Copyright 2026 " .. spec.author,
                "",
                'Licensed under the Apache License, Version 2.0 (the "License");',
                "you may not use this file except in compliance with the License.",
                "You may obtain a copy of the License at",
                "",
                "http://www.apache.org/licenses/LICENSE-2.0",
                "",
                "Unless required by applicable law or agreed to in writing, software",
                'distributed under the License is distributed on an "AS IS" BASIS,',
                "WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.",
                "See the License for the specific language governing permissions and",
                "limitations under the License.",
        })

        -- cleanup: ensure single blank lines between blocks
        local final_res = {}
        for i, line in ipairs(res) do
                if line ~= "" or (final_res[#final_res] ~= "" and i < #res) then
                        table.insert(final_res, line)
                end
        end

        return final_res
end

minidoc.generate(manifest(), "doc/" .. spec.id .. ".nvim.txt", {
        hooks = doc_hooks,
})

minidoc.generate(manifest(), "README.md", {
        hooks = readme_hooks,
})
