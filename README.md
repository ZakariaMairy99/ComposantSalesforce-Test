# SI Achat - Portail Fournisseurs

## Description

Projet Salesforce pour le Portail Fournisseurs avec un composant visuel de page de connexion et une logique metier Apex pour la gestion des appels d offres, soumissions et factures.

## Fonctionnalites principales

### Composant Login Hero Banner

Chemin: [force-app/main/default/lwc/loginHeroBanner](force-app/main/default/lwc/loginHeroBanner)

- Hero "Portail Fournisseurs" avec branding partenaire
- affichage des avantages (appels d offres, gestion, suivi)
- CTA "Consulter les Appels d Offres"
- CTA "Devenir fournisseur"
- animations CSS et rendu responsive

### Classe SupplierPortalController

Chemin: [force-app/main/default/classes/SupplierPortalController.cls](force-app/main/default/classes/SupplierPortalController.cls)

- consultation des appels d offres publics/restreints
- gestion des soumissions fournisseur
- consultation des bons de commande et factures
- gestion des documents (Salesforce Files)
- OCR facture et creation de facture a partir du BC

## Technologies

- Salesforce Platform
- Lightning Web Components (LWC)
- Apex
- Salesforce DX (SFDX)
- JavaScript (ES6)
- CSS3
- OCR.Space API

## Screen

![Login Hero Banner](docs/login-hero-banner-screen.png)

Description du screen:

- bandeau rouge degrade avec grille de fond et elements flottants
- titre principal "Portail Fournisseurs"
- 3 blocs de fonctionnalites avec icones
- boutons d action "Consulter les Appels d Offres" et "Devenir fournisseur"
