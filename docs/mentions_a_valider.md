# Mentions à faire valider par le patron

L'app rédige des devis. Elle ne donne **pas de conseil juridique**. Tout ce qui suit est écrit dans les devis (ou en est absent) et doit être relu et validé par le patron, si besoin avec son comptable ou son assureur. Quand une formulation est validée, coche-la et dis-le : on mettra le texte définitif dans le moteur de rendu (`server/app/render_docx.py`) ou dans le profil de l'entreprise (`server/data/companies.json`).

## Phrases écrites dans chaque devis

- [ ] **Prix, version complète** : « Le prix forfaitaire total pour la fourniture, la main-d'œuvre et les prestations complètes, est de X € TTC (TVA à 10 %). »
- [ ] **Prix, main-d'œuvre seule** : « Le prix forfaitaire total pour la main-d'œuvre est de X € TTC (TVA à 10 %). Les fournitures restent à la charge du client. »
  À vérifier : qui achète quoi, qui est responsable des fournitures, et l'effet sur la garantie décennale quand le client fournit le matériel.
- [ ] **Validité** : « Devis valable 30 jours. » (30 jours par défaut, modifiable devis par devis.)
- [ ] **Durée et démarrage** : « Durée des travaux : … » / « Délai de démarrage : … » (texte libre).
- [ ] **Introduction** : « Nous avons le plaisir de vous présenter notre devis… »
- [ ] **Signatures** (en option) : « Signature entreprise : » / « Signature client (bon pour accord) : ». Faut-il ajouter « Date » et la mention manuscrite « Bon pour accord » ?
- [ ] **Bandeau** « BROUILLON — informations à compléter » ou « profil entreprise incomplet ou factice » : il s'affiche tant que le SIRET ou l'assurance sont vides ou factices.

## Mentions légales d'un devis (à vérifier)

- [ ] **Identification de l'entreprise** (en pied de page, depuis `companies.json`) :
  - nom, forme juridique, SIRET, code NAF, adresse, e-mail, téléphone ;
  - selon le cas : capital social, RCS ou Répertoire des métiers, numéro de TVA intracommunautaire ;
  - faut-il les ajouter au profil ?
- [ ] **Assurance décennale** : nom de l'assureur, numéro de contrat, **zone géographique couverte**, et surtout **les corps d'état couverts** (peinture, électricité, véranda, ravalement, isolation…). Un devis pour un corps d'état non couvert ne devrait pas partir.
- [ ] **Détail des prestations** : les devis sont **forfaitaires** (des lots avec puces, sans prix ligne par ligne). Certaines situations exigent un décompte détaillé en quantités et en prix. À vérifier.
- [ ] **Date du devis, nom et adresse du client, adresse du chantier** : présents, et signalés en jaune s'ils manquent.
- [ ] **Taux de TVA** : l'IA propose 10 % (logement de plus de 2 ans), 20 % (local commercial, neuf) et 5,5 % (rénovation énergétique uniquement). Le taux réduit est soumis à une **attestation du client** : faut-il une mention dans le devis, et qui fournit le formulaire ?
- [ ] **Conditions de paiement et acompte** : échéancier en option (ex. acompte 2 500 € + solde 2 000 €). Montant ou pourcentage d'acompte habituel ? Pénalités de retard, indemnité forfaitaire de recouvrement (clients professionnels) ?
- [ ] **Droit de rétractation** (14 jours) quand le contrat est signé hors de l'entreprise (au domicile du client) ou à distance : faut-il la mention et le formulaire ?
- [ ] **Médiateur de la consommation** (clients particuliers) : nom et coordonnées du médiateur à indiquer ?
- [ ] **Normes citées** : l'IA ne cite un DTU ou la NF C 15-100 que si c'est clairement applicable. Les citations à garder ou à interdire sont à valider.

## Cohérence entre les entreprises

- [ ] **SIRET** : un écart a été repéré entre deux entités par le passé. Vérifier chaque SIRET sur l'annuaire officiel des entreprises avant de remplir `companies.json`.
- [ ] **Numérotation** : un compteur par entreprise au format `NN/AA` (ex. `26/26`). Des doublons ont existé par le passé ; l'app avertit désormais. Choisir le prochain numéro de chaque entreprise dans les Réglages de l'app.
- [ ] Quelle entreprise pour quel type de chantier (LEVIX, SAR BAT, SB CONCEPT, M BAT, ID BAT) ?

## Message au client

- [ ] Ton du message proposé (vouvoiement, court, sans pression commerciale) : à relire sur quelques exemples réels.
