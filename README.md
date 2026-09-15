# Blender Controls 3D pour Godot

Une extension d’éditeur pour manipuler les objets 3D avec les gestes de Blender : **G / R / S**, contraintes d’axes ou de plans, valeurs numériques et **B pendant une transformation pour choisir une base d’accrochage**.

Version ciblée : **Godot 4.7.2 stable**, éditeur 3D uniquement. Cette extension agit dans l’éditeur ; lancer la démo affiche la scène, sans ajouter ces commandes au jeu.

Version de l’extension : **0.1.0**. Les scripts, le projet de démo et les tests sont fournis sous licence MIT.

## Installation

### Dans ton projet

1. Décompresse l’archive.
2. Copie le dossier `addons/blender_controls` à la racine de ton projet. Tu dois obtenir `res://addons/blender_controls/plugin.cfg`.
3. Ouvre **Projet → Paramètres du projet → Extensions / Plugins**.
4. Active **Blender Controls 3D**.
5. Dans la vue 3D, vérifie que le bouton de l’extension est activé, sélectionne un objet, puis place la souris dans cette vue et appuie sur `G`.

La barre de l’extension permet d’activer les commandes, de choisir l’orientation de départ **Global / Local** et d’afficher l’aide.

### Essayer le projet fourni

Décompresse l’archive complète, importe son `project.godot` depuis le gestionnaire de projets Godot et ouvre `demo.tscn`. L’extension y est déjà déclarée comme activée.

La scène contient `Cube_Corail`, `Bloc_Turquoise` et `Parent_Tourne_Echelle_Non_Uniforme/Enfant_Dore`. Le troisième objet permet d’essayer les transformations sous un parent tourné avec une échelle différente sur chaque axe. Sélectionne un bloc depuis l’arbre de scène pour le retrouver facilement. Le sol et les éléments de présentation sont verrouillés.

## Commandes

Les touches sont des **étapes successives** : `G`, puis `X`, puis `2`, puis `Entrée`.

| Commande | Effet |
|---|---|
| `G` | Déplacer la sélection. |
| `R` | Tourner la sélection. |
| `S` | Redimensionner la sélection. |
| `X`, `Y`, `Z` | Contraindre à un axe. Répéter la même touche passe à l’autre orientation, puis libère la contrainte. |
| `Maj + X/Y/Z` | Pour G/S : agir dans le plan qui exclut cet axe. Pour R : tourner autour de cet axe. |
| Chiffres, `-`, `.` ou `,`, `/` | Saisir une valeur numérique ; les fractions simples sont acceptées. |
| `Retour arrière` | Corriger la saisie numérique. |
| `Ctrl` maintenu | Incréments : 1 unité en déplacement, 5° en rotation, 0,1 en échelle. |
| `Maj` maintenu | Réduire la sensibilité de la souris pour un réglage précis. |
| `B` pendant G/R/S | Choisir une nouvelle base d’accrochage. |
| `Entrée`, `Espace` ou clic gauche | Confirmer ; pendant le choix de base, le clic choisit d’abord la base. |
| `Échap` ou clic droit | Annuler et retrouver les transformations initiales. |

Avec **Global** comme orientation de départ : `G X` utilise X global, `G X X` utilise X local, `G X X X` retire la contrainte. Avec **Local**, l’ordre des deux orientations est inversé.

Les axes conservent la convention de Godot : **Y est vertical**. Ainsi `G Maj Y` permet de déplacer au sol dans le plan XZ. `G Maj Z` utilise le plan XY.

### Valeurs numériques

Les valeurs s’appliquent **par rapport au début de l’opération** : déplacement en unités de scène, rotation en degrés et échelle par facteur multiplicatif.

| Séquence | Résultat |
|---|---|
| `G X 2 Entrée` | Avance de 2 unités sur X. |
| `G Y -0,5 Entrée` | Descend de 0,5 unité sur Y. |
| `R Y 90 Entrée` | Tourne de 90° autour de Y. |
| `S 2 Entrée` | Double la taille. |
| `S X 1/2 Entrée` | Divise par deux la taille sur X. |

Pour un déplacement numérique prévisible, choisis un axe. Une fraction doit avoir un dénominateur non nul. Les expressions complètes, les suffixes d’unité et la saisie de plusieurs composantes avec `Tab` ne font pas partie de cette version.

### Accrocher avec B

1. Sélectionne `Cube_Corail` et commence une transformation avec `G`.
2. Appuie sur `B`. La sélection revient temporairement à sa transformation initiale pour choisir une référence stable.
3. Vise un sommet, une arête ou une face d’un maillage, puis clique pour définir le **point de départ** de l’accrochage.
4. Vise un point d’un autre objet. La prévisualisation suit la cible détectée.
5. Clique pour confirmer, ou appuie sur `Échap` pour annuler toute l’opération.

Le choix de base peut utiliser la géométrie statique de la scène. Les cibles excluent les objets transformés et leurs descendants, afin d’éviter l’accrochage sur la géométrie en mouvement.

