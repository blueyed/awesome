---------------------------------------------------------------------------
-- @author Uli Schlachter
-- @copyright 2010 Uli Schlachter
-- @release @AWESOME_VERSION@
-- @classmod wibox.widget.base
---------------------------------------------------------------------------

local debug = require("gears.debug")
local object = require("gears.object")
local cache = require("gears.cache")
local matrix = require("gears.matrix")
local Matrix = require("lgi").cairo.Matrix
local setmetatable = setmetatable
local pairs = pairs
local type = type
local table = table

local base = {}

--- Figure out the geometry in device coordinate space. This gives only tight
-- bounds if no rotations by non-multiples of 90° are used.
function base.rect_to_device_geometry(cr, x, y, width, height)
    return matrix.transform_rectangle(cr.matrix, x, y, width, height)
end

--- Fit a widget for the given available width and height
-- @param widget The widget to fit (this uses widget:fit(width, height)).
-- @param width The available width for the widget
-- @param height The available height for the widget
-- @return The width and height that the widget wants to use
function base.fit_widget(widget, width, height)
    -- Sanitize the input. This also filters out e.g. NaN.
    local width = math.max(0, width)
    local height = math.max(0, height)

    return widget._fit_geometry_cache:get(width, height)
end

--- Set/get a widget's buttons
function base:buttons(_buttons)
    if _buttons then
        self.widget_buttons = _buttons
    end

    return self.widget_buttons
end

--- Handle a button event on a widget. This is used internally.
function base.handle_button(event, widget, x, y, button, modifiers, geometry)
    local function is_any(mod)
        return #mod == 1 and mod[1] == "Any"
    end

    local function tables_equal(a, b)
        if #a ~= #b then
            return false
        end
        for k, v in pairs(b) do
            if a[k] ~= v then
                return false
            end
        end
        return true
    end

    -- Find all matching button objects
    local matches = {}
    for k, v in pairs(widget.widget_buttons) do
        local match = true
        -- Is it the right button?
        if v.button ~= 0 and v.button ~= button then match = false end
        -- Are the correct modifiers pressed?
        if (not is_any(v.modifiers)) and (not tables_equal(v.modifiers, modifiers)) then match = false end
        if match then
            table.insert(matches, v)
        end
    end

    -- Emit the signals
    for k, v in pairs(matches) do
        v:emit_signal(event,geometry)
    end
end

--- Create widget placement information. This should be used for a widget's
-- :layout() callback.
-- @param widget The widget that should be placed.
-- @param mat A cairo matrix transforming from the parent widget's coordinate
--        system. For example, use cairo.Matrix.create_translate(1, 2) to draw a
--        widget at position (1, 2) relative to the parent widget.
-- @param width The width of the widget in its own coordinate system. That is,
--        after applying the transformation matrix.
-- @param height The height of the widget in its own coordinate system. That is,
--        after applying the transformation matrix.
-- @return An opaque object that can be returned from :layout()
function base.place_widget_via_matrix(widget, mat, width, height)
    return {
        _widget = widget,
        _width = width,
        _height = height,
        _matrix = matrix.copy(mat)
    }
end

--- Create widget placement information. This should be used for a widget's
-- :layout() callback.
-- @param widget The widget that should be placed.
-- @param x The x coordinate for the widget.
-- @param y The y coordinate for the widget.
-- @param width The width of the widget in its own coordinate system. That is,
--        after applying the transformation matrix.
-- @param height The height of the widget in its own coordinate system. That is,
--        after applying the transformation matrix.
-- @return An opaque object that can be returned from :layout()
function base.place_widget_at(widget, x, y, width, height)
    return base.place_widget_via_matrix(widget, Matrix.create_translate(x, y), width, height)
end

--- Create a new widget. All widgets have to be generated via this function so
-- that the needed signals are added and mouse input handling is set up.
-- @param proxy If this is set, the returned widget will be a proxy for this
--              widget. It will be equivalent to this widget.
function base.make_widget(proxy)
    local ret = object()

    -- This signal is used by layouts to find out when they have to update.
    ret:add_signal("widget::layout_changed")
    ret:add_signal("widget::redraw_needed")
    -- Mouse input, oh noes!
    ret:add_signal("button::press")
    ret:add_signal("button::release")
    ret:add_signal("mouse::enter")
    ret:add_signal("mouse::leave")

    -- Backwards compatibility
    -- TODO: Remove this
    ret:add_signal("widget::updated")
    ret:connect_signal("widget::updated", function()
        ret:emit_signal("widget::layout_changed")
        ret:emit_signal("widget::redraw_needed")
    end)

    -- No buttons yet
    ret.widget_buttons = {}
    ret.buttons = base.buttons

    -- Make buttons work
    ret:connect_signal("button::press", function(...)
        return base.handle_button("press", ...)
    end)
    ret:connect_signal("button::release", function(...)
        return base.handle_button("release", ...)
    end)

    if proxy then
        ret.fit = function(_, ...) return proxy._fit_geometry_cache:get(proxy, ...) end
        ret.layout = function(_, width, height)
            return { base.place_widget(proxy, Matrix.create_identity(), width, height) }
        end
        proxy:connect_signal("widget::layout_changed", function()
            ret:emit_signal("widget::layout_changed")
        end)
        proxy:connect_signal("widget::redraw_needed", function()
            ret:emit_signal("widget::redraw_needed")
        end)
    end

    -- Add caches for :fit() and :layout()
    local function layout_cb(...)
        if ret.layout then
            return ret:layout(...)
        end
    end
    local function fit_cb(width, height)
        local w, h = 0, 0
        if ret.fit then
            w, h = ret:fit(width, height)
        else
            -- If it has no fit method, calculate based on the size of children
            local children = ret._layout_cache:get(width, height)
            for _, info in ipairs(children or {}) do
                local x, y, w2, h2 = matrix.transform_rectangle(info._matrix,
                    0, 0, info._width, info._height)
                w, h = math.max(w, x + w2), math.max(h, y + h2)
            end
        end
        -- Fix up the result that was returned
        w = math.max(0, math.min(width, w))
        h = math.max(0, math.min(height, h))
        return w, h
    end
    local function clear_cache()
        ret._fit_geometry_cache = cache.new(fit_cb)
        ret._layout_cache = cache.new(layout_cb)
    end
    clear_cache()
    ret:connect_signal("widget::layout_changed", clear_cache)

    return ret
end

--- Generate an empty widget which takes no space and displays nothing
function base.empty_widget()
    return base.make_widget()
end

--- Do some sanity checking on widget. This function raises a lua error if
-- widget is not a valid widget.
function base.check_widget(widget)
    debug.assert(type(widget) == "table")
    for k, func in pairs({ "add_signal", "connect_signal", "disconnect_signal" }) do
        debug.assert(type(widget[func]) == "function", func .. " is not a function")
    end
end

return base

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
