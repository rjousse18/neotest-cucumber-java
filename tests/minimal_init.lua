-- Minimal Neovim config for the test suite: puts the plugin and its dependencies on the runtimepath.
-- Dependencies are looked up in ./.deps (see `make deps`) or in $NEOTEST_CUCUMBER_DEPS.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local deps = vim.env.NEOTEST_CUCUMBER_DEPS or (root .. "/.deps")

vim.opt.runtimepath:prepend(root)
for _, name in ipairs({ "plenary.nvim", "nvim-nio", "neotest" }) do
  vim.opt.runtimepath:prepend(deps .. "/" .. name)
end
vim.cmd("runtime plugin/plenary.vim")
