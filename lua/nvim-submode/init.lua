local Trie = require("nvim-submode.trie")
local Queue = require("nvim-submode.queue")
local DEBUG = false
local function debugPrint(...)
  if DEBUG == true then
    print(...)
  end
end

local SUBMODE_COUNT_DISABLE = -1


local M = {}
M.EXIT_SUBMODE = -2

function M.reset_context()
  return {
    -- namespace
    ns = nil,
    -- namespace for input barrier
    barrier_ns = nil,

    timeoutlen_timer = nil,

    name = nil,
    display_name = nil,
    color = nil,
    state = nil,
    show_info = true,
  }
end

M.context = M.reset_context()
M.after_leave = function() end


local function get_mode_char()
  local current_mode = vim.api.nvim_get_mode()["mode"]
  local mode_info = current_mode:sub(1, 1)
  mode_info = mode_info == "V" and "v" or mode_info
  return mode_info
end

local function infoPrint(...)
  if M.context.show_info then
    print(...)
  end
end


function M.regularize_key_input(input)
  local regularized = vim.fn.keytrans(vim.api.nvim_replace_termcodes(input, true, true, true))
  return regularized:gsub("<lt>any>", "<any>"):gsub("<lt>Any>", "<any>")
end

local function is_number_str(c)
  return tonumber(c) ~= nil
end

---たとえキー入力を行わない場合であっても、nvimのバグを回避するために空文字列でこの関数を呼び出さなければならない
---@param keys any
function M.input_keys(keys)
  assert(type(keys) == "string", "keys must be string")
  -- This code must works! But dosen's since nvim has a bug!!!!
  -- vim.api.nvim_feedkeys(keys, "n", false)
  vim.api.nvim_feedkeys(keys, "ni", false)
end

--- Substitute any to real typed keys. e.g. f<any><any> and you typed "fsa" then the function returns "fsa"
---@param keys string
---@param anys table
---@return string
function M.replace_any(keys, anys)
  for _, typed in ipairs(anys) do
    keys = keys:gsub("<any>", typed, 1)
  end
  return keys
end

-- 本来input_barrierは不要だが、現在のon_keyでは<cmd>/K_LUAのときに後続のキーを受け取る方法がない
-- そこで、実際に入力するべきキーを第一層のon_keyで確定させた後、
-- その処理の前後でinput_barrierを起動し、不要な入力をinput_barrierにぶつけて強引に破棄する
-- vim.scheduleを呼ぶと、input_barrierによる破棄が完了するまで飛べるので、
-- うまくいく?
local function disable_input_barrier()
  --debugPrint("DISABLE barrier")
  vim.on_key(nil, M.context.barrier_ns)
  M.context.barrier_ns = nil
end

local function enable_input_barrier()
  --debugPrint("ENABLE barrier")
  if M.context.barrier_ns ~= nil then
    disable_input_barrier()
  end
  M.context.barrier_ns = vim.api.nvim_create_namespace("nvim-submode._internal_input_barrier")
  vim.on_key(function(_, _)
    return ""
  end, M.context.barrier_ns)
end

---Function to call on_key with pcall
---@param on_key_callback function
local function safe_on_key(on_key_callback, ns)
  vim.on_key(function(key, typed)
    local ok, res = pcall(on_key_callback, key, typed)
    if ok then
      return res
    else
      disable_input_barrier()
      M.disable()
      vim.notify(res, vim.log.levels.ERROR)
      return ""
    end
  end, ns)
end

function M.input_keys_with_input_barrier(keys)
  if (type(keys) ~= "string" or keys == "") then
    return
  end
  assert(type(keys) == "string", "keys must be string")
  local mode_info = get_mode_char()
  -- normalモードではinput barrierに起因する問題を確実に回避するため、normal!コマンドを使う
  if mode_info == "n" or mode_info == "v" then
    -- normal!コマンドでもon_keyは突破できないので強制的に切る
    -- この直後にコールバックで登録し直せば問題ない
    vim.on_key(nil, M.context.ns)
    -- 理由はわからないが、normalのときはinputと同じアプローチは取れない
    -- もともとはnvim_pasteを使っていたが、多分これが唯一上手くいく方法
    vim.cmd("normal! " .. vim.api.nvim_replace_termcodes(keys, true, true, true) .. "")
    return
  elseif mode_info == "i" or mode_info == "c" then
    if keys == "" then
      return
    end
    vim.on_key(nil, M.context.ns)
    -- もともとはnvim_pasteを使っていたが、多分これが唯一上手くいく方法
    -- 余計なキー入力が破棄されるまで待つためにscheduleを呼ぶ
    vim.schedule(function()
      disable_input_barrier()
      vim.api.nvim_input(keys)
    end)
    return
  else
    disable_input_barrier()
    M.input_keys(keys)
    vim.schedule(function()
      enable_input_barrier()
    end)
  end
