describe("nvim-submode statusline API", function()
  local submode
  local original_context

  before_each(function()
    submode = require("nvim-submode")
    original_context = submode.context
    submode.context = submode.reset_context()
    submode.state.submode = nil
    submode.state.submode_display_name = nil
    submode.state.submode_color = nil
  end)

  after_each(function()
    submode.context = original_context
    submode.state.submode = nil
    submode.state.submode_display_name = nil
    submode.state.submode_color = nil
  end)

  it("returns the compatible statusline state", function()
    submode.state.submode = "window"
    submode.state.submode_display_name = "Window"
    submode.state.submode_color = "#123456"

    assert.same({
      basemode = "",
      submode = "window",
      display_name = "Window",
      color = "#123456",
      user_object = {},
    }, submode.get_statusline())
    assert.same(submode.get_statusline(), submode.getStatusline())
  end)

  it("refreshes registered adapters and supports unregistering them", function()
    local received = {}
    local unregister = submode.register_statusline(function(state)
      received[#received + 1] = state
    end)

    submode.state.submode = "window"
    submode.state.submode_display_name = "Window"
    submode.refresh_statusline()
    assert.equals(1, #received)
    assert.equals("window", received[1].submode)

    received[1].submode = "changed"
    assert.equals("window", submode.get_statusline().submode)

    unregister()
    submode.refreshStatusline()
    assert.equals(1, #received)
  end)

  it("accepts an object adapter and stores user state", function()
    local received
    local adapter = {
      refresh = function(self, state)
        assert.equals(adapter, self)
        received = state
      end,
    }
    local unregister = submode.registerStatusline(adapter)
    local user_state = { tab = 3 }
    submode.setUserState(user_state)
    submode.refresh_statusline()

    assert.equals(user_state, received.user_object)
    unregister()
  end)
end)
