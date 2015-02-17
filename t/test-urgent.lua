--- Tests for urgent property.

awful = require("awful")

-- Some basic assertion that the tag is not marked "urgent" already.
assert(awful.tag.getproperty(tags[1][2], "urgent") == nil)


-- Setup signal handler which should be called.
-- TODO: generalize and move to runner.
local urgent_cb_done
client.connect_signal("property::urgent", function (c)
  urgent_cb_done = true
  assert(c.class == "XTerm", "Client should be xterm!")
end)

local manage_cb_done
client.connect_signal("manage", function (c)
  manage_cb_done = true
  assert(c.class == "XTerm", "Client should be xterm!")
end)


-- Steps to do for this test.
local steps = {
  -- Step 1: tag 2 should become urgent, when a client gets tagged via rules.
  function(count)
    if count == 1 then  -- Setup.
      urgent_cb_done = false
      -- Select first tag.
      awful.tag.viewonly(tags[1][1])

      runner.add_to_default_rules({ rule = { class = "XTerm" },
        properties = { tag = tags[1][2], focus = true } })

      awful.util.spawn("xterm")
    end
    if urgent_cb_done then
      assert(awful.tag.getproperty(tags[1][2], "urgent") == true)
      assert(awful.tag.getproperty(tags[1][2], "urgent_count") == 1)
      return true
    end
  end,

  -- Step 2: when switching to tag 2, it should not be urgent anymore.
  function(count)
    if count == 1 then
      -- Setup: switch to tag.
      os.execute('xdotool key super+2')

    elseif awful.tag.selectedlist()[1] == tags[1][2] then
      assert(#client.get() == 1)
      assert(client.get()[1] == client.focus)
      assert(awful.tag.getproperty(tags[1][2], "urgent") == false)
      assert(awful.tag.getproperty(tags[1][2], "urgent_count") == 0)
      return true
    end
  end,

  -- Step 3: tag 2 should not be urgent, but switched to.
  function(count)
    if count == 1 then  -- Setup.
      local urgent_cb_done = false

      -- Select first tag.
      os.execute('xdotool key super+1')

      runner.add_to_default_rules({ rule = { class = "XTerm" },
        properties = { tag = tags[1][2], focus = true, switchtotag = true }})

      awful.util.spawn("xterm")
    else
      if urgent_cb_done then
        assert(awful.tag.getproperty(tags[1][2], "urgent") == false)
        assert(awful.tag.getproperty(tags[1][2], "urgent_count") == 0)
        assert(awful.tag.selectedlist()[1] == tags[1][2])
        assert(awful.tag.selectedlist()[2] == nil)
        return true
      else
        assert(awful.tag.selectedlist()[1] == tags[1][1])
        assert(awful.tag.selectedlist()[2] == nil)
      end
    end
  end,


  -- Step 4: tag 2 should not become urgent, when a client gets tagged via
  -- rules with focus=false.
  function(count)
    if count == 1 then  -- Setup.
      client.get()[1]:kill()
      manage_cb_done = false

      runner.add_to_default_rules({rule = { class = "XTerm" },
        properties = { tag = tags[1][2], focus = false }})

      awful.util.spawn("xterm")
    end
    if manage_cb_done then
      assert(client.get()[1].urgent == false)
      assert(awful.tag.getproperty(tags[1][2], "urgent") == false)
      assert(awful.tag.getproperty(tags[1][2], "urgent_count") == 0)
      return true
    end
  end,
}

require("_runner").run_steps(steps)