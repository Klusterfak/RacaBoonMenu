--[[
    RacaBoonMenu
    ------------
    Addon pour WoW 3.3.5 (Project Ascension).

    Fenêtres :
      1) "Mes Mythical Boons"          -> icônes de tes Boons, cliquables (y compris en combat).
                                           Juste l'icône colorée quand tu en as, invisible sinon.
                                           Pas de cadre/carré de fond -> style flottant, transparent.
      2) "Boons alliés disponibles"    -> via un canal d'addon (SendAddonMessage), la liste des
                                           Boons que chaque allié a EN RÉSERVE dans ses sacs
                                           (nécessite que les alliés aient aussi RacaBoonMenu).

    Commandes : /rbm  (ou /racaboonmenu)
        /rbm                      -> affiche/masque les fenêtres
        /rbm options              -> ouvre le panneau d'options
        /rbm lock                 -> verrouille/déverrouille le déplacement des fenêtres
        /rbm reset                -> replace les fenêtres à leur position par défaut
        /rbm debug                -> active/désactive les messages de diagnostic
        /rbm addboon <nom exact>  -> enregistre un type de Boon supplémentaire (hors combat)

    -------------------------------------------------------------------------
    POURQUOI CETTE ARCHITECTURE (important, lire si tu modifies ce fichier) :
    -------------------------------------------------------------------------
    Utiliser un objet depuis les sacs pendant le combat nécessite un bouton
    "sécurisé" (SecureActionButtonTemplate) dont Blizzard gère lui-même le clic.
    Mais Blizzard interdit catégoriquement d'appeler Hide()/Show()/SetPoint()/
    SetSize()/SetAttribute() sur ce type de bouton depuis du code d'AddOn PENDANT
    LE COMBAT ("AddOn prevented the call of the secure function").

    Chaque bouton "Mes Mythical Boons" est donc lié UNE FOIS POUR TOUTES (hors
    combat, au chargement) à un NOM exact de Boon connu à l'avance, via une
    MACRO ("/use Nom\n/click StaticPopup1Button1" -- le 2e clic confirme toute
    popup de confirmation automatiquement). Ensuite, à chaque rafraîchissement
    (même en combat), on se contente de changer sa texture d'icône, son
    compteur et son opacité : les seules opérations non protégées qu'on peut
    faire à tout moment.
]]--

local ADDON_NAME   = "RacaBoonMenu"
local ADDON_PREFIX = "RacaBoonMenu"   -- préfixe du canal d'addon pour le partage entre alliés

-- ============================================================
-- Config / constantes
-- ============================================================

local BOON_PATTERN = "Mythical Boon"   -- filtre utilisé pour repérer les Mythical Boons (objets et buffs)
local ICON_PADDING  = 4

-- Valeurs par défaut ; en pratique on utilise toujours RacaBoonMenuDB.options
-- une fois le SavedVariables chargé (voir EnsureDB).
local ICON_SIZE     = 36
local ICONS_PER_ROW = 8

-- Liste des Mythical Boon connus (nom exact tel qu'affiché sur l'objet, avec
-- le ":"). Si un nouveau type de Boon est ajouté par le serveur, utilise
-- "/rbm addboon Mythical Boon: NouveauNom" (hors combat) pour l'ajouter toi-même.
local DEFAULT_BOON_NAMES = {
    "Mythical Boon: Ascension",
    "Mythical Boon: Wrathful",
    "Mythical Boon: Critical",
    "Mythical Boon: Ruthlessness",
    "Mythical Boon: Momentum",
    "Mythical Boon: Piercing",
    "Mythical Boon: Adaptation",
    "Mythical Boon: Bountiful",
    "Mythical Boon: Bloodlust",
    "Mythical Boon: Sanctuary",
    "Mythical Boon: Sanctified",
    "Mythical Boon: Infinity",
    "Mythical Boon: Inquisition",
}

-- Labels courts affichés sous chaque icône, façon WeakAura.
local BOON_SHORT_LABELS = {
    ["Mythical Boon: Ascension"]    = "Dmg",
    ["Mythical Boon: Wrathful"]     = "AP/SP",
    ["Mythical Boon: Critical"]     = "Crit",
    ["Mythical Boon: Ruthlessness"] = "CDmg",
    ["Mythical Boon: Momentum"]     = "Haste",
    ["Mythical Boon: Piercing"]     = "Pen",
    ["Mythical Boon: Adaptation"]   = "Adapt",
    ["Mythical Boon: Bountiful"]    = "Stats",
    ["Mythical Boon: Sanctuary"]    = "DR",
    ["Mythical Boon: Sanctified"]   = "Heal",
    ["Mythical Boon: Infinity"]     = "CD",
    ["Mythical Boon: Inquisition"]  = "Laser",
    ["Mythical Boon: Bloodlust"]    = "BL",
}

-- Table inverse : diminutif -> nom complet, pour retrouver l'icône d'un boon
-- reçu d'un allié (le message ne transporte que le diminutif, plus compact).
local BOON_LABEL_TO_NAME = {}
for fullName, label in pairs(BOON_SHORT_LABELS) do
    BOON_LABEL_TO_NAME[label] = fullName
end

-- Icônes codées en dur (chemins d'icônes standards du jeu, toujours présents
-- dans le client) : contrairement à GetItemIcon(), elles s'affichent tout de
-- suite, même si toi ou l'allié n'avez encore jamais eu l'objet en cache.
local BOON_ICON_PATHS = {
    ["Mythical Boon: Ascension"]    = "Interface\\Icons\\Spell_Shadow_DeathPact",
    ["Mythical Boon: Wrathful"]     = "Interface\\Icons\\Ability_Warrior_EndlessRage",
    ["Mythical Boon: Critical"]     = "Interface\\Icons\\Ability_CriticalStrike",
    ["Mythical Boon: Ruthlessness"] = "Interface\\Icons\\Ability_Racial_BloodRage",
    ["Mythical Boon: Momentum"]     = "Interface\\Icons\\Ability_Rogue_Sprint",
    ["Mythical Boon: Piercing"]     = "Interface\\Icons\\Ability_Warrior_PunishingBlow",
    ["Mythical Boon: Adaptation"]   = "Interface\\Icons\\Spell_Nature_EnchantArmor",
    ["Mythical Boon: Bountiful"]    = "Interface\\Icons\\Spell_Nature_UnyeildingStamina",
    ["Mythical Boon: Sanctuary"]    = "Interface\\Icons\\Spell_Holy_PowerWordShield",
    ["Mythical Boon: Sanctified"]   = "Interface\\Icons\\Spell_Holy_FlashHeal",
    ["Mythical Boon: Infinity"]     = "Interface\\Icons\\Spell_Nature_TimeStop",
    ["Mythical Boon: Inquisition"]  = "Interface\\Icons\\Spell_Holy_SearingLight",
    ["Mythical Boon: Bloodlust"]    = "Interface\\Icons\\Spell_Nature_BloodLust",
}

-- Certains boons appliquent en réalité un buff Blizzard "standard" plutôt qu'un
-- buff custom nommé "Mythical Boon: X" -- Bloodlust en est un exemple connu (le
-- buff actif s'appelle littéralement "Bloodlust", pas "Mythical Boon: Bloodlust").
-- Cette table fait le lien entre le nom de l'OBJET et le nom réel du BUFF à
-- surveiller pour l'affichage "actif" + le décompte de durée.
-- Si un autre boon a le même souci, ajoute une ligne ici avec le nom exact du
-- buff (visible via /rbm debug, qui liste chaque buff actif détecté).
local BOON_BUFF_NAME_ALIASES = {
    ["Mythical Boon: Bloodlust"] = "Bloodlust",
}

-- ============================================================
-- Localisation (FR / EN). IMPORTANT : ceci ne traduit QUE l'habillage
-- (titres, boutons, messages) -- jamais les noms de Boon eux-mêmes
-- (DEFAULT_BOON_NAMES) ni leurs diminutifs (BOON_SHORT_LABELS), qui doivent
-- rester des identifiants FIXES : ils servent à matcher les vrais objets du
-- jeu et à communiquer entre addons (un joueur en FR et un joueur en EN
-- doivent continuer à se comprendre).
-- ============================================================

local L = {}
local LOCALES = {
    FR = {
        TITLE_MAIN = "Mes Mythical Boons",
        TITLE_MAIN_NONE = "Mes Mythical Boons (aucun)",
        TITLE_ALLIES = "Boons alliés disponibles",
        TITLE_ALLIES_NONE = "Boons alliés disponibles (aucun)",
        TITLE_TOTAL = "Boon Totale",
        TITLE_TOTAL_NONE = "Boon Totale (aucun)",
        TITLE_OPTIONS = "RacaBoonMenu - Options",
        SUFFIX_PREVIEW = " [APERÇU]",
        SUFFIX_TOTAL_COUNT = " au total",

        ALERT_REACTIVATE_NOW = "Réactive %s maintenant !",
        ALERT_EXPIRE_ALLY = "%s expire dans %ds - %s en a un, utilisez-le !",
        ALERT_EXPIRING_SOON = "%s - 1 min avant expiration !",
        ALERT_DUPLICATE = "%dx %s dans le groupe - coordonnez le stack !",
        CHAT_GOT = "J'ai obtenu ",
        CHAT_USED = "J'ai utilisé ",

        SECTION_ICONS_MAIN = "Icônes - Mes Mythical Boons",
        SECTION_ICONS_TOTAL = "Icônes - Boon Totale",
        SLIDER_ICON_SIZE = "Taille des icônes",
        SLIDER_ICONS_PER_ROW = "Icônes par ligne",

        SECTION_SCALE = "Échelle de chaque fenêtre",
        SLIDER_SCALE_MAIN = "Mes Mythical Boons",
        SLIDER_SCALE_ALLIES = "Boons alliés disponibles",
        SLIDER_SCALE_TOTAL = "Boon Totale",
        SLIDER_SCALE_OPTIONS = "Panneau d'options",

        SECTION_APPEARANCE = "Apparence des fenêtres",
        LABEL_STYLE = "Style :",
        STYLE_MINIMAL = "Minimaliste",
        STYLE_CLASSIC = "Classique (fenêtre Blizzard)",
        STYLE_DARK = "Sombre (opaque)",
        CHECK_LOCK = "Verrouiller la position (masque aussi la croix)",
        CHECK_SHOW_TOTAL_TITLE = "Afficher le total de boons dans le titre",
        CHECK_TITLE_MAIN = "Afficher le titre \"Mes Mythical Boons\"",
        CHECK_TITLE_ALLIES = "Afficher le titre \"Boons alliés disponibles\"",
        CHECK_TITLE_TOTAL = "Afficher le titre \"Boon Totale\"",
        SLIDER_OPACITY = "Opacité des fenêtres",
        LABEL_LANGUAGE = "Langue :",

        SECTION_ANNOUNCE = "Annonces",
        CHECK_ANNOUNCE_PICKUP = "Annoncer à l'obtention",
        CHECK_ANNOUNCE_USE = "Annoncer à l'utilisation",
        LABEL_CHANNEL = "Canal :",

        SECTION_AUTO = "Automatisation",
        CHECK_ALLY_SHARE = "Partager mes Boons avec le groupe",
        CHECK_AUTO_SHOW = "Afficher auto. en Mythique (0 ou +)",
        CHECK_DUPLICATE_ALERT = "Alerter si un boon est en doublon dans le groupe",
        CHECK_ENABLE_ALLIES_WINDOW = "Activer la fenêtre \"Boons alliés disponibles\"",
        CHECK_ENABLE_TOTAL_WINDOW = "Activer la fenêtre \"Boon Totale\"",

        SECTION_PREVIEW = "Aperçu",
        PREVIEW_DESC = "Simule boons, alliés fictifs et 1 buff actif (20s) pour tout régler sans donjon.",
        BTN_PREVIEW_ON = "Activer l'aperçu",
        BTN_PREVIEW_OFF = "Désactiver l'aperçu",
        BTN_TEST_ALERTS = "Tester les alertes",
        BTN_TEST_GLOW = "Simuler 1 boon (30s, voir le glow)",

        MINIMAP_LEFT_CLICK = "Clic gauche : options",
        MINIMAP_RIGHT_CLICK = "Clic droit : afficher/masquer les fenêtres",
        MINIMAP_DRAG = "Glisser : déplacer l'icône",

        MSG_PREVIEW_COMBAT_BLOCKED = "le mode aperçu ne peut pas être activé/désactivé en combat (boutons protégés). Réessaie hors combat.",
        MSG_PREVIEW_ON = "mode aperçu activé (boons + alliés fictifs, 1 boon actif simulé 20s).",
        MSG_PREVIEW_OFF = "mode aperçu désactivé.",
        MSG_TEST_COMBAT_BLOCKED = "impossible de lancer le test en combat.",
        MSG_TEST_ISOLATED = "test isolé sur '%s' -- actif 30s (toi + allié fictif), glow/alerte dans les %d dernières secondes.",
        MSG_TEST_ENDED = "test terminé, '%s' repasse en scan normal.",
        MSG_VISUAL_DEFERRED = "ce changement sera appliqué à la fin du combat (boutons protégés).",
        MSG_VISUAL_APPLIED = "nouvelle taille appliquée.",
        MSG_LOCKED = "fenêtres verrouillées (croix de fermeture masquée).",
        MSG_UNLOCKED = "fenêtres déverrouillées (glisser pour déplacer).",
        MSG_DEBUG = "debug ",
        MSG_POS_RESET = "positions réinitialisées.",
        MSG_ADDBOON_USAGE = "usage -> /rbm addboon Mythical Boon: NomExact",
        MSG_ADDBOON_COMBAT = "impossible en combat. Réessaie hors combat, puis /reload si besoin.",
        MSG_ADDBOON_EXISTS = "' est déjà enregistré.",
        MSG_ADDBOON_ADDED = "' ajouté et cliquable dès maintenant.",
        MSG_UNKNOWN_BOON = "Boon inconnu détecté -> '",
        MSG_MACRO_EXECUTED = "macro exécutée -> ",
        MSG_REGISTER_FAILED = "impossible d'enregistrer '",
        MSG_DEBUG_ACTIVE_BUFF = "buff actif -> '%s'",
        MSG_DEBUG_AUTO_VIS = "UpdateAutoVisibility -> %s",
        STATE_ENABLED = "activé",
        STATE_DISABLED = "désactivé",
        MSG_ADDBOON_HINT_PREFIX = "Tape /rbm addboon ",
        MSG_ADDBOON_HINT_SUFFIX = " pour l'ajouter.",
    },
    EN = {
        TITLE_MAIN = "My Mythical Boons",
        TITLE_MAIN_NONE = "My Mythical Boons (none)",
        TITLE_ALLIES = "Allies' Available Boons",
        TITLE_ALLIES_NONE = "Allies' Available Boons (none)",
        TITLE_TOTAL = "Total Boons",
        TITLE_TOTAL_NONE = "Total Boons (none)",
        TITLE_OPTIONS = "RacaBoonMenu - Options",
        SUFFIX_PREVIEW = " [PREVIEW]",
        SUFFIX_TOTAL_COUNT = " total",

        ALERT_REACTIVATE_NOW = "Reactivate %s now!",
        ALERT_EXPIRE_ALLY = "%s expires in %ds - %s has one, use it!",
        ALERT_EXPIRING_SOON = "%s - 1 min before expiring!",
        ALERT_DUPLICATE = "%dx %s in the group - coordinate the stack!",
        CHAT_GOT = "I got ",
        CHAT_USED = "I used ",

        SECTION_ICONS_MAIN = "Icons - My Mythical Boons",
        SECTION_ICONS_TOTAL = "Icons - Total Boons",
        SLIDER_ICON_SIZE = "Icon size",
        SLIDER_ICONS_PER_ROW = "Icons per row",

        SECTION_SCALE = "Scale of each window",
        SLIDER_SCALE_MAIN = "My Mythical Boons",
        SLIDER_SCALE_ALLIES = "Allies' Available Boons",
        SLIDER_SCALE_TOTAL = "Total Boons",
        SLIDER_SCALE_OPTIONS = "Options panel",

        SECTION_APPEARANCE = "Window appearance",
        LABEL_STYLE = "Style:",
        STYLE_MINIMAL = "Minimal",
        STYLE_CLASSIC = "Classic (Blizzard window)",
        STYLE_DARK = "Dark (opaque)",
        CHECK_LOCK = "Lock position (also hides the close button)",
        CHECK_SHOW_TOTAL_TITLE = "Show total boon count in the title",
        CHECK_TITLE_MAIN = "Show title \"My Mythical Boons\"",
        CHECK_TITLE_ALLIES = "Show title \"Allies' Available Boons\"",
        CHECK_TITLE_TOTAL = "Show title \"Total Boons\"",
        SLIDER_OPACITY = "Window opacity",
        LABEL_LANGUAGE = "Language:",

        SECTION_ANNOUNCE = "Announcements",
        CHECK_ANNOUNCE_PICKUP = "Announce on pickup",
        CHECK_ANNOUNCE_USE = "Announce on use",
        LABEL_CHANNEL = "Channel:",

        SECTION_AUTO = "Automation",
        CHECK_ALLY_SHARE = "Share my Boons with the group",
        CHECK_AUTO_SHOW = "Auto-show in Mythic (0 or +)",
        CHECK_DUPLICATE_ALERT = "Alert when a boon is duplicated in the group",
        CHECK_ENABLE_ALLIES_WINDOW = "Enable the \"Allies' Available Boons\" window",
        CHECK_ENABLE_TOTAL_WINDOW = "Enable the \"Total Boons\" window",

        SECTION_PREVIEW = "Preview",
        PREVIEW_DESC = "Simulates boons, fake allies, and 1 active buff (20s) to set everything up without a dungeon.",
        BTN_PREVIEW_ON = "Enable preview",
        BTN_PREVIEW_OFF = "Disable preview",
        BTN_TEST_ALERTS = "Test alerts",
        BTN_TEST_GLOW = "Simulate 1 boon (30s, see the glow)",

        MINIMAP_LEFT_CLICK = "Left-click: options",
        MINIMAP_RIGHT_CLICK = "Right-click: show/hide windows",
        MINIMAP_DRAG = "Drag: move the icon",

        MSG_PREVIEW_COMBAT_BLOCKED = "preview mode can't be toggled in combat (protected buttons). Try again out of combat.",
        MSG_PREVIEW_ON = "preview mode enabled (boons + fake allies, 1 boon simulated active for 20s).",
        MSG_PREVIEW_OFF = "preview mode disabled.",
        MSG_TEST_COMBAT_BLOCKED = "can't start the test in combat.",
        MSG_TEST_ISOLATED = "isolated test on '%s' -- active 30s (you + fake ally), glow/alert in the last %d seconds.",
        MSG_TEST_ENDED = "test finished, '%s' is back to normal scanning.",
        MSG_VISUAL_DEFERRED = "this change will apply at the end of combat (protected buttons).",
        MSG_VISUAL_APPLIED = "new size applied.",
        MSG_LOCKED = "windows locked (close button hidden).",
        MSG_UNLOCKED = "windows unlocked (drag to move).",
        MSG_DEBUG = "debug ",
        MSG_POS_RESET = "positions reset.",
        MSG_ADDBOON_USAGE = "usage -> /rbm addboon Mythical Boon: ExactName",
        MSG_ADDBOON_COMBAT = "can't do this in combat. Try again out of combat, then /reload if needed.",
        MSG_ADDBOON_EXISTS = "' is already registered.",
        MSG_ADDBOON_ADDED = "' added and clickable right away.",
        MSG_UNKNOWN_BOON = "Unknown Boon detected -> '",
        MSG_MACRO_EXECUTED = "macro executed -> ",
        MSG_REGISTER_FAILED = "could not register '",
        MSG_DEBUG_ACTIVE_BUFF = "active buff -> '%s'",
        MSG_DEBUG_AUTO_VIS = "UpdateAutoVisibility -> %s",
        STATE_ENABLED = "enabled",
        STATE_DISABLED = "disabled",
        MSG_ADDBOON_HINT_PREFIX = "Type /rbm addboon ",
        MSG_ADDBOON_HINT_SUFFIX = " to add it.",
    },
}

local function ApplyLocale()
    local lang = (RacaBoonMenuDB and RacaBoonMenuDB.options and RacaBoonMenuDB.options.language) or "FR"
    local source = LOCALES[lang] or LOCALES.FR
    for k, v in pairs(source) do L[k] = v end
end
ApplyLocale()   -- valeurs FR par défaut disponibles dès le chargement, avant EnsureDB

local pendingVisualRefresh = false   -- true si un changement de taille attend la fin du combat
local pendingVisibilityRecheck = 0   -- >0 = nombre de secondes avant de revérifier UpdateAutoVisibility

-- [nom du boon] = GetTime() du dernier clic local sur ce boon. Le clic ne fait
-- QUE poser ce drapeau ; le "/say I used" n'est envoyé que lorsque le buff
-- apparaît réellement (voir RefreshActiveBoonState), donc peu importe le
-- nombre de clics (spam, ratés à cause du GCD, etc.), un seul message part
-- par utilisation réellement confirmée.
local pendingUseFlags = {}
local PENDING_USE_WINDOW = 5   -- secondes avant qu'un clic "en attente" soit considéré périmé

-- Mode aperçu : simule tous les boons "en réserve" pour régler taille/position/
-- grille sans avoir besoin d'être en donjon. Jamais sauvegardé (state de session
-- uniquement) ; désactivé automatiquement à la reconnexion.
local previewMode = false
-- [nom du boon] : pendant un test isolé ("Simuler 1 boon"), RefreshMainWindow
-- ignore complètement CE boon (ne le remplace pas par le vrai scan des sacs),
-- pour pouvoir tester UN SEUL boon sans faire apparaître les 13 d'un coup
-- comme le fait le mode aperçu complet.
local testLockName = nil

