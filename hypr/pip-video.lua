-- artmrn.pip-video: YouTube Picture-in-Picture polish (Chromium + Firefox).
--
-- Loaded from the user's hyprland.lua by the plugin install script:
--   dofile("<plugin-dir>/hypr/pip-video.lua")
-- Rounded corners and a grabbable border instead of Omarchy's fixed
-- sharp-edged look, plus SUPER + 2-finger pinch to resize live.

o.window(
  { title = "^Picture[- ]in[- ]Picture$" },
  {
    name = "pip-video",
    float = true,
    pin = true,
    border_size = 4,
    rounding = 12,
    keep_aspect_ratio = true,
    animation = "popin 80",
  }
)

-- SUPER + 2-finger pinch on the touchpad: grow/shrink the PiP video live.
-- Targets the PiP by title, so plain 2-finger pinch-zoom in browsers keeps
-- working everywhere else. Hold SUPER before the fingers touch the pad.
-- e.scale is a ratio relative to gesture start (starts at ~1.0, spread > 1,
-- pinch < 1), so the resize is driven by its per-update delta.
local pip_pinch_last = nil

hl.gesture({
  fingers = 2,
  direction = "pinch",
  mods = "SUPER",
  action = {
    start = function(e)
      pip_pinch_last = nil
    end,
    update = function(e)
      if e.scale == nil then
        return
      end
      if pip_pinch_last == nil then
        pip_pinch_last = e.scale
        return
      end
      local d = e.scale - pip_pinch_last
      pip_pinch_last = e.scale
      local dw = math.floor(d * 500)
      if dw == 0 then
        return
      end
      hl.dispatch(hl.dsp.window.resize({
        x = dw,
        y = math.floor(dw * 9 / 16),
        relative = true,
        window = "title:Picture[- ]in[- ]Picture",
      }))
    end,
  },
})
