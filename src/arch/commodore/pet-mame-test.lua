coroutine.resume(coroutine.create(function()
    local machine = manager.machine
    local kbd = machine.natkeyboard
    local video = machine.video

    local function wait_kbd()
        while kbd.is_posting do
            emu.wait(0.1)
        end
    end

    emu.wait(2)
    kbd:post_coded('dload"cpm"{ENTER}') wait_kbd()
    emu.wait(5)
    kbd:post_coded("run{ENTER}") wait_kbd()
    emu.wait(15)

    kbd:post_coded("bedit{ENTER}") wait_kbd()
    emu.wait(14)
    kbd:post_coded("10 lda #18{ENTER}") wait_kbd()
    kbd:post_coded("20 ldx #35{ENTER}") wait_kbd()
    kbd:post_coded("30 ldy #52{ENTER}") wait_kbd()
    kbd:post_coded("40 label: jmp label{ENTER}") wait_kbd()
    kbd:post_coded("save \"test.asm\"{ENTER}") wait_kbd()
    emu.wait(10)
    kbd:post_coded("quit{ENTER}") wait_kbd()
    emu.wait(10)
    kbd:post_coded("asm test.asm test.com{ENTER}") wait_kbd()
    emu.wait(50)
    kbd:post_coded("test{ENTER}") wait_kbd()
    emu.wait(5)

    local cpu = manager.machine.devices[':f3']
    if (tostring(cpu.state.A) == "12") and (tostring(cpu.state.X) == "23") and (tostring(cpu.state.Y) == "34") then
        print("success!")
        os.exit(0)
    end

    print("fail")
    video:snapshot()
    for k, v in pairs(cpu.state) do
        print(k, type(v), tostring(v))
    end

    os.exit(1)
end))
