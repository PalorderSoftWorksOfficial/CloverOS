-- fortune: a small wisdom dispenser (CloverOS package payload)
local wisdom = {
	"Computers are only as smart as the people who program them.",
	"There is no place like /home.",
	"A journey of a thousand commits begins with a single init.",
	"The best shell is the one you know by heart.",
	"Permissions are not a suggestion.",
	"When in doubt, read the man page.",
	"Root access solves nothing; it only sharpens the consequences.",
	"Every file is temporary; backups are forever.",
	"Packages come and go; dotfiles are eternal.",
	"The cursor blinks, therefore I am.",
}

math.randomseed(os.epoch("utc") + os.getComputerID())
print(wisdom[math.random(#wisdom)])
