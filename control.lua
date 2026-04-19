local MOD_PREFIX = "LRS1"
local ROOT_NAME = "lrs_root_frame"
local TEXTBOX_NAME = "lrs_code_textbox"
local STATUS_NAME = "lrs_status_label"
local SUMMARY_NAME = "lrs_summary_label"
local LEGACY_BUTTON_NAME = "lrs_toggle_button"
local SHORTCUT_NAME = "lrs-toggle"

local function ensure_global()
  storage.players = storage.players or {}
end

local function player_state(player_index)
  ensure_global()
  storage.players[player_index] = storage.players[player_index] or {
    last_code = "",
    last_summary = ""
  }
  return storage.players[player_index]
end

local function get_requester_point(player)
  if not (player and player.valid) then
    return nil, {"", "Invalid player."}
  end

  local requester_point = player.get_requester_point()
  if not requester_point then
    return nil, {"lrs.message-no-requester-point"}
  end

  return requester_point
end

local function shallow_copy_signal(signal)
  if not signal then
    return nil
  end

  local copy = {}
  if signal.type then
    copy.type = signal.type
  end
  if signal.name then
    copy.name = signal.name
  end
  if signal.quality then
    copy.quality = signal.quality
  end
  if signal.comparator then
    copy.comparator = signal.comparator
  end
  return next(copy) and copy or nil
end

local function normalize_slot_index(slot_index)
  local numeric = tonumber(slot_index)
  if not numeric or numeric < 1 then
    return nil
  end

  local integer = math.floor(numeric)
  if integer ~= numeric then
    return nil
  end

  return integer
end

local function sanitize_filter(filter, slot_index)
  if not filter then
    return nil
  end

  local clean = {}
  clean.value = shallow_copy_signal(filter.value)
  if filter.min ~= nil then
    clean.min = filter.min
  end
  if filter.max ~= nil then
    clean.max = filter.max
  end
  if filter.minimum_delivery_count ~= nil then
    clean.minimum_delivery_count = filter.minimum_delivery_count
  end
  if filter.import_from ~= nil then
    clean.import_from = filter.import_from
  end

  if not clean.value and clean.min == nil and clean.max == nil and clean.minimum_delivery_count == nil and clean.import_from == nil then
    return nil
  end

  local normalized_slot = normalize_slot_index(slot_index)
  if normalized_slot then
    clean.index = normalized_slot
  end

  return clean
end

local function count_profile_filters(filters)
  if type(filters) ~= "table" then
    return 0
  end

  local count = 0
  for _, filter in pairs(filters) do
    if type(filter) == "table" then
      count = count + 1
    end
  end
  return count
end

local function collect_profile_filters(filters)
  if type(filters) ~= "table" then
    return {}
  end

  local collected = {}
  local seen = {}
  local order = 0

  for array_index, filter in ipairs(filters) do
    order = order + 1
    collected[#collected + 1] = {
      filter = filter,
      order = order,
      slot_index = type(filter) == "table" and normalize_slot_index(filter.index) or nil
    }
    seen[array_index] = true
  end

  for key, filter in pairs(filters) do
    if not seen[key] then
      order = order + 1
      local slot_index = nil
      if type(filter) == "table" then
        slot_index = normalize_slot_index(filter.index)
      end
      if not slot_index then
        slot_index = normalize_slot_index(key)
      end

      collected[#collected + 1] = {
        filter = filter,
        order = order,
        slot_index = slot_index
      }
    end
  end

  table.sort(collected, function(a, b)
    local a_has_slot = a.slot_index ~= nil
    local b_has_slot = b.slot_index ~= nil
    if a_has_slot ~= b_has_slot then
      return a_has_slot
    end
    if a_has_slot and a.slot_index ~= b.slot_index then
      return a.slot_index < b.slot_index
    end
    return a.order < b.order
  end)

  return collected
end

