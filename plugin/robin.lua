if vim.g.loaded_robin == 1 then
        return
end
vim.g.loaded_robin = 1
vim.g.loaded_man = 1

vim.api.nvim_create_user_command("Man", function(params)
        require("robin").setup()
        local man = require("man")
        if params.bang then
                man.init_pager()
        else
                local _, err = pcall(man.open_page, params.count, params.smods, params.fargs)
                if err then
                        vim.notify("man.lua: " .. err, vim.log.levels.ERROR)
                end
        end
end, {
        bang = true,
        bar = true,
        range = true,
        addr = "other",
        nargs = "*",
        complete = function(...)
                return require("man").man_complete(...)
        end,
})

-- register the autocmds the built-in man plugin would have registered
local group = vim.api.nvim_create_augroup("robin.man", { clear = true })

vim.api.nvim_create_autocmd("BufReadCmd", {
        group = group,
        pattern = "man://*",
        nested = true,
        callback = function(params)
                local err = require("man").read_page(assert(params.match:match("man://(.*)")))
                if err then
                        vim.notify("man.lua: " .. err, vim.log.levels.ERROR)
                end
        end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        pattern = "man://*",
        callback = function()
                local err = require("man").refresh_page()
                if err then
                        vim.notify("man.lua: " .. err, vim.log.levels.ERROR)
                end
        end,
})
