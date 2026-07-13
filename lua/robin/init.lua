--- *robin.nvim.txt*                       Cross-instance cached manpages for Neovim
---
--- Apache License 2.0 Copyright (c) 2026 yilisharcs

---                               Table of Contents
---
---@toc

---@toc_entry INTRODUCTION
---@tag Robin
---@tag Robin-intro
---@text
--- *robin.nvim* is a filesystem cache for |:Man| that avoids re-running man(1) on
--- subsequent opens of the same page, specifically across Nvim sessions.
---
--- # Design ~
---
--- Opening the largest man page on your system can take time. If you're like me
--- and need to buy more RAM, you know it can take longer than 10 seconds (which
--- causes |man.lua| to timeout, error, and not render at all). If you're lucky,
--- it still took 10 seconds, and that's annoying. If you're unlucky and need to
--- open that frequently, those 10 seconds add up, and that's extra annoying.
---
--- This plugin monkey-patches the builtin plugin to intercept manpage requests.
--- After an initial slow open, opening the same page again will instead fetch it
--- from the cache, skipping the groff machinery entirely.
---
--- Do note that this doesn't override the existing same-session cache mechanism.
---
--- # Setup ~
---
--- This plugin works out of the box via 'runtimepath'. There is nothing to
--- configure; just install and forget.
---
--- # Tips ~
---
--- Just the Lua code below does not address the fact that `MANPAGER="nvim +Man!"`
--- still runs all that groff machinery that we want to avoid. For that, I humbly
--- recommend the wrapper below:
--- >bash
---     #!/usr/bin/env bash
---
---     if [ -t 1 ]; then
---         for arg in "$@"; do
---             case "$arg" in -*) exec /usr/bin/man "$@";; esac
---         done
---         exec nvim -c "Man $*" -c "only"
---     else
---         exec /usr/bin/man "$@"
---     fi
--- <
--- If your terminal is interactive, all non-flag arguments are passed to Nvim.
--- You can write the above to `~/.local/bin/man` (assuming that `~/.local/bin` is
--- in your PATH) and enjoy superior manpage navigation in your favorite editor.
---
--- # Q&A ~
---
--- Q: Why is it called `robin.nvim`?
--- A: Because it came after `batman.lua`.
---
--- Q: What is `batman.lua`?
--- A: No comment.

-- ################################################################################################
--
--                                       MODULE DEFINITION
--
-- ################################################################################################

local Robin = {}
local H = {}

---@toc_entry PLUGIN API
---@tag Robin-api
---@tag Robin-API
---@text
--- Public module functions for Robin.

--- Patch |man.read_page| with a filesystem cache.
---
--- This function is called automatically on first |:Man| invocation. You
--- should not need to call it directly.
function Robin.setup()
        -- monkey-patch `man.read_page`
        local man = require("man")
        local original = man.read_page
        local gp, gp_idx = H.upvalue(original, "get_page")
        local pf = H.upvalue(original, "parse_ref")
        local pp = H.upvalue(original, "parse_path")
        local gw = H.upvalue(original, "get_manwidth")
        local so = H.upvalue(original, "set_options")

        if not (gp and gp_idx and pf and pp and gw and so) then
                return
        end

        ---@diagnostic disable-next-line: duplicate-set-field
        man.read_page = function(ref)
                local name, sect = pf(ref)
                if not name then
                        return original(ref)
                end

                local path = man._find_path(name, sect)
                if not path then
                        return "no manual entry for " .. name
                end

                local _, sect1 = pp(path)
                local key = H.get_key(path, gw())

                if key then
                        local cached = H.cache_load(key)
                        if cached then
                                vim.b.manwidth = gw()
                                vim.b.man_sect = sect1
                                vim.bo.modifiable = true
                                vim.bo.readonly = false
                                vim.api.nvim_buf_set_lines(0, 0, -1, false, cached.lines)
                                for _, hl in ipairs(cached.hls) do
                                        H.orig_hl(0, -1, hl.attr, hl.row, hl.start, hl.final)
                                end
                                so()
                                return
                        end
                end

                -- cache miss: swap get_page for longer timeout, run original, capture
                debug.setupvalue(original, gp_idx, H.get_page_slow)
                H.capturing = true
                H.captured = {}
                original(ref)
                local hls = H.captured
                H.capturing = false

                if key then
                        H.cache_save(key, {
                                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                                hls = hls,
                        })
                end
        end
