--deepcopy:on
--define:normDebug
switch("warning", "ImplicitDefaultValue:off")
patchFile("stdlib", "jsffi", "patches/jsffi")

