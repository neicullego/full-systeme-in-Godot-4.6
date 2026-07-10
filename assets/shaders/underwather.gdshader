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

    // ── 1. L'EFFET SPLINE (LISSAGE HORIZONTAL) ──
    // On échantillonne 3 points (gauche, centre, droite) pour créer une courbe douce
    float blur = 0.006; // Écart entre les points échantillonnés
    float h_left   = texture(waterline_texture, vec2(uv.x - blur, 0.5)).r;
    float h_center = texture(waterline_texture, vec2(uv.x, 0.5)).r;
    float h_right  = texture(waterline_texture, vec2(uv.x + blur, 0.5)).r;
    
    // Moyenne pondérée (Le centre a plus de poids) pour créer la courbure
    float dynamic_waterline = (h_left + h_center * 2.0 + h_right) / 4.0;

    // ── 2. GESTION DES MASQUES ──
    float blend;
    float spline_mask = 0.0;

    if (dynamic_waterline <= 0.0) {
        blend = 1.0; // 100% sous l'eau
    } else if (dynamic_waterline >= 1.0) {
        blend = 0.0; // 100% dans l'air
    } else {
        // Calcul du fondu principal entre air et eau
        blend = smoothstep(
            dynamic_waterline - waterline_softness,
            dynamic_waterline + waterline_softness,
            uv.y
        );
        
        // CALCUL DE LA SPLINE : On mesure la distance entre le pixel actuel et la ligne
        float distance_to_line = abs(uv.y - dynamic_waterline);
        
        // On crée une ligne épaisse, centrée exactement sur la démarcation
        spline_mask = 1.0 - smoothstep(0.0, meniscus_thickness, distance_to_line);
    }

    // ── 3. ZONE UNDERWATER ──
    vec2 distorted_uv = uv;
    // On annule la distorsion tout près de la surface pour ne pas "déchirer" la spline
    float depth_from_surface = max(0.0, uv.y - dynamic_waterline);
    distorted_uv.x += sin(uv.y * 0.05 + time * 0.1) * distortion_strength * smoothstep(0.0, 0.05, depth_from_surface);
    
    vec4 underwater_color = texture(screen_texture, distorted_uv);

    // Absorption de la lumière sous l'eau
    float depth_factor = exp(-uv.y * light_absorption_strength);
    underwater_color.rgb *= depth_factor;
    underwater_color = mix(underwater_color, water_color, water_color.a);

    // ── 4. ZONE AIR ──
    vec4 air_color = texture(screen_texture, uv);

    // ── 5. MIX FINAL ──
    // On assemble l'air et l'eau...
    vec4 final_color = mix(air_color, underwater_color, blend);

    // ... ET LA MAGIE OPÈRE ICI : 
    // On plaque la spline du ménisque PAR-DESSUS l'assemblage pour sceller la coupure !
    final_color.rgb = mix(final_color.rgb, meniscus_color, spline_mask * meniscus_opacity);

    COLOR = final_color;
}