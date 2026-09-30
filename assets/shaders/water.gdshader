shader_type spatial;

// 'cull_disabled' permet de voir le mesh des deux côtés
render_mode depth_draw_always, cull_disabled;

// ── MODIFICATION : Gestion de plusieurs zones sèches (Maximum 10) ──
uniform int dry_types[10];
uniform int dry_zone_count = 0;
uniform mat4 dry_matrices[10];
uniform vec3 dry_sizes[10];

uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE: hint_depth_texture, filter_linear_mipmap;

uniform vec3 albedo : source_color;
uniform vec3 albedo2 : source_color;
uniform vec4 color_deep : source_color;
uniform vec4 color_shallow : source_color;

uniform float metallic : hint_range(0.0, 1.0) = 0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;

uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;
uniform sampler2D wave;

uniform float wave_time = 0;
uniform vec2 wave_direction = vec2(2.0,0.0);
uniform vec2 wave_2_direction = vec2(0.0,1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.005) = 0.025;
uniform float wave_speed = 2.0;
uniform float noise_scale = 10.0;
uniform float height_scale = 0.15;
uniform float beers_law = 2.0;
uniform float depth_offset = -0.75;

varying float height;
varying vec3 world_pos;

uniform float edge_scale = 0.1;
uniform vec3 edge_color : source_color;

// ── PARAMÈTRES : EFFET LUMINEUX DES CRÊTES ──
uniform vec3 crest_color : source_color = vec3(0.4, 0.85, 1.0);
uniform float crest_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float crest_intensity : hint_range(0.0, 5.0) = 1.8;

// ── PARAMÈTRES : TRANSPARENCE SOUS L'EAU ──
uniform float underwater_transparency : hint_range(0.0, 1.0) = 0.25;

// OPTIMISATION : Remplacement de pow() par des multiplications (beaucoup plus rapide)
float fresnel5(vec3 normal, vec3 view) {
	float f = 1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0);
	float f2 = f * f;
	return f2 * f2 * f; // Équivaut à pow(f, 5.0) en beaucoup plus léger
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	float h1 = texture(wave, world_pos.xz / noise_scale + wave_time * wave_speed).r;
	float h2 = texture(wave, world_pos.xz / (noise_scale * 0.4) + wave_time * (wave_speed * 1.5)).r;
	
	height = (h1 * 0.7) + (h2 * 0.3);
	VERTEX.y += height * height_scale;
}

void fragment() {
	// ── OPTIMISATION 1 : DÉCOUPE DES ZONES SÈCHES MULTIPLES ──
	// Placé en TOUT PREMIER pour annuler les calculs lourds si le pixel est vide (Early Discard)
	for (int i = 0; i < dry_zone_count; i++) {
		vec3 extents = dry_sizes[i];
		
		if (extents.x > 0.0) { // Sécurité minimale
			vec3 local_pos = (dry_matrices[i] * vec4(world_pos, 1.0)).xyz;
			int z_type = dry_types[i];
			
			if (z_type == 0) {
				// BOÎTE : abs() vectoriel et vérification simultanée
				vec3 abs_p = abs(local_pos);
				if (abs_p.x < extents.x && abs_p.y < extents.y && abs_p.z < extents.z) {
					discard;
				}
			} 
			else {
				// SPHÈRE & CYLINDRE : Utilisation de dot() plus rapide que les + de divisions isolées
				vec3 norm_p = local_pos / extents; 
				
				if (z_type == 1) {
					if (dot(norm_p, norm_p) < 1.0) discard;
				} 
				else if (z_type == 2) {
					// swizzle .xz pour isoler la base du cylindre
					if (dot(norm_p.xz, norm_p.xz) < 1.0 && abs(local_pos.y) < extents.y) discard;
				}
			}
		}
	}
	
	// Si le pixel a survécu au discard, on fait les calculs lourds...

	// --- 1. CALCUL DE LA PROFONDEUR ---
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	bool is_sky = depth_raw < 0.00001;
	
	float depth_lin = PROJECTION_MATRIX[3][2] / (depth_raw + PROJECTION_MATRIX[2][2]);
	float depth = is_sky ? 50.0 : depth_lin + VERTEX.z; // Regroupé sur une ligne

	float depth_blend = exp((depth + depth_offset) * -beers_law);
	depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);

	// --- 2. COULEURS & RÉFRACTION ---
	vec3 screen_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, depth_blend * 2.5).rgb;
	vec3 depth_color = mix(color_shallow.rgb, color_deep.rgb, depth_blend);
	vec3 water_color = mix(screen_color, depth_color, depth_blend);

	// --- 3. NORMALES ET VAGUES ---
	vec2 time1 = (TIME * wave_direction) * time_scale;
	vec2 time2 = (TIME * wave_2_direction) * time_scale;
	vec3 normal_blend = mix(
		texture(texture_normal, world_pos.xz / noise_scale + time1).rgb, 
		texture(texture_normal2, world_pos.xz / noise_scale + time2).rgb, 
		0.5
	);

	// --- 4. CALCUL DE L'EFFET LUMINEUX ---
	float micro_noise = normal_blend.r * 0.08;
	float crest_factor = clamp((height + micro_noise - crest_threshold) / (1.0 - crest_threshold), 0.0, 1.0);
	crest_factor = crest_factor * crest_factor; // OPTIMISATION : Remplace pow(x, 2.0)
	vec3 crest_glow = crest_color * crest_factor * crest_intensity;

	// --- 5. LOGIQUE DES FACES (REGROUPÉE) ---
	vec3 face_normal = FRONT_FACING ? NORMAL : -NORMAL;
	float fresnel_val = fresnel5(face_normal, VIEW);
	
	vec3 reflection_color = FRONT_FACING 
		? mix(albedo, albedo2, fresnel_val) 
		: mix(albedo2 * 0.2, edge_color * 0.5, fresnel_val);

	// --- 6. ÉCUME ET MÉLANGE ---
	float foam_factor = is_sky ? 1.0 : smoothstep(0.0, edge_scale, depth);
	vec3 refraction_color = mix(edge_color, water_color, foam_factor);
	vec3 combined_color = mix(refraction_color, reflection_color, fresnel_val);
	
	// --- 7. APPLICATION DES VALEURS FINALES ---
	vec3 final_crest = FRONT_FACING ? crest_glow : crest_glow * 1.5;
	ALBEDO = clamp(combined_color + final_crest, vec3(0.0), vec3(1.0));
	
	ALPHA = FRONT_FACING 
		? mix(0.5, 1.0, depth_blend) 
		: mix(underwater_transparency, 0.92, fresnel_val);
	
	METALLIC = metallic;
	ROUGHNESS = roughness;
	NORMAL_MAP = normal_blend;
}