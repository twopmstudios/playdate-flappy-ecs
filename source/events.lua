-- ==========================================
-- Event System
-- ==========================================
EventSystem = {}
EventSystem.listeners = {}

function EventSystem.subscribe(eventName, callback)
    if not EventSystem.listeners[eventName] then
        EventSystem.listeners[eventName] = {}
    end
    table.insert(EventSystem.listeners[eventName], callback)
    return #EventSystem.listeners[eventName] -- Return index for unsubscribe
end

function EventSystem.unsubscribe(eventName, index)
    if EventSystem.listeners[eventName] then
        EventSystem.listeners[eventName][index] = nil
    end
end

function EventSystem.emit(eventName, data)
    if EventSystem.listeners[eventName] then
        for _, callback in pairs(EventSystem.listeners[eventName]) do
            callback(data)
        end
    end
end
