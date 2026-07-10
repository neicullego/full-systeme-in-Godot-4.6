shader_type spatial;

// On retire billboard_keep_scale d'ici
render_mode unshaded, depth_test_disabled, cull_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.0, 0.9, 0.4, 1.0); // Couleur du cercle
uniform float inner_radius : hint_range(0.0, 0.5) = 0.35;
uniform float outer_radius : hint_range(0.0, 0.5) = 0.45;

// C'est ici que la magie opère pour remplacer le Billboard
void vertex() {
	// Oriente l'objet face à la caméra
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	
	// Conserve l'échelle (scale) que vous avez définie dans la scène
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), 
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), 
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), 
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    // Centre les coordonnées UV au milieu (-0.5 à 0.5)
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    
    // Découpe l'anneau (vide au centre et à l'extérieur)
    if (dist < inner_radius || dist > outer_radius) {
        discard;
    }
    
    // Calcul de l'angle (0 en haut, progresse dans le sens horaire)
    float angle = atan(uv.x, -uv.y); 
    float angle_normalized = (angle + PI) / (2.0 * PI);
    
    // Masque les fragments qui dépassent la progression actuelle
    if (angle_normalized > progress) {
        discard;
    }
    
    ALBEDO = color.rgb;
    ALPHA = color.a;
}