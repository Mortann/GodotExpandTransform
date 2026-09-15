# Recette manuelle — Blender Controls 3D

Cette liste décrit les résultats à vérifier, pas des tests déjà exécutés. Tester sur une copie de `demo.tscn`, dans la version exacte de Godot utilisée au quotidien.

## Environnement

- Version Godot et identifiant de compilation :
- Système et affichage :
- Disposition du clavier : AZERTY / QWERTY / autre :
- Échelle de l’éditeur :
- Date et personne ayant testé :
- Résultat global / anomalies :

Après chaque opération, contrôler les valeurs de l’inspecteur. Entre deux cas indépendants, annuler ou recharger la scène de démonstration sans conserver les changements.

## Installation et prise en main

- [ ] Importer le projet de démo : aucune erreur de script ; la barre de l’extension apparaît dans la vue 3D.
- [ ] Installer uniquement `addons/blender_controls` dans un projet vierge et activer le plugin.
- [ ] Désactiver puis réactiver plusieurs fois : une seule barre, sans messages d’erreur.
- [ ] Le bouton d’activation arrête puis rétablit les commandes ; le sélecteur Global/Local et l’aide fonctionnent.
- [ ] Lancer la démo : caméra, éclairage et trois blocs visibles. G/R/S ne contrôlent pas le jeu lancé.

## Transformations et contraintes

- [ ] Sur `Cube_Corail`, `G X 2 Entrée` ajoute 2 à X sans changer Y/Z.
- [ ] `G Y -0,5 Entrée` soustrait 0,5 à Y ; refaire avec `-0.5` donne le même résultat.
- [ ] `R Y 90 Entrée` tourne de 90° autour de l’axe global Y.
- [ ] `S 2 Entrée` double les trois dimensions. `S X 1/2 Entrée` ne réduit que X.
- [ ] Souris : G déplace, R tourne et S redimensionne sans saut à l’entrée du mode.
- [ ] `G X X X` passe global → local → libre. Refaire depuis l’orientation de départ Local : local → global → libre.
- [ ] Sur `Bloc_Turquoise`, vérifier la différence visible entre X global et X local.
- [ ] `G Maj Y` déplace uniquement dans le plan XZ. Refaire Maj X et Maj Z, puis répéter la touche pour tester les orientations.
- [ ] `S Maj Z` conserve la dimension Z selon le repère actif.
- [ ] `R Maj Y` a le même axe que `R Y`.
- [ ] Une nouvelle lettre d’axe remplace proprement la contrainte précédente.
- [ ] Maintenir Ctrl : incréments 1 unité / 5° / facteur 0,1. Relâcher : retour fluide.
- [ ] Maintenir puis relâcher Maj pendant un mouvement : sensibilité réduite, sans saut de transformation.
- [ ] Vérifier Ctrl+Maj et que les touches Maj+axe restent interprétées comme un choix de plan.

## Saisie numérique

- [ ] Tester chiffres de la rangée supérieure et du pavé numérique, moins, point et virgule.
- [ ] Sur AZERTY, saisir des nombres avec Maj ; vérifier que G, R, S, X, Y, Z correspondent aux lettres attendues.
- [ ] `S 1/2 Entrée` vaut 0,5 ; corriger avec Retour arrière et vérifier l’aperçu.
- [ ] Entrées incomplètes (`-`, `1/`) et division par zéro ne produisent ni erreur ni transformation infinie.
- [ ] Une valeur négative en échelle donne le résultat prévu ou un refus explicite ; aucune matrice invalide.
- [ ] Valeur zéro en échelle : traitement explicite et aucune erreur lors des opérations suivantes.
- [ ] Après saisie numérique, changer d’axe conserve une valeur cohérente.
- [ ] Échap depuis une saisie restaure exactement la transformation initiale.

## Accrochage B

