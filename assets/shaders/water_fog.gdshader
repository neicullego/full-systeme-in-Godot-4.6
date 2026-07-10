shader_type fog;

uniform float surface_y = 0.0;       // Hauteur de la surface (transmis par le script)
uniform float max_depth = 30.0;      // Profondeur à laquelle le brouillard est au maximum
uniform float max_density = 0.5;     // Densité maximale dans le fond
uniform float fog_curve = 1.5;       // Courbe de progression (1.0 = linéaire, >1.0 = progressif au début)
uniform vec3 fog_color : source_color = vec3(0.0, 0.1, 0.2);

void fog() {
    // Étape 1 : Calculer la profondeur de ce pixel/voxel de brouillard par rapport à la surface
    float depth = surface_y - WORLD_POSITION.y;
    
    if (depth > 0.0) {
        // Étape 2 : Plus le point 3D est bas, plus le facteur approche de 1.0
        float factor = clamp(depth / max_depth, 0.0, 1.0);
        
        // Application de la courbe pour que ce soit très transparent près de la surface
        factor = pow(factor, fog_curve);
        
        // Étape 3 : Application de la densité et de la couleur physique
        DENSITY = factor * max_density;
        ALBEDO = fog_color;
    } else {
        // Au-dessus de la surface de l'eau, le brouillard est totalement inexistant
        DENSITY = 0.0;
    }
}