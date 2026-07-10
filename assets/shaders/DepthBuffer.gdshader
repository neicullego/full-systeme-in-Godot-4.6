shader_type spatial;
// unshaded = pas influencé par la lumière du monde
// depth_test_disabled = s'affiche par-dessus tout le décor 3D
render_mode unshaded, depth_test_disabled, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

// --- CONFIGURATION DE L'EAU ---
uniform vec4 water_color : source_color = vec4(0.05, 0.45, 0.55, 0.5);
uniform vec4 deep_water_color : source_color = vec4(0.01, 0.05, 0.12, 1.0);
uniform float water_level = 0.0; // Hauteur globale Y de votre mer
uniform float water_density = 0.15; // Épaisseur du brouillard de profondeur
uniform float distortion_strength = 0.003;

// --- SYNC DES VAGUES (Doit être identique à votre shader de surface) ---
uniform float wave_frequency = 0.4;
uniform float wave_speed = 1.5;
uniform float wave_amplitude = 0.15;

void vertex() {
	// Cette ligne force mathématiquement le Quad à se coller sur l'écran de la caméra
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// 1. OBTENIR LA POSITION DE LA CAMÉRA DANS LE MONDE 3D
	vec3 camera_world_pos = INV_VIEW_MATRIX[3].xyz;
	
	// 2. RECONSTRUIRE LA POSITION DU PIXEL DE L'ÉCRAN DANS LE MONDE 3D
	// Technique mathématique ultra-stable pour Godot 4
	vec4 clip_space = vec4(uv * 2.0 - 1.0, 0.5, 1.0);
	vec4 view_space = INV_PROJECTION_MATRIX * clip_space;
	vec3 ray_direction = normalize((INV_VIEW_MATRIX * vec4(normalize(view_space.xyz / view_space.w), 0.0)).xyz);
	
	// Position exacte de la vitre de la caméra pour ce pixel
	vec3 pixel_lens_pos = camera_world_pos + ray_direction * 0.05;
	
	// 3. CALCUL DE LA HAUTEUR DE LA VAGUE À CET ENDROIT
	float wave = sin(pixel_lens_pos.x * wave_frequency + TIME * wave_speed) * wave_amplitude;
	wave += cos(pixel_lens_pos.z * wave_frequency * 1.3 - TIME * wave_speed * 0.7) * (wave_amplitude * 0.5);
	float dynamic_water_level = water_level + wave;
	
	// 4. LE PIXEL DE LA LENTILLE EST-IL SOUS L'EAU ?
	if (pixel_lens_pos.y < dynamic_water_level) {
		
		// Effet de réfraction (distorsion) sous l'eau
		vec2 distorted_uv = uv;
		distorted_uv.x += sin(pixel_lens_pos.y * 10.0 + TIME * 2.0) * distortion_strength;
		distorted_uv.y += cos(pixel_lens_pos.x * 10.0 + TIME * 1.5) * distortion_strength;
		distorted_uv = clamp(distorted_uv, vec2(0.001), vec2(0.999));
		
		vec3 scene_color = texture(screen_texture, distorted_uv).rgb;
		
		// 5. RECONSTRUCTION DU FOND MARIN (Depth Buffer)
		float depth_raw = texture(depth_texture, distorted_uv).r;
		vec4 ndc = vec4(distorted_uv * 2.0 - 1.0, depth_raw, 1.0);
		vec4 view = INV_PROJECTION_MATRIX * ndc;
		view /= view.w;
		vec3 world_ground = (INV_VIEW_MATRIX * view).xyz;
		
		// Calcul de la distance parcourue par la lumière sous l'eau
		float water_depth_distance = distance(pixel_lens_pos, world_ground);
		
		// Sécurité si le fond reconstruit est en fait hors de l'eau (ex: le ciel ou une île)
		if (world_ground.y > dynamic_water_level) {
			water_depth_distance = max(0.0, (dynamic_water_level - pixel_lens_pos.y) / max(0.001, ray_direction.y));
		}
		
		// Loi d'absorption de la lumière (Beer-Lambert)
		float fog_factor = exp(-water_depth_distance * water_density);
		vec3 water_tint = mix(deep_water_color.rgb, water_color.rgb, fog_factor);
		vec3 final_underwater = mix(water_tint, scene_color * water_tint, 0.5);
		
		// 🟢 LIGNE DE DÉMARCATION (Vue du dessous)
		if (dynamic_water_level - pixel_lens_pos.y < 0.02) {
			final_underwater = mix(final_underwater, vec3(0.02, 0.05, 0.08), 0.8);
		}
		
		ALBEDO = final_underwater;
		
	} else {
		// 6. LE PIXEL DE LA LENTILLE EST DANS L'AIR
		vec3 final_air = texture(screen_texture, uv).rgb;
		
		// 🟢 LIGNE DE DÉMARCATION (Vue du dessus)
		// Si la lentille est juste au-dessus de l'eau, on dessine le ménisque collé aux yeux
		if (pixel_lens_pos.y - dynamic_water_level < 0.02) {
			final_air = mix(final_air, vec3(0.02, 0.05, 0.08), 0.8);
		}
		
		ALBEDO = final_air;
	}
}