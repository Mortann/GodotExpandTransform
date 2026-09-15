# Validation — version 0.1.0

Date : 15 septembre 2026.

Moteur exécuté : **Godot 4.7.2.stable.official.ed1daf0bf**, Linux x86_64. Éditeur graphique X11, rendu OpenGL Compatibility. Le même exécutable sert aux scripts de test sans affichage.

## Résultats

| Suite | Vérifications | Échecs |
|---|---:|---:|
| Calculs de transformation | 47 | 0 |
| Détection géométrique de l’accrochage | 28 | 0 |
| Intégration dans l’éditeur | 69 | 0 |
| **Total** | **144** | **0** |

Les vérifications sont des assertions automatisées. Ce nombre ne représente pas 144 scénarios manuels distincts.

### Calculs

Contraintes d’axes et de plans en global/local, composition autour d’un pivot commun, échelles non uniformes, miroirs, parents transformés, rotation d’accrochage signée, calcul d’accrochage d’échelle conforme à la formule de Blender, cas dégénérés et projections perspective/orthographique.

### Accrochage

Détection exacte des sommets, arêtes et faces, interpolation des arêtes en perspective, occultation par une surface au premier plan, masques de visibilité de caméra, objets masqués, références verrouillées, exclusion des sous-arbres déplacés, références supprimées, découpage aux limites de la vue, cache complet d’un maillage de 16 640 triangles.

Le test de densité est un contrôle local limité, pas un benchmark de scènes de production. Les coûts de préparation augmentent avec la géométrie totale.

### Éditeur

Chargement de l’extension, G/X/valeur/Entrée, plans, cycle global/local/libre, saisie négative avec virgule et fractions, refus d’entrées invalides, undo/redo natif, undo de groupe, filtre parent/enfant, rotation sous parent non uniformément redimensionné, annulation à la sélection, à la sauvegarde, à la perte de focus et à la désactivation du bouton ; sélection vide ou verrouillée.

Le parcours **G → B → déplacer la souris → clic sur la base → déplacer vers la cible → clic → Annuler** est exécuté avec des événements `Input.parse_input_event` dans l’éditeur réel. Les tests vérifient la coïncidence du point source transformé avec la cible, l’absence d’interférence du B natif et le retour exact à la transformation initiale. G/R/S sont également envoyés au vrai contrôle de la vue ; un champ texte conserve sa saisie de G.

Une capture de l’éditeur durant l’accrochage a été inspectée visuellement : aide lisible, séparée du menu Perspective, valeur de déplacement et cible affichées.

## Limites de cette validation

Le clavier AZERTY physique, Windows/macOS, plusieurs écrans avec facteurs d’échelle différents, toutes les configurations de vues multiples et les interactions avec d’autres extensions ne sont pas validés ici. Le guide de recette manuelle décrit ces contrôles complémentaires. L’extension reste limitée aux objets 3D et à la géométrie statique des MeshInstance3D pour l’accrochage.

## Reproduction

Depuis la racine du projet, avec Python 3 :

```bash
python3 tests/run_tests.py --godot /chemin/vers/godot
# Linux/X11 : éditeur graphique
python3 tests/run_tests.py --godot /chemin/vers/godot --gui
```

Le projet est copié dans un dossier temporaire. Le plugin de test n’est activé que dans cette copie ; il n’est pas actif dans la démo livrée.