end

-- ################################################################################################
--
--                                         HELPER DATA
--
-- ################################################################################################

---@private
H.cache_dir = vim.fn.stdpath("cache") .. "/man"
vim.fn.mkdir(H.cache_dir, "p")

---@private
--- Capture `nvim_buf_add_highlight` calls during original `read_page`
--- so that they can be replayed on cache hit.
H.capturing = false

---@private
H.captured = {}

---@private
H.orig_hl = vim.api.nvim_buf_add_highlight
---@diagnostic disable-next-line: duplicate-set-field
vim.api.nvim_buf_add_highlight = function(buf, ns, group, row, s, e)
        if H.capturing and buf == 0 then
                H.captured[#H.captured + 1] = { attr = group, row = row, start = s, final = e }
        end
        return H.orig_hl(buf, ns, group, row, s, e)
end

-- ################################################################################################
--
--                                     HELPER FUNCTIONALITY
--
-- ################################################################################################

---@private
function H.get_key(path, manwidth)
        local stat = vim.uv.fs_stat(path)
        if not stat then
                return nil
        end
        return vim.fn.sha256(path .. ":" .. tostring(stat.mtime.sec) .. ":" .. tostring(manwidth))
end

---@private
--- Merge of man.lua's `system` and `get_page`. Runs `man -l {path}` with a
--- 30-second timeout (the default 10 seconds is too short for large pages
--- like configuration.nix(5)). Environment variables are inlined to avoid
--- relying on the `localfile_arg` detection path.
---
---@param path string Manpage file path.
---@param silent boolean? Suppress error output when true.
---@param manwidth integer? Window width for man output. Default: |get_manwidth()|.
---
---@return string # Rendered manpage content.
function H.get_page_slow(path, silent, manwidth)
        local cmd = { "man", "-l", path }
        if vim.fn.executable(cmd[1]) == 0 then
                error(string.format('executable not found: "%s"', cmd[1]), 0)
        end

        local r = vim.system(cmd, {
                env = {
                        MANPAGER = "cat",
                        MANWIDTH = tostring(manwidth),
                        MAN_KEEP_FORMATTING = "1",
                },
                timeout = 30000,
        }):wait()

        if not silent then
                if r.code ~= 0 then
                        local cmd_str = table.concat(cmd, " ")
                        error(string.format("command error '%s': %s", cmd_str, r.stderr))
                end
                assert(r.stdout ~= "")
        end

        return assert(r.stdout)
end

---@private
function H.cache_load(key)
        local f = io.open(H.cache_dir .. "/" .. key, "rb")
        if not f then
                return nil
        end
        local content = f:read("*a")
        f:close()
        local ok, cached = pcall(vim.json.decode, content)
        return ok and cached or nil
end

---@private
function H.cache_save(key, data)
        local f = io.open(H.cache_dir .. "/" .. key, "wb")
        if not f then
                return
        end
        f:write(vim.json.encode(data))
        f:close()
end

---@private
function H.upvalue(fn, name)
        local i = 1
        while true do
                local n, v = debug.getupvalue(fn, i)
                if not n then
                        return nil, nil
                end
                if n == name then
                        return v, i
                end
                i = i + 1
        end
end

return Robin

---@toc_entry TROUBLESHOOTING
---@tag Robin-troubleshooting
---@text
--- If you encounter issues, please follow these steps:
---
--- Use the provided minimal reproduction script to isolate the issue from your
--- personal configuration:
--- >bash
---     make repro
--- <
--- Alternatively, run it directly with Neovim:
--- >bash
---     nvim --clean -u scripts/repro.lua
--- <
--- If the issue persists in the minimal environment, please report it at:
---     https://github.com/yilisharcs/robin.nvim/issues

-- NOTE: this modeline automatically formats docstrings for mini.doc
-- vim: textwidth=82
