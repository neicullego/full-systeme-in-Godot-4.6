shader_type canvas_item;

// Propriétés modifiables dans l'inspecteur ou via script
uniform vec4 vignette_color : source_color = vec4(0.8, 0.0, 0.0, 1.0); // Rouge sang
uniform float intensity : hint_range(0.0, 5.0) = 1.5;
uniform float opacity : hint_range(0.0, 1.0) = 0.0; // Géré par le script (0 = invisible)

void fragment() {
    // Centre les coordonnées UV pour calculer la distance depuis le centre
    vec2 uv = UV - 0.5;
    
    // Calcule la distance par rapport au centre de l'écran
    float dist = length(uv);
    
    // Crée le dégradé (vignette) : transparent au centre, opaque sur les bords
    float vignette = smoothstep(0.2, 0.6, dist * intensity);
    
    // Applique la couleur et l'opacité globale
    vec4 final_color = vignette_color;
    final_color.a = vignette * opacity;
    
    COLOR = final_color;
}