-- left reflection a bit quieter so the leaving truck ends on the right
local echo = H.track("Street Echo")
return { e1 = H.set(echo, 0, "Wet", -7), e2 = H.set(echo, 1, "Wet", 0) }