end

--- @class Submoode
--- @field timeoutlen integer
--- @field default function
--- @field after_enter function
--- @field after_leave function
--- @field keymap_trie Trie
--- @field name string
--- @field display_name string
--- @field color string
--- @field show_info boolean
--- @field is_count_enable boolean


--- @class SubmodeMetadata
--- @field name string The name of submode
--- @field display_name string|nil The name of the submode displayed in the status line.
--- @field after_enter function|nil A callback that is triggered after the sub-mode is enabled.
--- @field after_leave function|nil A callback that is triggered after the submode is disable.
--- @field timeoutlen number|nil The waiting time before ending the partial match waiting period and executing the exact match, when both exact and partial key mappings exist. Same as g:timeoutlen
--- @field color string|nil
--- @field show_info boolean|nil
--- @field is_count_enable boolean|nil


---Build submode instance from SubmodeMetadata and submode keymaps.
---@param submode_metadata SubmodeMetadata
---@param submode_keymaps table
---@return Submoode
function M.build_submode(submode_metadata, submode_keymaps)
  local keymap_trie = Trie:new()
  assert(type(submode_metadata.name) == "string", "submode name is not given!")
  local name = submode_metadata.name
  assert(name ~= "_internal_input_barrier", "This submode name is used intenal. Please rename.")
  for _, sm_keymap in ipairs(submode_keymaps) do
    assert(#sm_keymap >= 2, "Each submode keymap has 2 or 3 element")
    assert(type(sm_keymap[1]) == "string", "Keymap LHS must be string")
    assert(type(sm_keymap[2]) == "string" or type(sm_keymap[2]) == "function", "Keymap RHS must be string or function")
    keymap_trie:insert(M.regularize_key_input(sm_keymap[1]), sm_keymap[2])
  end

  return {
    timeoutlen = submode_metadata.timeoutlen or vim.o.timeoutlen,
    default = function()

    end,
    after_enter = submode_metadata.after_enter or function() end,
    after_leave = submode_metadata.after_leave or function() end,
    keymap_trie = keymap_trie,
    name = submode_metadata.name,
    display_name = submode_metadata.display_name or submode_metadata.name,
    color = submode_metadata.color or "#999999",
    show_info = submode_metadata.show_info == nil and true or submode_metadata.show_info,
    is_count_enable = submode_metadata.is_count_enable == nil and true or submode_metadata.is_count_enable
  }
end

local decide_action

--- Actionを決定する純粋関数
--- @param mode Submoode
--- @param buf string typed buffer queue
--- @param c string typed char but can include "<any>"
--- @param any_substitutes table|nil それぞれの<any>として何が入力されかを表現するリスト
--- @param submode_count number same as v:count, which represents number modification to keymap.
--- @return function|nil rhs_callback rhsとして実際に入力されるキー列を返す関数。rhsのactionが関数の場合はその関数を実行する。
--- @return string|nil on_key_ret on_key関数の返り値として用いる。nilのときcが基底モードに対してpassthroughされる。nilの場合は遮断(基底モードにcが入力されない)
--- @return string next_buf The next state of the typed buffer queue
--- @return table next_any_substitutes any_substitutesの次の状態
--- @return boolean timer_start timerを起動するかどうかを表す。曖昧なキー入力時に使われる
decide_action = function(mode, buf, c, any_substitutes, submode_count)
  any_substitutes = any_substitutes or {}
  local trie = mode.keymap_trie
  -- 検索用のlhs。<any>を含む
  local search_lhs = buf .. c
  -- 実際のlhs。<any>の代わりに実際の入力に置き換わっている
  local cm = trie:search(search_lhs)
  local pm = trie:countStartsWith(search_lhs)
  if (submode_count ~= SUBMODE_COUNT_DISABLE and is_number_str(c)) then
    -- キー入力の途中で数字を打ったことになるが、この操作はカウントが有効な場合は許可されていないので、問答無用でマッチング失敗
    infoPrint("Number is not interpreted as key if submode enable.")
    return nil, nil, "", {}, false
  end
  if pm == 0 then
    if c == "<any>" then
      debugPrint("no lhs exists")
      return nil, nil, "", {}, false
    else
      -- "<any>"で再検索
      table.insert(any_substitutes, c)
      return decide_action(mode, buf, "<any>", any_substitutes, submode_count)
    end
  elseif cm == true and pm >= 1 then
    -- 完全一致のみ。特定のrhsに確定
    local leaf = trie:getLeaf(search_lhs)

    assert(leaf ~= nil)
    assert(leaf.isEndOfWord == true)
    assert(leaf.value ~= nil)

    local action = leaf.value
    local rhs_callback = function()
      local rhs = ""
      local exit = false
      if (type(action) == "string") then
        if (submode_count > 0) then
          -- submode_count回、キーマッピングを繰り返す
          rhs = action:rep(submode_count)
        else
          rhs = action
        end
      elseif type(action) == "function" then
        rhs, exit = action(submode_count, search_lhs, any_substitutes)
      end
      return rhs or "", exit
    end
    if pm == 1 then
      return rhs_callback, "", "", {}, false
    else -- pm>1
      return rhs_callback, "", search_lhs, {}, true
    end
  elseif cm == false and pm >= 1 then
    infoPrint("Waiting...:" .. search_lhs)

    return nil, "", search_lhs, any_substitutes, false
  end
  assert(false, "Logic Error")
  return nil, "", "", {}, false
end



--- @param mode Submoode
--- @param init_buf string|nil initialized value of buffer
function M.enable(mode, init_buf)
  local ns = vim.api.nvim_create_namespace("nvim-submode." .. mode.name)
  M.context.name = mode.name
  M.context.display_name = mode.display_name
  M.context.color = mode.color
  local is_count_enable = mode.is_count_enable

  mode.after_enter()
  M.after_leave = mode.after_leave

  -- typed buffer
  local buf = init_buf or ""
  if (init_buf ~= nil) then
    vim.schedule(function()
      -- 事前に入力済みであることを再現するため（これがないとon_keyがトリガーされない）
      M.input_keys("")
    end)
  end
  local callback
  local any_substitutes = {}
  local prev_t = ""
  local num_queue = Queue:new()
  -- 現在判定中のキーマッピングに対して適用予定のcount, -1であるときカウント機能が無効であることを示す
  local count_reg = nil
  local reset_typeahead_buf = function()
    buf = ""
    count_reg = nil
  end
  callback = function(k, t)
    local typed = vim.fn.keytrans(t)
    debugPrint("k:" .. vim.fn.keytrans(k) .. " t:" .. vim.fn.keytrans(t))
    if not is_number_str(prev_t) and is_number_str(typed) and count_reg == nil then
      -- Switch input_char from text to number
      debugPrint("Enqueue:", typed)
      num_queue:enqueue("")
    end
    enable_input_barrier()
    vim.on_key(nil, ns)
    local is_t_empty = t == ""
    t = is_t_empty and prev_t or t
    prev_t = t

    debugPrint(buf .. typed, "<-", typed)
    -- stop key waiting

    if (typed == "<Esc>") then
      -- If there are keybindings associated with <Esc>,
      -- it's necessary to wait until the consumption of their right-hand sides is complete before exiting the submode,
      -- so we use vim.schedule to wait until the processing is finished.
      vim.schedule(function()
        M.disable()
        M.after_leave()
        M.after_leave = function() end
      end)
      return ""
    else
      -- If t is empty, meaning that unnecessary rhs input is being provided due to the user's mapping,
      -- it should always return an empty string and be ignored.
      if is_t_empty then
        debugPrint("DISGARD:", k)
        vim.schedule(
          function()
            disable_input_barrier()
            safe_on_key(callback, ns)
          end
        )
        return ""
      end

      -- count_regがnilではないということは何かしらを入力途中であることを意味する
      if is_count_enable and is_number_str(typed) and count_reg == nil then
        debugPrint("Before:", num_queue:getBack())
        local current_end_of_num_queue = num_queue:getBack()
        debugPrint("count:", num_queue:getBack())
        debugPrint("length:", num_queue:size())
        num_queue:setBack(current_end_of_num_queue .. typed)
        infoPrint("Count:", num_queue:getBack())
        vim.schedule(function()
          disable_input_barrier()
          safe_on_key(callback, ns)
        end)
        return ""
      end
      -- レジスタに値がない場合のみ更新する
      if count_reg == nil then
        if is_count_enable then
          if num_queue:isEmpty() then
            count_reg = 0
          else
            -- -2 represents the error queue has not number
            count_reg = tonumber(num_queue:dequeue()) or -2
          end
        else
          count_reg = SUBMODE_COUNT_DISABLE
        end
      end
      debugPrint("NOT DISGARD", typed, k)
      local ok, is_timer_start, rhs_callback
      ok, rhs_callback, _, buf, any_substitutes, is_timer_start =
          pcall(decide_action, mode, buf, typed, any_substitutes, count_reg)
      if (not ok) then
        disable_input_barrier()
        -- Since rhs_callback is error messeage, rhs_callback must be string here
        vim.notify("ERROR: " .. rhs_callback, vim.log.levels.ERROR)
        return
      end

      if buf == "" then
        -- 実際にキーマップが実行されるか、キーマップがキャンセルされた場合のみレジスタをリセットする
        reset_typeahead_buf()
      end

      local execute_action = function()
        if M.context.timeoutlen_timer ~= nil then
          -- timer起動時にbufのリセットを省略したため、このタイミングで削除
          reset_typeahead_buf()
          M.context.timeoutlen_timer:stop()
          M.context.timeoutlen_timer = nil
        end

        if type(rhs_callback) ~= "function" then
          vim.notify("LOGIC ERROR: rhs_callback is not function", vim.log.levels.ERROR)
          return true
        end

        local res, exit = rhs_callback()
        -- 1. 戻り値resの型チェック（nilまたはstring以外はエラー）
        if type(res) ~= "string" and type(res) ~= "nil" then
          vim.notify("First return value from an action function must be string or nil.", vim.log.levels.ERROR)
          return true
        end

        -- 2. 戻り値exitの型チェックと値の検証
        local is_exit_number = (type(exit) == "number")

        if is_exit_number and exit ~= M.EXIT_SUBMODE then
          -- exitが数値だが M.EXIT_SUBMODE ではない場合はエラー
          vim.notify(
            "Second return value from an action function must be nil or M.EXIT_SUBMODE and others are not permitted.",
            vim.log.levels.ERROR
          )
          return true
        end

        M.input_keys_with_input_barrier(res or "") -- resはstringまたはnilなので、nilの場合は空文字列を使用

        if is_exit_number then
          return true
        else
          return false
        end
      end


      if is_timer_start then
        M.context.timeoutlen_timer = vim.defer_fn(function()
          disable_input_barrier()
          local exit = execute_action()
          if exit then
            vim.schedule(function()
              M.disable()
              M.after_leave()
              M.after_leave = function() end
            end)
            return ""
          end
          vim.schedule(function()
            disable_input_barrier()
            safe_on_key(callback, ns)
          end)
        end, mode.timeoutlen)
        vim.schedule(function()
          disable_input_barrier()
          safe_on_key(callback, ns)
        end)
      else
        local exit = execute_action()
        if exit then
          vim.schedule(function()
            M.disable()
            M.after_leave()
            M.after_leave = function() end
          end)
          return ""
        end
        vim.schedule(
          function()
            disable_input_barrier()
            safe_on_key(callback, ns)
          end
        )
      end
    end
    return ""
  end

  safe_on_key(
    callback, ns
  )
  M.context.ns = ns
end

function M.disable()
  disable_input_barrier()
  if M.context.ns ~= nil then
    vim.on_key(nil, M.context.ns)
    M.context.ns = nil
  end
  M.context = M.reset_context()
end

-- Utility Functions
function M.countable(action)
  return function(count, keys, anys)
    local res
    for _ = 1, count, 1 do
      res = action(count, keys, anys)
    end
    return res
  end
end

function M.get_submode_name()
  return M.context.display_name or nil
end

function M.get_submode_color()
  return M.context.color or nil
end

---set submode state
---@param state table the next state of submode
function M.set_state(state)
  assert(M.context.name~=nil,"set_state can only be used within a submode.")
  M.context.state = state
end

---get submode state
---@return table|nil curren_state the current state
function M.get_state()
  assert(M.context.name~=nil,"set_state can only be used within a submode.")
  return M.context.state
end
return M