-- ============================================================
-- SavedVariables par défaut
-- ============================================================

local function EnsureDB()
    if type(RacaBoonMenuDB) ~= "table" then
        RacaBoonMenuDB = {}
    end
    if not RacaBoonMenuDB.mainPos then
        RacaBoonMenuDB.mainPos = { point = "CENTER", x = -200, y = 150 }
    end
    if not RacaBoonMenuDB.alliesPos then
        RacaBoonMenuDB.alliesPos = { point = "CENTER", x = 200, y = 150 }
    end
    if not RacaBoonMenuDB.totalPos then
        RacaBoonMenuDB.totalPos = { point = "CENTER", x = 200, y = -100 }
    end
    if not RacaBoonMenuDB.optionsPos then
        RacaBoonMenuDB.optionsPos = { point = "CENTER", x = 0, y = 90 }
    end
    if RacaBoonMenuDB.locked == nil then
        RacaBoonMenuDB.locked = true
    end
    if not RacaBoonMenuDB.customBoons then
        RacaBoonMenuDB.customBoons = {}
    end
    if RacaBoonMenuDB.minimapAngle == nil then
        RacaBoonMenuDB.minimapAngle = 215
    end
    if not RacaBoonMenuDB.options then
        RacaBoonMenuDB.options = {}
    end
    local o = RacaBoonMenuDB.options
    -- Migration depuis l'ancien réglage unique (partagé entre fenêtres) vers
    -- des réglages séparés par fenêtre.
    if o.iconSize and not o.iconSizeMain then o.iconSizeMain = o.iconSize end
    if o.iconsPerRow and not o.iconsPerRowMain then o.iconsPerRowMain = o.iconsPerRow end

    if not o.iconSizeMain then o.iconSizeMain = 36 end
    if not o.iconsPerRowMain then o.iconsPerRowMain = 7 end
    if not o.iconSizeTotal then o.iconSizeTotal = 36 end
    if not o.iconsPerRowTotal then o.iconsPerRowTotal = 13 end
    if o.sayOnPickup == nil then o.sayOnPickup = true end
    if o.sayOnUse == nil then o.sayOnUse = true end
    if not o.announceChannel then o.announceChannel = "PARTY" end
    if o.allyShareEnabled == nil then o.allyShareEnabled = true end
    if o.autoShowInDungeon == nil then o.autoShowInDungeon = true end
    if o.alertOnDuplicateBoon == nil then o.alertOnDuplicateBoon = true end
    if o.totalWindowEnabled == nil then o.totalWindowEnabled = true end
    if o.alliesWindowEnabled == nil then o.alliesWindowEnabled = true end
    if not o.frameStyle then o.frameStyle = "minimal" end
    if o.showTotalCount == nil then o.showTotalCount = true end
    if not o.windowOpacity then o.windowOpacity = 1.0 end
    if o.showTitleTextMain == nil then o.showTitleTextMain = true end
    if o.showTitleTextAllies == nil then o.showTitleTextAllies = true end
    if o.showTitleTextTotal == nil then o.showTitleTextTotal = true end
    if not o.mainScale then o.mainScale = 1.0 end
    if not o.alliesScale then o.alliesScale = 1.0 end
    if not o.totalScale then o.totalScale = 0.55 end
    if not o.optionsScale then o.optionsScale = 0.8 end
    if not o.language then o.language = "FR" end
    ApplyLocale()

    ICON_SIZE = o.iconSizeMain
    ICONS_PER_ROW = o.iconsPerRowMain
end

-- ============================================================
-- Utilitaires
-- ============================================================

local function IsBoonName(name)
    if not name then return false end
    return string.find(name, BOON_PATTERN, 1, true) ~= nil
end

-- "Mythical Boon: Adaptation" -> "Adaptation"
local function GetShortBoonName(fullName)
    if not fullName then return "?" end
    local short = string.match(fullName, "^Mythical Boon:%s*(.+)$")
    return short or fullName
end

-- Label court affiché sous l'icône (façon WeakAura : "Dmg", "Crit", "CD"...)
local function GetBoonLabel(fullName)
    return BOON_SHORT_LABELS[fullName] or GetShortBoonName(fullName)
end

-- Icône associée à un nom complet de boon : d'abord la table codée en dur
-- (toujours disponible), sinon on retente via le cache d'objets en filet.
local function GetBoonIcon(fullName)
    return BOON_ICON_PATHS[fullName] or (GetItemIcon and GetItemIcon(fullName))
end

-- Icône associée à un diminutif (utilisé pour afficher les boons des alliés).
local function GetBoonIconByLabel(label)
    local fullName = BOON_LABEL_TO_NAME[label]
    if not fullName then return nil end
    return GetBoonIcon(fullName)
end

-- Renvoie la liste combinée des noms de Boon connus (par défaut + ajoutés
-- manuellement). Mise en cache : cette fonction est appelée très souvent
-- (à chaque changement de buff, à chaque BAG_UPDATE en aperçu...) alors que
-- la liste elle-même ne change quasiment jamais (seulement via /rbm addboon,
-- qui appelle InvalidateBoonNamesCache ci-dessous).
local cachedBoonNames = nil
local cachedBuffNameToItem = nil

local function InvalidateBoonNamesCache()
    cachedBoonNames = nil
    cachedBuffNameToItem = nil
end

local function GetRegisteredBoonNames()
    if cachedBoonNames then return cachedBoonNames end
    local names = {}
    for _, n in ipairs(DEFAULT_BOON_NAMES) do table.insert(names, n) end
    for _, n in ipairs(RacaBoonMenuDB.customBoons or {}) do table.insert(names, n) end
    cachedBoonNames = names
    return names
end

-- Table [nom du buff réel] -> [nom de l'objet enregistré] (voir
-- BOON_BUFF_NAME_ALIASES pour les cas comme Bloodlust). Mise en cache pour la
-- même raison que ci-dessus : utilisée à chaque changement de buff du joueur.
local function GetBuffNameToItemMap()
    if cachedBuffNameToItem then return cachedBuffNameToItem end
    local map = {}
    for _, itemName in ipairs(GetRegisteredBoonNames()) do
        local buffName = BOON_BUFF_NAME_ALIASES[itemName] or itemName
        map[buffName] = itemName
    end
    cachedBuffNameToItem = map
    return map
end

-- Renvoie la liste des unités à observer : le joueur + son groupe/raid
local function GetGroupUnits()
    local units = {}
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            table.insert(units, "raid" .. i)
        end
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        table.insert(units, "player")
        for i = 1, GetNumPartyMembers() do
            table.insert(units, "party" .. i)
        end
    else
        table.insert(units, "player")
    end
    return units
end

local function GetBroadcastChannel()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

-- Canal utilisé pour les annonces "/say" / "/p" (option choisie par l'utilisateur).
-- Si "PARTY" est choisi mais qu'on est en raid, on bascule sur RAID (sinon le
-- message ne serait vu que par le sous-groupe) ; si on est seul, on repli sur SAY.
local function GetAnnounceChannel()
    local choice = RacaBoonMenuDB.options.announceChannel or "SAY"
    if choice == "PARTY" then
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            return "RAID"
        elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
            return "PARTY"
        else
            return "SAY"
        end
    end
    return "SAY"
end

-- ============================================================
-- Styles de fenêtre (plusieurs présentations au choix dans les options)
-- ============================================================

