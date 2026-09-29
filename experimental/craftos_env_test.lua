-- CraftOS environment compatibility test script
print("Setting up CraftOS environment...")
shell.run("attach left drive")
shell.run("attach right speaker")
shell.run("attach back monitor")
if disk and disk.insertDisk then
  disk.insertDisk("left", "C:\\CloverOS_Disks\\0")
end
print("Environment setup complete.")
sleep(1)
