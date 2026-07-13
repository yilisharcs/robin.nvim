# robin.nvim

Cross-instance cached manpages for Neovim.

## INSTALLATION

Using Neovim's built-in package manager:

```lua
vim.pack.add({
        src = "https://github.com/yilisharcs/robin.nvim",
})
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
        "yilisharcs/robin.nvim",
}
```

## INTRODUCTION

_robin.nvim_ is a filesystem cache for `:Man` that avoids re-running man(1) on
subsequent opens of the same page, specifically across Nvim sessions.

### Design

Opening the largest man page on your system can take time. If you're like me
and need to buy more RAM, you know it can take longer than 10 seconds (which
causes `man.lua` to timeout, error, and not render at all). If you're lucky,
it still took 10 seconds, and that's annoying. If you're unlucky and need to
open that frequently, those 10 seconds add up, and that's extra annoying.

This plugin monkey-patches the builtin plugin to intercept manpage requests.
After an initial slow open, opening the same page again will instead fetch it
from the cache, skipping the groff machinery entirely.

Do note that this doesn't override the existing same-session cache mechanism.

### Setup

This plugin works out of the box via 'runtimepath'. There is nothing to
configure; just install and forget.

### Tips

Just the Lua code below does not address the fact that `MANPAGER="nvim +Man!"`
still runs all that groff machinery that we want to avoid. For that, I humbly
recommend the wrapper below:

```bash
#!/usr/bin/env bash

if [ -t 1 ]; then
    for arg in "$@"; do
        case "$arg" in -*) exec /usr/bin/man "$@";; esac
    done
    exec nvim -c "Man $*" -c "only"
else
    exec /usr/bin/man "$@"
fi
```

If your terminal is interactive, all non-flag arguments are passed to Nvim.
You can write the above to `~/.local/bin/man` (assuming that `~/.local/bin` is
in your PATH) and enjoy superior manpage navigation in your favorite editor.

### Q&A

Q: Why is it called `robin.nvim`?
A: Because it came after `batman.lua`.

Q: What is `batman.lua`?
A: No comment.

## TROUBLESHOOTING

If you encounter issues, please follow these steps:

Use the provided minimal reproduction script to isolate the issue from your
personal configuration:

```bash
make repro
```

Alternatively, run it directly with Neovim:

```bash
nvim --clean -u scripts/repro.lua
```

If the issue persists in the minimal environment, please report it at:

https://github.com/yilisharcs/robin.nvim/issues

## LICENSE

Copyright 2026 yilisharcs

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.