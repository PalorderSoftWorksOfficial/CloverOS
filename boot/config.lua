defaultentry = "CloverOS"
timeout = 5
backgroundcolor = colors.black
selectcolor = colors.orange
titlecolor = colors.lightGray

menuentry "CloverOS" {
    description "Boot CloverOS.";
    chainloader "boot/kernel.lua"
}

menuentry "CraftOS" {
    description "Boot into CraftOS.";
    craftos;
}
