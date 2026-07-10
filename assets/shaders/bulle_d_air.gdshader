shader_type spatial;
render_mode cull_disabled, blend_mix;

uniform vec4 bubble_color : source_color = vec4(0.7, 0.9, 1.0, 0.2);
uniform float water_base_y = 0.0;

// Paramètres synchronisés avec votre shader d'eau
uniform sampler2D wave : hint_default_black;
uniform float wave_time = 0.0;
uniform float noise_scale = 10.0;
uniform float height_scale = 0.15;
uniform float wave_speed = 2.0;

// --- NOUVEAUX PARAMÈTRES POUR LA ZONE SÈCHE ---
uniform mat4 dry_zone_inverse_matrix;
uniform vec3 dry_zone_half_size = vec3(0.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// --- 1. SÉCURITÉ : DISPARITION COMPLÈTE SI DANS LA ZONE SÈCHE ---
	if (dry_zone_half_size.x > 0.0 && dry_zone_half_size.y > 0.0 && dry_zone_half_size.z > 0.0) {
		// On utilise la matrice inverse, exactement comme le shader de l'eau !
		vec3 local_pos = (dry_zone_inverse_matrix * vec4(world_pos, 1.0)).xyz;
		if (abs(local_pos.x) < dry_zone_half_size.x &&
		    abs(local_pos.y) < dry_zone_half_size.y &&
		    abs(local_pos.z) < dry_zone_half_size.z) {
			discard; // La bulle est dans la base -> Invisibilité immédiate !
		}
	}

	// --- 2. CALCUL DE LA HAUTEUR DE LA VAGUE À LA POSITION DE LA BULLE ---
	float h1 = texture(wave, world_pos.xz / noise_scale + wave_time * wave_speed).r;
	float h2 = texture(wave, world_pos.xz / (noise_scale * 0.4) + wave_time * (wave_speed * 1.5)).r;
	float current_wave_height = (h1 * 0.7) + (h2 * 0.3);
	
	// Hauteur limite de l'eau à cet endroit précis du monde
	float exact_water_y = water_base_y + (current_wave_height * height_scale);

	// --- SÉCURITÉ : DISPARITION SI AU-DESSUS DE L'EAU ---
	if (world_pos.y > exact_water_y) {
		discard; 
	}

	// --- LOOK VISUEL DE LA BULLE (Effet de verre / Fresnel) ---
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	
	// Les bords de la bulle sont plus clairs et opaques que le centre
	ALBEDO = mix(bubble_color.rgb, vec3(1.0), fresnel * 0.6);
	ALPHA = mix(bubble_color.a, 0.8, fresnel);
	
	ROUGHNESS = 0.05;
	METALLIC = 0.1;
}