local FRAME_STYLES = {
    minimal = {
        label = "Minimaliste (transparent)",
        bgColor = { 0, 0, 0, 0.12 },
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        borderColor = { 1, 1, 1, 0.25 },
        titleAlpha = 0.8,
    },
    classic = {
        label = "Classique (fenêtre Blizzard)",
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        tile = true, tileSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
        borderColor = { 1, 1, 1, 1 },
        titleAlpha = 1,
    },
    dark = {
        label = "Sombre (opaque)",
        bgColor = { 0.03, 0.03, 0.03, 0.85 },
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        borderColor = { 0.5, 0.1, 0.1, 1 },
        titleAlpha = 1,
    },
}

local function ApplyFrameStyle(frame, titleOptionKey)
    local styleKey = RacaBoonMenuDB.options.frameStyle or "minimal"
    local style = FRAME_STYLES[styleKey] or FRAME_STYLES.minimal
    local opacity = RacaBoonMenuDB.options.windowOpacity or 1.0

    if frame.bg then
        if style.bgColor then
            frame.bg:Show()
            frame.bg:SetTexture(style.bgColor[1], style.bgColor[2], style.bgColor[3], style.bgColor[4] * opacity)
        else
            frame.bg:Hide()
        end
    end

    frame:SetBackdrop({
        bgFile = style.bgFile,
        edgeFile = style.edgeFile,
        edgeSize = style.edgeSize,
        tile = style.tile,
        tileSize = style.tileSize,
        insets = style.insets or { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local bc = style.borderColor
    frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] * opacity)
    if style.bgFile then
        frame:SetBackdropColor(1, 1, 1, opacity)
    end
    if frame.titleText then
        local showTitle = titleOptionKey == nil or RacaBoonMenuDB.options[titleOptionKey] ~= false
        if not showTitle then
            frame.titleText:Hide()
        else
            frame.titleText:Show()
            frame.titleText:SetAlpha(style.titleAlpha)
        end
    end
end

-- ============================================================
-- Création d'une fenêtre générique (base commune aux deux menus)
-- ============================================================

local function CreateBaseWindow(name, title, savedPosKey, titleOptionKey, iconSize, iconsPerRow)
    iconSize = iconSize or ICON_SIZE
    iconsPerRow = iconsPerRow or ICONS_PER_ROW

    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(iconsPerRow * (iconSize + ICON_PADDING) + 20, 90)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame.titleOptionKey = titleOptionKey
    frame.iconSize = iconSize
    frame.iconsPerRow = iconsPerRow

    frame:SetScript("OnDragStart", function(self)
        if not RacaBoonMenuDB.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        RacaBoonMenuDB[savedPosKey] = { point = point, x = x, y = y }
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    frame.bg = bg

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", frame, "TOP", 0, -8)
    titleText:SetText(title)
    frame.titleText = titleText

    ApplyFrameStyle(frame, titleOptionKey)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeBtn:SetAlpha(0.6)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    frame.closeBtn = closeBtn
    if RacaBoonMenuDB.locked then closeBtn:Hide() end

    local iconHolder = CreateFrame("Frame", nil, frame)
    iconHolder:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -28)
    iconHolder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    frame.iconHolder = iconHolder
    frame.iconButtons = {}
    frame.boonButtons = {}       -- [nom du boon] = bouton (fenêtre principale uniquement)
    frame.rows = {}              -- lignes de texte (fenêtre alliés uniquement)
    frame.nextButtonIndex = 1

    return frame
end

-- ============================================================
-- Grille d'icônes : positionnement + redimensionnement
-- ============================================================

local function LayoutIcons(frame, count, labelHeight)
    labelHeight = labelHeight or 0
    local size = frame.iconSize or ICON_SIZE
    local perRow = frame.iconsPerRow or ICONS_PER_ROW
    local rows = math.max(1, math.ceil(count / perRow))
    local cols = math.min(math.max(count, 1), perRow)
    local rowHeight = size + ICON_PADDING + labelHeight

    local width  = cols * (size + ICON_PADDING) + 20
    local height = rows * rowHeight + 40

    frame:SetSize(math.max(width, 140), height)

    for i, btn in ipairs(frame.iconButtons) do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", frame.iconHolder, "TOPLEFT",
            col * (size + ICON_PADDING),
            -row * rowHeight)
    end
end

-- ============================================================
-- Récupère/étend le pool de boutons icônes d'une fenêtre
-- ============================================================

-- Met à jour le cadran de cooldown (GCD ou cooldown propre de l'objet) d'un
-- bouton "Boon". Frame non sécurisé -> appelable à tout moment, même en combat.
-- Reste visible même pendant qu'un buff actif s'affiche (utile pour savoir
-- quand recliquer et stacker/prolonger).
-- Affiche/masque le "Pixel Glow" (façon WeakAura) d'un bouton -- 8 petits
-- points lumineux sur le contour, pas des étincelles éparpillées ni un cadre
-- statique. Simples textures, pas de frame séparé -> libre d'utilisation à
-- tout moment, combat inclus.
local function ShowBoonGlow(btn)
    if not btn.pixelGlowPoints or btn.glowActive then return end
    btn.glowActive = true
    for _, px in ipairs(btn.pixelGlowPoints) do px:Show() end
end

local function HideBoonGlow(btn)
    if not btn.pixelGlowPoints or not btn.glowActive then return end
    btn.glowActive = false
    for _, px in ipairs(btn.pixelGlowPoints) do px:Hide() end
end

-- Bordure rouge vif, spécifique aux dernières secondes (voir
-- URGENT_REACTIVATE_THRESHOLD) d'un BUFF ACTIF
-- (signal "réactive maintenant !"), en plus du glow doré habituel.
local function ShowBoonUrgentBorder(btn)
    if not btn.urgentBorderTexture or btn.urgentBorderActive then return end
    btn.urgentBorderActive = true
    btn.urgentBorderTexture:Show()
end

local function HideBoonUrgentBorder(btn)
    if not btn.urgentBorderTexture or not btn.urgentBorderActive then return end
    btn.urgentBorderActive = false
    btn.urgentBorderTexture:Hide()
end

local function UpdateBoonCooldown(btn)
    if not btn.cooldownFrame or not btn.boonName then return end
    btn.cooldownFrame:Show()

    local start, duration = GetItemCooldown(btn.boonName)
    if not start or not duration or duration == 0 then
        -- Beaucoup de ces objets n'ont pas de cooldown propre : seule la barre
        -- de GCD générale (partagée par toutes les actions) les bloque. Le
        -- spell 61304 est le "(Global Cooldown)" interne, universel, qui
        -- reflète ce GCD peu importe ce qui l'a déclenché.
        local gStart, gDuration = GetSpellCooldown(61304)
        if gStart and gDuration and gDuration > 0 then
            start, duration = gStart, gDuration
        end
    end

    if start and duration and duration > 0 then
        btn.cooldownFrame:SetCooldown(start, duration)
    else
        btn.cooldownFrame:SetCooldown(0, 0)
    end
end

-- Calcule les 8 positions (haut, droite, bas, gauche x2 chacun) autour du
-- contour d'une icône de taille "size", pour le "Pixel Glow" façon WeakAura.
local function GetPixelGlowOffsets(size)
    local half = size * 0.62
    return {
        { -half * 0.5, half },  { half * 0.5, half },   -- haut
        { half, half * 0.5 },   { half, -half * 0.5 },  -- droite
        { half * 0.5, -half },  { -half * 0.5, -half }, -- bas
        { -half, -half * 0.5 }, { -half, half * 0.5 },  -- gauche
    }
end

local function GetOrCreateButton(frame, index, clickable)
    local btn = frame.iconButtons[index]
    if btn then return btn end

    local size = frame.iconSize or ICON_SIZE
    local template = clickable and "SecureActionButtonTemplate" or nil
    btn = CreateFrame("Button", nil, frame.iconHolder, template)
    btn:SetSize(size, size)

    -- Juste l'icône, pas de carré/cadre de fond -> look flottant et transparent.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(true)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    countText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn.countText = countText

    -- Label court permanent sous l'icône, façon WeakAura ("Dmg", "Crit", "CD"...)
    -- Commun aux boutons cliquables ET non-cliquables (ex: fenêtre "Boon Totale").
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    btn.shortLabel = label

    if clickable then
        -- Décompte de durée, affiché juste au-dessus du label quand le buff est actif
        local duration = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        duration:SetPoint("TOP", btn, "BOTTOM", 0, -1)
        duration:SetTextColor(1, 0.82, 0.1, 1)
        duration:Hide()
        btn.durationText = duration
        -- Le label doit laisser la place à la ligne de durée au-dessus.
        label:ClearAllPoints()
        label:SetPoint("TOP", btn, "BOTTOM", 0, -14)

        -- Cadran de cooldown (swipe sombre) pour visualiser le GCD/CD de l'objet.
        -- C'est un simple enfant "Cooldown", PAS un template sécurisé : on peut
        -- l'actualiser à tout moment, y compris en plein combat, sans restriction.
        local cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cooldown:SetAllPoints(btn)
        cooldown:SetDrawEdge(false)
        cooldown:SetReverse(false)
        btn.cooldownFrame = cooldown

        -- "Pixel Glow" façon WeakAura : 8 petits points lumineux répartis sur
        -- le contour de l'icône, dont l'opacité défile en cascade (chenillard)
        -- -- simples textures, jamais de souci de sécurité, contrairement à
        -- AutoCastShine (étincelles jugées trop "pointillé") ou un cadre fixe
        -- (jugé trop statique).
        local pixelGlowPoints = {}
        for i, off in ipairs(GetPixelGlowOffsets(size)) do
            local px = btn:CreateTexture(nil, "OVERLAY")
            px:SetTexture("Interface\\Buttons\\WHITE8x8")
            px:SetBlendMode("ADD")
            px:SetVertexColor(1, 0.75, 0, 1)
            px:SetSize(8, 8)
            px:SetPoint("CENTER", btn, "CENTER", off[1], off[2])
            px:Hide()
            pixelGlowPoints[i] = px
        end
        btn.pixelGlowPoints = pixelGlowPoints
        btn.glowActive = false

        -- Glow "starburst" rouge vif, spécifique aux dernières secondes (voir
        -- URGENT_REACTIVATE_THRESHOLD) d'un
        -- buff ACTIF (signal "réactive maintenant !"), façon glow WeakAura --
        -- plus voyant qu'une simple bordure. Pas d'AnimationGroup ici
        -- (contrairement à une version précédente) : btn:CreateAnimationGroup()
        -- sur le bouton SÉCURISÉ lui-même cassait tout au chargement. La
        -- pulsation (alpha + taille + rotation) est calculée à la place dans le
        -- heartbeat général et appliquée via de simples appels sur la texture.
        local urgentBorder = btn:CreateTexture(nil, "OVERLAY")
        urgentBorder:SetTexture("Interface\\Cooldown\\star4")
        urgentBorder:SetBlendMode("ADD")
        urgentBorder:SetVertexColor(1, 0.1, 0.05, 1)
        urgentBorder:SetPoint("CENTER", btn, "CENTER", 0, 0)
        urgentBorder:SetSize(size * 1.8, size * 1.8)
        urgentBorder:Hide()
        btn.urgentBorderTexture = urgentBorder
    end

    -- Léger surlignage au survol uniquement (pas de cadre permanent).
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("CENTER", btn, "CENTER", 0, 0)
    border:SetSize(size * 1.4, size * 1.4)
    border:Hide()
    btn.border = border

    btn:SetScript("OnEnter", function(self)
        self.border:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.bag and self.slot then
            GameTooltip:SetBagItem(self.bag, self.slot)
        elseif self.boonName then
            GameTooltip:SetText(self.boonName)
        elseif self.unitName and self.spellName then
            GameTooltip:SetText(self.spellName)
            GameTooltip:AddLine(self.unitName, 1, 1, 1)
        elseif self.spellName then
            GameTooltip:SetText(self.spellName)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self.border:Hide()
        GameTooltip:Hide()
    end)

    if clickable then
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetAttribute("type", "macro")
        btn:SetScript("PostClick", function(self)
            if RacaBoonMenuDB and RacaBoonMenuDB.debug then
                print("|cff33ff99RacaBoonMenu|r : " .. L.MSG_MACRO_EXECUTED .. tostring(self:GetAttribute("macrotext")))
            end
            UpdateBoonCooldown(self)

            -- On ne fait QUE poser le drapeau ici : le message n'est envoyé que
            -- si le buff apparaît vraiment (RefreshActiveBoonState). Spammer le
            -- clic ne spamme donc jamais le chat -- au pire ça repousse juste
            -- l'horodatage du drapeau.
            if self.boonName then
                pendingUseFlags[self.boonName] = GetTime()
            end
        end)
    end

    frame.iconButtons[index] = btn
    return btn
end

-- Applique la taille d'icône courante à tous les boutons déjà créés.
-- NE DOIT être appelée que hors combat pour les boutons sécurisés (mainFrame).
local function ApplyIconSizeToButtons(frame)
    local size = frame.iconSize or ICON_SIZE
    for _, btn in ipairs(frame.iconButtons) do
        btn:SetSize(size, size)
        btn.border:SetSize(size * 1.4, size * 1.4)
        if btn.pixelGlowPoints then
            local offsets = GetPixelGlowOffsets(size)
            for i, px in ipairs(btn.pixelGlowPoints) do
                if offsets[i] then
                    px:ClearAllPoints()
                    px:SetPoint("CENTER", btn, "CENTER", offsets[i][1], offsets[i][2])
                end
            end
        end
        if btn.urgentBorderTexture then
            btn.urgentBorderTexture:SetSize(size * 1.8, size * 1.8)
        end
    end
end

-- ============================================================
-- Enregistrement des boutons "Boon" (fenêtre principale)
-- ============================================================

local function RegisterBoonButton(frame, name)
    if frame.boonButtons[name] then return frame.boonButtons[name] end

    local index = frame.nextButtonIndex
    local btn = GetOrCreateButton(frame, index, true)
    btn.boonName = name
    if btn.shortLabel then
        btn.shortLabel:SetText(GetBoonLabel(name))
    end

    -- Icône par défaut dès l'enregistrement, même sans posséder le boon (table
    -- codée en dur -> toujours disponible, pas besoin d'avoir vu l'objet).
    local defaultIcon = GetBoonIcon(name)
    if defaultIcon then
        btn.icon:SetTexture(defaultIcon)
    end

    -- On utilise une macro plutôt que type="item" : "/click StaticPopup1Button1"
    -- confirme automatiquement toute popup de confirmation que le jeu pourrait
    -- afficher à l'utilisation (c'est souvent pour ça qu'il fallait cliquer 2 fois).
    local ok, err = pcall(function()
        btn:SetAttribute("macrotext", "/use " .. name .. "\n/click StaticPopup1Button1")
    end)
    if not ok and RacaBoonMenuDB and RacaBoonMenuDB.debug then
        print("|cffff0000RacaBoonMenu debug|r : " .. L.MSG_REGISTER_FAILED .. name .. "' -> " .. tostring(err))
    end

    -- Invisible tant qu'on n'a pas le boon en sac (rien à afficher = rien à voir).
    btn:SetAlpha(0)

    frame.boonButtons[name] = btn
    frame.nextButtonIndex = index + 1
    return btn
