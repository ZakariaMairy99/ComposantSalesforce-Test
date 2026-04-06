public without sharing class SupplierPortalController {
    
    public class TenderWrapper {
        @AuraEnabled public Appel_Offres__c tenderRecord {get;set;}
        @AuraEnabled public Boolean isSubmitted {get;set;}
        @AuraEnabled public Id submissionId {get;set;}
        @AuraEnabled public String submissionStatus {get;set;}
        @AuraEnabled public DateTime submissionDate {get;set;}

        public TenderWrapper(Appel_Offres__c tender, Boolean submitted, Id subId, String status, DateTime subDate) {
            this.tenderRecord = tender;
            this.isSubmitted = submitted;
            this.submissionId = subId;
            this.submissionStatus = status;
            this.submissionDate = subDate;
        }
    }

    private static Id getEffectiveAccountId() {
        User currentUser = [SELECT Id, AccountId, Contact.AccountId, Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Id finalAccountId = currentUser.Contact.AccountId != null ? currentUser.Contact.AccountId : currentUser.AccountId;
        
        if (finalAccountId == null && currentUser.Profile.Name == 'System Administrator') {
            // Replace random Account query with fixed Account ID for testing
            finalAccountId = '001WS000003zInvYAE';
        }
        return finalAccountId;
    }

    private static List<TenderWrapper> wrapTenders(List<Appel_Offres__c> tenders, Id accountId) {
        List<TenderWrapper> wrappedList = new List<TenderWrapper>();
        if (tenders.isEmpty()) return wrappedList;

        Set<Id> aoIds = (new Map<Id, SObject>(tenders)).keySet();
        Map<Id, Soumission__c> aoToSub = new Map<Id, Soumission__c>();

        if (accountId != null) {
            for (Soumission__c sub : [
                SELECT Id, Appel_Offres__c, Statut__c, CreatedDate 
                FROM Soumission__c 
                WHERE Appel_Offres__c IN :aoIds 
                AND Compte_Fournisseur__c = :accountId
            ]) {
                aoToSub.put(sub.Appel_Offres__c, sub);
            }
        }

        for (Appel_Offres__c t : tenders) {
            Soumission__c s = aoToSub.get(t.Id);
            Boolean isSubmitted = s != null && s.Statut__c == 'Soumis';
            wrappedList.add(new TenderWrapper(t, isSubmitted, s?.Id, s?.Statut__c, s?.CreatedDate));
        }
        return wrappedList;
    }

    @AuraEnabled(cacheable=true)
    public static List<TenderWrapper> getTenders(String searchKey, String filterType, String tenderMode) {
        Id accountId = getEffectiveAccountId();

        String query = 'SELECT Id, Name, Date_Limite_Reponse__c, Status__c, Description__c, ' +
                       'Montant_Caution_Provisoire__c, RecordType.Name, RecordType.DeveloperName, Category__c ' +
                       'FROM Appel_Offres__c ' +
                       'WHERE Status__c = \'Publié\'';

        Set<Id> invitedTenderIds = new Set<Id>();

        // Filter by Tender Mode (Public vs Restricted)
        if (String.isNotBlank(tenderMode)) {
            if (tenderMode == 'Public') {
                query += ' AND RecordType.DeveloperName = \'Appel_d_offres_ouvert\'';
            } else if (tenderMode == 'Restricted') {
                query += ' AND RecordType.DeveloperName = \'Appel_d_offres_restreint\'';
                
                if (accountId != null) {
                    for (Invitation_AO__c inv : [
                        SELECT Appel_d_offres__c 
                        FROM Invitation_AO__c 
                        WHERE Fournisseur__c = :accountId 
                        AND Statut__c = 'Invité'
                    ]) {
                        invitedTenderIds.add(inv.Appel_d_offres__c);
                    }
                }
                query += ' AND Id IN :invitedTenderIds';
            }
        }

        if (String.isNotBlank(searchKey)) {
            String key = '%' + searchKey + '%';
            query += ' AND Name LIKE :key';
        }

        List<Appel_Offres__c> tenders = Database.query(query);

        // Get wrapped tenders with submission info
        List<TenderWrapper> wrappedTenders = wrapTenders(tenders, accountId);

        // Apply filter on wrapped results
        if (filterType == 'submitted') {
            List<TenderWrapper> filtered = new List<TenderWrapper>();
            for (TenderWrapper wrapper : wrappedTenders) {
                if (wrapper.isSubmitted) {
                    filtered.add(wrapper);
                }
            }
            wrappedTenders = filtered;
        } else if (filterType == 'not_submitted') {
            List<TenderWrapper> filtered = new List<TenderWrapper>();
            for (TenderWrapper wrapper : wrappedTenders) {
                if (!wrapper.isSubmitted) {
                    filtered.add(wrapper);
                }
            }
            wrappedTenders = filtered;
        }

        return wrappedTenders;
    }

    @AuraEnabled
    public static List<TenderWrapper> getOpenTenders() {
        Id accountId = getEffectiveAccountId();
        
        List<Appel_Offres__c> tenders = [
            SELECT Id, Name, Date_Limite_Reponse__c, Status__c, Description__c, 
                   Montant_Caution_Provisoire__c, Type_Procedure__c, Category__c
            FROM Appel_Offres__c 
            WHERE Status__c = 'Publié'
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
        return wrapTenders(tenders, accountId);
    }
    // ...existing code...

@AuraEnabled(cacheable=true)
public static List<Map<String, Object>> getRestrictedTenders() {
    try {
        // Requête pour récupérer les appels d'offres restreints
        List<Appel_Offres__c> tenders = [
            SELECT Id, Name, Date_Limite_Reponse__c, Status__c, Description__c, 
                   Montant_Caution_Provisoire__c, Type_Procedure__c, Category__c
            FROM Appel_Offres__c
            WHERE Status__c = 'Publié'
            AND RecordType.DeveloperName = 'Appel_d_offres_restreint'
            ORDER BY Date_Limite_Reponse__c ASC NULLS LAST
            LIMIT 50
        ];
        
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        Date now = Date.today();
        
        for (Appel_Offres__c ao : tenders) {
            Map<String, Object> wrapper = new Map<String, Object>();
            wrapper.put('tenderRecord', ao);
            
            // Vérifier si c'est nouveau (créé dans les 7 derniers jours)
            Boolean isNew = ao.CreatedDate != null && 
                           ao.CreatedDate >= System.now().addDays(-7);
            wrapper.put('isNew', isNew);
            
            result.add(wrapper);
        }
        
        return result;
    } catch (Exception e) {
        throw new AuraHandledException('Erreur lors de la récupération des appels d\'offres restreints: ' + e.getMessage());
    }
}



    @AuraEnabled
    public static String getOrCreateSubmission(Id aoId) {
        try {
            Id finalAccountId = getEffectiveAccountId();
            
            if (finalAccountId == null) {
                throw new AuraHandledException('Utilisateur non lié à une entreprise.');
            }

            List<Soumission__c> existingSubs = [
                SELECT Id 
                FROM Soumission__c 
                WHERE Appel_Offres__c = :aoId 
                AND Compte_Fournisseur__c = :finalAccountId
                LIMIT 1
            ];

            if (!existingSubs.isEmpty()) {
                return existingSubs[0].Id;
            }

            Soumission__c newSub = new Soumission__c();
            newSub.Appel_Offres__c = aoId;
            newSub.Compte_Fournisseur__c = finalAccountId;
            newSub.Statut__c = 'Brouillon';
            
            insert newSub;
            
            return newSub.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Erreur: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static TenderWrapper getAODetails(Id recordId) {
        Id accountId = getEffectiveAccountId();
        
        Appel_Offres__c tender = [
            SELECT Id, Name, Description__c, Status__c, Date_Limite_Reponse__c, 
                   Montant_Caution_Provisoire__c, Type_Procedure__c, CreatedDate,
                   RecordType.Name, Category__c
            FROM Appel_Offres__c 
            WHERE Id = :recordId
            LIMIT 1
        ];

        Soumission__c sub = null;
        if (accountId != null) {
            List<Soumission__c> subs = [
                SELECT Id, Statut__c, CreatedDate 
                FROM Soumission__c 
                WHERE Appel_Offres__c = :recordId AND Compte_Fournisseur__c = :accountId 
                LIMIT 1
            ];
            if (!subs.isEmpty()) {
                sub = subs[0];
            }
        }

        // Ensure isSubmitted logic matches wrapTenders
        Boolean isSubmitted = sub != null && sub.Statut__c == 'Soumis';
        return new TenderWrapper(tender, isSubmitted, sub?.Id, sub?.Statut__c, sub?.CreatedDate);
    }

    @AuraEnabled(cacheable=true)
    public static Soumission__c getSubmissionDetails(Id submissionId) {
        return [
            SELECT Id, Name, Date_Soumission__c, Statut__c, CreatedDate,
                   Appel_Offres__r.Name, Appel_Offres__r.Description__c,
                   Appel_Offres__r.Status__c, Appel_Offres__r.Date_Limite_Reponse__c,
                   Appel_Offres__r.Category__c
            FROM Soumission__c 
            WHERE Id = :submissionId
            LIMIT 1
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getSubmissionFiles(Id submissionId) {
        List<Map<String, Object>> fileList = new List<Map<String, Object>>();
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, 
                   ContentDocument.Title, 
                   ContentDocument.FileExtension, 
                   ContentDocument.ContentSize
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :submissionId
        ];

        for (ContentDocumentLink link : links) {
            Map<String, Object> file = new Map<String, Object>();
            file.put('ContentDocumentId', link.ContentDocumentId);
            file.put('Title', link.ContentDocument.Title);
            file.put('FileExtension', link.ContentDocument.FileExtension);
            fileList.add(file);
        }
        return fileList;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getAttachedDocuments(Id parentId) {
        List<Map<String, Object>> fileList = new List<Map<String, Object>>();
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, 
                   ContentDocument.Title, 
                   ContentDocument.FileExtension, 
                   ContentDocument.ContentSize,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :parentId
            AND (ContentDocument.Title LIKE '%Cahier des prescriptions spéciales%' 
                 OR ContentDocument.Title LIKE '%Règlement de consultation%')
        ];

        if (links.isEmpty()) return fileList;

        Set<Id> versionIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            versionIds.add(link.ContentDocument.LatestPublishedVersionId);
        }

        Map<Id, ContentDistribution> distMap = new Map<Id, ContentDistribution>();
        for (ContentDistribution cd : [
            SELECT ContentVersionId, DistributionPublicUrl, ContentDownloadUrl 
            FROM ContentDistribution 
            WHERE ContentVersionId IN :versionIds
        ]) {
            distMap.put(cd.ContentVersionId, cd);
        }

        List<ContentDistribution> newDistributions = new List<ContentDistribution>();
        for (ContentDocumentLink link : links) {
            Id vId = link.ContentDocument.LatestPublishedVersionId;
            if (!distMap.containsKey(vId)) {
                newDistributions.add(new ContentDistribution(
                    Name = link.ContentDocument.Title,
                    ContentVersionId = vId,
                    PreferencesAllowViewInBrowser = true,
                    PreferencesLinkLatestVersion = true
                ));
            }
        }

        if (!newDistributions.isEmpty()) {
            try {
                insert newDistributions;
                // Query them back to get URLs
                for (ContentDistribution cd : [
                    SELECT ContentVersionId, DistributionPublicUrl, ContentDownloadUrl 
                    FROM ContentDistribution 
                    WHERE Id IN :newDistributions
                ]) {
                    distMap.put(cd.ContentVersionId, cd);
                }
            } catch (Exception e) {
                System.debug('Error creating ContentDistribution: ' + e.getMessage());
            }
        }

        for (ContentDocumentLink link : links) {
            Id vId = link.ContentDocument.LatestPublishedVersionId;
            ContentDistribution cd = distMap.get(vId);
            
            Map<String, Object> file = new Map<String, Object>();
            file.put('ContentDocumentId', link.ContentDocumentId);
            file.put('versionId', vId);
            file.put('Title', link.ContentDocument.Title);
            file.put('FileExtension', link.ContentDocument.FileExtension);
            file.put('ContentSize', link.ContentDocument.ContentSize);
            
            if (cd != null) {
                file.put('pdfPreviewUrl', cd.DistributionPublicUrl);
                file.put('pdfDownloadUrl', cd.ContentDownloadUrl);
            }
            fileList.add(file);
        }
        return fileList;
    }

    @AuraEnabled(cacheable=true)
    public static List<Soumission__c> getMySubmissions(String searchKey) {
        // Debug current user to help diagnose missing ContactId issues
        User currentUser = [SELECT Id, ContactId, Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.debug('getMySubmissions - Current User Id: ' + currentUser.Id + ' ContactId: ' + currentUser.ContactId + ' Profile: ' + currentUser.Profile.Name);

        Id accountId = getEffectiveAccountId();
        // If no account found, provide a sandbox-only fallback for System Administrators without ContactId
        if (accountId == null) {
            if (currentUser.Profile != null && currentUser.Profile.Name == 'System Administrator' && currentUser.ContactId == null) {
                try {
                    Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
                    if (org.IsSandbox) {
                        System.debug('Sandbox admin without ContactId - returning recent submissions for testing');
                        if (String.isNotBlank(searchKey)) {
                            String key = '%' + searchKey + '%';
                            return [
                                SELECT Id, Name, Date_Soumission__c, Appel_Offres__r.Name,
                                       Appel_Offres__r.Category__c, Appel_Offres__r.Description__c,Statut__c,Appel_Offres__r.Date_Limite_Reponse__c 
                                FROM Soumission__c
                                WHERE Name LIKE :key OR Appel_Offres__r.Name LIKE :key
                                ORDER BY Date_Soumission__c DESC
                                LIMIT 10
                            ];
                        } else {
                            return [
                                SELECT Id, Name, Date_Soumission__c, Appel_Offres__r.Name,
                                       Appel_Offres__r.Category__c, Appel_Offres__r.Description__c,Statut__c,Appel_Offres__r.Date_Limite_Reponse__c 
                                FROM Soumission__c
                                ORDER BY Date_Soumission__c DESC
                                LIMIT 10
                            ];
                        }
                    }
                } catch (Exception e) {
                    System.debug('Error checking Organization.IsSandbox: ' + e.getMessage());
                }
            }
            return new List<Soumission__c>();
        }

        if (String.isNotBlank(searchKey)) {
            String key = '%' + searchKey + '%';
            return [
                SELECT Id, Name, Date_Soumission__c, Appel_Offres__r.Name, 
                       Appel_Offres__r.Category__c, Appel_Offres__r.Description__c,Statut__c,Appel_Offres__r.Date_Limite_Reponse__c 
                FROM Soumission__c
                WHERE Compte_Fournisseur__c = :accountId
                AND (Name LIKE :key OR Appel_Offres__r.Name LIKE :key OR Appel_Offres__r.Category__c LIKE :key)
                ORDER BY Date_Soumission__c DESC
            ];
        } else {
            return [
                SELECT Id, Name, Date_Soumission__c, Appel_Offres__r.Name, 
                       Appel_Offres__r.Category__c, Appel_Offres__r.Description__c,Statut__c,Appel_Offres__r.Date_Limite_Reponse__c 
                FROM Soumission__c
                WHERE Compte_Fournisseur__c = :accountId
                ORDER BY Date_Soumission__c DESC
            ];
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Soumission__c> getRecentSubmissions() {
        Id accountId = getEffectiveAccountId();
        if (accountId == null) return new List<Soumission__c>();

        return [
            SELECT Id, Name, Statut__c, CreatedDate, Date_Soumission__c,
                   Appel_Offres__r.Name, Appel_Offres__r.Category__c
            FROM Soumission__c 
            WHERE Compte_Fournisseur__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 3
        ];
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // METHODE D'APPEL A OCR.SPACE
    // ══════════════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static Map<String, Object> analyzeInvoiceOCR(String base64Data, String fileExtension) {
        Map<String, Object> result = new Map<String, Object>{
            'isSuccess' => false,
            'extractedNumber' => null,
            'rawText' => ''
        };

        try {
            // L'API OCR.Space nécessite une clé gratuite (helloworld est limité mais marche pour tester)
            String apiKey = 'helloworld'; 
            String endpoint = 'https://api.ocr.space/parse/image';
            
            // Format du bout de code (data:image/jpeg;base64,..... ou data:application/pdf;base64,....)
            String mimeType = fileExtension.toLowerCase() == 'pdf' ? 'application/pdf' : 'image/jpeg';
            String base64Image = 'data:' + mimeType + ';base64,' + base64Data;
            
            // Préparer le payload POST (application/x-www-form-urlencoded est souvent utilisé par OCR Space)
            String body = 'apikey=' + EncodingUtil.urlEncode(apiKey, 'UTF-8') 
                        + '&base64Image=' + EncodingUtil.urlEncode(base64Image, 'UTF-8')
                        + '&language=fre' // Français
                        + '&isOverlayRequired=true'
                        + '&OCREngine=2'
                        + '&scale=true'
                        + '&detectOrientation=true'
                        + '&isTable=true';

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setBody(body);
            req.setTimeout(120000); // L'OCR peut prendre du temps

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                // Parser la réponse JSON
                Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                // Vérifier si OCR space a réussi
                Integer exitCode = (Integer) jsonResponse.get('OCRExitCode');
                if (exitCode == 1 || exitCode == 2) { 
                    List<Object> parsedResults = (List<Object>) jsonResponse.get('ParsedResults');
                    if (parsedResults != null && !parsedResults.isEmpty()) {
                        Map<String, Object> firstResult = (Map<String, Object>) parsedResults[0];
                        String parsedText = (String) firstResult.get('ParsedText');
                        String normalizedText = normalizeOcrTextForInvoice(parsedText);
                        
                        result.put('isSuccess', true);
                        result.put('rawText', parsedText);

                        String extractedInvoiceNumber = extractInvoiceNumberFromText(normalizedText);
                        if (String.isNotBlank(extractedInvoiceNumber)) {
                            result.put('extractedNumber', extractedInvoiceNumber);
                        }
                    }
                } else {
                    result.put('error', 'Erreur OCR.Space: ' + jsonResponse.get('ErrorMessage'));
                }
            } else {
                result.put('error', 'L\'API a répondu avec le statut ' + res.getStatusCode());
            }
        } catch(Exception e) {
            result.put('error', 'Erreur Apex: ' + e.getMessage());
        }
        
        return result;
    }

    private static String normalizeOcrTextForInvoice(String text) {
        if (String.isBlank(text)) return '';
        String normalized = text.replace('\r', '\n');
        normalized = normalized.replaceAll('[\t]+', ' ');
        normalized = normalized.replaceAll(' +', ' ');
        normalized = normalized.replaceAll('(?i)Facturent', 'Facture n');
        normalized = normalized.replaceAll('(?i)Facturen[°ºo]?', 'Facture n');
        return normalized;
    }

    private static String extractInvoiceNumberFromText(String text) {
        if (String.isBlank(text)) return null;

        List<String> patterns = new List<String>{
            '(?im)^.*Factur\\w*\\s*n[°ºo]?\\s*[:\\-]?\\s*([A-Z0-9][A-Z0-9\\-/]+).*$',
            '(?im)^.*N[°ºo]\\s*Factur\\w*\\s*[:\\-]?\\s*([A-Z0-9][A-Z0-9\\-/]+).*$',
            '(?im)^.*Num[eé]ro\\s*de\\s*facture\\s*[:\\-]?\\s*([A-Z0-9][A-Z0-9\\-/]+).*$',
            '(?im)^.*Facture\\s*[:\\-]?\\s*([A-Z0-9]+/[A-Z0-9]+).*$'
        };

        for (String p : patterns) {
            Matcher m = Pattern.compile(p).matcher(text);
            if (m.find()) {
                String candidate = m.group(1) != null ? m.group(1).trim() : null;
                if (isLikelyInvoiceNumber(candidate)) {
                    return candidate;
                }
            }
        }
        return null;
    }

    private static Boolean isLikelyInvoiceNumber(String candidate) {
        if (String.isBlank(candidate)) return false;
        if (Pattern.compile('(?i)^(client|date|atlas|bc)$').matcher(candidate).matches()) return false;
        if (candidate.length() < 3) return false;
        if (!Pattern.compile('[0-9]').matcher(candidate).find()) return false;
        return true;
    }

    @AuraEnabled(cacheable=true)
    public static List<OrderForm__c> getMyPurchaseOrders(String searchKey) {
        Id accountId = getEffectiveAccountId();
        
        if (String.isBlank(searchKey)) {
            return [
                SELECT Id, Name, CreatedDate, TotalCostHT__c,Status__c , TotalCostTTC__c, TotalTTCAmountInvoiced__c, TotalTTCAmountNotInvoiced__c 
                FROM OrderForm__c 
                WHERE Provider__c = :accountId 
                ORDER BY CreatedDate DESC
            ];
        } else {
            String key = '%' + searchKey + '%';
            return [
                SELECT Id, Name, CreatedDate, TotalCostHT__c,Status__c , TotalCostTTC__c, TotalTTCAmountInvoiced__c, TotalTTCAmountNotInvoiced__c 
                FROM OrderForm__c 
                WHERE Provider__c = :accountId 
                AND Name LIKE :key
                ORDER BY CreatedDate DESC
            ];
        }
    }

    @AuraEnabled(cacheable=true)
    public static OrderForm__c getOrderFormDetails(Id recordId) {
        Id accountId = getEffectiveAccountId();
        
        OrderForm__c order = [
            SELECT Id, Name, CreatedDate, TotalCostHT__c, TotalCostTTC__c, TotalCostVAT__c, 
                   TotalTTCAmountInvoiced__c, TotalTTCAmountNotInvoiced__c, Provider__c,Status__c
            FROM OrderForm__c 
            WHERE Id = :recordId 
            AND Provider__c = :accountId 
            LIMIT 1
        ];
        System.debug('getOrderFormDetails - CreatedDate: ' + order.CreatedDate);
        return order;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getBCFiles(Id recordId) {
        System.debug('DEBUG getBCFiles - Starting for recordId: ' + recordId);
        List<Map<String, Object>> fileList = new List<Map<String, Object>>();
        
        try {
            // 1. Step A: Fix Visibility (InternalUsers -> AllUsers)
            // We need to query Visibility and ShareType to replicate the link
            List<ContentDocumentLink> links = [
                SELECT Id, ContentDocumentId, Visibility, ShareType 
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :recordId
            ];
            System.debug('DEBUG Link count: ' + links.size());

            if (links.isEmpty()) return fileList;

            List<ContentDocumentLink> toDelete = new List<ContentDocumentLink>();
            List<ContentDocumentLink> toInsert = new List<ContentDocumentLink>();
            Set<Id> docIds = new Set<Id>();

            for (ContentDocumentLink link : links) {
                docIds.add(link.ContentDocumentId); // Collect ID for Step B
                
                // If visibility is InternalUsers, external users (Portal) cannot see it properly.
                // We must replace it with 'AllUsers' to allow visibility to anyone with access to the record.
                if (link.Visibility == 'InternalUsers') {
                    toDelete.add(link);
                    
                    ContentDocumentLink newLink = new ContentDocumentLink();
                    newLink.LinkedEntityId = recordId;
                    newLink.ContentDocumentId = link.ContentDocumentId;
                    newLink.Visibility = 'AllUsers'; // The critical fix
                    // ShareType 'I' (Inferred) cannot be set on insert, so we default to 'V' (Viewer)
                    newLink.ShareType = (link.ShareType == 'I' || link.ShareType == null) ? 'V' : link.ShareType;
                    toInsert.add(newLink);
                }
            }

            // Perform the swap if needed
            if (!toDelete.isEmpty()) {
                System.debug('DEBUG Fixing Visibility for ' + toDelete.size() + ' links.');
                delete toDelete;
                insert toInsert;
            }

            // 2. Step B: Query latest version for these documents
            List<ContentVersion> versions = [
                SELECT Id, Title, FileExtension, ContentSize, ContentDocumentId 
                FROM ContentVersion 
                WHERE ContentDocumentId IN :docIds 
                AND IsLatest = true
            ];
            System.debug('DEBUG Version count: ' + versions.size());

            if (versions.isEmpty()) return fileList;

            Set<Id> versionIds = new Set<Id>();
            for (ContentVersion v : versions) {
                versionIds.add(v.Id);
            }

            // 3. Step C: Distribution Logic (Public Link)
            Map<Id, ContentDistribution> distMap = new Map<Id, ContentDistribution>();
            
            // Fetch existing distributions
            for (ContentDistribution cd : [
                SELECT ContentVersionId, DistributionPublicUrl, ContentDownloadUrl 
                FROM ContentDistribution 
                WHERE ContentVersionId IN :versionIds
                ORDER BY CreatedDate DESC
            ]) {
                if (!distMap.containsKey(cd.ContentVersionId)) {
                    distMap.put(cd.ContentVersionId, cd);
                }
            }

            List<ContentDistribution> newDistributions = new List<ContentDistribution>();
            for (ContentVersion v : versions) {
                if (!distMap.containsKey(v.Id)) {
                    newDistributions.add(new ContentDistribution(
                        Name = v.Title,
                        ContentVersionId = v.Id,
                        PreferencesAllowViewInBrowser = true,
                        PreferencesLinkLatestVersion = true,
                        PreferencesNotifyOnVisit = false
                    ));
                }
            }

            // Insert new distributions
            if (!newDistributions.isEmpty()) {
                try {
                    insert newDistributions;
                    
                    Set<Id> newDistIds = new Set<Id>();
                    for (ContentDistribution cd : newDistributions) {
                        newDistIds.add(cd.Id);
                    }
                    
                    // Re-query needed to get the URLs
                    for (ContentDistribution cd : [
                        SELECT ContentVersionId, DistributionPublicUrl, ContentDownloadUrl 
                        FROM ContentDistribution 
                        WHERE Id IN :newDistIds
                    ]) {
                        distMap.put(cd.ContentVersionId, cd);
                    }
                } catch (Exception e) {
                    System.debug('ERROR creating ContentDistribution: ' + e.getMessage());
                }
            }

            // 4. Return results (Title & pdfPreviewUrl)
            for (ContentVersion v : versions) {
                ContentDistribution cd = distMap.get(v.Id);
                
                Map<String, Object> file = new Map<String, Object>();
                file.put('Title', v.Title);
                file.put('FileExtension', v.FileExtension);
                file.put('ContentSize', v.ContentSize);
                file.put('ContentDocumentId', v.ContentDocumentId);
                
                if (cd != null) {
                    // System.debug('DEBUG Public URL: ' + cd.DistributionPublicUrl);
                    file.put('pdfPreviewUrl', cd.DistributionPublicUrl);
                    file.put('pdfDownloadUrl', cd.ContentDownloadUrl);
                }
                fileList.add(file);
            }

        } catch (Exception e) {
            System.debug('CRITICAL ERROR in getBCFiles: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return fileList;
    }


@AuraEnabled
public static Map<String, Object> createInvoiceFromBC(
        Id orderFormId,
        String fileName,
        String base64Data,
        String mimeType,
    String extractedInvoiceNumber,
    String extractedDateDepot,
    Decimal extractedTotalAmountHT,
    Decimal extractedTotalVATAmount,
    Decimal extractedTotalAmountTTC,
    List<Map<String, Object>> scannedLinesData) {
    Savepoint sp = Database.setSavepoint();
    try {
        Id accountId = getEffectiveAccountId();
        Boolean hasScannedPayload = scannedLinesData != null && !scannedLinesData.isEmpty();

        // 1. Récupérer le Account du Fournisseur pour condition et méthode de paiement
        Account supplierAccount = [
            SELECT Id, PaymentTerms__c, MethodOfPayment__c 
            FROM Account 
            WHERE Id = :accountId 
            LIMIT 1
        ];

        // 2. Récupérer le BC et sa demande d'achat associée pour l'Entité
        List<OrderForm__c> orders = [
            SELECT Id, Name, TotalCostTTC__c, TotalCostHT__c, TotalCostVAT__c,
                   TotalTTCAmountNotInvoiced__c, Provider__c,
                   PurshaseOrder__r.Entity__c // Récupérer l'entité depuis la DA (attention à la faute de frappe s/c dans le nom API)
            FROM OrderForm__c
            WHERE Id = :orderFormId AND Provider__c = :accountId
            LIMIT 1
        ];
        if (orders.isEmpty()) throw new AuraHandledException('Bon de commande introuvable ou accès refusé.');

        OrderForm__c bc = orders[0];

        Map<String, Id> invoiceRecordTypeByDevName = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Invoice__c'
            AND DeveloperName = 'BasicInvoiceOrderForm'
        ]) {
            invoiceRecordTypeByDevName.put(rt.DeveloperName, rt.Id);
        }
        Id invoiceRtBaseOrderFormId = invoiceRecordTypeByDevName.get('BasicInvoiceOrderForm');

        if (invoiceRtBaseOrderFormId == null) {
            throw new AuraHandledException('Record Type Facture base Bon de Commande introuvable.');
        }

        User currentUser = [
            SELECT Id, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];

        // 3. Gérer le numéro de facture (OCR ou fallback)
        String finalInvoiceNumber = String.isNotBlank(extractedInvoiceNumber) 
            ? extractedInvoiceNumber 
            : 'FAC-' + String.valueOf(Date.today()).replace('-', '') + '-' + String.valueOf(Math.abs(Math.mod(Crypto.getRandomInteger(), 9000)) + 1000);

        if (String.isBlank(supplierAccount.MethodOfPayment__c) || String.isBlank(supplierAccount.PaymentTerms__c)) {
            throw new AuraHandledException('Le fournisseur n\'a pas la méthode/condition de paiement requise pour créer la facture.');
        }

        // 4. Créer la Facture avec les valeurs dynamiques
        Invoice__c newInvoice = new Invoice__c();
        Date scannedInvoiceDate = parseDateOrNull(extractedDateDepot);
        // Mode hybride demandé: facture TOUJOURS base BC, même avec lignes scannées.
        newInvoice.RecordTypeId                  = invoiceRtBaseOrderFormId;
        newInvoice.OrderForm__c                  = bc.Id;
        newInvoice.Supplier__c                   = accountId;
        newInvoice.Status__c                     = 'En cours de création';
        if (scannedInvoiceDate != null) {
            // Date de facture = date lue sur la facture scannée.
            newInvoice.InvoiceDate__c = scannedInvoiceDate;
        }
        // Date de dépôt = date du jour (date du scan dans le portail).
        newInvoice.DateDepot__c = Date.today();
        
        // Champs dynamiques
        newInvoice.Entity__c                     = bc.PurshaseOrder__r.Entity__c; // Depuis la DA
        newInvoice.SupplierInvoiceNumber__c      = finalInvoiceNumber;            // Depuis l'OCR
        newInvoice.PaymentMethod__c              = supplierAccount.MethodOfPayment__c; // Depuis Fournisseur
        newInvoice.PaymentCondition__c           = supplierAccount.PaymentTerms__c;    // Depuis Fournisseur
        
        newInvoice.SubjectHonoraryDeclaration__c = false;

        // Tenter de persister les montants OCR si les champs sont éditables dans l'org.
        setFieldIfCreateable(newInvoice, 'TotalAmountHT__c', extractedTotalAmountHT);
        setFieldIfCreateable(newInvoice, 'TotalVATAmount__c', extractedTotalVATAmount);
        setFieldIfCreateable(newInvoice, 'TotalAmountTTC__c', extractedTotalAmountTTC);
        setFieldIfCreateable(newInvoice, 'OrderFormTotalCostTTC__c', bc.TotalCostTTC__c);
        
        if (currentUser.ContactId != null) {
            newInvoice.SupplierContact__c = currentUser.ContactId;
        }
        insert newInvoice;

        // Lignes BC chargées une seule fois pour fallback et enrichissement des lignes OCR.
        List<PurchasingLine__c> purchasingLines = [
            SELECT Id, ProductName__c, Quantity__c, UnitPriceHT__c,
                   VATAmount__c, TVACode__c, TTCAmountNotInvoiced__c,
                   CostCenter__c, Entity__c, Budget__c,
                   PurchaseFamilyCode__c, UnitOfMeasure__c
            FROM PurchasingLine__c
            WHERE OrderForm__c = :orderFormId
        ];

        // ── Récupérer les Record Types de ligne: mode BC et mode indépendant ─────────
        Map<String, Id> lineRecordTypeByDevName = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'InvoiceLine__c'
            AND DeveloperName = 'InvoiceLineBaseOrderForm'
        ]) {
            lineRecordTypeByDevName.put(rt.DeveloperName, rt.Id);
        }
        Id lineRtBaseOrderFormId = lineRecordTypeByDevName.get('InvoiceLineBaseOrderForm');
        if (!hasScannedPayload && lineRtBaseOrderFormId == null) {
            throw new AuraHandledException('Record Type Ligne de facture base Bon de Commande introuvable.');
        }
        if (hasScannedPayload && lineRtBaseOrderFormId == null) {
            throw new AuraHandledException('Record Type Ligne de facture base Bon de Commande introuvable pour les lignes scannées.');
        }

        List<InvoiceLine__c> invoiceLines = new List<InvoiceLine__c>();
        PurchasingLine__c templatePurchasingLine = !purchasingLines.isEmpty() ? purchasingLines[0] : null;

        // 1) Mode indépendant: créer les lignes uniquement depuis l'OCR si payload présent.
        if (hasScannedPayload) {
            for (Map<String, Object> scannedLine : scannedLinesData) {
                if (scannedLine == null) continue;

                String productName = (String) scannedLine.get('ProductName__c');
                Decimal quantity = toDecimalFromObject(scannedLine.get('Quantity__c'));
                Decimal unitPrice = toDecimalFromObject(scannedLine.get('UnitPriceHT__c'));
                Decimal htAmount = toDecimalFromObject(scannedLine.get('HTAmount__c'));

                // Fallback: si OCR manque PU HT ou Montant HT, on le déduit avec la quantité.
                if (quantity != null && quantity != 0) {
                    if (unitPrice == null && htAmount != null) {
                        unitPrice = (htAmount / quantity).setScale(2);
                    } else if (htAmount == null && unitPrice != null) {
                        htAmount = (unitPrice * quantity).setScale(2);
                    }
                }

                if (String.isBlank(productName) || quantity == null || unitPrice == null) {
                    continue;
                }

                InvoiceLine__c line = new InvoiceLine__c();
                line.Invoice__c = newInvoice.Id;
                line.ProductName__c = productName;
                line.Quantity__c = quantity;
                line.UnitPriceHT__c = unitPrice;
                setFieldIfCreateable(line, 'HTAmount__c', htAmount);
                
                // Renseigner un minimum comptable pour éviter les validations côté org.
                if (templatePurchasingLine != null) {
                    line.TVACode__c = templatePurchasingLine.TVACode__c;
                    line.CostCenter__c = templatePurchasingLine.CostCenter__c;
                    line.Entity__c = templatePurchasingLine.Entity__c;
                    line.Budget__c = templatePurchasingLine.Budget__c;
                    line.PurchaseFamilyCode__c = templatePurchasingLine.PurchaseFamilyCode__c;
                    line.UnitOfMeasure__c = templatePurchasingLine.UnitOfMeasure__c;
                }

                Decimal vatAmount = line.VATAmount__c != null ? line.VATAmount__c : 0;
                Decimal baseHt = htAmount != null ? htAmount : (unitPrice * quantity);
                line.TTCAmountInvoiced__c = baseHt + vatAmount;
                line.TTCAmountNotInvoiced__c = baseHt + vatAmount;
                line.TECH_AutoGeneratedLine__c = true;

                line.RecordTypeId = lineRtBaseOrderFormId;

                invoiceLines.add(line);
            }

            if (invoiceLines.isEmpty()) {
                throw new AuraHandledException('Aucune ligne scannée exploitable. Vérifiez le tableau produit sur la facture.');
            }

            // Mode TVA fixe par ligne demandé: appliquer la TVA scannée identique sur chaque ligne.
            if (extractedTotalVATAmount != null && extractedTotalVATAmount >= 0) {
                for (InvoiceLine__c lineForVat : invoiceLines) {
                    lineForVat.VATAmount__c = extractedTotalVATAmount.setScale(2);
                }
            } else if (templatePurchasingLine != null && templatePurchasingLine.VATAmount__c != null) {
                // Fallback de compatibilité si OCR n'a pas donné la TVA totale.
                for (InvoiceLine__c lineForTemplateVat : invoiceLines) {
                    lineForTemplateVat.VATAmount__c = templatePurchasingLine.VATAmount__c;
                }
            }

            // Recalcul TTC ligne après affectation TVA.
            for (InvoiceLine__c lineAfterVat : invoiceLines) {
                Decimal baseHt = lineAfterVat.HTAmount__c != null
                    ? lineAfterVat.HTAmount__c
                    : (lineAfterVat.UnitPriceHT__c * lineAfterVat.Quantity__c);
                Decimal vatAmount = lineAfterVat.VATAmount__c != null ? lineAfterVat.VATAmount__c : 0;
                lineAfterVat.TTCAmountInvoiced__c = baseHt + vatAmount;
                lineAfterVat.TTCAmountNotInvoiced__c = baseHt + vatAmount;
            }
        }

        // 2) Fallback BC uniquement si aucun payload OCR n'est fourni.
        if (!hasScannedPayload && invoiceLines.isEmpty()) {
            for (PurchasingLine__c pl : purchasingLines) {
                InvoiceLine__c line = new InvoiceLine__c();
                line.Invoice__c = newInvoice.Id;
                line.PurchasingLine__c = pl.Id;
                line.ProductName__c = pl.ProductName__c;
                line.Quantity__c = pl.Quantity__c;
                line.UnitPriceHT__c = pl.UnitPriceHT__c;
                line.VATAmount__c = pl.VATAmount__c != null ? pl.VATAmount__c : 1;
                line.TVACode__c = pl.TVACode__c;
                line.TTCAmountInvoiced__c = pl.TTCAmountNotInvoiced__c != null ? pl.TTCAmountNotInvoiced__c : 0;
                line.TTCAmountNotInvoiced__c = pl.TTCAmountNotInvoiced__c != null ? pl.TTCAmountNotInvoiced__c : 0;
                line.CostCenter__c = pl.CostCenter__c;
                line.Entity__c = pl.Entity__c;
                line.Budget__c = pl.Budget__c;
                line.PurchaseFamilyCode__c = pl.PurchaseFamilyCode__c;
                line.UnitOfMeasure__c = pl.UnitOfMeasure__c;
                line.TECH_AutoGeneratedLine__c = true;

                line.RecordTypeId = lineRtBaseOrderFormId;

                invoiceLines.add(line);
            }
        }

        if (!invoiceLines.isEmpty()) {
            Database.SaveResult[] lineInsertResults = Database.insert(invoiceLines, false);
            List<String> dmlErrors = new List<String>();
            Integer successCount = 0;
            List<Id> insertedLineIds = new List<Id>();

            for (Integer i = 0; i < lineInsertResults.size(); i++) {
                Database.SaveResult sr = lineInsertResults[i];
                if (sr.isSuccess()) {
                    successCount++;
                    insertedLineIds.add(sr.getId());
                } else {
                    for (Database.Error err : sr.getErrors()) {
                        dmlErrors.add('Ligne ' + (i + 1) + ': ' + err.getMessage());
                    }
                }
            }

            if (!dmlErrors.isEmpty()) {
                throw new AuraHandledException(
                    'Erreur création lignes facture (' + successCount + '/' + invoiceLines.size() + ' réussies): ' +
                    String.join(dmlErrors, ' | ')
                );
            }

            // Mode TVA fixe par ligne: forcer la TVA scannée sur chaque ligne après insert,
            // car des automatisations org peuvent recalculer la TVA.
            if (hasScannedPayload && extractedTotalVATAmount != null && extractedTotalVATAmount >= 0 && !insertedLineIds.isEmpty()) {
                List<InvoiceLine__c> insertedLines = [
                    SELECT Id, Quantity__c, UnitPriceHT__c, HTAmount__c, VATAmount__c,
                           TTCAmountInvoiced__c, TTCAmountNotInvoiced__c
                    FROM InvoiceLine__c
                    WHERE Id IN :insertedLineIds
                    ORDER BY CreatedDate ASC
                ];
                for (InvoiceLine__c l : insertedLines) {
                    Decimal lineHt = l.HTAmount__c != null ? l.HTAmount__c : (l.UnitPriceHT__c * l.Quantity__c);
                    Decimal lineVat = extractedTotalVATAmount.setScale(2);

                    l.VATAmount__c = lineVat;
                    Decimal baseHt = lineHt != null ? lineHt : 0;
                    l.TTCAmountInvoiced__c = baseHt + lineVat;
                    l.TTCAmountNotInvoiced__c = baseHt + lineVat;
                }

                Database.SaveResult[] lineUpdateResults = Database.update(insertedLines, false);
                List<String> updateErrors = new List<String>();
                for (Integer i = 0; i < lineUpdateResults.size(); i++) {
                    if (!lineUpdateResults[i].isSuccess()) {
                        for (Database.Error err : lineUpdateResults[i].getErrors()) {
                            updateErrors.add('Ligne TVA post-insert ' + (i + 1) + ': ' + err.getMessage());
                        }
                    }
                }

                if (!updateErrors.isEmpty()) {
                    throw new AuraHandledException('TVA scannée non appliquée après insert: ' + String.join(updateErrors, ' | '));
                }
            }
        }
        

        // ── Sauvegarder le fichier et le lier à la facture ──────────────
        if (String.isNotBlank(base64Data) && String.isNotBlank(fileName)) {
            ContentVersion cv = new ContentVersion();
            cv.Title           = fileName;
            cv.PathOnClient    = fileName;
            cv.VersionData     = EncodingUtil.base64Decode(base64Data);
            cv.IsMajorVersion  = true;
            insert cv;

            // Récupérer le ContentDocumentId généré
            Id contentDocId = [
                SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
            ].ContentDocumentId;

            // Lier à la facture
            insert new ContentDocumentLink(
                ContentDocumentId = contentDocId,
                LinkedEntityId    = newInvoice.Id,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            );

            // Lier aussi au BC pour référence
            insert new ContentDocumentLink(
                ContentDocumentId = contentDocId,
                LinkedEntityId    = orderFormId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            );
        }

        Invoice__c created = [
            SELECT Id, Name, Status__c, InvoiceDate__c FROM Invoice__c WHERE Id = :newInvoice.Id LIMIT 1
        ];

        return new Map<String, Object>{
            'Id'     => created.Id,
            'Name'   => created.Name,
            'Status' => created.Status__c,
            'Date'   => String.valueOf(created.InvoiceDate__c),
            'BCName' => bc.Name
        };

    } catch (AuraHandledException e) {
        Database.rollback(sp);
        throw e;
    } catch (DmlException dmlEx) {
        Database.rollback(sp);
        String details = dmlEx.getDmlMessage(0);
        throw new AuraHandledException('Erreur DML lors de la création de la facture/lignes: ' + details);
    } catch (Exception e) {
        Database.rollback(sp);
        throw new AuraHandledException('Erreur : ' + e.getMessage());
    }
}

private static PurchasingLine__c findBestPurchasingLine(List<PurchasingLine__c> candidates, String scannedProductName) {
    if (candidates == null || candidates.isEmpty() || String.isBlank(scannedProductName)) return null;

    String scannedNorm = normalizeProductLabel(scannedProductName);
    if (String.isBlank(scannedNorm)) return null;

    for (PurchasingLine__c pl : candidates) {
        if (normalizeProductLabel(pl.ProductName__c) == scannedNorm) {
            return pl;
        }
    }

    for (PurchasingLine__c pl : candidates) {
        String bcNorm = normalizeProductLabel(pl.ProductName__c);
        if (bcNorm.contains(scannedNorm) || scannedNorm.contains(bcNorm)) {
            return pl;
        }
    }

    return null;
}

private static String normalizeProductLabel(String value) {
    if (String.isBlank(value)) return '';
    String v = value.toLowerCase();
    v = v.replaceAll('[^a-z0-9]+', '');
    return v;
}

private static Date parseDateOrNull(String rawDate) {
    if (String.isBlank(rawDate)) {
        return null;
    }
    try {
        return Date.valueOf(rawDate);
    } catch (Exception e) {
        return null;
    }
}

private static Decimal toDecimalFromObject(Object value) {
    if (value == null) return null;
    try {
        if (value instanceof Decimal) return (Decimal) value;
        if (value instanceof Integer) return Decimal.valueOf(String.valueOf((Integer) value));
        if (value instanceof Long) return Decimal.valueOf(String.valueOf((Long) value));
        if (value instanceof Double) return Decimal.valueOf(String.valueOf((Double) value));
        String raw = String.valueOf(value);
        if (String.isBlank(raw)) return null;
        String normalized = raw.replaceAll('\\s+', '').replace(',', '.');
        return Decimal.valueOf(normalized);
    } catch (Exception ex) {
        return null;
    }
}

private static void setFieldIfCreateable(SObject targetRecord, String fieldApiName, Object value) {
    if (targetRecord == null || String.isBlank(fieldApiName) || value == null) {
        return;
    }

    Map<String, Schema.SObjectField> fieldsMap = targetRecord.getSObjectType().getDescribe().fields.getMap();
    if (!fieldsMap.containsKey(fieldApiName)) {
        return;
    }

    Schema.DescribeFieldResult fieldDesc = fieldsMap.get(fieldApiName).getDescribe();
    if (fieldDesc.isCreateable()) {
        targetRecord.put(fieldApiName, value);
    }
}

// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════

@AuraEnabled(cacheable=true)
public static List<Invoice__c> getMyInvoices(String searchKey, String statusFilter) {
    Id accountId = getEffectiveAccountId();
    if (accountId == null) return new List<Invoice__c>();

    String query =
        'SELECT Id, Name, Status__c, ' +
        '       InvoiceDate__c, BasicInvoiceDate__c, DateDepot__c, ' +
        '       TotalAmountHT__c, TotalAmountTTC__c, TotalVATAmount__c, ' +
        '       TTCAmountToPay__c, OrderFormAmountNotInvoicedYet__c, ' +
        '       SupplierInvoiceNumber__c, ' +
        '       OrderForm__c, OrderForm__r.Name, ' +
        '       SupplierContact__c, SupplierContact__r.Name ' +
        'FROM Invoice__c ' +
        'WHERE Supplier__c = :accountId';

    if (String.isNotBlank(statusFilter)) {
        query += ' AND Status__c = :statusFilter';
    }

    if (String.isNotBlank(searchKey)) {
        String key = '%' + searchKey + '%';
        query += ' AND (Name LIKE :key OR SupplierInvoiceNumber__c LIKE :key OR OrderForm__r.Name LIKE :key)';
    }

    query += ' ORDER BY DateDepot__c DESC NULLS LAST, CreatedDate DESC';

    return Database.query(query);
}

@AuraEnabled(cacheable=true)
public static Map<String, Object> getInvoiceKpis() {
    Id accountId = getEffectiveAccountId();
    Map<String, Object> kpis = new Map<String, Object>{
        'total'          => 0,
        'enCours'        => 0,    // En cours de création + En cours de validation
        'validees'       => 0,    // Validée + Scannée
        'rejetees'       => 0,    // Rejetée + Annulée
        'montantTotal'   => 0.0,
        'montantValidees'=> 0.0,
        'montantEnCours' => 0.0
    };

    if (accountId == null) return kpis;

    List<AggregateResult> results = [
        SELECT Status__c        status,
               COUNT(Id)        cnt,
               SUM(TotalAmountTTC__c) montant
        FROM   Invoice__c
        WHERE  Supplier__c = :accountId
        GROUP BY Status__c
    ];

    Integer total        = 0;
    Decimal montantTotal = 0;

    for (AggregateResult ar : results) {
        String  st  = (String)  ar.get('status');
        Integer cnt = (Integer) ar.get('cnt');
        Decimal amt = ar.get('montant') != null ? (Decimal) ar.get('montant') : 0;

        total        += cnt;
        montantTotal += amt;

        if (st == 'Validée' || st == 'Scannée') {
            Integer existing = (Integer) kpis.get('validees');
            Decimal existingMt = (Decimal) kpis.get('montantValidees');
            kpis.put('validees',       existing   + cnt);
            kpis.put('montantValidees',existingMt + amt);

        } else if (st == 'Rejetée' || st == 'Annulée') {
            Integer existing = (Integer) kpis.get('rejetees');
            kpis.put('rejetees', existing + cnt);

        } else if (st == 'En cours de création' || st == 'En cours de validation') {
            Integer existing   = (Integer) kpis.get('enCours');
            Decimal existingMt = (Decimal) kpis.get('montantEnCours');
            kpis.put('enCours',        existing   + cnt);
            kpis.put('montantEnCours', existingMt + amt);
        }
    }

    kpis.put('total',        total);
    kpis.put('montantTotal', montantTotal);
    return kpis;
}

@AuraEnabled(cacheable=true)
public static Invoice__c getInvoiceDetails(Id invoiceId) {
    Id accountId = getEffectiveAccountId();
    return [
        SELECT Id, Name, Status__c,
               InvoiceDate__c, BasicInvoiceDate__c, DateDepot__c, PostingDate__c,
               TotalAmountHT__c, TotalAmountTTC__c, TotalVATAmount__c,
               TTCAmountToPay__c, OrderFormAmountNotInvoicedYet__c,
               SupplierInvoiceNumber__c, Comment__c,
               OrderForm__c,        OrderForm__r.Name, OrderForm__r.TotalCostTTC__c,
               SupplierContact__c,  SupplierContact__r.Name,
               Comptable__c,        Comptable__r.Name
        FROM   Invoice__c
        WHERE  Id = :invoiceId
        AND    Supplier__c = :accountId
        LIMIT  1
    ];
}

}