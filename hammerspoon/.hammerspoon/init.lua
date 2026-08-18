require("cmd-v")

-- Reload on save, so editing these files is enough.
configWatcher = hs.pathwatcher.new(hs.configdir, function(files)
  for _, file in ipairs(files) do
    if file:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end):start()

-- Lets `hs -c "..."` talk to the running instance instead of hanging.
require("hs.ipc")

hs.alert.show("Hammerspoon ready")
