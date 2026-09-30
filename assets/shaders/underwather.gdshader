shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 water_color : source_color = vec4(0.0, 0.4, 0.7, 0.5);
uniform float distortion_strength = 0.01;
uniform float time = 0.0;
uniform sampler2D waterline_texture : filter_linear;
uniform float light_absorption_strength = 4.0;

// Douceur de la transition air/eau
uniform float waterline_softness : hint_range(0.001, 0.03) = 0.008;

// ── NOUVEAUX PARAMÈTRES POUR LA SPLINE (MÉNISQUE) ──
uniform float meniscus_thickness : hint_range(0.0, 0.05) = 0.006; // Épaisseur de la ligne
uniform vec3 meniscus_color : source_color = vec3(0.85, 0.95, 1.0); // Couleur de l'écume
uniform float meniscus_opacity : hint_range(0.0, 1.0) = 0.7; // Transparence de la ligne

void fragment() {
    vec2 uv = SCREEN_UV;

    // ── 1. L'EFFET SPLINE ──
    float blur = 0.006;
    float h_left   = texture(waterline_texture, vec2(uv.x - blur, 0.5)).r;
    float h_center = texture(waterline_texture, vec2(uv.x, 0.5)).r;
    float h_right  = texture(waterline_texture, vec2(uv.x + blur, 0.5)).r;
    float dynamic_waterline = (h_left + h_center * 2.0 + h_right) / 4.0;

    // ── 2. GESTION DES MASQUES ──
    float blend;
    float spline_mask = 0.0;

    if (dynamic_waterline <= 0.0) {
        blend = 1.0; 
    } else if (dynamic_waterline >= 1.0) {
        blend = 0.0; 
    } else {
        blend = smoothstep(dynamic_waterline - waterline_softness, dynamic_waterline + waterline_softness, uv.y);
        float distance_to_line = abs(uv.y - dynamic_waterline);
        spline_mask = 1.0 - smoothstep(0.0, meniscus_thickness, distance_to_line);
    }

    // ── 3. OPTIMISATION MASSIVE : MIX DES UVS ──
    vec2 distorted_uv = uv;
    float depth_from_surface = max(0.0, uv.y - dynamic_waterline);
    distorted_uv.x += sin(uv.y * 0.05 + time * 0.1) * distortion_strength * smoothstep(0.0, 0.05, depth_from_surface);
    
    // On mélange les coordonnées UV AVANT de lire la texture (1 seule lecture au lieu de 2 !)
    vec2 final_uv = mix(uv, distorted_uv, blend);
    vec4 final_color = texture(screen_texture, final_uv);

    // ── 4. COULEURS SOUS-MARINES (Seulement si nécessaire) ──
    if (blend > 0.0) {
        float depth_factor = exp(-uv.y * light_absorption_strength);
        vec3 underwater_rgb = final_color.rgb * depth_factor;
        underwater_rgb = mix(underwater_rgb, water_color.rgb, water_color.a);
        
        // On applique la teinte finale selon le blend
        final_color.rgb = mix(final_color.rgb, underwater_rgb, blend);
    }

    // ── 5. LE MÉNISQUE ──
    final_color.rgb = mix(final_color.rgb, meniscus_color, spline_mask * meniscus_opacity);

    COLOR = final_color;
}