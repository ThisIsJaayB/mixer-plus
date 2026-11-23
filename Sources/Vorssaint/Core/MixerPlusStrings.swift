// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Text for the mixer additions of this fork: recently active apps and the
/// controls built on top of them.
struct MixerPlusStrings {
    /// Button that lists every open app while inactive ones are hidden.
    let showAllApps: String
    /// The same button once every app is listed.
    let showRecentOnly: String
    /// Label of the picker for how long a quiet app stays listed.
    let hideAfter: String
    /// Switch for the live level drawn behind each app's fader.
    let showLevelMeters: String
    /// Name of the knob that moves an app between the left and right speakers.
    let pan: String
    /// The knob's readout in the middle, and the side named before a number.
    let panCentre: String
    let panLeft: String
    let panRight: String
    /// The Audio Unit effects on an app, and the controls of its list.
    let effects: String
    let addEffect: String
    let findingEffects: String
    let bypassEffect: String
    let turnEffectOn: String
    let openEffect: String
    let removeEffect: String
    /// Beside the name of a saved effect that could not be loaded.
    let effectUnavailable: String
    let effectHasNoSettings: String

    /// A time to linger the way the language writes it: "30 sec", "5 min".
    static func duration(_ seconds: Int, _ language: AppLanguage) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.minutes, .seconds], width: .abbreviated)
                .locale(Locale(identifier: language.rawValue)))
    }

    static func localized(_ language: AppLanguage) -> MixerPlusStrings {
        switch language {
        case .enUS: return .init(showAllApps: "Show all apps", showRecentOnly: "Show recent only",
                                 hideAfter: "Hide after silence of",
            showLevelMeters: "Show level meters",
            pan: "Pan", panCentre: "Centre", panLeft: "Left", panRight: "Right",
            effects: "Effects",
            addEffect: "Add effect",
            findingEffects: "Finding effects…",
            bypassEffect: "Bypass",
            turnEffectOn: "Turn on",
            openEffect: "Open",
            removeEffect: "Remove",
            effectUnavailable: "not available",
            effectHasNoSettings: "This effect has no adjustable settings.")
        case .ptBR: return .init(showAllApps: "Mostrar todos os apps", showRecentOnly: "Mostrar só os recentes",
                                 hideAfter: "Ocultar após silêncio de",
            showLevelMeters: "Mostrar medidores de nível",
            pan: "Pan", panCentre: "Centro", panLeft: "Esquerda", panRight: "Direita",
            effects: "Efeitos",
            addEffect: "Adicionar efeito",
            findingEffects: "Procurando efeitos…",
            bypassEffect: "Ignorar",
            turnEffectOn: "Ativar",
            openEffect: "Abrir",
            removeEffect: "Remover",
            effectUnavailable: "indisponível",
            effectHasNoSettings: "Este efeito não tem ajustes.")
        case .tr: return .init(showAllApps: "Tüm uygulamaları göster", showRecentOnly: "Yalnızca son kullanılanları göster",
                               hideAfter: "Şu kadar sessizlikten sonra gizle",
            showLevelMeters: "Seviye göstergelerini göster",
            pan: "Pan", panCentre: "Orta", panLeft: "Sol", panRight: "Sağ",
            effects: "Efektler",
            addEffect: "Efekt ekle",
            findingEffects: "Efektler aranıyor…",
            bypassEffect: "Atla",
            turnEffectOn: "Aç",
            openEffect: "Aç",
            removeEffect: "Kaldır",
            effectUnavailable: "kullanılamıyor",
            effectHasNoSettings: "Bu efektin ayarlanabilir seçeneği yok.")
        case .ru: return .init(showAllApps: "Показать все приложения", showRecentOnly: "Показать только недавние",
                               hideAfter: "Скрывать после тишины в течение",
            showLevelMeters: "Показывать индикаторы уровня",
            pan: "Панорама", panCentre: "Центр", panLeft: "Влево", panRight: "Вправо",
            effects: "Эффекты",
            addEffect: "Добавить эффект",
            findingEffects: "Поиск эффектов…",
            bypassEffect: "Обойти",
            turnEffectOn: "Включить",
            openEffect: "Открыть",
            removeEffect: "Удалить",
            effectUnavailable: "недоступен",
            effectHasNoSettings: "У этого эффекта нет настраиваемых параметров.")
        case .es: return .init(showAllApps: "Mostrar todas las apps", showRecentOnly: "Mostrar solo las recientes",
                               hideAfter: "Ocultar tras un silencio de",
            showLevelMeters: "Mostrar medidores de nivel",
            pan: "Panorama", panCentre: "Centro", panLeft: "Izquierda", panRight: "Derecha",
            effects: "Efectos",
            addEffect: "Añadir efecto",
            findingEffects: "Buscando efectos…",
            bypassEffect: "Omitir",
            turnEffectOn: "Activar",
            openEffect: "Abrir",
            removeEffect: "Eliminar",
            effectUnavailable: "no disponible",
            effectHasNoSettings: "Este efecto no tiene ajustes.")
        case .sk: return .init(showAllApps: "Zobraziť všetky aplikácie", showRecentOnly: "Zobraziť len nedávne",
                               hideAfter: "Skryť po tichu trvajúcom",
            showLevelMeters: "Zobraziť ukazovatele úrovne",
            pan: "Panoráma", panCentre: "Stred", panLeft: "Vľavo", panRight: "Vpravo",
            effects: "Efekty",
            addEffect: "Pridať efekt",
            findingEffects: "Hľadajú sa efekty…",
            bypassEffect: "Obísť",
            turnEffectOn: "Zapnúť",
            openEffect: "Otvoriť",
            removeEffect: "Odstrániť",
            effectUnavailable: "nedostupný",
            effectHasNoSettings: "Tento efekt nemá žiadne nastavenia.")
        case .de: return .init(showAllApps: "Alle Apps anzeigen", showRecentOnly: "Nur zuletzt aktive anzeigen",
                               hideAfter: "Ausblenden nach Stille von",
            showLevelMeters: "Pegelanzeigen einblenden",
            pan: "Panorama", panCentre: "Mitte", panLeft: "Links", panRight: "Rechts",
            effects: "Effekte",
            addEffect: "Effekt hinzufügen",
            findingEffects: "Effekte werden gesucht …",
            bypassEffect: "Umgehen",
            turnEffectOn: "Einschalten",
            openEffect: "Öffnen",
            removeEffect: "Entfernen",
            effectUnavailable: "nicht verfügbar",
            effectHasNoSettings: "Dieser Effekt hat keine einstellbaren Parameter.")
        case .fr: return .init(showAllApps: "Afficher toutes les apps", showRecentOnly: "Afficher les récentes seulement",
                               hideAfter: "Masquer après un silence de",
            showLevelMeters: "Afficher les indicateurs de niveau",
            pan: "Panoramique", panCentre: "Centre", panLeft: "Gauche", panRight: "Droite",
            effects: "Effets",
            addEffect: "Ajouter un effet",
            findingEffects: "Recherche des effets…",
            bypassEffect: "Contourner",
            turnEffectOn: "Activer",
            openEffect: "Ouvrir",
            removeEffect: "Supprimer",
            effectUnavailable: "indisponible",
            effectHasNoSettings: "Cet effet n’a aucun réglage.")
        case .it: return .init(showAllApps: "Mostra tutte le app", showRecentOnly: "Mostra solo le recenti",
                               hideAfter: "Nascondi dopo un silenzio di",
            showLevelMeters: "Mostra indicatori di livello",
            pan: "Pan", panCentre: "Centro", panLeft: "Sinistra", panRight: "Destra",
            effects: "Effetti",
            addEffect: "Aggiungi effetto",
            findingEffects: "Ricerca degli effetti…",
            bypassEffect: "Escludi",
            turnEffectOn: "Attiva",
            openEffect: "Apri",
            removeEffect: "Rimuovi",
            effectUnavailable: "non disponibile",
            effectHasNoSettings: "Questo effetto non ha impostazioni regolabili.")
        case .ja: return .init(showAllApps: "すべてのアプリを表示", showRecentOnly: "最近のアプリのみ表示",
                               hideAfter: "無音が続いたら隠すまでの時間",
            showLevelMeters: "レベルメーターを表示",
            pan: "パン", panCentre: "中央", panLeft: "左", panRight: "右",
            effects: "エフェクト",
            addEffect: "エフェクトを追加",
            findingEffects: "エフェクトを検索中…",
            bypassEffect: "バイパス",
            turnEffectOn: "オンにする",
            openEffect: "開く",
            removeEffect: "削除",
            effectUnavailable: "利用不可",
            effectHasNoSettings: "このエフェクトには調整できる設定がありません。")
        case .ko: return .init(showAllApps: "모든 앱 보기", showRecentOnly: "최근 앱만 보기",
                               hideAfter: "무음이 지속되면 숨기기까지",
            showLevelMeters: "레벨 미터 보기",
            pan: "팬", panCentre: "가운데", panLeft: "왼쪽", panRight: "오른쪽",
            effects: "이펙트",
            addEffect: "이펙트 추가",
            findingEffects: "이펙트 찾는 중…",
            bypassEffect: "바이패스",
            turnEffectOn: "켜기",
            openEffect: "열기",
            removeEffect: "제거",
            effectUnavailable: "사용할 수 없음",
            effectHasNoSettings: "이 이펙트에는 조절할 설정이 없습니다.")
        case .uk: return .init(showAllApps: "Показати всі програми", showRecentOnly: "Показати лише нещодавні",
                               hideAfter: "Приховувати після тиші протягом",
            showLevelMeters: "Показувати індикатори рівня",
            pan: "Панорама", panCentre: "Центр", panLeft: "Ліворуч", panRight: "Праворуч",
            effects: "Ефекти",
            addEffect: "Додати ефект",
            findingEffects: "Пошук ефектів…",
            bypassEffect: "Обійти",
            turnEffectOn: "Увімкнути",
            openEffect: "Відкрити",
            removeEffect: "Вилучити",
            effectUnavailable: "недоступний",
            effectHasNoSettings: "Цей ефект не має налаштовуваних параметрів.")
        case .zhHans: return .init(showAllApps: "显示所有 App", showRecentOnly: "仅显示最近的 App",
                                   hideAfter: "静音多久后隐藏",
            showLevelMeters: "显示电平表",
            pan: "声相", panCentre: "居中", panLeft: "左", panRight: "右",
            effects: "效果",
            addEffect: "添加效果",
            findingEffects: "正在查找效果…",
            bypassEffect: "旁通",
            turnEffectOn: "启用",
            openEffect: "打开",
            removeEffect: "移除",
            effectUnavailable: "不可用",
            effectHasNoSettings: "此效果没有可调整的设置。")
        case .zhTW: return .init(showAllApps: "顯示所有 App", showRecentOnly: "只顯示最近的 App",
                                 hideAfter: "靜音多久後隱藏",
            showLevelMeters: "顯示音量表",
            pan: "聲相", panCentre: "置中", panLeft: "左", panRight: "右",
            effects: "效果",
            addEffect: "加入效果",
            findingEffects: "正在尋找效果…",
            bypassEffect: "旁通",
            turnEffectOn: "啟用",
            openEffect: "打開",
            removeEffect: "移除",
            effectUnavailable: "無法使用",
            effectHasNoSettings: "此效果沒有可調整的設定。")
        case .zhHK: return .init(showAllApps: "顯示所有 App", showRecentOnly: "只顯示最近的 App",
                                 hideAfter: "靜音多久後隱藏",
            showLevelMeters: "顯示音量表",
            pan: "聲相", panCentre: "置中", panLeft: "左", panRight: "右",
            effects: "效果",
            addEffect: "加入效果",
            findingEffects: "正在尋找效果…",
            bypassEffect: "旁通",
            turnEffectOn: "啟用",
            openEffect: "打開",
            removeEffect: "移除",
            effectUnavailable: "無法使用",
            effectHasNoSettings: "此效果沒有可調整的設定。")
        }
    }
}