- [ ] `G B` ramène les objets à leur pose initiale pendant le choix de base.
- [ ] Choisir un sommet du cube corail par clic, viser un sommet du bloc turquoise, cliquer : les sommets coïncident sans contrainte.
- [ ] Refaire avec une base sur une arête, puis une face. Le marqueur permet de comprendre la géométrie retenue.
- [ ] Choisir une base sur une autre géométrie statique : le décalage de référence reste cohérent.
- [ ] Les objets déplacés et leurs descendants ne s’accrochent pas à eux-mêmes.
- [ ] Un clic dans le vide ne choisit pas arbitrairement une base ou une cible.
- [ ] `G X B` : seule X varie ; la cible hors axe est projetée. `G Maj Y B` : Y reste identique.
- [ ] `R Y B` et `S B` conservent le pivot moyen des origines ; la base ne devient pas le pivot.
- [ ] Refaire B pour changer la base pendant la même opération et vérifier le retour à une référence stable.
- [ ] Échap/clic droit avant choix de base, après choix et après visée restaurent la pose initiale.
- [ ] Vérifier les points près du bord de la vue, derrière la caméra et sur des faces occultées ; aucun marqueur trompeur ou erreur.
- [ ] Au repos, B garde le comportement natif Godot ; il ne lance pas le sélecteur de base de l’extension.

## Plusieurs objets et hiérarchie

- [ ] Sélectionner les blocs corail et turquoise : G les déplace du même vecteur ; R/S utilisent leur pivot moyen.
- [ ] Changer l’ordre de sélection puis essayer un axe local : le repère de référence reste compréhensible.
- [ ] Transformer `Enfant_Dore` seul sous son parent tourné et à échelle non uniforme ; contrôler le résultat global et l’annulation.
- [ ] Sélectionner parent et enfant : le mouvement n’est appliqué qu’une fois à l’enfant.
- [ ] Sélectionner un nœud verrouillé : pas de modification non voulue. Essayer une sélection mixte verrouillée/non verrouillée.
- [ ] Sélection vide, nœud non 3D ou objet supprimé : aucune erreur.
- [ ] Tester un objet importé/instance de scène et les règles d’édition de Godot.

## Historique et cycle de vie

- [ ] Une opération avec beaucoup de mouvements de souris crée une seule entrée Annuler.
- [ ] Annuler puis Rétablir rend exactement les valeurs confirmées, en sélection simple et multiple.
- [ ] Échap et clic droit ne créent pas d’entrée fantôme dans l’historique.
- [ ] Changer de scène pendant G, R, S ou le choix B restaure les objets ; aucune opération ne se prolonge dans l’autre scène.
- [ ] Changer d’application pendant une opération : annulation propre au retour.
- [ ] Désactiver le bouton ou le plugin pendant l’opération : restauration des objets et disparition des indications.
- [ ] Sauvegarder pendant une opération : l’aperçu temporaire n’est pas enregistré comme résultat confirmé.
- [ ] Fermer la scène ou le projet pendant l’opération : aucune erreur de référence après fermeture.

## Focus, navigation et affichage

- [ ] Taper « grsxyzb » dans un nom de nœud, un champ de texte d’inspecteur, une recherche et l’éditeur de script : aucune transformation.
- [ ] En 2D, G/R/S/B gardent leur usage de l’éditeur ; aucun affichage 3D de l’extension.
- [ ] Navigation habituelle de caméra au repos : clic droit, déplacement, rotation et zoom inchangés.
- [ ] Vues perspective et orthographique : déplacement, axes et B cohérents avec la projection.
- [ ] Configurations 2 et 4 vues : seule la vue qui reçoit l’opération pilote la transformation et affiche les indications au bon endroit.
- [ ] Changer la taille de la vue et l’échelle de l’éditeur (100 %, 150 %, 200 %) : texte lisible et détection B alignée avec la souris.
- [ ] Menus, fenêtres modales et barres d’outils ne déclenchent pas de transformation cachée.
- [ ] Quitter la vue avec la souris pendant une opération : comportement stable, possibilité d’annuler, aucun état bloqué.

## Limites à caractériser

- [ ] Essayer un maillage dense : noter le nombre de triangles et la fluidité du choix de base et des cibles.
- [ ] CSG, MultiMesh et maillages animés/déformés ne sont pas considérés validés par les tests de géométrie statique.
- [ ] Noter tout écart à Blender observé avec une séquence courte, la scène, les valeurs avant/après et une capture si utile.