end

local function RegisterAllKnownBoons(frame)
    for _, name in ipairs(GetRegisteredBoonNames()) do
        RegisterBoonButton(frame, name)
    end
    LayoutIcons(frame, #frame.iconButtons, 26)
end

-- ============================================================
-- Partage des Boons avec les alliés (communication inter-addon)
-- ============================================================

local mainFrame -- déclaré ici, utilisé par plusieurs fonctions plus bas (RefreshAlliesWindow, BuildMyBoonMessage...)
local RefreshMainWindow -- idem : défini plus bas, appelé par RefreshActiveBoonState avant
local GetGroupTotalCount -- idem : défini plus bas, utilisé par RefreshAlliesWindow avant

local allyBoonData = {}   -- [nomJoueur] = { [nomCourtDuBoon] = quantité, ... }
local alliesFrame   -- "Boons alliés disponibles" : liste texte détaillée par allié
local totalFrame    -- "Boon Totale" : grille d'icônes, total du groupe

-- ============================================================
-- Fenêtre "Boons alliés disponibles" : liste texte détaillée, un allié par
-- ligne avec ses boons en réserve (nom + icône), telle qu'elle existait avant.
-- ============================================================

local function RefreshAlliesWindow()
    if not alliesFrame or not alliesFrame:IsShown() then return end

    local names = {}
    for name in pairs(allyBoonData) do table.insert(names, name) end
    table.sort(names)

    local function GetOrCreateAllyRow(index)
        local row = alliesFrame.rows[index]
        if row then return row end
        row = alliesFrame.iconHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetJustifyH("LEFT")
        row:SetWidth(260)
        alliesFrame.rows[index] = row
        return row
    end

    local rowIndex = 0
    local yOffset = 0
    for _, name in ipairs(names) do
        local boons = allyBoonData[name]
        local parts = {}
        for boonName, count in pairs(boons) do
            if count and count > 0 then
                local icon = GetBoonIconByLabel(boonName)
                local iconMarkup = icon and ("|T" .. icon .. ":14:14|t") or ""
                local display = count > 1 and (boonName .. " x" .. count) or boonName
                table.insert(parts, { label = boonName, text = iconMarkup .. display })
            end
        end
        if #parts > 0 then
            -- Trié sur le LABEL uniquement (pas le texte complet, qui inclurait
            -- le code d'icône et casserait l'ordre alphabétique attendu).
            table.sort(parts, function(a, b) return a.label < b.label end)
            local textParts = {}
            for _, p in ipairs(parts) do table.insert(textParts, p.text) end

            rowIndex = rowIndex + 1
            local row = GetOrCreateAllyRow(rowIndex)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", alliesFrame.iconHolder, "TOPLEFT", 0, -yOffset)
            row:SetText("|cffffd100" .. name .. "|r: " .. table.concat(textParts, ", "))
            row:Show()

            -- Hauteur RÉELLEMENT prise par ce texte (tient compte du retour à la
            -- ligne automatique), pas une estimation fixe par allié.
            yOffset = yOffset + row:GetStringHeight() + 6
        end
    end

    for i = rowIndex + 1, #alliesFrame.rows do
        alliesFrame.rows[i]:Hide()
    end

    local height = math.max(yOffset, 16) + 40
    alliesFrame:SetSize(280, height)

    if rowIndex == 0 then
        alliesFrame.titleText:SetText(L.TITLE_ALLIES_NONE)
    else
        alliesFrame.titleText:SetText(L.TITLE_ALLIES .. " (" .. rowIndex .. ")")
    end
end

-- ============================================================
-- Fenêtre "Boon Totale" : grille d'icônes (même style que "Mes Mythical
-- Boons"), affichant le TOTAL du groupe (toi + tous les alliés qui partagent)
-- pour chaque type de boon. PAS cliquable -- ça reste le rôle exclusif de la
-- fenêtre "Mes Mythical Boons". Grisée quand personne dans le groupe n'a le
-- boon, colorée sinon, avec le total affiché en bas à droite de l'icône.
-- ============================================================

local function RegisterTotalBoonButtons(frame)
    for i, name in ipairs(GetRegisteredBoonNames()) do
        local btn = GetOrCreateButton(frame, i, false)
        btn.boonName = name
        btn.shortLabel:SetText(GetBoonLabel(name))
        local defaultIcon = GetBoonIcon(name)
        if defaultIcon then btn.icon:SetTexture(defaultIcon) end
        pcall(function() btn.icon:SetDesaturated(true) end)
        btn:SetAlpha(1)
        btn:Show()
        -- Purement informative : pas de clic, pas de curseur "actionnable".
        btn:EnableMouse(false)
    end
    LayoutIcons(frame, #GetRegisteredBoonNames(), 14)
end

local function RefreshTotalWindow()
    if not totalFrame or not totalFrame:IsShown() then return end

    local shownCount = 0
    for i, name in ipairs(GetRegisteredBoonNames()) do
        local btn = totalFrame.iconButtons[i]
        if btn then
            local total = mainFrame and GetGroupTotalCount(name) or 0
            if total > 0 then
                -- Même icône que partout ailleurs (objet réel), en couleur.
                local icon = GetBoonIcon(name)
                if icon then btn.icon:SetTexture(icon) end
                pcall(btn.icon.SetDesaturated, btn.icon, false)
                btn.countText:SetText(total)
                btn.countText:Show()
                shownCount = shownCount + 1
            else
                -- Aucun boon de ce type dans tout le groupe : icône grisée.
                pcall(btn.icon.SetDesaturated, btn.icon, true)
                btn.countText:Hide()
            end
        end
    end

    if shownCount == 0 then
        totalFrame.titleText:SetText(L.TITLE_TOTAL_NONE)
    else
        totalFrame.titleText:SetText(L.TITLE_TOTAL .. " (" .. shownCount .. ")")
    end
end

local function PruneAllyData()
    local validNames = {}
    for _, unit in ipairs(GetGroupUnits()) do
        if UnitExists(unit) then
            validNames[UnitName(unit)] = true
        end
    end
    local changed = false
    for name in pairs(allyBoonData) do
        if not validNames[name] then
            allyBoonData[name] = nil
            changed = true
        end
    end
    if changed then
        RefreshAlliesWindow()
        RefreshTotalWindow()
    end
end

local function BuildMyBoonMessage()
    local parts = {}
    for name in pairs(mainFrame.boonButtons) do
        local count = mainFrame.lastCounts[name] or 0
        if count > 0 then
            -- On envoie le diminutif ("BL", "AP/SP"...) plutôt que le nom complet :
            -- message plus court, et ça correspond direct au style des icônes.
            table.insert(parts, GetBoonLabel(name) .. ":" .. count)
        end
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

local function BroadcastMyBoons(force)
    if not RacaBoonMenuDB.options.allyShareEnabled then return end
    local channel = GetBroadcastChannel()
    if not channel then return end
    local message = BuildMyBoonMessage()
    if not force and message == mainFrame.lastBroadcast then return end
    mainFrame.lastBroadcast = message
    pcall(SendAddonMessage, ADDON_PREFIX, message, channel)
end

-- ============================================================
-- Total du groupe : utilisé UNIQUEMENT par la fenêtre "Boon Totale" (via
-- RefreshTotalWindow) -- plus de badge en doublon sur "Mes Mythical Boons",
-- puisque cette fenêtre dédiée existe déjà pour ça (ça rendait la fenêtre
-- principale confuse avec deux chiffres différents sur la même icône).
-- ============================================================

function GetGroupTotalCount(name)
    local total = mainFrame.lastCounts[name] or 0
    local label = GetBoonLabel(name)
    for _, boons in pairs(allyBoonData) do
        if boons[label] and boons[label] > 0 then
            total = total + boons[label]
        end
    end
    return total
end

-- ============================================================
-- Alerte "doublon" : quand au moins 2 joueurs du groupe (toi inclus) ont le
-- MÊME type de Boon disponible en même temps. Utile car les Boons stackent et
-- se rafraîchissent à la dernière seconde pour prolonger le buff au maximum --
-- ça vaut le coup de le savoir pour coordonner qui les garde/enchaîne.
-- ============================================================

local duplicateAlerted = {}   -- [diminutif] = true tant que le doublon est actif (anti-spam)

local function CheckDuplicateBoonAlert()
    if not mainFrame or not RacaBoonMenuDB.options.alertOnDuplicateBoon then return end

    local holders = {}   -- [diminutif] = nombre de joueurs (toi + alliés) qui l'ont
    for name in pairs(mainFrame.boonButtons) do
        if (mainFrame.lastCounts[name] or 0) > 0 then
            local label = GetBoonLabel(name)
            holders[label] = (holders[label] or 0) + 1
        end
    end
    for _, boons in pairs(allyBoonData) do
        for label, count in pairs(boons) do
            if count and count > 0 then
                holders[label] = (holders[label] or 0) + 1
            end
        end
    end

    -- Efface l'anti-spam pour les diminutifs qui ne sont plus en doublon
    for label in pairs(duplicateAlerted) do
        if not holders[label] or holders[label] < 2 then
            duplicateAlerted[label] = nil
        end
    end

    for label, count in pairs(holders) do
        if count >= 2 and not duplicateAlerted[label] then
            duplicateAlerted[label] = true
            if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
                RaidNotice_AddMessage(RaidWarningFrame,
                    string.format(L.ALERT_DUPLICATE, count, label),
                    ChatTypeInfo["RAID_WARNING"])
            end
        end
    end
end

local function HandleAllyBoonMessage(sender, message)
    local senderShort = string.match(sender, "^([^-]+)") or sender
    if senderShort == UnitName("player") then return end

    local boons = {}
    for pair in string.gmatch(message, "[^;]+") do
        local n, c = string.match(pair, "^(.-):(%d+)$")
        if n then boons[n] = tonumber(c) end
    end
    allyBoonData[senderShort] = boons
    RefreshAlliesWindow()
    RefreshTotalWindow()
    CheckDuplicateBoonAlert()
end

-- ============================================================
-- Annonce /say "I used X" ET affichage "actif" (icône du buff + décompte),
-- basés sur la même surveillance des buffs Mythical Boon actuellement actifs
-- sur le joueur. Quand le buff tombe, on redemande un RefreshMainWindow pour
-- que la case redevienne invisible (ou revienne au style "en réserve") sans
-- qu'on ait à gérer manuellement toutes les transitions ici.
-- ============================================================

local lastActiveStacks = {}
local hasTrackedOnce = false

-- Suivi du temps depuis la première apparition de chaque boon dans les sacs
-- (les objets "Mythical Boon" expirent au bout de 10 minutes en réserve) --
-- permet d'afficher un décompte même si l'objet n'est pas encore utilisé.
local itemPickupTime = {}
local ITEM_BAG_DURATION = 600  -- 10 minutes, en secondes
local EXPIRING_SOON_THRESHOLD = 60  -- glow d'alerte quand il reste moins d'1 min
local URGENT_REACTIVATE_THRESHOLD = 10  -- bordure rouge vif + alerte "réactive maintenant !" (buff actif)

-- [nom du boon] = true une fois l'alerte "1 min restante" affichée, pour ne la
-- montrer qu'UNE SEULE fois par réserve (pas de spam d'alerte chaque tick).
local expiringWarned = {}

-- [nom du boon] = true une fois l'alerte "réactive maintenant" affichée pour
-- CETTE activation en cours (remise à nil dès que le buff retombe, pour
-- pouvoir réafficher l'alerte à la prochaine activation).
local urgentWarned = {}

local function CheckExpiringSoonAlert(name)
    if not itemPickupTime[name] then
        expiringWarned[name] = nil
        return
    end
    local remaining = itemPickupTime[name] + ITEM_BAG_DURATION - GetTime()
    if remaining <= 0 then
        expiringWarned[name] = nil
    elseif remaining <= EXPIRING_SOON_THRESHOLD and not expiringWarned[name] then
        expiringWarned[name] = true
        if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
            RaidNotice_AddMessage(RaidWarningFrame,
                string.format(L.ALERT_EXPIRING_SOON, GetBoonLabel(name)),
                ChatTypeInfo["RAID_WARNING"])
        end
    end
end

-- Renvoie la liste des alliés (par nom) qui ont encore ce boon en réserve,
-- d'après les données déjà partagées via le système d'addon comm.
local function GetAllyHoldersForBoon(name)
    local label = GetBoonLabel(name)
    local holders = {}
    for allyName, boons in pairs(allyBoonData) do
        if boons[label] and boons[label] > 0 then
            table.insert(holders, allyName)
        end
    end
    return holders
end

-- Alerte "réactive maintenant" quand un buff ACTIF tombe à 10s ou moins --
-- seulement si TOI ou un ALLIÉ a encore un exemplaire disponible en réserve.
-- Le message précise qui peut agir : toi directement, ou qui prévenir.
local function CheckUrgentReactivateAlert(name, remaining, hasSpareInBag, allyHolders)
    if remaining <= 0 then
        urgentWarned[name] = nil
        return
    end
    if remaining <= URGENT_REACTIVATE_THRESHOLD and not urgentWarned[name] then
        local label = GetBoonLabel(name)
        local message
        if hasSpareInBag then
            message = string.format(L.ALERT_REACTIVATE_NOW, label)
        elseif allyHolders and #allyHolders > 0 then
            message = string.format(L.ALERT_EXPIRE_ALLY, label, math.floor(remaining), table.concat(allyHolders, ", "))
        else
            return  -- personne n'a de réserve : rien d'actionnable, pas d'alerte
        end

        urgentWarned[name] = true
        if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
            RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo["RAID_WARNING"])
        end
        pcall(PlaySound, "RaidWarning")
    end
end

local function FormatBoonDuration(remaining)
    if remaining <= 0 then return "" end
    if remaining >= 60 then
        return math.floor(remaining / 60) .. "m"
    end
    return math.floor(remaining) .. "s"
end

local function RefreshActiveBoonState()
    if not mainFrame then return end

    -- Table [nom du buff réel] -> [nom de l'objet enregistré]. Pour la plupart
    -- des boons, buff et objet ont le même nom ; pour les alias connus (voir
    -- BOON_BUFF_NAME_ALIASES, ex: Bloodlust), on fait le lien explicitement.
    local buffNameToItem = GetBuffNameToItemMap()

    local activeByName = {}
    local i = 1
    while true do
        local name, _, icon, count, _, duration, expirationTime = UnitBuff("player", i)
        if not name then break end
        if RacaBoonMenuDB and RacaBoonMenuDB.debug then
            print("|cff888888RacaBoonMenu debug|r : " .. string.format(L.MSG_DEBUG_ACTIVE_BUFF, name))
        end

        local itemName = buffNameToItem[name]
        if not itemName and IsBoonName(name) and mainFrame.boonButtons[name] then
            -- Filet de sécurité : le nom du buff contient "Mythical Boon" et
            -- correspond directement à un objet enregistré, même sans alias.
            itemName = name
        end

        if itemName then
            activeByName[itemName] = { icon = icon, count = count or 1, expirationTime = expirationTime }
        end
        i = i + 1
    end

    local needsFullRefresh = false

    for name, btn in pairs(mainFrame.boonButtons) do
      if testLockName ~= name then
        local active = activeByName[name]
        if active then
            -- IMPORTANT : lastActiveStacks[name] == nil signifie "n'était PAS actif
            -- au dernier contrôle" (voir la branche "else" plus bas qui le remet à
            -- nil), pas "actif avec 0 stack". Un boon qui ne stack pas (ex: Bloodlust)
            -- renvoie count=0 en permanence -> comparer juste les nombres (0 > 0)
            -- ratait donc TOUJOURS sa toute première activation. On distingue donc
            -- explicitement "vient de s'activer" (transition) de "a pris un stack
            -- de plus" (boons qui stackent, ex: Bountiful).
            local prevCount = lastActiveStacks[name]
            local justActivated = (prevCount == nil)
            local stackedFurther = (prevCount ~= nil) and (active.count > prevCount)

            -- On n'annonce que si CE client a un clic "en attente" récent sur ce
            -- boon (évite l'annonce chez tout le groupe pour les boons qui
            -- appliquent le buff à toute l'équipe, comme Bountiful).
            local pendingTime = pendingUseFlags[name]
            if pendingTime and (GetTime() - pendingTime) < PENDING_USE_WINDOW
                and (justActivated or stackedFurther) and RacaBoonMenuDB.options.sayOnUse then
                local _, itemLink = GetItemInfo(name)
                SendChatMessage(L.CHAT_USED .. (itemLink or GetShortBoonName(name)), GetAnnounceChannel())
                pendingUseFlags[name] = nil
            end

            lastActiveStacks[name] = active.count

            -- Actif : on force l'icône du BUFF (peut différer de celle de l'objet)
            -- + le décompte de durée, visible même si l'objet n'est plus en sac.
            -- Le cadran de GCD reste visible même pendant l'affichage du buff actif
            -- (utile : cliquer reste possible pour stacker/prolonger). Le glow
            -- reste caché tant que le buff n'approche pas de l'expiration : le
            -- glow ne sert QUE de signal "il faut le relancer maintenant", pas
            -- d'indicateur permanent "ce buff est actif".
            btn.activeExpiration = active.expirationTime
            btn:SetAlpha(1)
            if active.icon then btn.icon:SetTexture(active.icon) end
            btn.durationText:Show()
            UpdateBoonCooldown(btn)

            -- Affiche les stacks du BUFF actif (pas la quantité en sac).
            if active.count and active.count > 1 then
                btn.countText:SetText(active.count)
                btn.countText:Show()
            else
                btn.countText:Hide()
            end

            -- Glow (pixel + bordure rouge) UNIQUEMENT dans les dernières
            -- secondes (voir URGENT_REACTIVATE_THRESHOLD) ET si j'ai vraiment
            -- un exemplaire de réserve pour stacker -- sinon ce serait
            -- trompeur (rien à cliquer chez moi).
            -- L'alerte, elle, part aussi si un ALLIÉ a une réserve : lui seul
            -- pourra agir, mais ça m'informe pour le prévenir.
            local activeRemaining = active.expirationTime and (active.expirationTime - GetTime())
            local hasSpareInBag = (mainFrame.lastCounts[name] or 0) > 0
            if activeRemaining and activeRemaining <= URGENT_REACTIVATE_THRESHOLD then
                if hasSpareInBag then
                    ShowBoonGlow(btn)
                    ShowBoonUrgentBorder(btn)
                else
                    HideBoonGlow(btn)
                    HideBoonUrgentBorder(btn)
                end
                local allyHolders = hasSpareInBag and nil or GetAllyHoldersForBoon(name)
                CheckUrgentReactivateAlert(name, activeRemaining, hasSpareInBag, allyHolders)
            else
                HideBoonGlow(btn)
                HideBoonUrgentBorder(btn)
                urgentWarned[name] = nil
            end
        else
            lastActiveStacks[name] = nil
            urgentWarned[name] = nil
            HideBoonGlow(btn)
            HideBoonUrgentBorder(btn)
            if btn.activeExpiration then
                -- Vient de s'arrêter : on efface l'état "actif" et on laisse
                -- RefreshMainWindow restaurer le bon état (caché ou en réserve),
                -- y compris la décision de garder ou non le glow (ex: si le
                -- boon en réserve expire encore dans moins d'1 min).
                btn.activeExpiration = nil
                btn.durationText:Hide()
                needsFullRefresh = true
            end
        end
      end
    end
    hasTrackedOnce = true

    if needsFullRefresh and RefreshMainWindow then
        RefreshMainWindow()
    end
end

-- ============================================================
-- Fenêtre 1 : mes Mythical Boons (objets dans les sacs, cliquables)
-- ============================================================

function RefreshMainWindow()
    if not mainFrame or not mainFrame:IsShown() then return end

    local presentByName = {}
    local unrecognized = {}

    if previewMode then
        -- Mode aperçu : on simule que tous les boons connus sont en réserve,
        -- pour régler taille/grille/position sans dépendre d'un vrai donjon.
        for _, itemName in ipairs(GetRegisteredBoonNames()) do
            presentByName[itemName] = {
                icon = GetBoonIcon(itemName), count = math.random(1, 3),
                bag = nil, slot = nil, link = nil,
            }
        end
    else
        for bag = 0, 4 do
            local slots = GetContainerNumSlots(bag)
            for slot = 1, slots do
                local itemLink = GetContainerItemLink(bag, slot)
                if itemLink then
                    local itemName = GetItemInfo(itemLink)
                    if IsBoonName(itemName) then
                        -- En 3.3.5, GetContainerItemInfo renvoie : texture, itemCount, locked, quality, readable, lootable, link
                        local itemIcon, itemCount = GetContainerItemInfo(bag, slot)
                        if not itemIcon then
                            itemIcon = GetItemIcon and GetItemIcon(itemLink) or select(10, GetItemInfo(itemLink))
                        end

                        local entry = presentByName[itemName]
                        if entry then
                            entry.count = (entry.count or 0) + (itemCount or 1)
                        else
                            presentByName[itemName] = {
                                icon = itemIcon, count = itemCount,
                                bag = bag, slot = slot, link = itemLink,
                            }
                        end

                        if not mainFrame.boonButtons[itemName] then
                            unrecognized[itemName] = true
                        end
                    end
                end
            end
        end
    end

    local isFirstRun = not mainFrame.hasRunOnce
    local hasUnrecognized = false
    local shownCount = 0
    local totalItemCount = 0

    for name, btn in pairs(mainFrame.boonButtons) do
      if testLockName == name then
        shownCount = shownCount + 1
      else
        -- Ce boon est sous test isolé si testLockName == name : on ne touche
        -- à RIEN pour lui dans ce cas, le vrai scan des sacs ne doit pas
        -- écraser l'état simulé par SimulateUrgentGlow (icône, réserve,
        -- timer actif...). Tous les autres boons sont traités normalement.
        local data = presentByName[name]
        local newCount = data and (data.count or 1) or 0
        local oldCount = mainFrame.lastCounts[name] or 0

        UpdateBoonCooldown(btn)

        if data then
            btn.bag, btn.slot = data.bag, data.slot
        else
            btn.bag, btn.slot = nil, nil
        end

        -- Suivi de l'heure de récupération, pour le décompte des 10 min en réserve.
        -- On réinitialise à chaque VRAI changement de quantité (nouvelle prise,
        -- ou utilisation partielle) tant qu'il en reste : chaque exemplaire a son
        -- propre décompte de 10 min côté serveur, donc on affiche toujours
        -- l'estimation la plus fraîche plutôt qu'un vieux chiffre figé depuis la
        -- toute première détection (c'était le bug : le timer ne bougeait plus
        -- après avoir utilisé un exemplaire, même s'il en restait un autre).
        if data then
            if not itemPickupTime[name] or newCount ~= oldCount then
                itemPickupTime[name] = GetTime()
                expiringWarned[name] = nil   -- nouvelle estimation -> l'alerte pourra ressortir
            end
        else
            itemPickupTime[name] = nil
            expiringWarned[name] = nil
        end
        if not previewMode then
            CheckExpiringSoonAlert(name)
        end

        -- Si le boon est actuellement actif, RefreshActiveBoonState gère déjà
        -- l'icône (celle du buff) et l'opacité : on ne touche à rien pour ne
        -- pas écraser cet affichage en pleine utilisation.
        if not btn.activeExpiration then
            if data then
                btn.icon:SetTexture(data.icon)
                -- En réserve (pas actif) : pas de chiffre affiché du tout, juste
                -- l'icône + le label, façon affichage d'origine -- ça évite la
                -- confusion avec le décompte de stacks du buff quand il est actif.
                btn.countText:Hide()
                -- Disponible : icône visible, en couleur + décompte des 10 min restantes.
                btn:SetAlpha(1)
                local remaining = itemPickupTime[name] + ITEM_BAG_DURATION - GetTime()
                if remaining > 0 then
                    btn.durationText:SetText(FormatBoonDuration(remaining))
                    btn.durationText:Show()
                    if remaining <= EXPIRING_SOON_THRESHOLD then
                        ShowBoonGlow(btn)
                    else
                        HideBoonGlow(btn)
                    end
                else
                    btn.durationText:Hide()
                    HideBoonGlow(btn)
                end
                shownCount = shownCount + 1
            else
                -- Pas en réserve : totalement invisible, rien à afficher.
                btn:SetAlpha(0)
                btn.countText:Hide()
                btn.durationText:Hide()
                HideBoonGlow(btn)
            end
        elseif data then
            shownCount = shownCount + 1
        else
            -- Actif mais l'objet n'est plus en sac (dernière charge consommée) :
            -- on compte quand même comme "visible" pour le titre de la fenêtre.
            shownCount = shownCount + 1
        end

        if not previewMode and not isFirstRun and newCount > oldCount and RacaBoonMenuDB.options.sayOnPickup then
            local linkOrName = (data and data.link) or GetShortBoonName(name)
            SendChatMessage(L.CHAT_GOT .. linkOrName, GetAnnounceChannel())
        end

        mainFrame.lastCounts[name] = newCount
        if data then
            totalItemCount = totalItemCount + newCount
        end
      end
    end
    mainFrame.hasRunOnce = true

    for _ in pairs(unrecognized) do
        hasUnrecognized = true
        break
    end
    if hasUnrecognized and not InCombatLockdown() then
        for name in pairs(unrecognized) do
            print("|cffffcc00RacaBoonMenu|r : " .. L.MSG_UNKNOWN_BOON .. name ..
                "'. " .. L.MSG_ADDBOON_HINT_PREFIX .. name .. L.MSG_ADDBOON_HINT_SUFFIX)
        end
    end

    if shownCount == 0 then
        mainFrame.titleText:SetText(L.TITLE_MAIN_NONE .. (previewMode and L.SUFFIX_PREVIEW or ""))
    else
        local totalSuffix = ""
        if RacaBoonMenuDB.options.showTotalCount and totalItemCount > 0 then
            totalSuffix = " - " .. totalItemCount .. L.SUFFIX_TOTAL_COUNT
        end
        mainFrame.titleText:SetText(L.TITLE_MAIN .. " (" .. shownCount .. ")" .. totalSuffix .. (previewMode and L.SUFFIX_PREVIEW or ""))
    end

    if not previewMode then
        BroadcastMyBoons(false)
        CheckDuplicateBoonAlert()
    end
    -- IMPORTANT : "Boon Totale" doit aussi refléter MES PROPRES boons, pas
    -- seulement se mettre à jour quand un allié envoie ses données -- c'était
    -- le bug (fenêtre qui semblait ignorer mes boons).
    RefreshTotalWindow()
end

-- ============================================================
-- Application de la position sauvegardée
-- ============================================================

local function ApplySavedPosition(frame, posData)
    frame:ClearAllPoints()
    frame:SetPoint(posData.point or "CENTER", UIParent, posData.point or "CENTER", posData.x or 0, posData.y or 0)
end

-- Verrouillé = position figée ET croix de fermeture cachée (pour éviter toute
-- fermeture accidentelle sur un emplacement qu'on a volontairement figé).
local function ApplyLockState()
    for _, f in ipairs({ mainFrame, alliesFrame, totalFrame }) do
        if f and f.closeBtn then
            if RacaBoonMenuDB.locked then
                f.closeBtn:Hide()
            else
                f.closeBtn:Show()
            end
        end
    end
end

-- ============================================================
-- Affichage manuel / automatique des fenêtres
-- ============================================================

local function AreWindowsShown()
    return mainFrame and mainFrame:IsShown()
end

-- mainFrame contient des boutons SÉCURISÉS (icônes cliquables) : le cacher/
-- afficher pendant le combat est bloqué par Blizzard ("prevented the call of
-- secure function ... Hide()"), même si mainFrame lui-même n'est pas protégé
-- -- masquer un parent masque implicitement ses enfants sécurisés. On reporte
-- donc le changement à la fin du combat si besoin, comme pour le redimensionnement.
local pendingWindowVisibility = nil

local function SetWindowsShown(shouldShow)
    if mainFrame then
        if InCombatLockdown() then
            pendingWindowVisibility = shouldShow
        else
            if shouldShow then mainFrame:Show() else mainFrame:Hide() end
        end
    end
    if alliesFrame then
        if shouldShow and RacaBoonMenuDB.options.alliesWindowEnabled then
            alliesFrame:Show()
        else
            alliesFrame:Hide()
        end
    end
    if totalFrame then
        if shouldShow and RacaBoonMenuDB.options.totalWindowEnabled then
            totalFrame:Show()
        else
            totalFrame:Hide()
        end
    end
    if shouldShow and not InCombatLockdown() then
        RefreshMainWindow()
        RefreshAlliesWindow()
        RefreshTotalWindow()
    end
end

local function ToggleAllWindows()
    SetWindowsShown(not AreWindowsShown())
end

-- Active/désactive le mode aperçu : simule tous les boons "en réserve" pour
-- régler taille/grille/position sans dépendre d'un vrai donjon. Réinitialise le
-- suivi des quantités à la sortie pour éviter tout faux comptage ensuite.
local function TogglePreviewMode()
    if InCombatLockdown() then
        print("|cffff0000RacaBoonMenu|r : " .. L.MSG_PREVIEW_COMBAT_BLOCKED)
        return
    end
    previewMode = not previewMode
    if previewMode then
        if mainFrame and not mainFrame:IsShown() then mainFrame:Show() end
        if alliesFrame and not alliesFrame:IsShown() then alliesFrame:Show() end
        if totalFrame and not totalFrame:IsShown() then totalFrame:Show() end

        -- Simule 2 alliés fictifs pour prévisualiser aussi ces fenêtres.
        allyBoonData["Aperçu-Zarok"] = { Dmg = 2, Crit = 1, Stats = 3, Haste = 1 }
        allyBoonData["Aperçu-Nyra"]  = { BL = 2, DR = 1, Heal = 3 }

        -- IMPORTANT : c'est CETTE ligne qui remplit réellement les quantités
        -- fictives en sac (RefreshMainWindow gère la simulation aléatoire quand
        -- previewMode est actif). Sans elle, "hasSpareInBag" restait toujours
        -- faux et le glow "urgent" ne se déclenchait jamais -- c'était le bug.
        RefreshMainWindow()
        RefreshAlliesWindow()
        RefreshTotalWindow()

        -- Simule UN boon actif (glow doré + décompte + cadran GCD), pour
        -- prévisualiser aussi cet état sans attendre un vrai donjon. Le tick
        -- existant (chaque seconde) prendra le relais automatiquement pour le
        -- décompte, l'alerte à 10s, et le retour à l'état normal à expiration.
        local names = GetRegisteredBoonNames()
        if names[1] and mainFrame and mainFrame.boonButtons[names[1]] then
            local demoBtn = mainFrame.boonButtons[names[1]]
            demoBtn.activeExpiration = GetTime() + 20
            demoBtn.icon:SetTexture(GetBoonIcon(names[1]))
            demoBtn.durationText:Show()
            ShowBoonGlow(demoBtn)
        end

        print("|cff33ff99RacaBoonMenu|r : " .. L.MSG_PREVIEW_ON)
    else
        if mainFrame then
            mainFrame.lastCounts = {}
            mainFrame.hasRunOnce = false
            for _, btn in pairs(mainFrame.boonButtons) do
                itemPickupTime[btn.boonName] = nil
                expiringWarned[btn.boonName] = nil
                if btn.activeExpiration then
                    btn.activeExpiration = nil
                    btn.durationText:Hide()
                    HideBoonGlow(btn)
                    HideBoonUrgentBorder(btn)
                end
            end
        end
        allyBoonData["Aperçu-Zarok"] = nil
        allyBoonData["Aperçu-Nyra"] = nil
        RefreshAlliesWindow()
        RefreshTotalWindow()
        print("|cff33ff99RacaBoonMenu|r : " .. L.MSG_PREVIEW_OFF)
    end
    RefreshMainWindow()
end

-- Déclenche immédiatement les deux alertes (10s + doublon) avec des données
-- fictives, pour les entendre/voir sans attendre les vraies conditions.
local function TestAlerts()
    local names = GetRegisteredBoonNames()
    local demoName = names[1]
    if not demoName then return end

    urgentWarned[demoName] = nil
    CheckUrgentReactivateAlert(demoName, 3, true, nil)

    local demoLabel = GetBoonLabel(demoName)
    duplicateAlerted[demoLabel] = nil
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame,
            string.format(L.ALERT_DUPLICATE, 2, demoLabel),
            ChatTypeInfo["RAID_WARNING"])
    end
end

-- Simule UN SEUL boon (pas les 13 via le mode aperçu complet, trop dur à
-- vérifier isolément) : le rend actif pendant 30 secondes avec un exemplaire
-- de réserve simulé, pour voir en vrai le déclenchement du glow + de
-- l'alerte au passage sous le seuil "urgent" (URGENT_REACTIVATE_THRESHOLD).
-- Simule aussi UN ALLIÉ ayant le même boon en réserve, pour tester en même
-- temps l'affichage "Boons alliés"/"Boon Totale" et l'alerte de doublon --
-- exactement comme en conditions réelles de groupe.
local TEST_ALLY_NAME = "Test-Allié"

local function SimulateUrgentGlow()
    local names = GetRegisteredBoonNames()
    local demoName = names[1]
    if not (demoName and mainFrame) then return end

    if InCombatLockdown() then
        print("|cffff0000RacaBoonMenu|r : " .. L.MSG_TEST_COMBAT_BLOCKED)
        return
    end
    if not mainFrame:IsShown() then mainFrame:Show() end

    local btn = mainFrame.boonButtons[demoName]
    if not btn then return end

    testLockName = demoName
    mainFrame.lastCounts[demoName] = 1   -- simule un exemplaire de réserve

    btn.activeExpiration = GetTime() + 30
    btn.icon:SetTexture(GetBoonIcon(demoName))
    btn.durationText:Show()
    btn:SetAlpha(1)
    urgentWarned[demoName] = nil

    -- Allié fictif avec le MÊME boon : alimente "Boons alliés disponibles",
    -- "Boon Totale" (total combiné) et l'alerte de doublon dans le groupe.
    local demoLabel = GetBoonLabel(demoName)
    allyBoonData[TEST_ALLY_NAME] = { [demoLabel] = 2 }
    duplicateAlerted[demoLabel] = nil
    if alliesFrame and alliesFrame:IsShown() then RefreshAlliesWindow() end
    if totalFrame and totalFrame:IsShown() then RefreshTotalWindow() end
    CheckDuplicateBoonAlert()

    -- Le message reflète directement la vraie constante utilisée par la
    -- logique de déclenchement, pour ne jamais désynchroniser test et réalité.
    print("|cff33ff99RacaBoonMenu|r : " .. string.format(L.MSG_TEST_ISOLATED, demoLabel, URGENT_REACTIVATE_THRESHOLD))
end

-- Détecte un donjon en difficulté MYTHIQUE (Mythic 0 inclus, Mythic+ inclus),
-- mais PAS Normal ni Héroïque (là où les Boons n'existent pas). Sur ce serveur,
-- GetInstanceInfo() renvoie un "difficultyName" VIDE (confirmé via /rbm debug),
-- donc on se base sur l'INDEX numérique à la place : 1=Normal, 2=Héroïque,
-- 3+=Mythic (0 et + confondus, le passage en + se fait via une clé activée,
-- pas via un changement d'index). Si jamais un serveur futur utilise un index
-- différent, /rbm debug affichera la valeur exacte pour ajuster ce seuil.
local MYTHIC_DIFFICULTY_INDEX_THRESHOLD = 3

local function IsInMythicDifficulty()
    local inInstance, instanceType = IsInInstance()
    local name, gotType, difficultyIndex, difficultyName, maxPlayers = GetInstanceInfo()

    if RacaBoonMenuDB and RacaBoonMenuDB.debug then
        print(string.format(
            "|cff888888RacaBoonMenu debug|r : IsInInstance=%s/%s | GetInstanceInfo name='%s' type='%s' diffIndex=%s diffName='%s' maxPlayers=%s",
            tostring(inInstance), tostring(instanceType),
            tostring(name), tostring(gotType), tostring(difficultyIndex), tostring(difficultyName), tostring(maxPlayers)
        ))
    end

    if not inInstance or instanceType ~= "party" then return false end
    return difficultyIndex ~= nil and difficultyIndex >= MYTHIC_DIFFICULTY_INDEX_THRESHOLD
end

-- Affiche automatiquement les fenêtres en Mythic (0 ou +), et les masque en
-- Normal/Héroïque ou hors donjon.
local function UpdateAutoVisibility()
    if not RacaBoonMenuDB.options.autoShowInDungeon then return end
    local shouldShow = IsInMythicDifficulty()
    if RacaBoonMenuDB and RacaBoonMenuDB.debug then
        print("|cff888888RacaBoonMenu debug|r : " .. string.format(L.MSG_DEBUG_AUTO_VIS, tostring(shouldShow)))
    end
    SetWindowsShown(shouldShow)
end

-- ============================================================
-- Application différée des changements de taille (options)
-- ============================================================

-- mainFrame utilise des boutons SÉCURISÉS : SetSize/SetPoint dessus sont
-- interdits en combat, d'où la vérification + le report éventuel ci-dessous.
local function ApplyMainVisualSettings()
    ApplyIconSizeToButtons(mainFrame)
    LayoutIcons(mainFrame, #mainFrame.iconButtons, 26)
end

local function RequestMainVisualRefresh()
    if InCombatLockdown() then
        pendingVisualRefresh = true
        print("|cffffcc00RacaBoonMenu|r : " .. L.MSG_VISUAL_DEFERRED)
    else
        ApplyMainVisualSettings()
    end
end

-- totalFrame n'utilise QUE des boutons non-sécurisés (pas cliquables) :
-- aucune restriction de combat, on applique donc toujours immédiatement.
local function ApplyTotalVisualSettings()
    if not totalFrame then return end
    ApplyIconSizeToButtons(totalFrame)
    LayoutIcons(totalFrame, #totalFrame.iconButtons, 14)
end

-- ============================================================
-- Panneau d'options
-- ============================================================

local optionsFrame

local function CreateOptionsFrame()
    local f = CreateFrame("Frame", "RacaBoonMenuOptionsFrame", UIParent)
    f:SetSize(1040, 720)
    f:SetScale(RacaBoonMenuDB.options.optionsScale)
    ApplySavedPosition(f, RacaBoonMenuDB.optionsPos)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        RacaBoonMenuDB.optionsPos = { point = point, x = x, y = y }
    end)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText(L.TITLE_OPTIONS)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Trois colonnes : Icônes | Échelle + Apparence des fenêtres | Annonces +
    -- Automatisation + Aperçu. Les boutons de test (colonne 3) sont maintenant
    -- empilés verticalement (voir plus bas) au lieu de côte à côte, ce qui
    -- réglait le vrai problème de débordement -- pas besoin d'une 4e colonne.
    local leftCol = CreateFrame("Frame", nil, f)
    leftCol:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -46)
    leftCol:SetSize(280, 1)

    local midCol = CreateFrame("Frame", nil, f)
    midCol:SetPoint("TOPLEFT", f, "TOPLEFT", 330, -46)
    midCol:SetSize(280, 1)

    local rightCol = CreateFrame("Frame", nil, f)
    rightCol:SetPoint("TOPLEFT", f, "TOPLEFT", 640, -46)
    rightCol:SetSize(280, 1)

    local function AddSectionHeader(anchorTo, offsetY, text)
        local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", -4, offsetY)
        header:SetText("|cffffd100" .. text .. "|r")
        return header
    end

    local function AddSlider(anchorTo, offsetY, sliderName, min, max, step, labelPrefix, dbKey, applyFn)
        local slider = CreateFrame("Slider", sliderName, f, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 4, offsetY)
        slider:SetWidth(240)
        slider:SetMinMaxValues(min, max)
        slider:SetValueStep(step)
        _G[slider:GetName().."Low"]:SetText(tostring(min))
        _G[slider:GetName().."High"]:SetText(tostring(max))
        local current = RacaBoonMenuDB.options[dbKey]
        _G[slider:GetName().."Text"]:SetText(labelPrefix .. " : " .. current)
        slider:SetValue(current)
        slider:SetScript("OnValueChanged", function(self, value)
            if step >= 1 then
                value = math.floor(value + 0.5)
            else
                value = math.floor(value / step + 0.5) * step
            end
            _G[self:GetName().."Text"]:SetText(labelPrefix .. " : " .. value)
            RacaBoonMenuDB.options[dbKey] = value
            applyFn(value)
        end)
        return slider
    end

    -- ===== Colonne 1 : Apparence des icônes (Mes Mythical Boons) =====
    local sectionAppearance = AddSectionHeader(leftCol, -4, L.SECTION_ICONS_MAIN)

    local sizeSlider = AddSlider(sectionAppearance, -14, "RacaBoonMenuIconSizeSlider",
        20, 56, 2, L.SLIDER_ICON_SIZE, "iconSizeMain", function(value)
            if mainFrame then mainFrame.iconSize = value end
            ICON_SIZE = value
            RequestMainVisualRefresh()
        end)

    local rowSlider = AddSlider(sizeSlider, -24, "RacaBoonMenuRowSlider",
        3, 13, 1, L.SLIDER_ICONS_PER_ROW, "iconsPerRowMain", function(value)
            if mainFrame then mainFrame.iconsPerRow = value end
            ICONS_PER_ROW = value
            RequestMainVisualRefresh()
        end)

    -- ===== Colonne 1 : Apparence des icônes (Boon Totale) =====
    -- Fenêtre non-sécurisée -> aucune contrainte de combat, réglages 100%
    -- indépendants de ceux de "Mes Mythical Boons".
    local sectionAppearanceTotal = AddSectionHeader(rowSlider, -24, L.SECTION_ICONS_TOTAL)

    local totalSizeSlider = AddSlider(sectionAppearanceTotal, -14, "RacaBoonMenuTotalIconSizeSlider",
        20, 56, 2, L.SLIDER_ICON_SIZE, "iconSizeTotal", function(value)
            if totalFrame then
                totalFrame.iconSize = value
                ApplyTotalVisualSettings()
            end
        end)

    local totalRowSlider = AddSlider(totalSizeSlider, -24, "RacaBoonMenuTotalRowSlider",
        3, 13, 1, L.SLIDER_ICONS_PER_ROW, "iconsPerRowTotal", function(value)
            if totalFrame then
                totalFrame.iconsPerRow = value
                ApplyTotalVisualSettings()
            end
        end)

    -- ===== Colonne 2 : Échelle de chaque fenêtre =====
    local sectionScale = AddSectionHeader(midCol, -4, L.SECTION_SCALE)

    local mainScaleSlider = AddSlider(sectionScale, -14, "RacaBoonMenuMainScaleSlider",
        0.5, 2.0, 0.05, L.SLIDER_SCALE_MAIN, "mainScale", function(value)
            if mainFrame then mainFrame:SetScale(value) end
        end)

    local alliesScaleSlider = AddSlider(mainScaleSlider, -24, "RacaBoonMenuAlliesScaleSlider",
        0.5, 2.0, 0.05, L.SLIDER_SCALE_ALLIES, "alliesScale", function(value)
            if alliesFrame then alliesFrame:SetScale(value) end
        end)

    local totalScaleSlider = AddSlider(alliesScaleSlider, -24, "RacaBoonMenuTotalScaleSlider",
        0.5, 2.0, 0.05, L.SLIDER_SCALE_TOTAL, "totalScale", function(value)
            if totalFrame then totalFrame:SetScale(value) end
        end)

    -- Slider spécial pour l'échelle du panneau d'options : contrairement aux
    -- autres, il agit sur SA PROPRE fenêtre parente. Appliquer SetScale() en
    -- temps réel à chaque micro-mouvement (comme le fait AddSlider normalement)
    -- fait rétrécir/grossir le panneau -- et donc ce slider lui-même -- PENDANT
    -- qu'on le glisse, ce qui casse le suivi de la souris (glissement erratique,
    -- valeur qui saute). Fix : le texte se met à jour en direct, mais
    -- f:SetScale() n'est appliqué qu'au relâchement du clic.
    local optionsScaleSlider = CreateFrame("Slider", "RacaBoonMenuOptionsScaleSlider", f, "OptionsSliderTemplate")
    optionsScaleSlider:SetPoint("TOPLEFT", totalScaleSlider, "BOTTOMLEFT", 4, -24)
    optionsScaleSlider:SetWidth(240)
    optionsScaleSlider:SetMinMaxValues(0.5, 1.5)
    optionsScaleSlider:SetValueStep(0.05)
    _G[optionsScaleSlider:GetName().."Low"]:SetText("0.5")
    _G[optionsScaleSlider:GetName().."High"]:SetText("1.5")
    local currentOptionsScale = RacaBoonMenuDB.options.optionsScale
    _G[optionsScaleSlider:GetName().."Text"]:SetText(L.SLIDER_SCALE_OPTIONS .. " : " .. currentOptionsScale)
    optionsScaleSlider:SetValue(currentOptionsScale)
    optionsScaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 0.05 + 0.5) * 0.05
        _G[self:GetName().."Text"]:SetText(L.SLIDER_SCALE_OPTIONS .. " : " .. value)
        RacaBoonMenuDB.options.optionsScale = value
        -- Pas de f:SetScale(value) ici : voir OnMouseUp plus bas.
    end)
    optionsScaleSlider:SetScript("OnMouseUp", function(self)
        f:SetScale(RacaBoonMenuDB.options.optionsScale)
    end)

    -- ===== Colonne 2 (suite) : Apparence des fenêtres =====
    local sectionStyle = AddSectionHeader(optionsScaleSlider, -24, L.SECTION_APPEARANCE)

    local styleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    styleLabel:SetPoint("TOPLEFT", sectionStyle, "BOTTOMLEFT", 4, -14)
    styleLabel:SetText(L.LABEL_STYLE)

    local styleButtons = {}
    local function RefreshStyleButtons()
        for key, btn in pairs(styleButtons) do
            if RacaBoonMenuDB.options.frameStyle == key then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
    end

    local styleOrder = { "minimal", "classic", "dark" }
    local styleShortLabels = { minimal = L.STYLE_MINIMAL, classic = L.STYLE_CLASSIC, dark = L.STYLE_DARK }
    local prevStyleBtn = styleLabel
    for _, key in ipairs(styleOrder) do
        local styleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        styleBtn:SetSize(84, 20)
        styleBtn:SetText((styleShortLabels[key] or key):match("^(%S+)"))  -- juste le premier mot, plus compact
        if prevStyleBtn == styleLabel then
            styleBtn:SetPoint("LEFT", styleLabel, "RIGHT", 8, 0)
        else
            styleBtn:SetPoint("LEFT", prevStyleBtn, "RIGHT", 4, 0)
        end
        styleBtn:SetScript("OnClick", function()
            RacaBoonMenuDB.options.frameStyle = key
            if mainFrame then ApplyFrameStyle(mainFrame, "showTitleTextMain") end
            if alliesFrame then ApplyFrameStyle(alliesFrame, "showTitleTextAllies") end
            if totalFrame then ApplyFrameStyle(totalFrame, "showTitleTextTotal") end
            RefreshStyleButtons()
        end)
        styleButtons[key] = styleBtn
        prevStyleBtn = styleBtn
    end
    RefreshStyleButtons()

    local checkLock = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    checkLock:SetPoint("TOPLEFT", styleLabel, "BOTTOMLEFT", -4, -12)
    checkLock:SetChecked(RacaBoonMenuDB.locked)
    local labelLock = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelLock:SetPoint("LEFT", checkLock, "RIGHT", 4, 0)
    labelLock:SetWidth(220)
    labelLock:SetJustifyH("LEFT")
    labelLock:SetText(L.CHECK_LOCK)
    checkLock:SetScript("OnClick", function(self)
        RacaBoonMenuDB.locked = self:GetChecked() and true or false
        ApplyLockState()
    end)

    local checkTotal = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    checkTotal:SetPoint("TOPLEFT", checkLock, "BOTTOMLEFT", 0, -18)
    checkTotal:SetChecked(RacaBoonMenuDB.options.showTotalCount)
    local labelTotal = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelTotal:SetPoint("LEFT", checkTotal, "RIGHT", 4, 0)
    labelTotal:SetWidth(220)
    labelTotal:SetJustifyH("LEFT")
    labelTotal:SetText(L.CHECK_SHOW_TOTAL_TITLE)
    checkTotal:SetScript("OnClick", function(self)
        RacaBoonMenuDB.options.showTotalCount = self:GetChecked() and true or false
        if mainFrame then RefreshMainWindow() end
    end)

    local checkTitleMain = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    checkTitleMain:SetPoint("TOPLEFT", checkTotal, "BOTTOMLEFT", 0, -14)
    checkTitleMain:SetChecked(RacaBoonMenuDB.options.showTitleTextMain)
    local labelTitleMain = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelTitleMain:SetPoint("LEFT", checkTitleMain, "RIGHT", 4, 0)
    labelTitleMain:SetWidth(220)
    labelTitleMain:SetJustifyH("LEFT")
    labelTitleMain:SetText(L.CHECK_TITLE_MAIN)
    checkTitleMain:SetScript("OnClick", function(self)
        RacaBoonMenuDB.options.showTitleTextMain = self:GetChecked() and true or false
        if mainFrame then ApplyFrameStyle(mainFrame, "showTitleTextMain") end
    end)

    local checkTitleAllies = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    checkTitleAllies:SetPoint("TOPLEFT", checkTitleMain, "BOTTOMLEFT", 0, -14)
    checkTitleAllies:SetChecked(RacaBoonMenuDB.options.showTitleTextAllies)
    local labelTitleAllies = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelTitleAllies:SetPoint("LEFT", checkTitleAllies, "RIGHT", 4, 0)
    labelTitleAllies:SetWidth(220)
    labelTitleAllies:SetJustifyH("LEFT")
    labelTitleAllies:SetText(L.CHECK_TITLE_ALLIES)
    checkTitleAllies:SetScript("OnClick", function(self)
        RacaBoonMenuDB.options.showTitleTextAllies = self:GetChecked() and true or false
        if alliesFrame then ApplyFrameStyle(alliesFrame, "showTitleTextAllies") end
    end)

    local checkTitleTotal = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    checkTitleTotal:SetPoint("TOPLEFT", checkTitleAllies, "BOTTOMLEFT", 0, -18)
    checkTitleTotal:SetChecked(RacaBoonMenuDB.options.showTitleTextTotal)
    local labelTitleTotal = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelTitleTotal:SetPoint("LEFT", checkTitleTotal, "RIGHT", 4, 0)
    labelTitleTotal:SetWidth(220)
    labelTitleTotal:SetJustifyH("LEFT")
    labelTitleTotal:SetText(L.CHECK_TITLE_TOTAL)
    checkTitleTotal:SetScript("OnClick", function(self)
        RacaBoonMenuDB.options.showTitleTextTotal = self:GetChecked() and true or false
        if totalFrame then ApplyFrameStyle(totalFrame, "showTitleTextTotal") end
    end)

    local opacitySlider = AddSlider(checkTitleTotal, -16, "RacaBoonMenuOpacitySlider",
        0, 1.0, 0.05, L.SLIDER_OPACITY, "windowOpacity", function(value)
            if mainFrame then ApplyFrameStyle(mainFrame, "showTitleTextMain") end
            if alliesFrame then ApplyFrameStyle(alliesFrame, "showTitleTextAllies") end
            if totalFrame then ApplyFrameStyle(totalFrame, "showTitleTextTotal") end
        end)

    -- Choix de la langue -- change RacaBoonMenuDB.options.language + rafraîchit
    -- la table L pour les prochains textes générés, mais un /reload reste
    -- nécessaire pour que TOUT le texte déjà affiché (titres, autres options
    -- déjà construites...) se mette à jour partout d'un coup.
    local langLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    langLabel:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", -4, -16)
    langLabel:SetText(L.LABEL_LANGUAGE)

    local langButtons = {}
    local function RefreshLangButtons()
        for key, btn in pairs(langButtons) do
            if RacaBoonMenuDB.options.language == key then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
    end
    local function MakeLangButton(key, text, anchorTo)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(70, 20)
        btn:SetText(text)
        if anchorTo == langLabel then
            btn:SetPoint("LEFT", anchorTo, "RIGHT", 8, 0)
        else
            btn:SetPoint("LEFT", anchorTo, "RIGHT", 4, 0)
        end
        btn:SetScript("OnClick", function()
            RacaBoonMenuDB.options.language = key
            ApplyLocale()
            RefreshLangButtons()
            print("|cff33ff99RacaBoonMenu|r : " ..
                (key == "FR" and "langue changée en Français -- /reload pour tout appliquer."
                    or "language changed to English -- /reload to apply everywhere."))
        end)
        langButtons[key] = btn
        return btn
    end
    local langBtnFR = MakeLangButton("FR", "Français", langLabel)
    local langBtnEN = MakeLangButton("EN", "English", langBtnFR)
    RefreshLangButtons()

    -- ===== Colonne 3 : Annonces =====
    local sectionAnnounce = AddSectionHeader(rightCol, -4, L.SECTION_ANNOUNCE)

    local function AddCheck(anchorTo, offsetY, labelText, dbKey, onClickExtra)
        local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 4, offsetY)
        check:SetChecked(RacaBoonMenuDB.options[dbKey])
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        label:SetWidth(260)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)
        check:SetScript("OnClick", function(self)
            RacaBoonMenuDB.options[dbKey] = self:GetChecked() and true or false
            if onClickExtra then onClickExtra() end
        end)
        return check
    end

    local checkPickup = AddCheck(sectionAnnounce, -16, L.CHECK_ANNOUNCE_PICKUP, "sayOnPickup")
    local checkUse = AddCheck(checkPickup, -6, L.CHECK_ANNOUNCE_USE, "sayOnUse")

    -- Choix du canal (mutuellement exclusif, façon boutons radio)
    local channelLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    channelLabel:SetPoint("TOPLEFT", checkUse, "BOTTOMLEFT", 0, -10)
    channelLabel:SetText(L.LABEL_CHANNEL)

    local checkSay = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    checkSay:SetPoint("LEFT", channelLabel, "RIGHT", 6, 0)
    local labelSay = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelSay:SetPoint("LEFT", checkSay, "RIGHT", 2, 0)
    labelSay:SetText("/say")

    local checkParty = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    checkParty:SetPoint("LEFT", labelSay, "RIGHT", 14, 0)
    local labelParty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelParty:SetPoint("LEFT", checkParty, "RIGHT", 2, 0)
    labelParty:SetText("/p (groupe)")

    local function RefreshChannelChecks()
        local isParty = RacaBoonMenuDB.options.announceChannel == "PARTY"
        checkSay:SetChecked(not isParty)
        checkParty:SetChecked(isParty)
    end
    checkSay:SetScript("OnClick", function()
        RacaBoonMenuDB.options.announceChannel = "SAY"
        RefreshChannelChecks()
    end)
    checkParty:SetScript("OnClick", function()
        RacaBoonMenuDB.options.announceChannel = "PARTY"
        RefreshChannelChecks()
    end)
    RefreshChannelChecks()

    -- ===== Colonne 3 : Automatisation =====
    local sectionAuto = AddSectionHeader(checkSay, -24, L.SECTION_AUTO)

    local checkAlly = AddCheck(sectionAuto, -16, L.CHECK_ALLY_SHARE, "allyShareEnabled")
    local checkAutoShow = AddCheck(checkAlly, -10, L.CHECK_AUTO_SHOW, "autoShowInDungeon", UpdateAutoVisibility)
    local checkDuplicate = AddCheck(checkAutoShow, -10, L.CHECK_DUPLICATE_ALERT, "alertOnDuplicateBoon")
    local checkAllyWindow = AddCheck(checkDuplicate, -16, L.CHECK_ENABLE_ALLIES_WINDOW, "alliesWindowEnabled", function()
        if alliesFrame then
            if RacaBoonMenuDB.options.alliesWindowEnabled and AreWindowsShown() then
                alliesFrame:Show()
                RefreshAlliesWindow()
            else
                alliesFrame:Hide()
            end
        end
    end)
    local checkTotalWindow = AddCheck(checkAllyWindow, -16, L.CHECK_ENABLE_TOTAL_WINDOW, "totalWindowEnabled", function()
        if totalFrame then
            if RacaBoonMenuDB.options.totalWindowEnabled and AreWindowsShown() then
                totalFrame:Show()
                RefreshTotalWindow()
            else
                totalFrame:Hide()
            end
        end
    end)

    -- ===== Colonne 3 : Aperçu =====
    local sectionPreview = AddSectionHeader(checkTotalWindow, -20, L.SECTION_PREVIEW)
    local previewLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewLabel:SetPoint("TOPLEFT", sectionPreview, "BOTTOMLEFT", 4, -14)
    previewLabel:SetWidth(260)
    previewLabel:SetJustifyH("LEFT")
    previewLabel:SetText(L.PREVIEW_DESC)

    local previewBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    previewBtn:SetSize(240, 22)
    previewBtn:SetPoint("TOPLEFT", previewLabel, "BOTTOMLEFT", 0, -8)
    previewBtn:SetText(previewMode and L.BTN_PREVIEW_OFF or L.BTN_PREVIEW_ON)
    previewBtn:SetScript("OnClick", function(self)
        TogglePreviewMode()
        self:SetText(previewMode and L.BTN_PREVIEW_OFF or L.BTN_PREVIEW_ON)
    end)

    local testAlertBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    testAlertBtn:SetSize(240, 22)
    testAlertBtn:SetPoint("TOPLEFT", previewBtn, "BOTTOMLEFT", 0, -6)
    testAlertBtn:SetText(L.BTN_TEST_ALERTS)
    testAlertBtn:SetScript("OnClick", function()
        TestAlerts()
    end)

    local simulateUrgentBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    simulateUrgentBtn:SetSize(240, 22)
    simulateUrgentBtn:SetPoint("TOPLEFT", testAlertBtn, "BOTTOMLEFT", 0, -6)
    simulateUrgentBtn:SetText(L.BTN_TEST_GLOW)
    simulateUrgentBtn:SetScript("OnClick", function()
        SimulateUrgentGlow()
    end)

    f:SetHeight(720)
    f:Hide()
    return f
