plugged := env("HOME") / ".local/share/nvim/plugged"

run:
    nvim --clean --cmd 'set runtimepath+=.,{{plugged}}/coop.nvim'

develop:
    nvim --clean --cmd 'set runtimepath+=.,{{plugged}}/coop.nvim' -c 'runtime plugin/symbiont.lua' -c ':SymbiontSubmit I am testing a acp implementation, please exercise every renderable output type that does not need permission so I can verify the rendering pipeline. Build a todo plan with three entries spanning high, medium, and low priority and progress them through pending, in_progress, and completed as you work. Read this justfile (read tool with a file location). Read the file lua/symbiont/session.lua so a second read tool call shows up directly under the first without a new header. Grep the repo for the word symbiont (search tool). Fetch https://example.com (fetch tool). In your final reply include a paragraph of plain text, a fenced lua code block, and an inline markdown link to one of the files you read. Do not write a reasoning block yourself, the agent reasoning channel is rendered separately by the client.' -c ':Symbiont' -c 'set clipboard=unnamed,unnamedplus'

test:
    nvim --headless -c 'PlenaryBustedDirectory tests/ {minimal_init = "tests/minimal_init.lua"}'
