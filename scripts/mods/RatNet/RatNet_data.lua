local mod = get_mod("RatNet")

return {
	name = "RatNet",
	description = mod:localize("mod_description"),
	is_togglable = false,
	options = {
		widgets = {
			{
				setting_id	= "lobby_state",
				type		= "dropdown",
				default_value = "private",
				options = {
					{text = "closed",   value = "closed"},
					{text = "private",   value = "private"},
					{text = "public",   value = "public"},
				},
			},
			{
				setting_id	= "use_desired_players",
				type		= "checkbox",
				default_value = false,
				sub_widgets = {
					{
						setting_id  = "desired_players",
						type		= "numeric",
						default_value = 4,
						range = {1, 32}
					}
				}
			},
			{
				setting_id	= "intent",
				type		= "text",
				default_value = "",
				max_length	= 500
			},
			{
				setting_id	= "stream_link",
				type		= "text",
				default_value = "",
				validate	= function(value)
					return (value == "") or mod.validate_stream_link(mod.standardize_stream_link(value))
				end
			},
			{
				setting_id	= "join_request_sound",
				type		= "dropdown",
				default_value = "pusfume",
				options = {
					{text = "none_text",   value = "none"},
					{text = "pusfume_text",   value = "pusfume"},
					{text = "saltzpyre_text",   value = "saltzpyre"},
					{text = "bass_text",		value = "bass"},
					{text = "dings_text",   value = "dings"},
					{text = "strings_text",   value = "strings"},
					{text = "conga_text",   value = "conga"},
					{text = "orchestra_text",   value = "orchestra"},
					{text = "torgue_text",   value = "torgue"},
					{text = "darksouls_text",   value = "darksouls"},
					{text = "hellothere_text",   value = "hellothere"},
					{text = "exalt_text",   value = "exalt"},
					{text = "vvvg_text",   value = "vvvg"},
					{text = "startrek_text",   value = "startrek"},
					{text = "terraria_text",   value = "terraria"},
					{text = "wololo_text",   value = "wololo"},
				},
			},
			{
				setting_id  = "defaults_group",
				type		= "group",
				sub_widgets = {
					{
						setting_id	= "default_intent",
						type		= "text",
						default_value = "",
						max_length	= 500
					},
					{
						setting_id	= "use_default_lobby_state",
						type		= "checkbox",
						default_value = true,
						sub_widgets = {
							{
								setting_id	= "default_lobby_state",
								type		= "dropdown",
								default_value = "private",
								options = {
									{text = "closed",   value = "closed"},
									{text = "private",   value = "private"},
									{text = "public",   value = "public"},
								},
							},
						},
					},
					{
						setting_id	= "use_default_use_desired_players",
						type		= "checkbox",
						default_value = true,
						sub_widgets = {
							{
								setting_id	= "default_use_desired_players",
								type		= "checkbox",
								default_value = false,
								sub_widgets = {
									{
										setting_id  = "default_desired_players",
										type		= "numeric",
										default_value = 4,
										range = {1, 32}
									}
								}
							},
						},
					},
				},
			},
			{
				setting_id  = "advanced_group",
				type		= "group",
				sub_widgets = {
					{
						setting_id	= "debug_mode",
						type		= "checkbox",
						default_value = false
					},
				},
			},
		}
	}
}