end

local function ToggleOptions()
    if not optionsFrame then
        optionsFrame = CreateOptionsFrame()
    end
    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        optionsFrame:Show()
    end
end

-- ============================================================
-- Icône minimap
-- ============================================================
-- Clic gauche  : ouvre/ferme le panneau d'options
-- Clic droit   : affiche/masque les fenêtres manuellement
-- Glisser      : déplace l'icône autour de la minimap

local function UpdateMinimapButtonPosition(button)
    local angle = RacaBoonMenuDB.minimapAngle or 215
    local rad = math.rad(angle)
    local radius = 80
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function CreateMinimapButton()
    local button = CreateFrame("Button", "RacaBoonMenuMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Sapphire_02")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("RacaBoonMenu")
        GameTooltip:AddLine("Clic gauche : options", 1, 1, 1)
        GameTooltip:AddLine("Clic droit : afficher/masquer les fenêtres", 1, 1, 1)
        GameTooltip:AddLine("Glisser : déplacer l'icône", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            ToggleOptions()
        else
            ToggleAllWindows()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            RacaBoonMenuDB.minimapAngle = angle
            UpdateMinimapButtonPosition(self)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    UpdateMinimapButtonPosition(button)
    return button
end

-- ============================================================
-- Initialisation
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= ADDON_NAME then return end

        EnsureDB()

        mainFrame = CreateBaseWindow("RacaBoonMenuMainFrame", L.TITLE_MAIN, "mainPos", "showTitleTextMain",
            RacaBoonMenuDB.options.iconSizeMain, RacaBoonMenuDB.options.iconsPerRowMain)
        ApplySavedPosition(mainFrame, RacaBoonMenuDB.mainPos)
        mainFrame:SetScale(RacaBoonMenuDB.options.mainScale)
        mainFrame.lastCounts = {}
        mainFrame.hasRunOnce = false
        mainFrame.lastBroadcast = nil
        RegisterAllKnownBoons(mainFrame)   -- hors combat garanti ici (login/reload)
        mainFrame:Show()

        alliesFrame = CreateBaseWindow("RacaBoonMenuAlliesFrame", L.TITLE_ALLIES, "alliesPos", "showTitleTextAllies")
        ApplySavedPosition(alliesFrame, RacaBoonMenuDB.alliesPos)
        alliesFrame:SetScale(RacaBoonMenuDB.options.alliesScale)
        if RacaBoonMenuDB.options.alliesWindowEnabled then
            alliesFrame:Show()
        end

        totalFrame = CreateBaseWindow("RacaBoonMenuTotalFrame", L.TITLE_TOTAL, "totalPos", "showTitleTextTotal",
            RacaBoonMenuDB.options.iconSizeTotal, RacaBoonMenuDB.options.iconsPerRowTotal)
        ApplySavedPosition(totalFrame, RacaBoonMenuDB.totalPos)
        totalFrame:SetScale(RacaBoonMenuDB.options.totalScale)
        RegisterTotalBoonButtons(totalFrame)   -- hors combat garanti ici (login/reload)
        if RacaBoonMenuDB.options.totalWindowEnabled then
            totalFrame:Show()
        end

        CreateMinimapButton()

        RefreshMainWindow()
        RefreshActiveBoonState()
        RefreshAlliesWindow()
        RefreshTotalWindow()
        UpdateAutoVisibility()

    elseif event == "BAG_UPDATE" then
        RefreshMainWindow()

    elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        -- Se déclenche quand le serveur confirme un changement de cooldown
        -- (bien plus fiable que de vérifier juste après le clic).
        if mainFrame then
            for _, btn in pairs(mainFrame.boonButtons) do
                UpdateBoonCooldown(btn)
            end
        end

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            RefreshActiveBoonState()
        end
        PruneAllyData()
        BroadcastMyBoons(true)   -- renvoie mon état complet pour les nouveaux arrivants

    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        PruneAllyData()
        BroadcastMyBoons(true)

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingWindowVisibility ~= nil then
            local shouldShow = pendingWindowVisibility
            pendingWindowVisibility = nil
            if mainFrame then
                if shouldShow then mainFrame:Show() else mainFrame:Hide() end
            end
        end
        RefreshMainWindow()
        if pendingVisualRefresh then
            pendingVisualRefresh = false
            ApplyMainVisualSettings()
            print("|cff33ff99RacaBoonMenu|r : " .. L.MSG_VISUAL_APPLIED)
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix == ADDON_PREFIX then
            HandleAllyBoonMessage(sender, message)
        end

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        UpdateAutoVisibility()
        -- RequestRaidInfo() force le serveur à renvoyer les infos d'instance à
        -- jour (déclenche UPDATE_INSTANCE_INFO peu après) ; en filet, on revérifie
        -- aussi 2s plus tard au cas où cet event ne suffirait pas sur ce serveur.
        RequestRaidInfo()
        pendingVisibilityRecheck = 2

    elseif event == "UPDATE_INSTANCE_INFO" then
        UpdateAutoVisibility()
    end
end)