local function serialize_point(point)
  local profile = {
    version = 1,
    enabled = point.enabled,
    trash_not_requested = point.trash_not_requested,
    sections = {}
  }

  local sections = {}
  for _, section in pairs(point.sections) do
    sections[#sections + 1] = section
  end

  table.sort(sections, function(a, b)
    return a.index < b.index
  end)

  for _, section in ipairs(sections) do
    local section_data = {
      group = section.group ~= "" and section.group or nil,
      active = section.active,
      multiplier = section.multiplier,
      filters = {}
    }

    for slot_index, filter in pairs(section.filters) do
      local clean = sanitize_filter(filter, slot_index)
      if clean then
        section_data.filters[#section_data.filters + 1] = clean
      end
    end

    table.sort(section_data.filters, function(a, b)
      return (a.index or math.huge) < (b.index or math.huge)
    end)

    profile.sections[#profile.sections + 1] = section_data
  end

  return profile
end

local function make_summary(profile)
  local section_count = #profile.sections
  local filter_count = 0

  for _, section in ipairs(profile.sections) do
    filter_count = filter_count + count_profile_filters(section.filters)
  end

  return {"lrs.summary-template", section_count, filter_count}
end

local function encode_profile(profile)
  local json = helpers.table_to_json(profile)
  local encoded = helpers.encode_string(json)
  if not encoded then
    return nil, {"lrs.message-export-failed"}
  end

  return MOD_PREFIX .. ":" .. encoded
end

local function decode_profile(code)
  if type(code) ~= "string" then
    return nil, {"lrs.message-import-invalid"}
  end

  local trimmed = code:gsub("^%s+", ""):gsub("%s+$", "")
  local prefix = MOD_PREFIX .. ":"
  if trimmed:sub(1, #prefix) ~= prefix then
    return nil, {"lrs.message-import-prefix"}
  end

  local payload = trimmed:sub(#prefix + 1)
  local json = helpers.decode_string(payload)
  if not json then
    return nil, {"lrs.message-import-invalid"}
  end

  local profile = helpers.json_to_table(json)
  if type(profile) ~= "table" or type(profile.sections) ~= "table" then
    return nil, {"lrs.message-import-invalid"}
  end

  return profile
end

local function count_manual_sections(point)
  local count = 0
  for _, section in pairs(point.sections) do
    if section.is_manual then
      count = count + 1
    end
  end
  return count
end

local function clear_manual_sections(point)
  local indices = {}
  for _, section in pairs(point.sections) do
    if section.is_manual then
      indices[#indices + 1] = section.index
    end
  end

  table.sort(indices, function(a, b)
    return a > b
  end)

  for _, index in ipairs(indices) do
    point.remove_section(index)
  end
end

local function apply_profile_to_point(profile, point)
  clear_manual_sections(point)

  local skipped = {}
  local created_sections = 0
  local created_filters = 0

  point.enabled = profile.enabled ~= false
  point.trash_not_requested = profile.trash_not_requested == true

  for _, section_data in ipairs(profile.sections) do
    local section = point.add_section(section_data.group)
    if section then
      created_sections = created_sections + 1
      section.active = section_data.active ~= false
      section.multiplier = tonumber(section_data.multiplier) or 1

      -- Older v1 payloads store filters sequentially without slot metadata.
      -- Newer payloads carry the original slot index so custom layouts survive export/import.
      local next_slot_index = 1
      local used_slots = {}

      for _, entry in ipairs(collect_profile_filters(section_data.filters)) do
        local filter = entry.filter
        if type(filter) ~= "table" then
          skipped[#skipped + 1] = {"lrs.skip-missing-name"}
        else
          local value = filter.value
          local value_name = value and value.name
          local value_type = value and value.type

          if not value_name then
            skipped[#skipped + 1] = {"lrs.skip-missing-name"}
          elseif value_type and value_type ~= "item" then
            skipped[#skipped + 1] = {"lrs.skip-unsupported-type", value_name, value_type}
          elseif not prototypes.item[value_name] then
            skipped[#skipped + 1] = {"lrs.skip-missing-item", value_name}
          else
            local slot_index = entry.slot_index
            if slot_index and used_slots[slot_index] then
              slot_index = nil
            end
            if not slot_index then
              while used_slots[next_slot_index] do
                next_slot_index = next_slot_index + 1
              end
              slot_index = next_slot_index
            end

            used_slots[slot_index] = true
            section.set_slot(slot_index, {
              value = {
                type = value_type,
                name = value_name,
                quality = value.quality,
                comparator = value.comparator
              },
              min = filter.min,
              max = filter.max,
              minimum_delivery_count = filter.minimum_delivery_count,
              import_from = filter.import_from
            })
            created_filters = created_filters + 1
          end
        end
      end
    end
  end

  return {
    created_sections = created_sections,
    created_filters = created_filters,
    skipped = skipped
  }
end

local function get_root(player)
  return player.gui.screen[ROOT_NAME]
end

local function set_status(player, message, is_error)
  local root = get_root(player)
  if not root then
    return
  end

  local content = root.content_frame
  content[STATUS_NAME].caption = message
  content[STATUS_NAME].style.font_color = is_error and {1, 0.3, 0.3} or {0.55, 0.95, 0.55}
end

local function set_summary(player, summary)
  local root = get_root(player)
  if not root then
    return
  end

  root.content_frame[SUMMARY_NAME].caption = summary
end

local function set_code(player, code)
  local root = get_root(player)
  if not root then
    return
  end

  root.content_frame[TEXTBOX_NAME].text = code or ""
end

local function destroy_legacy_button(player)
  local top = player.gui.top
  local frame = top and top.mod_gui_top_frame
  local flow = frame and frame.mod_gui_inner_frame
  local button = flow and flow[LEGACY_BUTTON_NAME]
  if button and button.valid then
    button.destroy()
  end

  if flow and flow.valid and #flow.children_names == 0 then
    flow.destroy()
  end

  if frame and frame.valid and #frame.children_names == 0 then
    frame.destroy()
  end
end

local function destroy_gui(player)
  local root = get_root(player)
  if root then
    root.destroy()
  end
end

local function build_gui(player)
  destroy_gui(player)

  local state = player_state(player.index)
  local root = player.gui.screen.add{
    type = "frame",
    name = ROOT_NAME,
    direction = "vertical",
    caption = {"lrs.frame-title"}
  }
  root.auto_center = true

  local content = root.add{
    type = "flow",
    name = "content_frame",
    direction = "vertical"
  }
  content.style.padding = 12
  content.style.vertical_spacing = 8
  content.style.minimal_width = 720
  content.style.maximal_width = 720

  local intro = content.add{
    type = "label",
    caption = {"lrs.frame-intro"}
  }
  intro.style.single_line = false

  local buttons = content.add{
    type = "flow",
    direction = "horizontal"
  }
  buttons.style.horizontal_spacing = 8

  buttons.add{
    type = "button",
    name = "lrs_capture_button",
    caption = {"lrs.capture-button"}
  }
  buttons.add{
    type = "button",
    name = "lrs_apply_button",
    caption = {"lrs.apply-button"}
  }
  buttons.add{
    type = "button",
    name = "lrs_close_button",
    caption = {"lrs.close-button"}
  }

  local summary = content.add{
    type = "label",
    name = SUMMARY_NAME,
    caption = state.last_summary ~= "" and state.last_summary or {"lrs.summary-empty"}
  }
  summary.style.single_line = false

  local text_box = content.add{
    type = "text-box",
    name = TEXTBOX_NAME,
    text = state.last_code or ""
  }
  text_box.style.minimal_height = 260
  text_box.style.maximal_height = 260
  text_box.word_wrap = true

  local status = content.add{
    type = "label",
    name = STATUS_NAME,
    caption = {"lrs.status-idle"}
  }
  status.style.single_line = false
  status.style.font_color = {0.8, 0.8, 0.8}

  player.opened = root
end

local function toggle_gui(player)
  if get_root(player) then
    destroy_gui(player)
  else
    build_gui(player)
  end
end

local function capture_current_profile(player)
  local point, err = get_requester_point(player)
  if not point then
    set_status(player, err, true)
    return
  end

  local profile = serialize_point(point)
  local code, encode_err = encode_profile(profile)
  if not code then
    set_status(player, encode_err, true)
    return
  end

  local state = player_state(player.index)
  state.last_code = code
  state.last_summary = make_summary(profile)

  set_code(player, code)
  set_summary(player, state.last_summary)
  set_status(player, {"lrs.message-captured"}, false)
end

local function apply_code_from_gui(player)
  local root = get_root(player)
  if not root then
    return
  end

  local code = root.content_frame[TEXTBOX_NAME].text
  local profile, decode_err = decode_profile(code)
  if not profile then
    set_status(player, decode_err, true)
    return
  end

  local point, point_err = get_requester_point(player)
  if not point then
    set_status(player, point_err, true)
    return
  end

  local result = apply_profile_to_point(profile, point)
  local state = player_state(player.index)
  state.last_code = code
  state.last_summary = make_summary(profile)

  set_summary(player, state.last_summary)

  if #result.skipped > 0 then
    set_status(
      player,
      {"lrs.message-applied-with-skips", result.created_sections, result.created_filters, #result.skipped},
      false
    )
    for _, skipped_message in ipairs(result.skipped) do
      player.print({"", "[LRS] ", skipped_message})
    end
  else
    set_status(player, {"lrs.message-applied", result.created_sections, result.created_filters}, false)
  end
end

local function on_gui_click(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  local name = event.element and event.element.valid and event.element.name
  if name == "lrs_close_button" then
    destroy_gui(player)
    return
  end

  if name == "lrs_capture_button" then
    capture_current_profile(player)
    return
  end

  if name == "lrs_apply_button" then
    apply_code_from_gui(player)
  end
end

local function on_lua_shortcut(event)
  if event.prototype_name ~= SHORTCUT_NAME then
    return
  end

  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  toggle_gui(player)
end

local function on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then
    destroy_legacy_button(player)
  end
end

local function on_player_joined(event)
  local player = game.get_player(event.player_index)
  if player then
    destroy_legacy_button(player)
  end
end

local function init()
  ensure_global()
  for _, player in pairs(game.players) do
    destroy_legacy_button(player)
  end
end

script.on_init(init)
script.on_configuration_changed(init)
script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(defines.events.on_player_joined_game, on_player_joined)
script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_lua_shortcut, on_lua_shortcut)

commands.add_command("lrs-export", {"lrs.command-export-help"}, function(command)
  local player = game.get_player(command.player_index)
  if not player then
    return
  end

  local point = get_requester_point(player)
  if not point then
    player.print({"", "[LRS] ", {"lrs.message-no-requester-point"}})
    return
  end

  local profile = serialize_point(point)
  local code, err = encode_profile(profile)
  if not code then
    player.print({"", "[LRS] ", err})
    return
  end

  local state = player_state(player.index)
  state.last_code = code
  state.last_summary = make_summary(profile)
  player.print({"", "[LRS] ", code})
end)

commands.add_command("lrs-clear-manual", {"lrs.command-clear-help"}, function(command)
  local player = game.get_player(command.player_index)
  if not player then
    return
  end

  local point = get_requester_point(player)
  if not point then
    player.print({"", "[LRS] ", {"lrs.message-no-requester-point"}})
    return
  end

  local count = count_manual_sections(point)
  clear_manual_sections(point)
  player.print({"", "[LRS] ", {"lrs.message-cleared", count}})
end)
