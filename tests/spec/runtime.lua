describe("nvim-submode.runtime", function()
  local runtime_api
  local submode
  local original_build_submode
  local original_enable
  local original_disable
  local entered_mode
  local enabled_mode

  before_each(function()
    vim = vim or {}
    vim.tbl_extend = vim.tbl_extend or function(_, target, source)
      for key, value in pairs(source) do
        target[key] = value
      end
      return target
    end

    package.loaded["nvim-submode.runtime"] = nil
    runtime_api = require("nvim-submode.runtime")
    submode = require("nvim-submode")
    original_build_submode = submode.build_submode
    original_enable = submode.enable
    original_disable = submode.disable
    entered_mode = nil
    enabled_mode = nil
  end)

  after_each(function()
    submode.build_submode = original_build_submode
    submode.enable = original_enable
    submode.disable = original_disable
  end)

  it("creates an inactive runtime with a copy of its state", function()
    local runtime = runtime_api.create({
      id = "window",
      mappings = {
        { lhs = "h", action = function() end },
      },
    })

    assert.is_false(runtime:is_active())
    assert.same({
      id = "window",
      active = false,
      mapping = nil,
      count = 1,
    }, runtime:get_state())
  end)

  it("converts action results and passes context to actions", function()
    local received
    submode.build_submode = function(metadata, keymaps)
      entered_mode = {
        metadata = metadata,
        keymap = keymaps[1],
      }
      return entered_mode
    end
    submode.enable = function(mode)
      enabled_mode = mode
    end

    local runtime = runtime_api.create({
      id = "window",
      mappings = {
        {
          lhs = "f<any>",
          kind = "any",
          action = function(context)
            received = context
            return { input = "<C-W>h", exit = true }
          end,
        },
      },
      options = { timeout_ms = 150, count = false, interrupt = "<Tab>" },
    })

    runtime:start()
    local input, exit = entered_mode.keymap[2](3, "f<any>", { "s" })

    assert.same({
      runtime = runtime,
      id = "window",
      lhs = "f<any>",
      count = 3,
      captures = { "s" },
      input = nil,
    }, received)
    assert.equals("<C-W>h", input)
    assert.is_true(exit)
    assert.equals(enabled_mode, entered_mode)
    assert.equals(150, entered_mode.metadata.timeoutlen)
    assert.is_false(entered_mode.metadata.is_count_enable)
  end)

  it("updates state and calls lifecycle callbacks", function()
    local events = {}
    submode.build_submode = function(metadata, keymaps)
      entered_mode = {
        metadata = metadata,
        keymap = keymaps[1],
      }
      return entered_mode
    end
    submode.enable = function(mode)
      mode.metadata.after_enter()
    end
    submode.disable = function()
      entered_mode.metadata.after_leave()
    end

    local runtime = runtime_api.create({
      id = "window",
      mappings = {
        { lhs = "h", action = function() end },
      },
      on_enter = function(state)
        events[#events + 1] = { "enter", state.active }
      end,
      on_leave = function(reason, state)
        events[#events + 1] = { "leave", reason, state.active }
      end,
    })

    runtime:start()
    assert.is_true(runtime:is_active())
    runtime:stop()

    assert.is_false(runtime:is_active())
    assert.same({
      { "enter", true },
      { "leave", "stop", false },
    }, events)
  end)
end)
