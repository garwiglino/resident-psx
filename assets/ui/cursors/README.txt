CURSEURS ET VISEE

Source active : Tabler Icons, Pawel Kuna, licence MIT.
https://github.com/tabler/tabler-icons
Licence originale conservee dans thin/LICENSE-Tabler.txt.
Usage commercial et modifications autorises ; conserver cette licence.

SVG de la collection outline, sous-dossier thin :
pointer.svg    = pointer, 14x14, trait source 1.7
hand_point.svg = hand-finger, 16x16, trait source 1.5
hand_open.svg  = hand-stop, 16x16, trait source 1.5
hand_grab.svg  = hand-grab, 16x16, trait source 1.5
blocked.svg    = ban, 14x14, trait source 1.7
aim.svg        = crosshair, 12x12, trait source 2
hit.svg        = x, 10x10, trait source 2.4
Chemins SVG originaux conserves ; couleur de trait blanche pour la teinte en jeu.

La couleur est appliquee en jeu, avec une ombre sombre d'un pixel.
Le pointeur, les mains et la visee sont dessines a la resolution native 320x240,
avec filtrage au plus proche, sans mipmaps ni interpolation des positions.
Le lissage alpha des SVG est retire une seule fois au chargement : les pixels
des contours sont opaques ou transparents, puis la teinte et le fondu s'appliquent.
Le curseur systeme est masque dans la fenetre de jeu et restaure a sa fermeture.

Reglages communs : assets/ui/cursors/default_cursors.tres.
Sur la racine SessionJeu : Curseurs et visee > Cursor Style.
Les points actifs servent a aligner la pointe ou le centre sur le vrai clic.
Les couleurs et images peuvent etre changees dans cette ressource.
