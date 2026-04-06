import { LightningElement } from 'lwc';

export default class LoginHeroBanner extends LightningElement {
    features = [
        {
            id: '1',
            title: "Appels d'offres",
            desc: "Consultez et répondez aux appels d'offres en temps réel",
            icon: 'utility:description'
        },
        {
            id: '2',
            title: 'Gestion simplifiée',
            desc: 'Gérez vos documents et contrats en un seul endroit',
            icon: 'utility:groups'
        },
        {
            id: '3',
            title: 'Suivi en direct',
            desc: "Suivez l'avancement de vos demandes instantanément",
            icon: 'utility:graph'
        }
    ];
    handleBecomeSupplier() {
        window.location.assign('/portal/devenir-fournisseur');
    }
}