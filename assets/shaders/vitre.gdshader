// NOTE: Shader automatically converted from Godot Engine 4.6.stable's StandardMaterial3D.
// MODIFIÉ POUR INCLURE LE POST-PROCESS UNDERWATER

shader_type spatial;
render_mode blend_mul, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// --- PARAMÈTRES DE BASE DU VERRE ---
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform ivec2 albedo_texture_size;
uniform float point_size : hint_range(0.1, 128.0, 0.1);

uniform float roughness : hint_range(0.0, 1.0);
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;

uniform float specular : hint_range(0.0, 1.0, 0.01);
uniform float metallic : hint_range(0.0, 1.0, 0.01);

uniform sampler2D texture_refraction : filter_linear_mipmap, repeat_enable;
uniform float refraction : hint_range(-1.0, 1.0, 0.001);
uniform vec4 refraction_texture_channel;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

// --- NOUVEAUX PARAMÈTRES UNDERWATER (Copiés de votre post-process) ---
uniform sampler2D waterline_texture : filter_linear; // Texture envoyée par la caméra
uniform vec4 water_color : source_color = vec4(0.0, 0.4, 0.7, 0.5);
uniform float light_absorption_strength = 4.0;
uniform float waterline_softness : hint_range(0.001, 0.03) = 0.008;
uniform float meniscus_thickness : hint_range(0.0, 0.05) = 0.006;
uniform vec3 meniscus_color : source_color = vec3(0.85, 0.95, 1.0);
uniform float meniscus_opacity : hint_range(0.0, 1.0) = 0.7;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec2 base_uv = UV;

	vec4 albedo_tex = texture(texture_albedo, base_uv);
	ALBEDO = albedo.rgb * albedo_tex.rgb;

	float metallic_tex = dot(texture(texture_metallic, base_uv), metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	SPECULAR = specular;

	vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;

	// --- 1. Calcul de la Réfraction du Verre ---
	vec3 ref_normal = NORMAL;
	vec2 ref_ofs = SCREEN_UV - ref_normal.xy * dot(texture(texture_refraction, base_uv), refraction_texture_channel) * refraction;
	float ref_amount = 1.0 - albedo.a * albedo_tex.a;

	float refraction_depth_tex = textureLod(depth_texture, ref_ofs, 0.0).r;
	vec4 ndc = OUTPUT_IS_SRGB ? vec4(vec3(SCREEN_UV, refraction_depth_tex) * 2.0 - 1.0, 1.0) : vec4(SCREEN_UV * 2.0 - 1.0, refraction_depth_tex, 1.0);
	vec4 refraction_view_pos = INV_PROJECTION_MATRIX * ndc;
	refraction_view_pos.xyz /= refraction_view_pos.w;

	// Récupération de l'image derrière la vitre (avec distorsion)
	vec2 final_screen_uv = mix(SCREEN_UV, ref_ofs, smoothstep(0.0, 1.0, VERTEX.z - refraction_view_pos.z));
	vec3 background_scene = textureLod(screen_texture, final_screen_uv, ROUGHNESS * 8.0).rgb;

	// --- 2. LOGIQUE UNDERWATER (Découpe de la ligne d'eau) ---
	float blur = 0.006;
	float h_left   = texture(waterline_texture, vec2(SCREEN_UV.x - blur, 0.5)).r;
	float h_center = texture(waterline_texture, vec2(SCREEN_UV.x, 0.5)).r;
	float h_right  = texture(waterline_texture, vec2(SCREEN_UV.x + blur, 0.5)).r;
	float dynamic_waterline = (h_left + h_center * 2.0 + h_right) / 4.0;

	float blend_water;
	float spline_mask = 0.0;
	
	if (dynamic_waterline <= 0.0) {
		blend_water = 1.0;
	} else if (dynamic_waterline >= 1.0) {
		blend_water = 0.0;
	} else {
		blend_water = smoothstep(
			dynamic_waterline - waterline_softness,
			dynamic_waterline + waterline_softness,
			SCREEN_UV.y
		);
		float distance_to_line = abs(SCREEN_UV.y - dynamic_waterline);
		spline_mask = 1.0 - smoothstep(0.0, meniscus_thickness, distance_to_line);
	}

	// --- 3. Appliquer les effets visuels de l'eau ---
	vec3 underwater_scene = background_scene;
	float depth_factor = exp(-SCREEN_UV.y * light_absorption_strength);
	underwater_scene *= depth_factor; // Assombrissement en profondeur
	underwater_scene = mix(underwater_scene, water_color.rgb, water_color.a); // Teinte bleue

	// Assemblage de l'air et de l'eau
	vec3 final_scene = mix(background_scene, underwater_scene, blend_water);
	// Ajout de la ligne d'écume (ménisque)
	final_scene = mix(final_scene, meniscus_color, spline_mask * meniscus_opacity);

	// --- 4. Rendu Final ---
	EMISSION += final_scene * ref_amount * EXPOSURE;
	ALBEDO *= 1.0 - ref_amount;
	ALPHA = 1.0;
}