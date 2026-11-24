// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Text about this fork and the project it is built on. The original
/// project's name appears here on purpose: these are the lines that credit it.
struct ForkStrings {
    let forkSupportHeading: String
    let forkSupportMessage: String
    let forkSupportButton: String
    let originalProjectHeading: String
    let originalProjectMessage: String

    static func localized(_ language: AppLanguage) -> ForkStrings {
        switch language {
        case .enUS: return .init(
            forkSupportHeading: "Support JaysHub Mixer Plus",
            forkSupportMessage: "This fork adds the mixing desk, per-app effects and pan, and the stuck-key watch. If they help you, a coffee supports the work that goes into them.",
            forkSupportButton: "Buy Me a Coffee",
            originalProjectHeading: "Built on Vorssaint",
            originalProjectMessage: "Everything else in this app is the work of the Vorssaint project. If it helps you, please support them too.")
        case .ptBR: return .init(
            forkSupportHeading: "Apoie o JaysHub Mixer Plus",
            forkSupportMessage: "Este fork adiciona a mesa de mixagem, efeitos e pan por app e o monitor de teclas presas. Se eles ajudam você, um café apoia o trabalho envolvido.",
            forkSupportButton: "Pague um café",
            originalProjectHeading: "Feito sobre o Vorssaint",
            originalProjectMessage: "Todo o resto deste app é trabalho do projeto Vorssaint. Se ele ajuda você, apoie-os também.")
        case .tr: return .init(
            forkSupportHeading: "JaysHub Mixer Plus’ı destekleyin",
            forkSupportMessage: "Bu çatal; miks masasını, uygulama başına efektleri ve pan’ı, ayrıca takılı tuş izleyicisini ekler. İşinize yarıyorsa bir kahve bu emeği destekler.",
            forkSupportButton: "Bir kahve ısmarla",
            originalProjectHeading: "Vorssaint üzerine kurulu",
            originalProjectMessage: "Bu uygulamadaki geri kalan her şey Vorssaint projesinin emeğidir. İşinize yarıyorsa onları da destekleyin.")
        case .ru: return .init(
            forkSupportHeading: "Поддержите JaysHub Mixer Plus",
            forkSupportMessage: "Этот форк добавляет микшерный пульт, эффекты и панораму для каждого приложения и слежение за залипшими клавишами. Если они вам помогают, чашка кофе поддержит эту работу.",
            forkSupportButton: "Угостить кофе",
            originalProjectHeading: "Создано на основе Vorssaint",
            originalProjectMessage: "Всё остальное в этом приложении — работа проекта Vorssaint. Если оно вам помогает, поддержите и их.")
        case .es: return .init(
            forkSupportHeading: "Apoya JaysHub Mixer Plus",
            forkSupportMessage: "Este fork añade la mesa de mezclas, los efectos y el panorama por app y la vigilancia de teclas atascadas. Si te ayudan, un café apoya el trabajo que llevan.",
            forkSupportButton: "Invítame a un café",
            originalProjectHeading: "Creado sobre Vorssaint",
            originalProjectMessage: "Todo lo demás en esta app es obra del proyecto Vorssaint. Si te ayuda, apóyalos también.")
        case .sk: return .init(
            forkSupportHeading: "Podporte JaysHub Mixer Plus",
            forkSupportMessage: "Tento fork pridáva mixážny pult, efekty a panorámu pre jednotlivé aplikácie a sledovanie zaseknutých klávesov. Ak vám pomáhajú, káva podporí prácu na nich.",
            forkSupportButton: "Kúpiť mi kávu",
            originalProjectHeading: "Postavené na Vorssaint",
            originalProjectMessage: "Všetko ostatné v tejto aplikácii je práca projektu Vorssaint. Ak vám pomáha, podporte aj ich.")
        case .de: return .init(
            forkSupportHeading: "JaysHub Mixer Plus unterstützen",
            forkSupportMessage: "Dieser Fork ergänzt das Mischpult, Effekte und Panorama pro App und die Überwachung hängender Tasten. Wenn sie dir helfen, unterstützt ein Kaffee die Arbeit daran.",
            forkSupportButton: "Spendiere mir einen Kaffee",
            originalProjectHeading: "Aufgebaut auf Vorssaint",
            originalProjectMessage: "Alles andere in dieser App ist die Arbeit des Vorssaint-Projekts. Wenn sie dir hilft, unterstütze bitte auch sie.")
        case .fr: return .init(
            forkSupportHeading: "Soutenir JaysHub Mixer Plus",
            forkSupportMessage: "Ce fork ajoute la table de mixage, les effets et le panoramique par app, ainsi que la surveillance des touches bloquées. S’ils vous sont utiles, un café soutient le travail qu’ils demandent.",
            forkSupportButton: "Offrez-moi un café",
            originalProjectHeading: "Construit sur Vorssaint",
            originalProjectMessage: "Tout le reste de cette app est le travail du projet Vorssaint. Si elle vous est utile, soutenez-les aussi.")
        case .it: return .init(
            forkSupportHeading: "Sostieni JaysHub Mixer Plus",
            forkSupportMessage: "Questo fork aggiunge il banco di missaggio, gli effetti e il panorama per app e il controllo dei tasti bloccati. Se ti sono utili, un caffè sostiene il lavoro che richiedono.",
            forkSupportButton: "Offrimi un caffè",
            originalProjectHeading: "Basato su Vorssaint",
            originalProjectMessage: "Tutto il resto di questa app è opera del progetto Vorssaint. Se ti è utile, sostieni anche loro.")
        case .ja: return .init(
            forkSupportHeading: "JaysHub Mixer Plus を支援",
            forkSupportMessage: "このフォークは、ミキシングデスク、アプリごとのエフェクトとパン、押されたままのキーの監視を追加しています。役に立ったら、コーヒー1杯がその作業の支えになります。",
            forkSupportButton: "コーヒーをおごる",
            originalProjectHeading: "Vorssaint をもとに開発",
            originalProjectMessage: "このアプリのそれ以外の部分はすべて Vorssaint プロジェクトによるものです。役に立ったら、ぜひそちらも支援してください。")
        case .ko: return .init(
            forkSupportHeading: "JaysHub Mixer Plus 후원하기",
            forkSupportMessage: "이 포크는 믹싱 데스크, 앱별 이펙트와 팬, 눌린 키 감시 기능을 추가합니다. 도움이 된다면 커피 한 잔이 이 작업에 힘이 됩니다.",
            forkSupportButton: "커피 한 잔 사주기",
            originalProjectHeading: "Vorssaint 기반",
            originalProjectMessage: "이 앱의 나머지 부분은 모두 Vorssaint 프로젝트의 작업입니다. 도움이 된다면 그들도 후원해 주세요.")
        case .uk: return .init(
            forkSupportHeading: "Підтримайте JaysHub Mixer Plus",
            forkSupportMessage: "Цей форк додає мікшерний пульт, ефекти й панораму для кожної програми та стеження за залиплими клавішами. Якщо вони вам допомагають, чашка кави підтримає цю роботу.",
            forkSupportButton: "Пригостити кавою",
            originalProjectHeading: "Створено на основі Vorssaint",
            originalProjectMessage: "Усе інше в цій програмі — робота проєкту Vorssaint. Якщо вона вам допомагає, підтримайте і їх.")
        case .zhHans: return .init(
            forkSupportHeading: "支持 JaysHub Mixer Plus",
            forkSupportMessage: "此分支增加了调音台、每个 App 的效果器与声相，以及卡键监视。如果它们对你有帮助，一杯咖啡就是对这些工作的支持。",
            forkSupportButton: "请我喝杯咖啡",
            originalProjectHeading: "基于 Vorssaint 构建",
            originalProjectMessage: "此 App 的其余部分都是 Vorssaint 项目的成果。如果它对你有帮助，也请支持他们。")
        case .zhTW: return .init(
            forkSupportHeading: "支持 JaysHub Mixer Plus",
            forkSupportMessage: "此分支加入了混音台、每個 App 的效果器與聲相，以及卡鍵監視。如果它們對你有幫助，一杯咖啡就是對這些工作的支持。",
            forkSupportButton: "請我喝杯咖啡",
            originalProjectHeading: "以 Vorssaint 為基礎",
            originalProjectMessage: "此 App 的其餘部分都是 Vorssaint 專案的成果。如果它對你有幫助，也請支持他們。")
        case .zhHK: return .init(
            forkSupportHeading: "支持 JaysHub Mixer Plus",
            forkSupportMessage: "此分支加入了混音台、每個 App 的效果器與聲相，以及卡鍵監視。如果它們對你有幫助，一杯咖啡就是對這些工作的支持。",
            forkSupportButton: "請我喝杯咖啡",
            originalProjectHeading: "以 Vorssaint 為基礎",
            originalProjectMessage: "此 App 的其餘部分都是 Vorssaint 專案的成果。如果它對你有幫助，也請支持他們。")
        }
    }
}