Une fois la base choisie, l’accrochage est actif automatiquement ; **Ctrl le suspend temporairement**. `B` permet de choisir une nouvelle base. Les points détectés sont prioritaires dans cet ordre : sommet à proximité du curseur, arête à proximité, puis face sous le curseur. Les objets masqués sont ignorés ; les objets verrouillés peuvent servir de références sans être modifiés.

Une contrainte reste prioritaire : avec `G X B`, la cible est projetée sur X et n’est atteinte exactement que si elle est compatible avec cet axe. Le même principe s’applique à un plan. Avec `R B` ou `S B`, la rotation ou l’échelle peut aligner la référence vers la cible, mais ne peut pas toujours superposer les deux points si leur position est incompatible avec cette opération.

**La base d’accrochage n’est pas le pivot.** Rotation et échelle utilisent le centre moyen des origines des objets transformés. Pour plusieurs objets, les axes locaux utilisent le repère d’un objet de référence de la sélection. Consulte l’indication affichée dans la vue avant de valider.

Au repos, `B` conserve son comportement natif dans Godot, dont l’accrochage aux sommets. La sélection par rectangle de Blender n’est pas ajoutée : le `B` demandé ici correspond au choix de base **pendant** G/R/S.

## Annulation et intégration à l’éditeur

Une opération confirmée crée une seule action dans l’historique Godot, même pour plusieurs objets. **Annuler / Rétablir** reste disponible avec les commandes habituelles de l’éditeur.

Une opération en cours est annulée lors d’un changement de scène, d’une perte de focus de la fenêtre, d’une désactivation de l’extension ou d’une sauvegarde. Un clic hors de la vue annule aussi l’opération. Les champs de texte de l’inspecteur et l’éditeur de script conservent leurs touches habituelles. Les raccourcis globaux de Godot ne sont pas modifiés.

## Périmètre et limites

- Manipulation de nœuds `Node3D` ; les parents et enfants sélectionnés ensemble ne doivent pas subir deux fois la transformation.
- Accrochage sur la géométrie des `MeshInstance3D` statiques : sommets, arêtes et faces.
- Pas d’édition des sommets, faces ou topologie d’un maillage, ni de mode 2D.
- Pas de reproduction complète des modes de pivot, orientations, modificateurs ou outils de Blender.
- La rotation trackball `R R`, le choix d’axe au clic milieu et la navigation de caméra pendant une opération ne sont pas ajoutés. Annule ou confirme avant de naviguer. Passer de G à R/S pendant une opération repart de sa pose initiale.
- Pas d’accrochage garanti sur CSG, MultiMesh ou sur la géométrie déformée par squelette, blend shapes ou shaders.
- Les arêtes sont celles des triangles du maillage : les diagonales de triangulation peuvent donc être détectées.
- Une référence au pivot ou perpendiculaire à la cible ne définit pas toujours un accrochage d’échelle : choisis une base décalée du pivot. L’accrochage S utilise un rapport positif comme Blender ; pour un miroir, saisis un facteur négatif.
- Les facteurs d’échelle de valeur absolue inférieure à `0,000001` sont refusés explicitement pour éviter une transformation singulière.
- Vu exactement de face, un axe de déplacement ne peut pas être déterminé à la souris : utilise une valeur numérique ou change la vue.
- La géométrie est mise en cache au choix de la base, sans plafond caché de triangles. Les très grandes scènes peuvent occasionner une pause lors de cette préparation. Les déformations exécutées en continu par un script `@tool` ne sont pas suivies pendant l’opération.

## Vérification

**144 vérifications automatisées réussies sur Godot 4.7.2**, dont 69 dans l’éditeur réel avec événements clavier et souris. Le [rapport de validation](docs/VALIDATION.md) détaille les résultats et leur portée.

Pour reproduire les tests avec Python 3 et le binaire Godot :

```bash
python3 tests/run_tests.py --godot /chemin/vers/godot
```

Sur Linux avec un affichage X11 disponible, ajouter `--gui` teste aussi l’éditeur graphique. Le lanceur travaille sur une copie temporaire du projet.

La procédure de vérification interactive et les cas supplémentaires sont dans [docs/TESTS_MANUELS.md](docs/TESTS_MANUELS.md). Ses cases restent vides : elles servent à la recette dans ton environnement, et ne représentent pas des tests manuels déjà exécutés.

## Références

Les contraintes et le cycle d’orientation suivent le fonctionnement documenté dans le [manuel Blender — Axis Locking](https://docs.blender.org/manual/en/5.2/scene_layout/object/editing/transform/control/axis_locking.html). Le choix de référence avec `B` est décrit dans le [manuel Blender — Transform Modal Map, Set Snap Base](https://docs.blender.org/manual/en/latest/modeling/transform/modal_map.html).

L’installation suit la structure `addons` documentée par [Godot — Making plugins](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/making_plugins.html).

Le calcul d’accrochage de S suit la projection décrite par `ResizeBetween` dans le [code officiel de Blender 4.5](https://github.com/blender/blender/blob/v4.5.0/source/blender/editors/transform/transform_mode_resize.cc).

## Licence

[MIT](LICENSE). Projet indépendant ; aucune affiliation à Blender ou à Godot.
