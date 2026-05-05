return require("telescope").register_extension({
  exports = {
    ["nvim-vibe"] = require("nvim-vibe.telescope").projects,
  },
})