-- Heartbeat : renvoie périodiquement mon état pour couvrir les messages perdus
-- ou les alliés qui viennent de charger l'addon en cours de route. Met aussi à
-- jour le décompte de durée ("35s", "1m"...) affiché sous les boons actifs.
local heartbeatElapsed = 0
local durationTickElapsed = 0
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    -- Animation "Pixel Glow" (façon WeakAura) + pulsation du glow "urgent" --
    -- calculées ici et appliquées via de simples appels sur des textures
    -- (SetAlpha/SetSize/SetRotation), jamais une AnimationGroup sur le bouton
    -- sécurisé lui-même (c'est ce qui cassait tout précédemment).
    -- Une seule boucle sur les boutons (au lieu de deux) : chaque bouton n'est
    -- de toute façon jamais concerné par les deux effets à la fois en pratique.
    if mainFrame then
        local now = GetTime()

        -- Pixel Glow "actif" : les 8 points s'allument/s'éteignent en cascade
        -- (chenillard) autour du contour, comme le glow WeakAura classique --
        -- rythme plus rapide et contraste plus marqué pour bien se voir.
        local pixelCount = 8

        -- Pulsation du glow "urgent" (10s restantes), plus intense (alpha +
        -- taille + rotation combinés) que le Pixel Glow ci-dessus.
        local pulseAlpha = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(now * 8))
        local pulseScale = 1.6 + 0.5 * (0.5 + 0.5 * math.sin(now * 4))
        local baseSize = mainFrame.iconSize or ICON_SIZE
        local urgentSize = baseSize * pulseScale
        local rotation = (now * 1.5) % (2 * math.pi)

        for _, btn in pairs(mainFrame.boonButtons) do
            if btn.glowActive and btn.pixelGlowPoints then
                for i, px in ipairs(btn.pixelGlowPoints) do
                    local phase = (i - 1) / pixelCount
                    local a = 0.15 + 0.85 * (0.5 + 0.5 * math.sin(now * 7 - phase * 2 * math.pi))
                    px:SetAlpha(a)
                end
            end
            if btn.urgentBorderActive and btn.urgentBorderTexture then
                btn.urgentBorderTexture:SetAlpha(pulseAlpha)
                btn.urgentBorderTexture:SetSize(urgentSize, urgentSize)
                pcall(btn.urgentBorderTexture.SetRotation, btn.urgentBorderTexture, rotation)
            end
        end
    end

    heartbeatElapsed = heartbeatElapsed + elapsed
    if heartbeatElapsed >= 5 then
        heartbeatElapsed = 0
        if mainFrame then BroadcastMyBoons(true) end
    end

    if pendingVisibilityRecheck > 0 then
        pendingVisibilityRecheck = pendingVisibilityRecheck - elapsed
        if pendingVisibilityRecheck <= 0 then
            pendingVisibilityRecheck = 0
            UpdateAutoVisibility()
        end
    end

    durationTickElapsed = durationTickElapsed + elapsed
    if durationTickElapsed >= 1 and mainFrame then
        durationTickElapsed = 0
        local anyExpired = false
        for name, btn in pairs(mainFrame.boonButtons) do
            if btn.activeExpiration then
                local remaining = btn.activeExpiration - GetTime()
                if remaining > 0 then
                    btn.durationText:SetText(FormatBoonDuration(remaining))
                    UpdateBoonCooldown(btn)
                    local hasSpareInBag = (mainFrame.lastCounts[name] or 0) > 0
                    if remaining <= URGENT_REACTIVATE_THRESHOLD then
                        if hasSpareInBag then
                            ShowBoonGlow(btn)
                            ShowBoonUrgentBorder(btn)
                        else
                            HideBoonGlow(btn)
                            HideBoonUrgentBorder(btn)
                        end
                        local allyHolders = hasSpareInBag and nil or GetAllyHoldersForBoon(name)
                        CheckUrgentReactivateAlert(name, remaining, hasSpareInBag, allyHolders)
                    else
                        HideBoonGlow(btn)
                        HideBoonUrgentBorder(btn)
                        urgentWarned[name] = nil
                    end
                else
                    HideBoonGlow(btn)
                    btn.activeExpiration = nil
                    btn.durationText:Hide()
                    HideBoonUrgentBorder(btn)
                    urgentWarned[name] = nil
                    anyExpired = true
                    if testLockName == name then
                        testLockName = nil   -- fin du test isolé, le scan normal reprend pour ce boon
                        -- Nettoyage de l'allié fictif simulé pendant le test.
                        allyBoonData[TEST_ALLY_NAME] = nil
                        if alliesFrame and alliesFrame:IsShown() then RefreshAlliesWindow() end
                        if totalFrame and totalFrame:IsShown() then RefreshTotalWindow() end
                        print("|cff33ff99RacaBoonMenu|r : " .. string.format(L.MSG_TEST_ENDED, GetBoonLabel(name)))
                    end
                end
            else
                -- Filet de sécurité si BAG_UPDATE_COOLDOWN ne se déclenche pas
                -- de façon fiable sur ce serveur : on revérifie chaque seconde.
                UpdateBoonCooldown(btn)

                -- Décompte des 10 min restantes en réserve (objet non actif),
                -- avec le glow + l'alerte écran en dessous d'1 min restante.
                if itemPickupTime[name] then
                    if not previewMode then
                        CheckExpiringSoonAlert(name)
                    end
                    local remaining = itemPickupTime[name] + ITEM_BAG_DURATION - GetTime()
                    if remaining > 0 then
                        btn.durationText:SetText(FormatBoonDuration(remaining))
                        if remaining <= EXPIRING_SOON_THRESHOLD then
                            ShowBoonGlow(btn)
                        else
                            HideBoonGlow(btn)
                        end
                    else
                        itemPickupTime[name] = nil
                        expiringWarned[name] = nil
                        btn.durationText:Hide()
                        HideBoonGlow(btn)
                        anyExpired = true
                    end
                end
            end
        end
        if anyExpired then
            RefreshMainWindow()
        end
    end
