-- Attach and open the modem
local modem = peripheral.find("modem")
modem.open(1)  -- Open channel 1 for communication

print("Waiting for messages on channel 1...")

while true do
    local senderID, message, protocol = rednet.receive(5)  -- Wait up to 5 seconds
    if senderID then
        print("Received from " .. senderID .. ": " .. message)
        rednet.send(senderID, "Hello, Pocket!", protocol)
    else
        print("No message received...")
    end
end
