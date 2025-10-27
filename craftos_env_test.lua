 print("Setting up CraftOS environment...")
    pcall(function()
        shell.run("attach left drive")
        shell.run("attach right speaker")
        shell.run("attach back monitor")
        if disk and disk.insertDisk then
            disk.insertDisk("left", "C:\\CloverOS_Disks\\0")
        end
    end)
    print("Environment setup complete.")
    sleep(1)