end)

-- ============================================================
-- Commande slash
-- ============================================================

SLASH_RACABOONMENU1 = "/rbm"
SLASH_RACABOONMENU2 = "/racaboonmenu"

SlashCmdList["RACABOONMENU"] = function(msg)
    msg = msg or ""
    local lower = string.lower(msg)

    if lower == "lock" then
        RacaBoonMenuDB.locked = not RacaBoonMenuDB.locked
        ApplyLockState()
        if RacaBoonMenuDB.locked then
            print("|cff33ff99RacaBoonMenu|r : " .. L.MSG_LOCKED)
        else
            print("|cff33ff99RacaBoonMenu|r : " .. L.MSG_UNLOCKED)
        end

    elseif lower == "debug" then
        RacaBoonMenuDB.debug = not RacaBoonMenuDB.debug
        print("|cff33ff99RacaBoonMenu|r : " .. L.MSG_DEBUG .. (RacaBoonMenuDB.debug and L.STATE_ENABLED or L.STATE_DISABLED) .. ".")

    elseif lower == "options" or lower == "option" then
        ToggleOptions()

    elseif lower == "preview" or lower == "apercu" or lower == "aperçu" then
        TogglePreviewMode()

    elseif lower == "reset" then
        RacaBoonMenuDB.mainPos = { point = "CENTER", x = -200, y = 150 }
        RacaBoonMenuDB.alliesPos = { point = "CENTER", x = 200, y = 150 }
        RacaBoonMenuDB.totalPos = { point = "CENTER", x = 200, y = -100 }
        ApplySavedPosition(mainFrame, RacaBoonMenuDB.mainPos)
        ApplySavedPosition(alliesFrame, RacaBoonMenuDB.alliesPos)
        ApplySavedPosition(totalFrame, RacaBoonMenuDB.totalPos)
        print("|cff33ff99RacaBoonMenu|r : " .. L.MSG_POS_RESET)

    elseif string.sub(lower, 1, 7) == "addboon" then
        local newName = string.match(msg, "^%s*[Aa]ddboon%s+(.+)$")
        if not newName or newName == "" then
            print("|cffff0000RacaBoonMenu|r : " .. L.MSG_ADDBOON_USAGE)
        elseif InCombatLockdown() then
            print("|cffff0000RacaBoonMenu|r : " .. L.MSG_ADDBOON_COMBAT)
        else
            local already = false
            for _, n in ipairs(GetRegisteredBoonNames()) do
                if n == newName then already = true end
            end
            if already then
                print("|cff33ff99RacaBoonMenu|r : '" .. newName .. L.MSG_ADDBOON_EXISTS)
            else
                table.insert(RacaBoonMenuDB.customBoons, newName)
                InvalidateBoonNamesCache()
                RegisterBoonButton(mainFrame, newName)
                LayoutIcons(mainFrame, #mainFrame.iconButtons, 26)
                RefreshMainWindow()
                print("|cff33ff99RacaBoonMenu|r : '" .. newName .. L.MSG_ADDBOON_ADDED)
            end
        end

    else
        ToggleAllWindows()
    end
end
