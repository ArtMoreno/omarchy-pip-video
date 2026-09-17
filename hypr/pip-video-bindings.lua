-- artmrn.pip-video keybindings (managed by the plugin install script).
--
-- Loaded from the user's bindings.lua by the plugin install script:
--   dofile("<plugin-dir>/hypr/pip-video-bindings.lua")
-- Helper scripts resolve through ~/.local/bin, where the install script
-- symlinks them, so this file works on any machine.

local pip_bin_dir = (os.getenv("HOME") or "") .. "/.local/bin"

-- Video wallpaper (mpvpaper). Copy a YouTube URL, press SUPER+ALT+V.
o.bind("SUPER + ALT + V", "Video wallpaper from clipboard", pip_bin_dir .. "/video-wallpaper clip")
o.bind("SUPER + ALT + C", "Video wallpaper stop", pip_bin_dir .. "/video-wallpaper stop")
o.bind("SUPER + ALT + P", "Video wallpaper pause/resume", pip_bin_dir .. "/video-wallpaper pause")
o.bind("SUPER + ALT + B", "Video wallpaper mute/unmute", pip_bin_dir .. "/video-wallpaper mute")

-- See-through: adjust opacity of all windows on the current workspace
-- so the video wallpaper shows through apps.
o.bind("SUPER + CTRL + BRACKETLEFT", "Workspace windows more transparent", pip_bin_dir .. "/workspace-opacity down")
o.bind("SUPER + CTRL + BRACKETRIGHT", "Workspace windows more opaque", pip_bin_dir .. "/workspace-opacity up")
o.bind("SUPER + ALT + BACKSPACE", "Workspace windows reset transparency", pip_bin_dir .. "/workspace-opacity reset")

-- YouTube PiP video: shrink/grow with the keyboard (aspect kept 16:9).
-- Works even when the PiP is not focused.
o.bind("SUPER + ALT + H", "YouTube PiP smaller", hl.dsp.window.resize({ x = -50, y = -28, relative = true, window = "title:Picture[- ]in[- ]Picture" }))
o.bind("SUPER + ALT + L", "YouTube PiP bigger", hl.dsp.window.resize({ x = 50, y = 28, relative = true, window = "title:Picture[- ]in[- ]Picture" }))
-- YouTube PiP video: explicit height axis (width untouched).
o.bind("SUPER + ALT + J", "YouTube PiP shorter", hl.dsp.window.resize({ x = 0, y = -30, relative = true, window = "title:Picture[- ]in[- ]Picture" }))
o.bind("SUPER + ALT + U", "YouTube PiP taller", hl.dsp.window.resize({ x = 0, y = 30, relative = true, window = "title:Picture[- ]in[- ]Picture" }))
