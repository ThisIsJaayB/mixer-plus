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
            showLevelMeters: "Show level meters")
        case .ptBR: return .init(showAllApps: "Mostrar todos os apps", showRecentOnly: "Mostrar só os recentes",
                                 hideAfter: "Ocultar após silêncio de",
            showLevelMeters: "Mostrar medidores de nível")
        case .tr: return .init(showAllApps: "Tüm uygulamaları göster", showRecentOnly: "Yalnızca son kullanılanları göster",
                               hideAfter: "Şu kadar sessizlikten sonra gizle",
            showLevelMeters: "Seviye göstergelerini göster")
        case .ru: return .init(showAllApps: "Показать все приложения", showRecentOnly: "Показать только недавние",
                               hideAfter: "Скрывать после тишины в течение",
            showLevelMeters: "Показывать индикаторы уровня")
        case .es: return .init(showAllApps: "Mostrar todas las apps", showRecentOnly: "Mostrar solo las recientes",
                               hideAfter: "Ocultar tras un silencio de",
            showLevelMeters: "Mostrar medidores de nivel")
        case .sk: return .init(showAllApps: "Zobraziť všetky aplikácie", showRecentOnly: "Zobraziť len nedávne",
                               hideAfter: "Skryť po tichu trvajúcom",
            showLevelMeters: "Zobraziť ukazovatele úrovne")
        case .de: return .init(showAllApps: "Alle Apps anzeigen", showRecentOnly: "Nur zuletzt aktive anzeigen",
                               hideAfter: "Ausblenden nach Stille von",
            showLevelMeters: "Pegelanzeigen einblenden")
        case .fr: return .init(showAllApps: "Afficher toutes les apps", showRecentOnly: "Afficher les récentes seulement",
                               hideAfter: "Masquer après un silence de",
            showLevelMeters: "Afficher les indicateurs de niveau")
        case .it: return .init(showAllApps: "Mostra tutte le app", showRecentOnly: "Mostra solo le recenti",
                               hideAfter: "Nascondi dopo un silenzio di",
            showLevelMeters: "Mostra indicatori di livello")
        case .ja: return .init(showAllApps: "すべてのアプリを表示", showRecentOnly: "最近のアプリのみ表示",
                               hideAfter: "無音が続いたら隠すまでの時間",
            showLevelMeters: "レベルメーターを表示")
        case .ko: return .init(showAllApps: "모든 앱 보기", showRecentOnly: "최근 앱만 보기",
                               hideAfter: "무음이 지속되면 숨기기까지",
            showLevelMeters: "레벨 미터 보기")
        case .uk: return .init(showAllApps: "Показати всі програми", showRecentOnly: "Показати лише нещодавні",
                               hideAfter: "Приховувати після тиші протягом",
            showLevelMeters: "Показувати індикатори рівня")
        case .zhHans: return .init(showAllApps: "显示所有 App", showRecentOnly: "仅显示最近的 App",
                                   hideAfter: "静音多久后隐藏",
            showLevelMeters: "显示电平表")
        case .zhTW: return .init(showAllApps: "顯示所有 App", showRecentOnly: "只顯示最近的 App",
                                 hideAfter: "靜音多久後隱藏",
            showLevelMeters: "顯示音量表")
        case .zhHK: return .init(showAllApps: "顯示所有 App", showRecentOnly: "只顯示最近的 App",
                                 hideAfter: "靜音多久後隱藏",
            showLevelMeters: "顯示音量表")
        }
    }
}
