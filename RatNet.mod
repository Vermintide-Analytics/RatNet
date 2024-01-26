return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`RatNet` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("RatNet", {
			mod_script       = "scripts/mods/RatNet/RatNet",
			mod_data         = "scripts/mods/RatNet/RatNet_data",
			mod_localization = "scripts/mods/RatNet/RatNet_localization",
		})
	end,
	packages = {
		"resource_packages/RatNet/RatNet",
	},
}
